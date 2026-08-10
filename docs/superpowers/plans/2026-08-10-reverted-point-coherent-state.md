# Estado coerente do ponto revertido — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer o pacote gravado no save para um ponto estratégico com retaliação pendente ser internamente coerente: o ponto volta ao inimigo com guarnição parcial e armado, o investimento do jogador em soldados é devolvido, e as estáticas não são duplicadas.

**Architecture:** Estende o mesmo seam da correção anterior — `fn_saveLoop.sqf` altera apenas as cópias locais do que está sendo gravado, nunca variáveis vivas. Uma função pura nova (`A3A_fnc_createWeakenedGarrison`) gera os dados da guarnição enfraquecida sem escrever em lugar nenhum; `fn_markerChange.sqf` passa a registrar quais estáticas vieram com a captura.

**Tech Stack:** SQF (Arma 3), mod Antistasi Ultimate. Sem framework de testes.

Spec: `docs/superpowers/specs/2026-08-10-reverted-point-coherent-state-design.md`

## Global Constraints

- **Não existe framework de testes automatizados neste repositório.** Não há Python nem Node disponíveis e o linter do repo não roda aqui. Onde o template de tarefa pediria TDD, cada tarefa abaixo especifica em seu lugar uma verificação por revisão de código, e a verificação real acontece in-game (Task 6). **Nunca invente um teste automatizado nem afirme ter rodado um.**
- **Toda função SQF nova precisa de DUAS coisas** para existir em runtime: o arquivo em `A3A/addons/core/functions/<Categoria>/fn_<nome>.sqf` **e** uma entrada `class <nome> {};` na categoria correspondente de `A3A/addons/core/CfgFunctions.hpp`. Sem a segunda, `A3A_fnc_<nome>` é `nil` em runtime.
- **Forma da entrada de `A3A_pendingCaptures`:** `[_marker : STRING, _previousOwner : SIDE, _startTime : NUMBER, _capturedStatics : ARRAY of OBJECT]`. Leituras existentes usam `#0`, `#1` e `#2` — acrescentar o 4º elemento não pode quebrá-las.
- **`_previousOwner` é sempre `Occupants` ou `Invaders`**, nunca `teamPlayer` nem `sideUnknown` (garantido pelo guard `if (_loser in [Occupants, Invaders])` em `fn_markerChange.sqf`).
- **O caminho de save nunca modifica variável viva.** Em `fn_saveLoop.sqf` é proibido escrever em `sidesX`, `garrison`, `staticsToSave` ou `server`. Só as cópias locais do que está sendo gravado mudam. (A poda de `A3A_pendingCaptures` por idade, já existente, é a única exceção e já está implementada.)
- **Cidades estão fora de escopo.** Cidades nunca entram em `A3A_pendingCaptures`.
- **Mensagens de commit em português sem acentos** na primeira linha (ex.: `feat: Adiciona geracao de guarnicao enfraquecida`). Usar `git add <arquivos especificos>` — **nunca** `git add -A` nem `git add .`.
- **ATENÇÃO — alteração TEMP-DEBUG não commitada:** `A3A/addons/core/functions/Base/fn_markerChange.sqf` tem no working tree uma alteração temporária que força retaliação em toda captura (um `_resources = _resources max (5 * A3A_balanceVehicleCost);` e um bloco `if (_resources < _minAttack) exitWith {...}` comentado, ambos marcados com `// TEMP-DEBUG`). Ela é intencional e serve para testar. **Não commite essas linhas e não as remova.** Ao rodar `git add` em `fn_markerChange.sqf`, use `git add -p` ou confira o diff staged para garantir que só as suas mudanças entraram.

---

### Task 1: `A3A_fnc_createWeakenedGarrison` — gerador puro da guarnição enfraquecida

**Files:**
- Create: `A3A/addons/core/functions/Garrison/fn_createWeakenedGarrison.sqf`
- Modify: `A3A/addons/core/CfgFunctions.hpp` (categoria `Garrison`)

