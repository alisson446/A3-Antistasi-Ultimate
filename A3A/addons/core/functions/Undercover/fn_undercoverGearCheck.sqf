/*
Maintainer: Alisson Oliveira
    Checks whether the player's current appearance passes as a civilian.
    Single source of truth for the undercover gear rules: used both by the
    entry gate (canGoUndercover) and by the monitoring loop (goUndercover),
    which previously duplicated these checks with diverging helmet criteria.

    Displays nothing and applies no punishment. The caller decides what to do
    with the result.

Arguments:
    <BOOL> True if the player is inside a vehicle. Weapons are then ignored,
           since they are considered stowed. Everything else stays visible
           through the windows and still applies.

Return Value:
    ARRAY<BOOL, ARRAY, STRING>
        <BOOL>   True if the appearance passes as a civilian
        <ARRAY>  Short diagnostic strings, empty when the check passes
        <STRING> Accumulated hint text, ready for A3A_fnc_customHint. Never
                 empty: when the check passes it holds just the header, so a
                 caller can keep appending its own fragments on top.

Scope: Local
Environment: Any
Public: Yes
Dependencies:
    <HashMap> A3A_faction_civ
    <ARRAY> allArmoredHeadgear

Example:
    ([true] call A3A_fnc_undercoverGearCheck) params ["_ok", "_reasons", "_text"];
*/

#include "..\..\script_component.hpp"

params [["_inVehicle", false, [false]]];

private _ok = true;
private _reasons = [];
private _text = localize "STR_A3A_fn_undercover_canGoUn_no_while";

// Weapons are the only item a vehicle hides.
if (!_inVehicle && {(primaryWeapon player != "") || (secondaryWeapon player != "") || (handgunWeapon player != "")}) then
{
    _text = format [localize "STR_A3A_fn_undercover_canGoUn_no_reason_weapon", _text];
    _ok = false;
    _reasons pushBack "Weapon visible";
};

if (vest player != "") then
{
    _text = format [localize "STR_A3A_fn_undercover_canGoUn_no_reason_vest", _text];
    _ok = false;
    _reasons pushBack "Vest visible";
};

if (headgear player in allArmoredHeadgear) then
{
    _text = format [localize "STR_A3A_fn_undercover_canGoUn_no_reason_helmet", _text];
    _ok = false;
    _reasons pushBack "Helmet visible";
};

if (hmd player != "") then
{
    _text = format [localize "STR_A3A_fn_undercover_canGoUn_no_reason_ngv", _text];
    _ok = false;
    _reasons pushBack "NVG visible";
};

if ((uniform player != "") && {!(uniform player in (A3A_faction_civ get "uniforms"))}) then
{
    _text = format [localize "STR_A3A_fn_undercover_canGoUn_no_reason_uniform", _text];
    _ok = false;
    _reasons pushBack "Suspicious uniform";
};

if (uniform player == "") then
{
    _text = format [localize "STR_A3A_fn_undercover_canGoUn_no_reason_naked", _text];
    _ok = false;
    _reasons pushBack "No clothes";
};

[_ok, _reasons, _text]
