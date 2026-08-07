/*
Function:
    A3A_fnc_pendingCaptureRemove

Description:
    Removes a marker from A3A_pendingCaptures, if present. Self-dispatches
    to the server when called elsewhere, since A3A_fnc_singleAttack (the
    retaliation script that clears entries) may run on a headless client.

    An optional token (the entry's _startTime) can be given to only remove
    the entry if it matches - so a retaliation script that is still winding
    down can never delete a newer entry registered for the same marker by a
    later capture. Omitting the token preserves the old unconditional-clear
    behavior, used by fn_markerChange.sqf to drop any stale entry whenever a
    marker's ownership changes, regardless of which retaliation registered it.

Scope: Global
Environment: Server (self-dispatches if called elsewhere)

Parameters:
    <STRING> Marker name to clear from the pending-capture registry.
    <NUMBER> (optional, default -1) Token identifying the specific entry to
        remove (matched against the entry's _startTime). -1 (or omitted)
        matches any entry for the marker, since time is always >= 0.

Returns:
    Nothing

Example:
    ["outpost_12"] call A3A_fnc_pendingCaptureRemove;
    ["outpost_12", _pendingToken] call A3A_fnc_pendingCaptureRemove;
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

params ["_marker", ["_token", -1]];

if (!isServer) exitWith { [_marker, _token] remoteExec ["A3A_fnc_pendingCaptureRemove", 2]; };

private _idx = A3A_pendingCaptures findIf { (_x#0) == _marker && {(_token < 0) || {(_x#2) == _token}} };
if (_idx == -1) exitWith {};

A3A_pendingCaptures deleteAt _idx;
publicVariable "A3A_pendingCaptures";
