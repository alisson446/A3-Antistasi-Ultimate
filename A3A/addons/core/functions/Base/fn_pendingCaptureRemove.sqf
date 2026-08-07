/*
Function:
    A3A_fnc_pendingCaptureRemove

Description:
    Removes a marker from A3A_pendingCaptures, if present. Self-dispatches
    to the server when called elsewhere, since A3A_fnc_singleAttack (the
    retaliation script that clears entries) may run on a headless client.

Scope: Global
Environment: Server (self-dispatches if called elsewhere)

Parameters:
    <STRING> Marker name to clear from the pending-capture registry.

Returns:
    Nothing

Example:
    ["outpost_12"] call A3A_fnc_pendingCaptureRemove;
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

params ["_marker"];

if (!isServer) exitWith { [_marker] remoteExec ["A3A_fnc_pendingCaptureRemove", 2]; };

private _idx = A3A_pendingCaptures findIf { (_x#0) == _marker };
if (_idx == -1) exitWith {};

A3A_pendingCaptures deleteAt _idx;
publicVariable "A3A_pendingCaptures";
