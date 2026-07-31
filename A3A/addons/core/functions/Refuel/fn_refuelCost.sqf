/*
Maintainer: Alisson Oliveira
    Converte um aumento de combustivel em creditos.

    Funcao pura: nao le `player`, nao escreve variavel, nao abre UI e nao faz
    rede. Pode ser chamada livremente para exibir um preco.

Arguments:
    <OBJECT> Veiculo abastecido
    <NUMBER> Variacao de `fuel`, 0..1

Return Value:
    <NUMBER> Custo em creditos, fracionario, nunca negativo

Scope: Any, Local Arguments, Local Effect
Environment: Any
Public: Yes
Dependencies:
    A3A_fnc_fuelTankCapacity, A3U_refuelCostPerLiter (parametro de missao)

Example:
    [vehicle player, 0.5] call A3A_fnc_refuelCost;
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

params [["_vehicle", objNull, [objNull]], ["_deltaFuel", 0, [0]]];

if (isNull _vehicle) exitWith {
    Error("refuelCost: veiculo nulo");
    0
};

if (_deltaFuel <= 0) exitWith { 0 };

// * getVariable com default em vez de acesso direto: a funcao e publica e
// * pode ser chamada do debug console antes dos parametros existirem.
private _perLiter = missionNamespace getVariable ["A3U_refuelCostPerLiter", 0];
private _liters = _deltaFuel * ([_vehicle] call A3A_fnc_fuelTankCapacity);

// * Sem arredondar de proposito. Um tick de abastecimento custa fracoes de
// * credito; arredondar aqui faria cada tick virar zero e o abastecimento
// * inteiro sair de graca. O arredondamento acontece uma vez so, na hora de
// * debitar.
(_liters * _perLiter) max 0