**Interfaces:**
- Consumes: `A3A_fnc_garrisonSize` (`[_marker] call` → NUMBER, contagem de unidades da força nominal cheia); `A3A_fnc_createGarrisonLine` (`[_preferenceLine, _side] call` → `[_vehicle, _crew, _cargoGroup]`, função pura).
- Produces: `A3A_fnc_createWeakenedGarrison`, chamada como `[_marker, _side] call A3A_fnc_createWeakenedGarrison`, retorna `[_oldArray, _wurzelGarrison, _wurzelRequested]` onde `_oldArray` é ARRAY of STRING (tipos de unidade) e os outros dois são ARRAY de linhas de guarnição. Task 3 consome exatamente esse retorno.

**Contexto necessário:** o mod tem dois sistemas de guarnição vivendo lado a lado, e ambos são salvos:
- **array antigo** — `garrison getVariable [_marker, []]`, lista plana de strings de tipo de unidade. É o que alimenta a contagem exibida no mapa.
- **arrays wurzel** — `garrison getVariable [format ["%1_garrison", _marker], []]` e `..._requested`, que alimentam o spawn real. Cada "linha" tem a forma `[_vehicle, _crew, _cargoGroup]`, e uma linha vazia (ausente/a reforçar) é `["", [], []]`.

A referência de como uma guarnição inimiga nova é construída está em `A3A/addons/core/functions/init/fn_initGarrisons.sqf:8-21` (preenche com grupos aleatórios até `garrisonSize` e faz `resize`) e nas listas de grupos por facção nas linhas 36-41 do mesmo arquivo.

- [ ] **Step 1: Criar o arquivo da função**

Criar `A3A/addons/core/functions/Garrison/fn_createWeakenedGarrison.sqf` com exatamente este conteúdo:

```sqf
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
```

- [ ] **Step 2: Registrar a função em CfgFunctions.hpp**

Em `A3A/addons/core/CfgFunctions.hpp`, na classe `Garrison`, adicionar a linha `class createWeakenedGarrison {};` logo após `class createGarrisonLine {};`. O bloco deve ficar assim:

```cpp
            class createGarrison {};
            class createGarrisonLine {};
            class createWeakenedGarrison {};
            class crewLocationStatics {};
```

- [ ] **Step 3: Verificar por revisão de código**

Não há teste automatizado a rodar. Reler o arquivo criado inteiro e confirmar, item a item:
- chaves, parênteses e colchetes balanceados; toda instrução terminada em `;`
- `_target` nunca é 0 nem negativo (o `max 2` garante isso), então o `while` sempre termina
- o `while` está protegido contra pool vazio pelo `if (count _groupPool > 0)` — sem essa proteção seria loop infinito
- a função não contém nenhum `setVariable`, `publicVariable` nem atribuição a variável global (é pura)
- `class createWeakenedGarrison {};` está dentro da classe `Garrison` de `CfgFunctions.hpp`, não de outra categoria

- [ ] **Step 4: Commit**

```bash
git add "A3A/addons/core/functions/Garrison/fn_createWeakenedGarrison.sqf" "A3A/addons/core/CfgFunctions.hpp"
git commit -m "feat: Adiciona gerador puro de guarnicao enfraquecida"
```

---

### Task 2: Registrar as estáticas capturadas na entrada pendente

**Files:**
- Modify: `A3A/addons/core/functions/Base/fn_markerChange.sqf` (bloco de estáticas, ~linhas 343-352)

**Interfaces:**
- Consumes: `A3A_pendingCaptures`, cujas entradas foram criadas mais cedo na mesma execução desta função com a forma `[_markerX, _loser, _pendingToken]`.
- Produces: entradas de `A3A_pendingCaptures` passam a ter um 4º elemento `_capturedStatics : ARRAY of OBJECT`. Task 5 consome esse elemento via `_x param [3, []]`.

**Contexto necessário:** o bloco que captura as estáticas roda **depois** do bloco que registra a captura pendente (que fica por volta da linha 84-89, dentro de `if (_winner == teamPlayer) then {...}` mais acima no arquivo). Por isso a entrada não pode nascer já com a lista — ela é atualizada no lugar, depois. Se nenhuma retaliação foi enviada, não existe entrada e não há nada a atualizar; o código precisa tolerar isso.

