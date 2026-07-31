/*
Maintainer: Alisson Oliveira
    Calcula o custo em creditos de um fast travel, simulando o combustivel que
    seria gasto se o trajeto fosse feito dirigindo ate o destino.

    Funcao pura: nao le `player`, nao escreve variavel, nao abre UI e nao faz
    rede. Pode ser chamada livremente para exibir um preco.

Arguments:
    <OBJECT> Unidade de referencia (player, ou leader do grupo em modo HC)
    <ARRAY> Posicao de destino (world position)

Return Value:
    <NUMBER> Custo em creditos, arredondado, nunca negativo

Scope: Any, Local Arguments, Local Effect
Environment: Any
Public: Yes
Dependencies:
    A3U_ftCostPerKm (parametro de missao)

Example:
    [player, getMarkerPos "Synd_HQ"] call A3A_fnc_fastTravelCost;
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

// * Multiplicadores por tipo de veiculo. Constantes de propósito: a spec
// * decidiu nao expor isso como parametro de missao.
#define FT_MULT_FOOT    0.5
#define FT_MULT_LIGHT   1.0
#define FT_MULT_HEAVY   2.0
#define FT_MULT_TANK    3.0
#define FT_MULT_AIR     3.0

params [["_unit", objNull, [objNull]], ["_destPos", [], [[]]]];

if (isNull _unit || {_destPos isEqualTo []}) exitWith {
    Error("fastTravelCost: unidade nula ou destino vazio");
    0
};

private _vehicleX = vehicle _unit;

// * A ordem importa, mas nao entre os isKindOf: Tank, Truck_F e Wheeled_APC_F
// * sao ramos irmãos sob LandVehicle, entao esses quatro testes ja sao
// * mutuamente exclusivos. Quem precisa vir primeiro e o teste "a pe"
// * (_vehicleX isEqualTo _unit): sem ele, uma unidade sem veiculo nao casa
// * com nenhum isKindOf e cairia no default de 1.0 em vez de 0.5.
private _mult = switch (true) do {
    case (_vehicleX isEqualTo _unit):            { FT_MULT_FOOT };
    case (_vehicleX isKindOf "Air"):             { FT_MULT_AIR };
    case (_vehicleX isKindOf "Tank"):            { FT_MULT_TANK };
    case (_vehicleX isKindOf "Truck_F"):         { FT_MULT_HEAVY };
    case (_vehicleX isKindOf "Wheeled_APC_F"):   { FT_MULT_HEAVY };
    default                                      { FT_MULT_LIGHT };
};

private _distanceKm = ((position _unit) distance2D _destPos) / 1000;

(round (_distanceKm * A3U_ftCostPerKm * _mult)) max 0
