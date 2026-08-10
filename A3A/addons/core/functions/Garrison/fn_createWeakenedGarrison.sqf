#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
params ["_marker", "_side"];

/*  Monta uma guarnicao a meia forca ("enfraquecida") para um marker, como dado puro.
*
*   NAO escreve em nenhuma variavel viva - quem chama decide o que fazer com o resultado.
*   Usada pelo save para gravar uma guarnicao parcial coerente num ponto cuja captura
*   esta sendo revertida, no lugar da guarnicao vazia que a captura deixou.
*
*   O dimensionamento parte de A3A_fnc_garrisonSize (forca NOMINAL do ponto), e nao da
*   guarnicao atual: fn_garrisonUpdate.sqf remove entradas conforme as unidades morrem,
*   entao no momento da captura o array so tem os sobreviventes do assalto do jogador.
*
*   Params:
*     _marker : STRING : nome do marker
*     _side   : SIDE   : lado dono da guarnicao (Occupants ou Invaders)
*
*   Returns:
*     [_oldArray, _wurzelGarrison, _wurzelRequested]
*       _oldArray        : ARRAY of STRING : tipos de unidade (alimenta a contagem do mapa)
*       _wurzelGarrison  : ARRAY : linhas presentes
*       _wurzelRequested : ARRAY : linhas ausentes (a serem reforcadas)
*/

private _target = round (([_marker] call A3A_fnc_garrisonSize) / 2) max 2;

// Mesmas listas de grupos usadas por fn_initGarrisons.sqf:36-41.
// Invaders sempre usa os grupos de tier; Occupants usa tier em aeroporto/base militar
// e milicia nos demais tipos de ponto.
private _groupPool = if (_side == Invaders) then {
    ((A3A_faction_inv get "groupsTierSquads") apply {_x select 1}) + ((A3A_faction_inv get "groupsTierMedium") apply {_x select 1})
} else {
    if ((_marker in airportsX) || {_marker in milbases}) then {
        ((A3A_faction_occ get "groupsTierSquads") apply {_x select 1}) + ((A3A_faction_occ get "groupsTierMedium") apply {_x select 1})
    } else {
        (A3A_faction_occ get "groupsMilitiaSquads") + (A3A_faction_occ get "groupsMilitiaMedium")
    };
};

private _oldArray = [];
if (count _groupPool > 0) then {
    while {count _oldArray < _target} do {
        _oldArray append (selectRandom _groupPool);
    };
    _oldArray resize _target;
} else {
    Error_1("No group pool available to build weakened garrison for %1", _marker);
};

private _type = "Other";
switch (true) do {
    case (_marker in airportsX): {_type = "Airport"};
    case (_marker in outposts): {_type = "Outpost"};
    case (_marker in milbases): {_type = "MilitaryBase"};
};

private _preference = garrison getVariable [format ["%1_preference", _type], []];
private _wurzelGarrison = [];
private _wurzelRequested = [];
{
    private _line = [_x, _side] call A3A_fnc_createGarrisonLine;
    if (_forEachIndex % 2 == 0) then {
        _wurzelGarrison pushBack _line;
        _wurzelRequested pushBack ["", [], []];
    } else {
        _wurzelGarrison pushBack ["", [], []];
        _wurzelRequested pushBack _line;
    };
} forEach _preference;

[_oldArray, _wurzelGarrison, _wurzelRequested];