O bloco atual é:

```sqf
	//Convert all of the static weapons to teamPlayer, essentially. Make them mannable by AI.
	//Make the size larger, as rarely does the marker cover the whole outpost.
	private _staticWeapons = nearestObjects [_positionX, ["LandVehicle", "Ship"], _size * 1.5, true];
	{
		[_x, teamPlayer, true] call A3A_fnc_vehKilledOrCaptured;
		if !(_x in staticsToSave) then {
			staticsToSave pushBack _x;
		};
	} forEach _staticWeapons;
	publicVariable "staticsToSave";
```

Note o guard `if !(_x in staticsToSave)`: coisas que já eram do jogador antes da captura **não** são re-adicionadas. Portanto só as que passam por esse `if` foram adicionadas por esta captura, e só essas devem reverter. Isso é o que preserva a propriedade do jogador (um veículo estacionado ali depois, uma estática comprada) intacta.

- [ ] **Step 1: Coletar as estáticas efetivamente adicionadas e gravá-las na entrada pendente**

Substituir o bloco acima por:

```sqf
	//Convert all of the static weapons to teamPlayer, essentially. Make them mannable by AI.
	//Make the size larger, as rarely does the marker cover the whole outpost.
	private _staticWeapons = nearestObjects [_positionX, ["LandVehicle", "Ship"], _size * 1.5, true];
	private _capturedStatics = [];
	{
		[_x, teamPlayer, true] call A3A_fnc_vehKilledOrCaptured;
		if !(_x in staticsToSave) then {
			staticsToSave pushBack _x;
			_capturedStatics pushBack _x;
		};
	} forEach _staticWeapons;
	publicVariable "staticsToSave";

	// Registra na entrada de captura pendente (criada mais acima nesta mesma execucao)
	// quais estaticas vieram COM o ponto, para que o save possa exclui-las e evitar
	// duplicacao no load. Sem retaliacao enviada nao existe entrada, e nao ha o que fazer.
	private _pendingIdx = A3A_pendingCaptures findIf { (_x#0) == _markerX };
	if (_pendingIdx != -1) then {
		(A3A_pendingCaptures select _pendingIdx) set [3, _capturedStatics];
		publicVariable "A3A_pendingCaptures";
	};
```

- [ ] **Step 2: Verificar por revisão de código**

Não há teste automatizado a rodar. Confirmar:
- `_capturedStatics` só recebe objetos que passaram pelo `if !(_x in staticsToSave)`, ou seja, exatamente os adicionados por esta captura
- o bloco novo está dentro do mesmo `if (_winner == teamPlayer) then {...}` que já continha o bloco de estáticas — não foi movido para fora
- o `findIf` cobre o caso "sem entrada pendente" retornando -1, e nesse caso nada é escrito
- nenhuma outra parte de `fn_markerChange.sqf` foi alterada
- **as linhas marcadas `// TEMP-DEBUG` mais acima no arquivo continuam intactas e não foram staged** (conferir com `git diff --staged`)

- [ ] **Step 3: Commit**

```bash
git add -p "A3A/addons/core/functions/Base/fn_markerChange.sqf"
```

Aceitar **apenas** o hunk do bloco de estáticas. Recusar qualquer hunk que contenha `// TEMP-DEBUG`. Depois conferir e commitar:

```bash
git diff --staged
git commit -m "feat: Registra estaticas capturadas na entrada de captura pendente"
```

---

### Task 3: Gravar guarnição enfraquecida para markers pendentes

**Files:**
- Modify: `A3A/addons/core/functions/Save/fn_saveLoop.sqf` (bloco de guarnição, ~linhas 312-333)

**Interfaces:**
- Consumes: `A3A_fnc_createWeakenedGarrison` (Task 1), chamada como `[_marker, _side] call A3A_fnc_createWeakenedGarrison`, retorna `[_oldArray, _wurzelGarrison, _wurzelRequested]`.
- Produces: nada consumido por tarefas posteriores.

