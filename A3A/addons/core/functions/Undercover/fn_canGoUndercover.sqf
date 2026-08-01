/*
Author: Wurzel0701
    Checks if the player is able to go undercover

Arguments:
    <NIL>

Return Value:
    ARRAY<BOOL, STRING> The result of the check and a small reason

Scope: Local
Environment: Any
Public: Yes
Dependencies:
    <OBJECT> A3A_faction_civ
    <ARRAY> controlsX
    <ARRAY> airportsX
    <ARRAY> outposts
    <ARRAY> seaports
    <ARRAY> undercoverVehicles
    <NAMESPACE> sidesX
    <SIDE> teamPlayer
    <SIDE> Invaders
    <SIDE> Occupants

Example:
    [] call A3A_fnc_canGoUndercover;
*/

#include "..\..\script_component.hpp"

private _reasons = [];

if (player != player getVariable["owner", player]) exitWith
{
    ["Undercover", localize "STR_A3A_fn_undercover_canGoUn_no_ai"] call A3A_fnc_customHint;
    [false, "No Undercover while controlling AI"];
};

if (captive player) exitWith
{
    ["Undercover", localize "STR_A3A_fn_undercover_canGoUn_already"] call A3A_fnc_customHint;
    [false, "Already undercover"];
};

private _lowCiv = Faction(civilian) getOrDefault ["attributeLowCiv", false];
private _civNonHuman = Faction(civilian) getOrDefault ["attributeCivNonHuman", false];

if (_lowCiv || {_civNonHuman}) exitWith {
    [localize "STR_A3A_goUndercover_title", localize "STR_A3A_fn_undercover_canGoUn_no_lowciv"] call A3A_fnc_customHint;
    [false, "Undercover not allowed in current civ template."];
};

private _secureBases = airportsX + milbases + outposts + seaports + (controlsX select {isOnRoad(getMarkerPos _x)});
private _result = [];

if !(isNull (objectParent player)) then
{
    if (!(typeOf(objectParent player) in undercoverVehicles)) exitWith
    {
        ["Undercover", localize "STR_A3A_fn_undercover_canGoUn_no_nociv"] call A3A_fnc_customHint;
        _result = [false, "In non civilian vehicle"];
    };
    if ((objectParent player) getVariable ["A3A_reported", false]) exitWith
    {
        ["Undercover", localize "STR_A3A_fn_undercover_canGoUn_no_reported1"] call A3A_fnc_customHint;
        _result = [false, "In reported vehicle"];
    };
    if ((objectParent player) getVariable ["SA_Tow_Ropes", []] isNotEqualTo []) exitWith
    {
        ["Undercover", localize "STR_A3A_fn_undercover_canGoUn_no_towrope"] call A3A_fnc_customHint;
        _result = [false, "In vehicle with tow ropes attached"];
    };

    // Vests, helmets, NVGs and uniforms stay visible through the windows.
    // Weapons are considered stowed, so they are not checked here.
    ([true] call A3A_fnc_undercoverGearCheck) params ["_gearOk", "_gearReasons", "_gearText"];
    if (!_gearOk) exitWith
    {
        ["Undercover", _gearText] call A3A_fnc_customHint;
        _result = [false] + _gearReasons;
    };
}
else
{
    if (dateToNumber date < (player getVariable ["compromised", 0])) exitWith
    {
        ["Undercover", localize "STR_A3A_fn_undercover_canGoUn_no_reported2"] call A3A_fnc_customHint;
        _result = [false, "Recently reported"];
    };

    ([false] call A3A_fnc_undercoverGearCheck) params ["_gearOk", "_gearReasons", "_gearText"];
    _result = [_gearOk] + _gearReasons;

    // Tow ropes are not gear, so they stay here and append on top of the text
    // the gear check already accumulated.
    if (!isNull (player getVariable ["SA_Tow_Ropes_Vehicle", objNull])) then
    {
        _gearText = format [localize "STR_A3A_fn_undercover_canGoUn_no_reason_rope", _gearText];
        _result set [0, false];
        _result pushBack "Holding tow ropes";
    };
    if !(_result select 0) then
    {
        ["Undercover", _gearText] call A3A_fnc_customHint;
    };
};

if (count _result != 0 && !(_result select 0)) exitWith
{
    _result;
};

private _base = [_secureBases, player] call BIS_fnc_nearestPosition;
private _size = [_base] call A3A_fnc_sizeMarker;
if ((player distance2D getMarkerPos _base < _size * 2) && (sidesX getVariable [_base, sideUnknown] != teamPlayer)) exitWith
{
    ["Undercover", localize "STR_A3A_fn_undercover_canGoUn_no_close"] call A3A_fnc_customHint;
    [false, "Near enemy territory"];
};

if
(
    {
        ((side _x == Invaders) || (side _x == Occupants)) &&
        {(_x knowsAbout player > 1.4) &&
        {_x distance player < 500}}
    } count allUnits > 0
) exitWith
{
    ["Undercover", localize "STR_A3A_fn_undercover_canGoUn_no_spotted"] call A3A_fnc_customHint;
    [false, "Spotted by enemies"];
};

[true, ""];