/*
Maintainer: Alisson Oliveira
    Processa uma amostra de combustivel de um veiculo que esta num posto.

    Calcula o delta desde a amostra anterior, descarta o que nao e
    abastecimento, acumula o custo, corta o combustivel quando o saldo nao
    cobre e debita em bloco. E o coracao da mecanica.

    Nao decide quem paga nem quais veiculos observar: isso e do
    A3A_fnc_refuelMonitor. Aqui o pagador ja e `player`.

Arguments:
    <OBJECT> Veiculo sendo abastecido

Return Value:
    Nothing

Scope: Clients, Local Arguments, Global Effect
Environment: Any
Public: No
Dependencies:
    A3A_fnc_fuelTankCapacity, A3A_fnc_refuelCost, A3A_fnc_resourcesPlayer,
    SCRT_fnc_misc_deniedHint

Example:
    [vehicle player] call A3A_fnc_refuelSessionTick;
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

// * Acima de qualquer uma destas taxas nao e bomba: e setFuel de script
// * (garagem, spawn de veiculo, load de save). A de litros cobre tanque
// * grande; a de fracao cobre tanque pequeno, onde encher tudo de uma vez sao
// * poucos litros e passaria pelo limite em litros. O par erra para o lado
// * seguro: no maximo deixa de cobrar, nunca cobra combustivel que o jogador
// * nao comprou.
#define REFUEL_MAX_LPS 40
#define REFUEL_MAX_FRACTION_PER_SEC 0.4
// * Pendente que dispara a chamada de resourcesPlayer, que faz
// * `[] spawn A3A_fnc_statistics` toda vez (fn_resourcesPlayer.sqf:11) e por
// * isso nao pode ser chamada por tick.
#define REFUEL_COMMIT_THRESHOLD 25
// * O ACE e o refuel nativo continuam bombeando depois do corte, entao o
// * aviso de saldo se repetiria a cada amostra sem este cooldown.
#define REFUEL_DENIED_COOLDOWN 15

params [["_vehicle", objNull, [objNull]]];

if (isNull _vehicle) exitWith { Error("refuelSessionTick: veiculo nulo") };

private _fuel = fuel _vehicle;
private _now = time;

// * Estado da sessao: [_refFuel, _lastFuel, _pendingCost, _chargedCost,
// * _chargedLiters, _lastSampleTime, _lastRiseTime, _deniedUntil].
// * setVariable local de proposito - cada cliente tem a sua propria visao.
private _session = _vehicle getVariable ["A3A_refuelSession", []];

if (_session isEqualTo []) exitWith {
    // * Primeira amostra so estabelece a linha de base. Nunca cobra: nao ha
    // * delta anterior para comparar, e cobrar aqui seria cobrar por
    // * combustivel que ja estava no tanque.
    _vehicle setVariable ["A3A_refuelSession", [_fuel, _fuel, 0, 0, 0, _now, _now, 0]];
};

_session params [
    "_refFuel", "_lastFuel", "_pendingCost", "_chargedCost",
    "_chargedLiters", "_lastSampleTime", "_lastRiseTime", "_deniedUntil"
];

private _delta = _fuel - _lastFuel;
private _capacity = [_vehicle] call A3A_fnc_fuelTankCapacity;

// * Taxa medida contra o tempo real desde a amostra anterior, nao contra o
// * intervalo nominal do loop: sob queda de FPS o sleep estica e um
// * abastecimento normal pareceria um salto de script.
private _elapsed = (_now - _lastSampleTime) max 0.001;
private _litersPerSecond = (_delta * _capacity) / _elapsed;
private _fractionPerSecond = _delta / _elapsed;

if (
    _delta <= 0
    || {_litersPerSecond > REFUEL_MAX_LPS}
    || {_fractionPerSecond > REFUEL_MAX_FRACTION_PER_SEC}
) exitWith {
    // * Consumo do motor ou escrita de script. Desloca a referencia no mesmo
    // * tanto para que a reconciliacao do fechamento nao veja isso como
    // * divergencia, e re-baseia sem cobrar.
    _vehicle setVariable ["A3A_refuelSession", [
        _refFuel + _delta, _fuel, _pendingCost, _chargedCost,
        _chargedLiters, _now, _lastRiseTime, _deniedUntil
    ]];
};

private _cost = [_vehicle, _delta] call A3A_fnc_refuelCost;
private _chargedFuel = _delta;

// * Saldo disponivel desconta o pendente ainda nao debitado. E isso que
// * mantem a bomba pre-paga mesmo com o debito acontecendo em bloco.
private _available = (player getVariable ["moneyX", 0]) - _pendingCost;

if (_cost > _available) then {
    private _affordableCost = _available max 0;
    private _affordableFuel = if (_cost > 0) then { _delta * (_affordableCost / _cost) } else { 0 };
    private _cappedFuel = _lastFuel + _affordableFuel;

    // * setFuel precisa rodar na maquina dona do veiculo, como em
    // * fn_refuelVehicleFromSources.sqf:79-81.
    if (local _vehicle) then {
        _vehicle setFuel _cappedFuel;
    } else {
        [_vehicle, _cappedFuel] remoteExecCall ["setFuel", _vehicle];
    };

    _chargedFuel = _affordableFuel;
    _cost = _affordableCost;
    _fuel = _cappedFuel;

    if (_now >= _deniedUntil) then {
        _deniedUntil = _now + REFUEL_DENIED_COOLDOWN;
        [
            localize "STR_A3A_refuel_header",
            format [
                localize "STR_A3A_refuel_denied",
                round (player getVariable ["moneyX", 0]),
                A3A_faction_civ get "currencySymbol"
            ]
        ] call SCRT_fnc_misc_deniedHint;
    };
};

_pendingCost = _pendingCost + _cost;
_chargedLiters = _chargedLiters + (_chargedFuel * _capacity);
if (_chargedFuel > 0) then { _lastRiseTime = _now };

if (_pendingCost >= REFUEL_COMMIT_THRESHOLD) then {
    private _commit = floor _pendingCost;
    [-_commit] call A3A_fnc_resourcesPlayer;
    _chargedCost = _chargedCost + _commit;
    _pendingCost = _pendingCost - _commit;
};

_vehicle setVariable ["A3A_refuelSession", [
    _refFuel, _fuel, _pendingCost, _chargedCost,
    _chargedLiters, _now, _lastRiseTime, _deniedUntil
]];