**Contexto necessário:** o bloco atual monta dois arrays (`_garrison` e `_wurzelGarrison`) lendo as variáveis vivas para cada marker, e os grava. Hoje, para um ponto cuja captura está sendo revertida, essas variáveis contêm o estado **vazio** que a captura deixou — o ponto volta inimigo e indefeso. O bloco atual é:

```sqf
{
	_garrison pushBack [
		_x,
		garrison getVariable [_x,[]],
		garrison getVariable [_x + "_lootCD", 0],
		garrison getVariable [_x + "_powCD", 0],
		garrison getVariable [_x + "_samDestroyedCD", 0]
	];
	_wurzelGarrison pushBack [
		_x,
		garrison getVariable [format ["%1_garrison",_x], []],
	 	garrison getVariable [format ["%1_requested",_x], []],
		garrison getVariable [format ["%1_over", _x], []]
	];
} forEach _markersX;
```

- [ ] **Step 1: Pré-computar a guarnição enfraquecida dos markers pendentes**

Imediatamente **antes** da linha `_markersX = markersX - controlsX - watchpostsFIA - roadblocksFIA - aapostsFIA - atpostsFIA - hmgpostsFIA;`, inserir:

```sqf
// Um ponto cuja captura esta sendo revertida voltaria ao inimigo com a guarnicao VAZIA
// que a captura deixou - indefeso e recapturavel de graca. Gera uma guarnicao a meia
// forca para gravar no lugar. Dado puro: nada aqui toca variavel viva.
private _pendingGarrisonHM = createHashMap;
{
	_x params ["_pMarker", "_pOwner"];
	_pendingGarrisonHM set [_pMarker, [_pMarker, _pOwner] call A3A_fnc_createWeakenedGarrison];
} forEach A3A_pendingCaptures;
```

- [ ] **Step 2: Usar a guarnição enfraquecida no lugar da viva, para markers pendentes**

Substituir o bloco `forEach _markersX` mostrado acima por:

```sqf
{
	private _oldLine = garrison getVariable [_x,[]];
	private _wGarr = garrison getVariable [format ["%1_garrison",_x], []];
	private _wReq = garrison getVariable [format ["%1_requested",_x], []];

	private _weakened = _pendingGarrisonHM getOrDefault [_x, []];
	if (_weakened isNotEqualTo []) then {
		_oldLine = _weakened#0;
		_wGarr = _weakened#1;
		_wReq = _weakened#2;
	};

	_garrison pushBack [
		_x,
		_oldLine,
		garrison getVariable [_x + "_lootCD", 0],
		garrison getVariable [_x + "_powCD", 0],
		garrison getVariable [_x + "_samDestroyedCD", 0]
	];
	_wurzelGarrison pushBack [
		_x,
		_wGarr,
	 	_wReq,
		garrison getVariable [format ["%1_over", _x], []]
	];
} forEach _markersX;
```

- [ ] **Step 3: Verificar por revisão de código**

Não há teste automatizado a rodar. Confirmar:
- com `A3A_pendingCaptures` vazio, `_pendingGarrisonHM` fica vazio, `getOrDefault` sempre devolve `[]`, e os três valores continuam vindo das variáveis vivas — **comportamento idêntico ao atual**, sem regressão
- os campos que **não** fazem parte do enfraquecimento (`_lootCD`, `_powCD`, `_samDestroyedCD`, `%1_over`) continuam vindo das variáveis vivas
- nenhum `setVariable` ou `publicVariable` foi introduzido — o bloco só lê
- `_pendingGarrisonHM` é declarado antes do `forEach _markersX` que o consome

- [ ] **Step 4: Commit**

```bash
git add "A3A/addons/core/functions/Save/fn_saveLoop.sqf"
git commit -m "feat: Grava guarnicao enfraquecida para pontos com captura pendente"
```

---

### Task 4: Devolver HR e dinheiro dos soldados guarnecendo um ponto pendente

**Files:**
- Modify: `A3A/addons/core/functions/Save/fn_saveLoop.sqf` (~linha 197, entre o cálculo e a gravação de `resourcesFIA`/`hr`)

