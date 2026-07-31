/*
Maintainer: Alisson Oliveira
    Fecha a sessao de abastecimento de um veiculo e acerta a conta.

    Compara o combustivel que o tanque de fato ganhou com o que foi cobrado e
    debita ou estorna a diferenca. E isso que fecha a janela em que se pagou
    por combustivel que depois some - correcao de fuel vinda do servidor,
    dessincronia de MP, load de save no meio, ou o proprio corte por falta de
    saldo.

    Chamada de mais de um lugar do monitor (fim por inatividade, veiculo fora
    do raio, jogador longe do posto), por isso e funcao propria.

Arguments:
    <OBJECT> Veiculo com sessao aberta

Return Value:
    Nothing

Scope: Clients, Local Arguments, Local Effect
Environment: Any
Public: No
Dependencies:
    A3A_fnc_fuelTankCapacity, A3A_fnc_resourcesPlayer, A3A_fnc_customHint

Example:
    [vehicle player] call A3A_fnc_refuelSessionClose;
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

params [["_vehicle", objNull, [objNull]]];

if (isNull _vehicle) exitWith {};

private _session = _vehicle getVariable ["A3A_refuelSession", []];
if (_session isEqualTo []) exitWith {};

// * Limpa antes de qualquer outra coisa: se algo abaixo falhar, a proxima
// * amostra recomeca de uma linha de base limpa em vez de reprocessar esta.
_vehicle setVariable ["A3A_refuelSession", nil];

_session params [
    "_refFuel", "_lastFuel", "_pendingCost", "_chargedCost",
    "_chargedLiters", "_lastSampleTime", "_lastRiseTime", "_deniedUntil"
];

if (!alive _vehicle) exitWith {
    // * `fuel` de destroco nao serve de medida. Cobra o pendente e encerra,
    // * sem resumo: o veiculo explodiu, o jogador tem o que olhar.
    private _commit = round _pendingCost;
    if (_commit > 0) then { [-_commit] call A3A_fnc_resourcesPlayer };
};

private _perLiter = missionNamespace getVariable ["A3U_refuelCostPerLiter", 0];
private _capacity = [_vehicle] call A3A_fnc_fuelTankCapacity;

// * _refFuel acompanhou toda variacao nao cobrada, entao (fuel - _refFuel) e
// * exatamente a soma dos deltas cobrados quando nada anomalo aconteceu.
// * Qualquer divergencia aqui e o que escapou da amostragem.
private _realLiters = (((fuel _vehicle) - _refFuel) max 0) * _capacity;

// * round uma vez so, sobre a diferenca: _chargedCost ja e inteiro (o tick
// * sempre debita floor) e _pendingCost e o resto fracionario nunca debitado.
private _settle = round ((_realLiters * _perLiter) - _chargedCost - _pendingCost);

if (_settle isNotEqualTo 0) then { [-_settle] call A3A_fnc_resourcesPlayer };

private _total = _chargedCost + _settle;

// * Sessao sem cobranca nenhuma nao gera hint. E o caso do veiculo parado no
// * posto sem abastecer e do jogador sem dinheiro, que fecha e reabre sessao
// * enquanto a bomba continua ligada.
if (_total <= 0) exitWith {};

[
    localize "STR_A3A_refuel_header",
    format [
        localize "STR_A3A_refuel_charged",
        round _realLiters,
        _total,
        A3A_faction_civ get "currencySymbol",
        round (player getVariable ["moneyX", 0])
    ]
] call A3A_fnc_customHint;
