/*
Maintainer: Alisson Oliveira
    Cobra o custo de combustivel de um fast travel. Decide a carteira, bloqueia
    quando o saldo nao cobre, pede confirmacao e debita.

    Unico lugar do mod que sabe quem paga o que. Os call sites so checam o
    retorno.

Arguments:
    <OBJECT> Unidade de referencia (player, ou leader do grupo em modo HC)
    <ARRAY> Posicao de destino (world position)
    <STRING> Modo: "player" | "rally" | "hc"
    <STRING> Nome do destino para o dialogo (opcional, default "")

Return Value:
    <NUMBER> -1 para abortar a viagem; >= 0 com o valor cobrado

Scope: Clients, Local Arguments, Global Effect
Environment: Scheduled (usa BIS_fnc_guiMessage)
Public: Yes
Dependencies:
    A3A_fnc_fastTravelCost, A3A_fnc_fastTravelApplyFunds,
    A3U_ftCostPlayer, A3U_ftCostRallyPoint, A3U_ftCostHighCommand

Example:
    [player, getMarkerPos "Synd_HQ", "player", "HQ"] call A3A_fnc_fastTravelCharge;
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

params [
    ["_unit", objNull, [objNull]],
    ["_destPos", [], [[]]],
    ["_mode", "player", [""]],
    ["_destName", "", [""]]
];

// * Unico ponto de validacao de _mode. Um modo fora da whitelist aborta a
// * viagem em vez de cair no default do switch abaixo ou ser comparado por
// * isEqualTo mais adiante - assim nenhum modo desconhecido chega a debitar
// * a carteira errada ou virar viagem gratis.
if !(_mode in ["player", "rally", "hc"]) exitWith {
    Error_1("fastTravelCharge: modo desconhecido %1", _mode);
    -1
};

private _enabled = switch (_mode) do {
    case "player":  { A3U_ftCostPlayer };
    case "rally":   { A3U_ftCostRallyPoint };
    case "hc":      { A3U_ftCostHighCommand };
    default {
        Error_1("fastTravelCharge: modo desconhecido %1", _mode);
        0
    };
};

if (_enabled isEqualTo 0) exitWith { 0 };

private _cost = [_unit, _destPos] call A3A_fnc_fastTravelCost;

// * ANCORA-REEMBOLSO: custo zero nao cobra nada, entao nao ha o que estornar.
// * Viagens de poucas dezenas de metros caem aqui e saem de graca, sem dialogo.
if (_cost <= 0) exitWith { 0 };

private _currency = A3A_faction_civ get "currencySymbol";
private _balance = if (_mode isEqualTo "hc") then {
    server getVariable ["resourcesFIA", 0]
} else {
    player getVariable ["moneyX", 0]
};

if (_balance < _cost) exitWith {
    private _key = if (_mode isEqualTo "hc") then {
        "STR_A3A_Dialogs_fast_travel_cost_denied_hc"
    } else {
        "STR_A3A_Dialogs_fast_travel_cost_denied"
    };
    [
        localize "STR_A3A_Dialogs_fast_travel_header",
        format [localize _key, _cost, _currency, _balance]
    ] call SCRT_fnc_misc_deniedHint;
    -1
};

private _distanceKm = ((position _unit) distance2D _destPos) / 1000;
private _message = format [
    localize "STR_A3A_Dialogs_fast_travel_cost_confirm",
    _destName,
    _distanceKm toFixed 1,
    _cost,
    _currency,
    _balance - _cost
];

// * Parent=false: so o mapa esta aberto aqui, nao um dialogo, ao contrario de
// * fn_FIAskillAdd.sqf:27. Mesmo parametro que fn_popup.sqf:20 usa fora de
// * dialogo. BIS_fnc_guiMessage devolve false tanto para "Nao" quanto para
// * falha ao criar a mensagem - o log abaixo distingue uma recusa real de um
// * dialogo que nao abriu.
if !([_message, localize "STR_A3A_Dialogs_fast_travel_header", true, false] call BIS_fnc_guiMessage) exitWith {
    Info_1("fastTravelCharge: viagem recusada ou dialogo falhou (modo %1)", _mode);
    -1
};

[-_cost, _mode] call A3A_fnc_fastTravelApplyFunds;

_cost