**Interfaces:**
- Consumes: `A3A_pendingCaptures` (elemento `#0`, o nome do marker).
- Produces: nada consumido por tarefas posteriores.

**Contexto necessário — este é o ponto de maior risco do plano.** `fn_garrisonAdd.sqf:15,44` cobra por soldado recrutado para guarnição: 1 de HR e `server getVariable _unitType` de dinheiro. O soldado passa a existir como string de tipo em `garrison getVariable [_markerX,[]]`. Se o ponto reverte, esse investimento se perde junto com o ponto.

O risco é **crédito duplicado**: `fn_saveLoop.sqf:157` já soma ao HR gravado as unidades vivas que satisfaçam `(_x getVariable ["spawner",false]) and (group _x in (hcAllGroups theBoss) or (isPlayer (leader _x))) and (side group _x == teamPlayer)`. Se as unidades de guarnição spawnadas satisfizerem esse filtro, o reembolso creditaria **em cima** do que já foi contado — um exploit invertido, gerando HR e dinheiro de graça a cada save.

A leitura do código indica que guarnições não entram nesse filtro (não são grupos de High Command nem lideradas por jogador), mas isso **tem que ser confirmado in-game** antes de considerar esta tarefa concluída — ver Step 3 e o item correspondente da Task 6.

O trecho atual é:

```sqf
if (!isNil "isRallyPointPlaced" && {isRallyPointPlaced}) then {
	private _rallyPointCost = [FactionGet(reb,"lootCrate")] call A3A_fnc_vehiclePrice;
	_resourcesBackground = _resourcesBackground + round(_rallyPointCost/1.3);
};

["resourcesFIA", _resourcesBackground] call A3A_fnc_setStatVariable;
["hr", _hrBackground] call A3A_fnc_setStatVariable;
```

- [ ] **Step 1: Somar o reembolso aos totais antes de gravá-los**

Inserir o bloco novo entre o `if (!isNil "isRallyPointPlaced" ...)` e a linha `["resourcesFIA", ...]`, ficando assim:

```sqf
if (!isNil "isRallyPointPlaced" && {isRallyPointPlaced}) then {
	private _rallyPointCost = [FactionGet(reb,"lootCrate")] call A3A_fnc_vehiclePrice;
	_resourcesBackground = _resourcesBackground + round(_rallyPointCost/1.3);
};

// Soldados que o jogador recrutou para guarnecer um ponto cuja captura esta sendo
// revertida se perderiam junto com o ponto. Credita o custo deles de volta nos totais
// gravados (mesmo custo cobrado em fn_garrisonAdd.sqf: 1 HR + preco do tipo de unidade),
// para que reforcar um ponto contestado nunca saia mais caro que nao reforcar.
{
	private _pMarker = _x#0;
	{
		_hrBackground = _hrBackground + 1;
		_resourcesBackground = _resourcesBackground + (server getVariable [_x, 0]);
	} forEach (garrison getVariable [_pMarker, []]);
} forEach A3A_pendingCaptures;

["resourcesFIA", _resourcesBackground] call A3A_fnc_setStatVariable;
["hr", _hrBackground] call A3A_fnc_setStatVariable;
```

- [ ] **Step 2: Verificar por revisão de código**

Não há teste automatizado a rodar. Confirmar:
- `_pMarker` é extraído do `_x` externo **antes** do `forEach` interno — o `forEach` interno rebinda `_x` para a string de tipo de unidade, e é esse `_x` interno que deve ir em `server getVariable [_x, 0]`
- o bloco está **antes** das duas linhas `setStatVariable` que gravam os totais, senão o reembolso não entra no save
- `server getVariable [_x, 0]` usa a forma com default, para não retornar `nil` num tipo de unidade desconhecido
- nenhum `setVariable` em `server` — só leitura; os acumuladores são variáveis locais
- com `A3A_pendingCaptures` vazio, nada é somado — sem regressão

- [ ] **Step 3: Registrar a pendência de verificação in-game**

