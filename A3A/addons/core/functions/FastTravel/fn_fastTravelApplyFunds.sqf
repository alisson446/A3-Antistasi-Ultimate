/*
Maintainer: Alisson Oliveira
    Aplica um movimento de creditos na carteira correspondente ao modo de fast
    travel. Delta negativo cobra, delta positivo estorna.

    Este e o unico lugar que mapeia modo -> carteira. Nenhum call site deve
    decidir sozinho entre moneyX e resourcesFIA.

Arguments:
    <NUMBER> Delta em creditos (negativo cobra, positivo estorna)
    <STRING> Modo: "player" | "rally" | "hc"

Return Value:
    Nothing

Scope: Clients, Local Arguments, Global Effect
Environment: Any
Public: Yes
Dependencies:
    A3A_fnc_resourcesPlayer, A3A_fnc_resourcesFIA

Example:
    [-250, "player"] call A3A_fnc_fastTravelApplyFunds;
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

params [["_delta", 0, [0]], ["_mode", "", [""]]];

if (_delta isEqualTo 0) exitWith {};

// * Movimento de HC sai do caixa da faccao; viagem do jogador e rally point
// * saem da carteira pessoal. Decidido na spec.
if (_mode isEqualTo "hc") then {
    // A3A_fnc_resourcesFIA recebe [_hr, _resourcesFIA] e roda no servidor.
    [0, _delta] remoteExec ["A3A_fnc_resourcesFIA", 2];
} else {
    [_delta] call A3A_fnc_resourcesPlayer;
};
