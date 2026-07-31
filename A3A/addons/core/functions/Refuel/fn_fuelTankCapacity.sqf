/*
Maintainer: Alisson Oliveira
    Devolve a capacidade do tanque de um veiculo em litros.

    Le ace_refuel_fuelCapacity, cai para fuelCapacity, e por ultimo para uma
    constante. Nunca devolve zero: capacidade zero faria o veiculo abastecer
    de graca, entao veiculo de mod com config incompleto paga um preco
    plausivel em vez de virar brecha.

Arguments:
    <OBJECT> Veiculo

Return Value:
    <NUMBER> Capacidade em litros, sempre maior que zero

Scope: Any, Local Arguments, Local Effect
Environment: Any
Public: Yes
Dependencies:
    Nenhuma

Example:
    [vehicle player] call A3A_fnc_fuelTankCapacity;
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

// * Fallback para veiculo cujo config nao declara capacidade nenhuma.
#define REFUEL_DEFAULT_CAPACITY 100

params [["_vehicle", objNull, [objNull]]];

if (isNull _vehicle) exitWith {
    Error("fuelTankCapacity: veiculo nulo");
    REFUEL_DEFAULT_CAPACITY
};

private _cfg = configOf _vehicle;

// * Mesmo encadeamento de fn_refuelVehicleFromSources.sqf:26-30, com o
// * fallback a mais no fim.
private _capacity = getNumber (_cfg >> "ace_refuel_fuelCapacity");
if (_capacity <= 0) then { _capacity = getNumber (_cfg >> "fuelCapacity") };
if (_capacity <= 0) then { _capacity = REFUEL_DEFAULT_CAPACITY };

_capacity