Esta tarefa **não pode ser considerada validada por revisão de código apenas**. O risco de crédito duplicado só se resolve in-game. Anotar explicitamente no relatório da tarefa que a verificação dos itens 12 e 13 do checklist (Task 6) é obrigatória antes de a branch ser finalizada, e que, se o total de HR/dinheiro divergir entre o cenário com o ponto spawnado e despawnado, este bloco é a causa provável.

- [ ] **Step 4: Commit**

```bash
git add "A3A/addons/core/functions/Save/fn_saveLoop.sqf"
git commit -m "feat: Devolve HR e dinheiro de soldados em ponto com captura pendente"
```

---

### Task 5: Excluir do save as estáticas capturadas com o ponto

**Files:**
- Modify: `A3A/addons/core/functions/Save/fn_saveLoop.sqf` (~linha 239, imediatamente antes de `// Build save data`)

**Interfaces:**
- Consumes: o 4º elemento das entradas de `A3A_pendingCaptures` (Task 2), acessado com `_x param [3, []]`.
- Produces: nada consumido por tarefas posteriores.

**Contexto necessário:** ao capturar, `fn_markerChange.sqf` move as estáticas do ponto para `staticsToSave` como propriedade do jogador. No load, `fn_loadStat.sqf:370-406` recria cada entrada de `staticsX` com `createVehicle` e a inicializa como do jogador, **sem checar se já existe algo equivalente no local** — e o ponto inimigo, agora revertido, gera as suas próprias. Resultado: armamento duplicado no mesmo lugar.

A exclusão precisa acontecer enquanto os objetos ainda têm **identidade de objeto**, ou seja, antes do `apply` que os converte em arrays de propriedades. O trecho atual é:

```sqf
// Push buildings to save; ignore dead or outside friendly markers.
A3A_buildingsToSave select {
	(A3A_builderAllowRoads || { !isOnRoad _x }) &&
	{ !surfaceIsWater getPosASL _x }
} apply {
	_arrayEst pushBackUnique _x;
};

// Build save data
_arrayEst = _arrayEst apply {
```

- [ ] **Step 1: Remover as estáticas capturadas de `_arrayEst`**

Inserir o bloco novo entre o `A3A_buildingsToSave select {...}` e o comentário `// Build save data`, ficando assim:

```sqf
// Push buildings to save; ignore dead or outside friendly markers.
A3A_buildingsToSave select {
	(A3A_builderAllowRoads || { !isOnRoad _x }) &&
	{ !surfaceIsWater getPosASL _x }
} apply {
	_arrayEst pushBackUnique _x;
};

// Estaticas que vieram COM um ponto cuja captura esta sendo revertida nao podem ser
// gravadas como do jogador: no load o ponto inimigo gera as dele, e as duas copias
// apareceriam sobrepostas. Tem que ser aqui, enquanto ainda ha identidade de objeto -
// depois do apply abaixo sobram so arrays de propriedades.
{
	_arrayEst = _arrayEst - (_x param [3, []]);
} forEach A3A_pendingCaptures;

// Build save data
_arrayEst = _arrayEst apply {
```

- [ ] **Step 2: Verificar por revisão de código**

Não há teste automatizado a rodar. Confirmar:
- o bloco está **antes** de `_arrayEst = _arrayEst apply {...}` — depois dele os objetos viraram arrays de propriedades e a subtração não casaria com nada
- `_x param [3, []]` devolve `[]` para entradas sem o 4º elemento, então a subtração vira no-op nesse caso em vez de erro
- objetos destruídos durante a retaliação não causam problema: a subtração de arrays compara por referência, e o filtro `alive _x` mais acima já removeu os mortos de `_arrayEst` — subtrair uma referência que não está lá é no-op
- com `A3A_pendingCaptures` vazio, `_arrayEst` não muda — sem regressão
- `staticsToSave` (variável viva) **não** foi modificada; só a cópia local `_arrayEst`

- [ ] **Step 3: Commit**

```bash
git add "A3A/addons/core/functions/Save/fn_saveLoop.sqf"
git commit -m "feat: Exclui do save estaticas capturadas com ponto pendente"
```

---

### Task 6: Estender o checklist de verificação in-game

