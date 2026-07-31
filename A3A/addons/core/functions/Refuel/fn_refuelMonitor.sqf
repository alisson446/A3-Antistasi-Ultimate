/*
Maintainer: Alisson Oliveira
    Loop do cliente que observa abastecimento em postos de combustivel.

    Fica dormindo enquanto o jogador nao esta perto de um posto. Perto de um,
    escolhe os veiculos candidatos, resolve quem paga e delega a cobranca ao
    A3A_fnc_refuelSessionTick.

    A proximidade do posto nao dispara cobranca: ela so decide quando olhar.
    Sem subida de `fuel` nenhum credito sai.

Arguments:
    Nenhum

Return Value:
    Nothing

Scope: Clients, Local Arguments, Global Effect
Environment: Spawned
Public: No
Dependencies:
    A3A_fnc_refuelSessionTick, A3A_fnc_refuelSessionClose,
    A3A_fuelStationTypes, A3U_refuelCostEnabled, A3U_refuelCostPerLiter

Example:
    [] spawn A3A_fnc_refuelMonitor;
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

#define REFUEL_TICK 1
// * Jogador -> posto: acorda o monitor. Folgado o bastante para cobrir a
// * mangueira do ACE esticada e o veiculo estacionado atras da bomba.
#define REFUEL_STATION_RANGE 40
// * Posto -> veiculo observado.
#define REFUEL_VEHICLE_RANGE 25
// * Sem subida por este tempo, o abastecimento acabou.
#define REFUEL_IDLE_TIMEOUT 3

if (!hasInterface) exitWith {};

if ((missionNamespace getVariable ["A3U_refuelCostEnabled", 0]) isEqualTo 0) exitWith {
    Info("refuelMonitor: cobranca de abastecimento desligada nos parametros");
};

if ((missionNamespace getVariable ["A3U_refuelCostPerLiter", 0]) <= 0) exitWith {
    Info("refuelMonitor: preco por litro zerado, monitor nao iniciado");
};

if (isNil "A3A_fuelStationTypes") exitWith {
    Error("refuelMonitor: A3A_fuelStationTypes indefinido, monitor nao iniciado");
};

private _tracked = [];

while {true} do {
    sleep REFUEL_TICK;

    private _now = time;

    if (isNull player || {!alive player}) then {
        { [_x] call A3A_fnc_refuelSessionClose } forEach _tracked;
        _tracked = [];
        continue;
    };

    // * nearestObjects e teste do motor. Varrer A3A_fuelStations em SQF
    // * custaria uma passada pelo array inteiro a cada segundo de partida.
    private _stations = nearestObjects [player, A3A_fuelStationTypes, REFUEL_STATION_RANGE];

    private _current = [];
    {
        private _station = _x;
        {
            private _veh = _x;
            if !(_veh in _current) then {
                // * Pagador: motorista jogador, se houver; senao o jogador
                // * vivo mais proximo. Cada cliente aplica a mesma regra e so
                // * cobra se ela apontar para ele mesmo - sem lista
                // * compartilhada e sem servidor no caminho.
                private _payer = driver _veh;
                if (!isPlayer _payer) then {
                    _payer = objNull;
                    private _bestDist = 1e10;
                    {
                        private _dist = _x distance _veh;
                        if (_dist < _bestDist) then {
                            _bestDist = _dist;
                            _payer = _x;
                        };
                    } forEach (allPlayers select {alive _x && {!(_x isKindOf "HeadlessClient_F")}});
                };
                if (_payer isEqualTo player) then { _current pushBack _veh };
            };
        } forEach ((nearestObjects [_station, ["LandVehicle", "Air", "Ship"], REFUEL_VEHICLE_RANGE]) select {alive _x});
    } forEach _stations;

    // * Saiu da condicao (veiculo se afastou, jogador saiu do posto, outro
    // * jogador virou o pagador): fecha e acerta a conta.
    {
        if !(_x in _current) then { [_x] call A3A_fnc_refuelSessionClose };
    } forEach _tracked;

    {
        [_x] call A3A_fnc_refuelSessionTick;

        private _session = _x getVariable ["A3A_refuelSession", []];
        if (_session isNotEqualTo []) then {
            _session params [
                "_refFuel", "_lastFuel", "_pendingCost", "_chargedCost",
                "_chargedLiters", "_lastSampleTime", "_lastRiseTime"
            ];
            if (_now - _lastRiseTime > REFUEL_IDLE_TIMEOUT) then {
                // * Fecha para dar o resumo logo depois da bomba parar. O
                // * veiculo continua em _current e a proxima amostra abre uma
                // * sessao nova, que nao cobra nada enquanto nada subir.
                [_x] call A3A_fnc_refuelSessionClose;
            };
        };
    } forEach _current;

    _tracked = _current;
};