**Files:**
- Modify: `docs/superpowers/2026-08-07-retaliation-save-exploit-checklist.md`

**Interfaces:**
- Consumes: nada.
- Produces: nada.

**Contexto necessário:** o checklist já existe e vai até o item 11. Esta tarefa acrescenta os itens 12 a 16, sem renumerar nem alterar os existentes. O item 11 atual já cobre parcialmente o cenário de guarnição, mas foi escrito antes deste trabalho e diz que a composição inconsistente "pode precisar de uma correção separada" — que é justamente o que este plano implementa.

- [ ] **Step 1: Acrescentar os itens novos ao final do arquivo**

Adicionar ao final de `docs/superpowers/2026-08-07-retaliation-save-exploit-checklist.md`:

```markdown
- [ ] 12. **(Crítico — risco de crédito duplicado.)** Anotar HR e dinheiro
      atuais. Capturar um ponto com retaliação pendente, recrutar 3 soldados
      para guarnecê-lo, e anotar os totais de novo. Salvar e recarregar
      **com o ponto spawnado** (jogador perto). Confirmar que HR e dinheiro
      voltaram exatamente ao valor de antes do recrutamento — nem menos
      (investimento perdido), nem mais (crédito duplicado).

- [ ] 13. **(Crítico — risco de crédito duplicado.)** Repetir o item 12, mas
      salvando **com o ponto despawnado** (jogador longe o bastante para o
      ponto não estar spawnado). O resultado tem que ser o mesmo do item 12.
      Se os dois cenários derem totais diferentes, o bloco de reembolso em
      `fn_saveLoop.sqf` está creditando em cima do que a contagem de
      unidades vivas já somava — parar e corrigir antes de seguir.

- [ ] 14. Após um reload que reverteu um ponto pendente, clicar no marker no
      mapa e confirmar que ele tem guarnição **parcial**: não vazio (o que
      permitiria recaptura de graça) e visivelmente menor que o normal
      daquele ponto. A string exibida pode ser "Weakened" ou "Decimated"
      dependendo do tamanho do ponto — ambas são aceitáveis; o que não é
      aceitável é guarnição zerada ou cheia.

- [ ] 15. No mesmo ponto revertido do item 14, confirmar que existem
      estáticas (o ponto não voltou desarmado) e que **não há estáticas
      duplicadas ou sobrepostas** no local. Comparar com o aspecto do ponto
      antes da captura original.

- [ ] 16. Antes da captura, estacionar um veículo seu dentro da área do
      ponto e/ou comprar uma estática ali. Capturar, deixar a retaliação
      pendente, salvar e recarregar. Confirmar que **esse veículo/estática
      continua sendo seu** e não foi entregue ao inimigo nem removido —
      só o que veio COM o ponto deve reverter.
```

- [ ] **Step 2: Commit**

```bash
git add "docs/superpowers/2026-08-07-retaliation-save-exploit-checklist.md"
git commit -m "docs: Adiciona itens de verificacao do ponto revertido coerente"
```

---

## Ordem e dependências

- Task 1 antes da Task 3 (que chama a função criada na 1).
- Task 2 antes da Task 5 (que lê o 4º elemento gravado na 2).
- Tasks 3, 4 e 5 tocam o mesmo arquivo (`fn_saveLoop.sqf`) em regiões diferentes; executar em sequência, nunca em paralelo.
- Task 6 pode ser feita por último, é só documentação.

## Antes de finalizar a branch

1. Executar o checklist in-game, **obrigatoriamente incluindo os itens 12 e 13** (risco de crédito duplicado).
2. Reverter a alteração TEMP-DEBUG:

```bash
git checkout -- "A3A/addons/core/functions/Base/fn_markerChange.sqf"
```

Atenção: isso descarta **todas** as mudanças não commitadas desse arquivo. Confirmar antes que as mudanças da Task 2 já estão commitadas (`git log --oneline -5` e `git diff HEAD -- "A3A/addons/core/functions/Base/fn_markerChange.sqf"` deve mostrar só as linhas TEMP-DEBUG).
