# Custo de Combustível no Fast Travel — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cobrar créditos por fast travel proporcionais à distância e ao tipo de veículo, com confirmação antes do débito e bloqueio quando o saldo não cobre a viagem.

**Architecture:** Três funções novas em `A3A/addons/core/functions/FastTravel/` — uma de cálculo puro, uma de transação (diálogo + saldo + débito) e uma de movimento de carteira. Dois call sites existentes ganham um gate de uma linha logo antes da tela preta com timer. Quatro parâmetros novos na seção `Experimental` controlam o que é cobrado e quanto.

**Tech Stack:** SQF (Arma 3), CBA-style macros do Antistasi (`QPATHTOFOLDER`, `FIX_LINE_NUMBERS`, `Error_1`), Stringtable XML, `description.ext` params.

**Spec:** `docs/superpowers/specs/2026-07-31-fast-travel-fuel-cost-design.md`

## Global Constraints

- Indentação: `fn_fastTravelRadio.sqf` usa **tabs**. `fn_rally_travelToRallyPoint.sqf` e todos os arquivos novos usam **4 espaços**. Params.hpp usa 4 espaços. Não misturar dentro de um arquivo.
- Todo arquivo SQF novo em `core` começa com `#include "..\..\script_component.hpp"` seguido de `FIX_LINE_NUMBERS()`.
- Toda função nova precisa ser registrada em `A3A/addons/core/CfgFunctions.hpp`, senão não existe em runtime.
- Símbolo de moeda **sempre** via `A3A_faction_civ get "currencySymbol"`. Nunca literal.
- Texto visível ao jogador **sempre** via `localize`. Nunca string crua.
- Mensagens de negativa usam `SCRT_fnc_misc_deniedHint`. Mensagens neutras usam `A3A_fnc_customHint`.
- Chaves de Stringtable novas precisam pelo menos de `<Original>` em inglês. Outros idiomas são opcionais.
- Não tocar em `A3A/addons/gui/` — a GUI `mainDialog`/`fastTravelTab` é código WIP inativo e está fora de escopo.
- **Não existe framework de teste unitário para SQF neste projeto.** A verificação é: linter estático + procedimento manual no debug console / in-game. Cada task descreve o comando exato e a saída esperada.
- Linter: `python Tools/sqfvalidator/sqflint.py -d A3A/addons` (o wrapper é `Tools/validate_antistasi.ps1`). Rodar da raiz do repo.

---

### Task 1: Parâmetros de missão e suas strings

Cria os 4 parâmetros que controlam a feature. Fazer isso primeiro porque as três funções leem esses globais — sem eles, qualquer teste das funções falha com variável indefinida.

Os parâmetros do `class Params` de `description.ext` viram variáveis globais automaticamente, pelo nome da classe, por comportamento da engine do Arma 3. Não é preciso `BIS_fnc_getParamValue` nem `publicVariable` (isso só existe em `fn_initServer.sqf` para `LogLevel` e `A3A_logDebugConsole`, que precisam existir antes de tudo).

**Files:**
- Modify: `A3A/addons/core/Params.hpp` (inserir após a linha 3096, fim de `A3U_AITakeFromArsenal`, antes da linha em branco que precede `DevelopmentParamsSpacer`)
- Modify: `A3A/addons/scrt/Stringtable.xml` (container `params`, inserir antes de `<Key ID="STR_params_development">`, ~linha 8276)

**Interfaces:**
- Consumes: nada
- Produces: globais `A3U_ftCostPlayer` (0/1), `A3U_ftCostRallyPoint` (0/1), `A3U_ftCostHighCommand` (0/1), `A3U_ftCostPerKm` (NUMBER)

- [ ] **Step 1: Adicionar os 4 parâmetros em Params.hpp**

Inserir imediatamente após o fechamento de `class A3U_AITakeFromArsenal` (linha 3096):

```cpp
    class A3U_ftCostPlayer : ExperimentalParams
    {
        title = $STR_params_ftCostPlayer;
        tooltip = $STR_params_ftCostPlayer_desc;
        values[] = {0, 1};
        texts[] = {$STR_antistasi_dialogs_generic_button_no_text, $STR_antistasi_dialogs_generic_button_yes_text};
        default = 1;
    };
    class A3U_ftCostRallyPoint : ExperimentalParams
    {
        title = $STR_params_ftCostRallyPoint;
        tooltip = $STR_params_ftCostRallyPoint_desc;
        values[] = {0, 1};
        texts[] = {$STR_antistasi_dialogs_generic_button_no_text, $STR_antistasi_dialogs_generic_button_yes_text};
        default = 1;
    };
    class A3U_ftCostHighCommand : ExperimentalParams
    {
        title = $STR_params_ftCostHighCommand;
        tooltip = $STR_params_ftCostHighCommand_desc;
        values[] = {0, 1};
        texts[] = {$STR_antistasi_dialogs_generic_button_no_text, $STR_antistasi_dialogs_generic_button_yes_text};
        default = 1;
    };
    class A3U_ftCostPerKm : ExperimentalParams
    {
        title = $STR_params_ftCostPerKm;
        tooltip = $STR_params_ftCostPerKm_desc;
        values[] = {5, 10, 15, 20, 30, 50};
        texts[] = {"5", "10", "15", "20", "30", "50"};
        default = 20;
    };
```

Sem subclasse `class difficulty` — segue `A3U_AITakeFromArsenal`, que também não tem. Herdam `lockOnSave = 0` de `ExperimentalParams`, então nenhum trava saves.

- [ ] **Step 2: Adicionar as 8 chaves de string**

Em `A3A/addons/scrt/Stringtable.xml`, dentro do container `params`, imediatamente antes de `<Key ID="STR_params_development">`:

```xml
            <Key ID="STR_params_ftCostPlayer">
                <Original>Fast Travel: charge fuel cost</Original>
            </Key>
            <Key ID="STR_params_ftCostPlayer_desc">
                <Original>Charges the player's wallet for fast travel, based on distance and vehicle type.</Original>
            </Key>
            <Key ID="STR_params_ftCostRallyPoint">
                <Original>Fast Travel: charge for rally point</Original>
            </Key>
            <Key ID="STR_params_ftCostRallyPoint_desc">
                <Original>Charges the player's wallet when travelling to the rally point.</Original>
            </Key>
            <Key ID="STR_params_ftCostHighCommand">
                <Original>Fast Travel: charge for High Command</Original>
            </Key>
            <Key ID="STR_params_ftCostHighCommand_desc">
                <Original>Charges faction funds when moving a High Command group.</Original>
            </Key>
            <Key ID="STR_params_ftCostPerKm">
                <Original>Fast Travel: cost per km</Original>
            </Key>
            <Key ID="STR_params_ftCostPerKm_desc">
                <Original>Base credits charged per kilometre travelled, before the vehicle multiplier.</Original>
            </Key>
```

- [ ] **Step 3: Verificar que o XML continua bem formado**

Run: `python -c "import xml.etree.ElementTree as ET; ET.parse(r'A3A/addons/scrt/Stringtable.xml'); print('OK')"`

Expected: `OK`. Se der `ParseError`, uma tag ficou aberta ou desbalanceada.

- [ ] **Step 4: Verificar in-game que os parâmetros aparecem**

Abrir a missão, na tela de setup selecionar o tipo de parâmetros "4" no dropdown (agrupa `Extender`, `Experimental`, `Development`). Sob OPÇÕES EXPERIMENTAIS devem aparecer as 4 entradas novas com os textos do Step 2, e nenhum texto aparecendo como `STR_params_ftCost...` cru — string crua significa chave não encontrada.

Depois de iniciar a missão, no debug console:

```sqf
[A3U_ftCostPlayer, A3U_ftCostRallyPoint, A3U_ftCostHighCommand, A3U_ftCostPerKm]
```

Expected: `[1,1,1,20]` com os defaults.

- [ ] **Step 5: Commit**

```bash
git add A3A/addons/core/Params.hpp A3A/addons/scrt/Stringtable.xml
git commit -m "feat: Parametros de custo de fast travel"
```

---

### Task 2: `A3A_fnc_fastTravelCost` — cálculo puro

A única parte verificável sem gastar dinheiro nem abrir diálogo. Cria a pasta e o registro em CfgFunctions, que as tasks seguintes reusam.

**Files:**
- Create: `A3A/addons/core/functions/FastTravel/fn_fastTravelCost.sqf`
- Modify: `A3A/addons/core/CfgFunctions.hpp` (inserir bloco novo entre o `};` que fecha `class EventHandler`, linha 358, e `class Garrison`, linha 360 — as classes estão em ordem alfabética)

**Interfaces:**
- Consumes: global `A3U_ftCostPerKm` (Task 1)
- Produces: `[_unit, _destPos] call A3A_fnc_fastTravelCost` → NUMBER (créditos, arredondado, `>= 0`)

- [ ] **Step 1: Registrar a pasta em CfgFunctions.hpp**

Inserir entre `class EventHandler { ... };` e `class Garrison {`. Já lista as três funções do plano inteiro, para não mexer nesse arquivo de novo nas tasks 3 e 4:

```cpp
        class FastTravel {
            file = QPATHTOFOLDER(functions\FastTravel);
            class fastTravelApplyFunds {};
            class fastTravelCharge {};
            class fastTravelCost {};
        };
```

Atenção: registrar uma classe cujo `.sqf` ainda não existe faz o build reclamar. As tasks 3 e 4 criam os outros dois arquivos; se precisar validar o build no fim desta task, crie `fn_fastTravelApplyFunds.sqf` e `fn_fastTravelCharge.sqf` já nas tasks certas antes de empacotar.

- [ ] **Step 2: Escrever `fn_fastTravelCost.sqf`**

```sqf
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

// * A ordem importa. Tanques casam com mais de uma classe, entao o teste de
// * "Tank" tem que vir antes dos testes de caminhao/APC.
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
```

Não há entrada para `Boat`: `fn_fastTravelRadio.sqf:52-56` nega fast travel se qualquer unidade do grupo estiver num barco, e `fn_rally_travelToRallyPoint.sqf:5` exige o jogador a pé. Um barco cairia no `default` (1.0), que é um valor sensato. Anfíbios como o Marshall são `Wheeled_APC_F`, não `Boat`, e pagam 2.0 corretamente.

- [ ] **Step 3: Rodar o linter**

Run: `python Tools/sqfvalidator/sqflint.py -d A3A/addons`

Expected: nenhum erro apontando para `fn_fastTravelCost.sqf`. Em SQF um erro de sintaxe não aparece até a função ser chamada em runtime, então essa checagem não é opcional.

- [ ] **Step 4: Verificar a fórmula no debug console**

Com a missão rodando e `A3U_ftCostPerKm` em 20, a pé (`vehicle player == player`):

```sqf
private _p = position player;
[
    [player, _p] call A3A_fnc_fastTravelCost,
    [player, [(_p#0) + 1000, _p#1, 0]] call A3A_fnc_fastTravelCost,
    [player, [(_p#0) + 10000, _p#1, 0]] call A3A_fnc_fastTravelCost
]
```

Expected: `[0,10,100]` — 0 km → 0; 1 km × 20 × 0.5 = 10; 10 km × 20 × 0.5 = 100.

Entrar num carro comum (Offroad) e repetir a mesma linha.

Expected: `[0,20,200]` — o dobro, porque o multiplicador vai de 0.5 para 1.0.

Se o segundo teste devolver os mesmos valores do primeiro, `vehicle player` não está sendo lido — provavelmente o `case` de `isEqualTo` está capturando errado.

- [ ] **Step 5: Commit**

```bash
git add A3A/addons/core/CfgFunctions.hpp A3A/addons/core/functions/FastTravel/fn_fastTravelCost.sqf
git commit -m "feat: A3A_fnc_fastTravelCost, calculo de custo de fast travel"
```

---

### Task 3: `A3A_fnc_fastTravelApplyFunds` — movimento de carteira

Função pequena e isolada: é o **único** lugar que decide qual carteira corresponde a qual modo. Vem antes de `fastTravelCharge` porque `charge` depende dela.

**Files:**
- Create: `A3A/addons/core/functions/FastTravel/fn_fastTravelApplyFunds.sqf`

**Interfaces:**
- Consumes: `A3A_fnc_resourcesPlayer`, `A3A_fnc_resourcesFIA` (já existem)
- Produces: `[_delta, _mode] call A3A_fnc_fastTravelApplyFunds` → Nothing. `_delta` negativo cobra, positivo estorna. `_mode` ∈ `"player" | "rally" | "hc"`.

- [ ] **Step 1: Escrever `fn_fastTravelApplyFunds.sqf`**

```sqf
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
```

Ambas as funções chamadas já cortam o saldo em zero (`fn_resourcesPlayer.sqf:8` e `fn_resourcesFIA.sqf:20`), então nenhuma carteira fica negativa.

- [ ] **Step 2: Rodar o linter**

Run: `python Tools/sqfvalidator/sqflint.py -d A3A/addons`

Expected: nenhum erro apontando para `fn_fastTravelApplyFunds.sqf`.

- [ ] **Step 3: Verificar débito e estorno no debug console**

```sqf
private _antes = player getVariable "moneyX";
[-100, "player"] call A3A_fnc_fastTravelApplyFunds;
private _depois = player getVariable "moneyX";
[100, "player"] call A3A_fnc_fastTravelApplyFunds;
[_antes, _depois, player getVariable "moneyX"]
```

Expected: `_depois` é `_antes - 100`, e o terceiro valor volta a ser `_antes`.

Como comandante (`player == theBoss`), verificar o caixa da facção:

```sqf
private _antes = server getVariable "resourcesFIA";
[-100, "hc"] call A3A_fnc_fastTravelApplyFunds;
sleep 1;
[_antes, server getVariable "resourcesFIA", player getVariable "moneyX"]
```

Expected: o caixa da facção caiu 100 e `moneyX` ficou **intacto**. O `sleep 1` existe porque o `remoteExec` para o servidor não é instantâneo — sem ele a leitura pode pegar o valor antigo. Rodar num bloco `spawn` para o `sleep` funcionar.

- [ ] **Step 4: Commit**

```bash
git add A3A/addons/core/functions/FastTravel/fn_fastTravelApplyFunds.sqf
git commit -m "feat: A3A_fnc_fastTravelApplyFunds, carteira do fast travel"
```

---

### Task 4: `A3A_fnc_fastTravelCharge` — transação e suas strings

Junta tudo: toggle, cálculo, saldo, negativa, confirmação e débito. As três strings novas entram aqui porque é esta função que as usa.

**Files:**
- Create: `A3A/addons/core/functions/FastTravel/fn_fastTravelCharge.sqf`
- Modify: `A3A/addons/scrt/Stringtable.xml` (container `A3A_Dialogs`, que vai da linha ~17097 até o `</Container>` da linha ~17433 — inserir antes desse fechamento)

**Interfaces:**
- Consumes: `A3A_fnc_fastTravelCost` (Task 2), `A3A_fnc_fastTravelApplyFunds` (Task 3), globais da Task 1
- Produces: `[_unit, _destPos, _mode, _destName] call A3A_fnc_fastTravelCharge` → NUMBER. `-1` = abortar a viagem; `>= 0` = valor efetivamente cobrado (0 quando desligado ou grátis). **Ambiente scheduled obrigatório** (usa `BIS_fnc_guiMessage`).

- [ ] **Step 1: Adicionar as 3 chaves de string**

Em `A3A/addons/scrt/Stringtable.xml`, dentro do container `A3A_Dialogs`, imediatamente antes do `</Container>` que o fecha:

```xml
            <Key ID="STR_A3A_Dialogs_fast_travel_cost_confirm">
                <Original>Travel to %1?&lt;br/&gt;Distance: %2 km&lt;br/&gt;Fuel cost: %3%4&lt;br/&gt;Balance after: %5%4</Original>
            </Key>
            <Key ID="STR_A3A_Dialogs_fast_travel_cost_denied">
                <Original>You need %1%2 to cover the fuel for this trip, but you only have %3%2.</Original>
            </Key>
            <Key ID="STR_A3A_Dialogs_fast_travel_cost_denied_hc">
                <Original>The faction needs %1%2 to cover the fuel for this move, but only has %3%2.</Original>
            </Key>
```

As tags `<br/>` precisam vir escapadas como `&lt;br/&gt;` dentro do XML. `BIS_fnc_guiMessage` renderiza structured text, então elas viram quebra de linha de verdade no diálogo.

Ordem dos argumentos de `format`, que o Step 2 tem que respeitar:
- `_confirm`: `%1` destino, `%2` distância em km, `%3` custo, `%4` moeda, `%5` saldo restante
- `_denied` e `_denied_hc`: `%1` custo, `%2` moeda, `%3` saldo atual

- [ ] **Step 2: Escrever `fn_fastTravelCharge.sqf`**

```sqf
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

// Mesmo formato de chamada usado em fn_FIAskillAdd.sqf:27. Devolve BOOL.
if !([_message, localize "STR_A3A_Dialogs_fast_travel_header", true, true] call BIS_fnc_guiMessage) exitWith { -1 };

[-_cost, _mode] call A3A_fnc_fastTravelApplyFunds;

_cost
```

Saldo exatamente igual ao custo é permitido: a guarda é `_balance < _cost`, não `<=`.

- [ ] **Step 3: Verificar que o XML continua bem formado**

Run: `python -c "import xml.etree.ElementTree as ET; ET.parse(r'A3A/addons/scrt/Stringtable.xml'); print('OK')"`

Expected: `OK`.

- [ ] **Step 4: Rodar o linter**

Run: `python Tools/sqfvalidator/sqflint.py -d A3A/addons`

Expected: nenhum erro apontando para `fn_fastTravelCharge.sqf`.

- [ ] **Step 5: Verificar os quatro caminhos no debug console**

Todos precisam rodar dentro de `spawn`, porque a função é scheduled.

Caminho feliz — aceitar:
```sqf
[] spawn {
    private _p = position player;
    private _antes = player getVariable "moneyX";
    private _r = [player, [(_p#0) + 5000, _p#1, 0], "player", "Teste"] call A3A_fnc_fastTravelCharge;
    hint format ["retorno %1 | antes %2 | agora %3", _r, _antes, player getVariable "moneyX"];
};
```
Expected: diálogo aparece com "Travel to Teste?", distância `5.0 km`, custo `50` (a pé, taxa 20). Ao aceitar: retorno `50`, saldo caiu 50. Nenhum texto aparecendo como `STR_...` cru.

Caminho recusar: repetir e clicar Não.
Expected: retorno `-1`, saldo **inalterado**.

Caminho saldo insuficiente:
```sqf
[] spawn {
    player setVariable ["moneyX", 5, true];
    private _p = position player;
    hint str ([player, [(_p#0) + 5000, _p#1, 0], "player", "Teste"] call A3A_fnc_fastTravelCharge);
};
```
Expected: `deniedHint` com som de falha, mensagem citando 50 e 5, retorno `-1`, **sem** diálogo de confirmação.

Caminho desligado:
```sqf
[] spawn {
    A3U_ftCostPlayer = 0;
    private _p = position player;
    hint str ([player, [(_p#0) + 5000, _p#1, 0], "player", "Teste"] call A3A_fnc_fastTravelCharge);
    A3U_ftCostPlayer = 1;
};
```
Expected: retorno `0`, sem diálogo, sem débito.

- [ ] **Step 6: Commit**

```bash
git add A3A/addons/core/functions/FastTravel/fn_fastTravelCharge.sqf A3A/addons/scrt/Stringtable.xml
git commit -m "feat: A3A_fnc_fastTravelCharge, transacao do custo de fast travel"
```

---

### Task 5: Gate no fast travel normal e de High Command

Liga a feature no call site principal, e trata o cancelamento tardio que acontece depois do débito.

**Files:**
- Modify: `A3A/addons/core/functions/Dialogs/fn_fastTravelRadio.sqf` (3 pontos: inserir entre as linhas 145 e 147; alterar o `exitWith` das linhas 171-173; comentar o `exitWith` das linhas 194-196)

**Interfaces:**
- Consumes: `A3A_fnc_fastTravelCharge` (Task 4), `A3A_fnc_fastTravelApplyFunds` (Task 3)
- Produces: nada para tasks seguintes

**Atenção: este arquivo usa TABS para indentar.**

- [ ] **Step 1: Inserir o gate de custo**

As guardas de validação terminam na linha 140. A linha 142 abre `if (_positionTel distance getMarkerPos _base < 500) then {`, que calcula `_positionX` (143) e `_distanceX` (144), e a 145 declara `_forcedX`. Inserir logo após a linha 145, antes da linha em branco que precede `if (!_esHC) then {` (147):

```sqf
		// * Custo de combustivel. Cobra aqui, depois de todas as guardas e
		// * antes da tela preta com timer, como pede a spec.
		// * ANCORA-REEMBOLSO: ponto de cobranca. As outras ancoras deste
		// * arquivo tratam o que acontece se a viagem falhar depois daqui.
		// * Grep por ANCORA-REEMBOLSO para achar a politica inteira.
		private _ftMode = ["player", "hc"] select _esHC;
		private _costUnit = if (_esHC) then {_boss} else {player};
		private _destName = markerText _base;
		if (_destName isEqualTo "") then {_destName = _base};
		private _charged = [_costUnit, _positionX, _ftMode, _destName] call A3A_fnc_fastTravelCharge;
		if (_charged < 0) exitWith {};
```

Três detalhes que não são arbitrários:
- O destino é `_positionX`, não `getMarkerPos _base` — é o mesmo alvo que a linha 144 usa para calcular o timer.
- `_costUnit` é `player` no caso não-HC mesmo quando o jogador não lidera o grupo. A linha 144 usa `position _boss` para o timer, mas para o custo o que importa é de onde o jogador sai.
- O `exitWith` **não** precisa fechar o mapa. Ele está dentro do bloco `then {` aberto na linha 142, e em SQF o `exitWith` sai só do escopo mais interno que o contém — a execução continua na linha 234, que já faz `if (!_esHC) then { openMap false }`. É o mesmo mecanismo de que o `exitWith` da linha 171 depende hoje. Adicionar `openMap false` aqui seria fechar o mapa duas vezes.

O nome vem de `markerText` porque **`A3A_fnc_getLocationMarkerName` não existe** neste repositório, apesar de ser chamada em três arquivos da GUI inativa. Marcadores de cidade recebem `setMarkerTextLocal` em `fn_initZones.sqf:122`; o fallback cobre marcadores de editor sem texto.

- [ ] **Step 2: Estornar no cancelamento tardio**

Substituir o `exitWith` das linhas 171-173 (que agora estarão deslocadas ~11 linhas para baixo):

```sqf
		if (_checkForPlayer and !_isValidTargetLocation) exitWith {
			// * ANCORA-REEMBOLSO: a viagem foi cancelada DEPOIS da cobranca,
			// * porque outro jogador entrou num veiculo do grupo durante a
			// * contagem. Ninguem se moveu, entao devolve o valor integral.
			// * Se um dia a politica mudar para "cobrou, cobrou", e esta
			// * linha que sai.
			[_charged, _ftMode] call A3A_fnc_fastTravelApplyFunds;
			[localize "STR_A3A_Dialogs_fast_travel_header", format [localize "STR_A3A_Dialogs_fast_travel_cancel",groupID _groupX]] call A3A_fnc_customHint;
		};
```

`_charged` e `_ftMode` foram declarados no Step 1 dentro do mesmo bloco `then {` aberto na linha 142, então estão em escopo aqui.

- [ ] **Step 3: Documentar o não-estorno na falha de posicionamento**

No `exitWith` de `findEmptyPosition` (linhas 194-196 originais), adicionar o comentário. **Não mudar o comportamento** — só marcar a decisão:

```sqf
						if (_pos isEqualTo []) exitWith {
							// * ANCORA-REEMBOLSO: sem estorno, de proposito. Este ponto
							// * fica no meio do teleporte, com parte do grupo ja movida,
							// * entao a viagem aconteceu em parte. Devolver o dinheiro
							// * aqui seria pagar pelo deslocamento ja feito.
							[localize "STR_A3A_Dialogs_fast_travel_header", localize "STR_A3A_Dialogs_fast_travel_no_empty_position"] call SCRT_fnc_misc_deniedHint
						};
```

- [ ] **Step 4: Rodar o linter**

Run: `python Tools/sqfvalidator/sqflint.py -d A3A/addons`

Expected: nenhum erro apontando para `fn_fastTravelRadio.sqf`.

- [ ] **Step 5: Verificar que as âncoras estão todas achaveis**

Run: `grep -rn "ANCORA-REEMBOLSO" A3A/addons`

Expected: 4 ocorrências — 1 em `fn_fastTravelCharge.sqf` (custo zero) e 3 em `fn_fastTravelRadio.sqf` (cobrança, estorno, não-estorno). Esse grep é o requisito explícito da spec: a política de reembolso é provisória e tem que ser fácil de revisitar inteira.

- [ ] **Step 6: Verificar in-game**

1. Fast travel normal, a pé, para um destino distante: aparece o diálogo com o nome do destino, distância e custo. Aceitar → tela preta e timer normais, saldo debitado.
2. Recusar no diálogo: nada acontece, mapa volta ao normal, saldo intacto.
3. Zerar a carteira (`player setVariable ["moneyX", 0, true]`) e tentar: `deniedHint`, **sem** tela preta, sem teleporte.
4. `A3U_ftCostPlayer = 0` e tentar: viagem acontece direto, sem diálogo, sem débito.
5. Modo HC — selecionar um grupo com a barra de High Command e mandar viajar: debita `server getVariable "resourcesFIA"` e deixa `moneyX` intacto.
6. De carro vs. a pé para o mesmo destino: o custo de carro é exatamente o dobro.

- [ ] **Step 7: Commit**

```bash
git add A3A/addons/core/functions/Dialogs/fn_fastTravelRadio.sqf
git commit -m "feat: Cobrar combustivel no fast travel normal e de High Command"
```

---

### Task 6: Gate no rally point

Fecha o último caminho. Vale como task separada porque cobre **dois** pontos de entrada de uma vez, e é fácil testar só um deles e achar que terminou.

**Files:**
- Modify: `A3A/addons/scrt/Rally/fn_rally_travelToRallyPoint.sqf` (inserir entre as linhas 41 e 43)

**Interfaces:**
- Consumes: `A3A_fnc_fastTravelCharge` (Task 4)
- Produces: nada

**Atenção: este arquivo usa 4 ESPAÇOS para indentar, diferente da Task 5.**

- [ ] **Step 1: Inserir o gate**

A linha 40 calcula `_positionX` e a 41 o `_distanceX`. Inserir depois da 41, antes de `disableUserInput true` (linha 43):

```sqf
// * Custo de combustivel, cobrado antes da tela preta e do timer.
// * Este gate mora aqui, e nao em fn_fastTravelRadio.sqf, porque o rally tem
// * DOIS pontos de entrada: o desvio em fn_fastTravelRadio.sqf:74 e a
// * addAction da bandeira do HQ em fn_initClient.sqf:519. So aqui os dois sao
// * cobertos.
private _charged = [player, _positionX, "rally", localize "STR_A3AP_rally_header"] call A3A_fnc_fastTravelCharge;
if (_charged < 0) exitWith {};
```

Sem `openMap false` aqui — esta função não abre o mapa.

`STR_A3AP_rally_header` já existe e vale "Rally Point".

Não há estorno neste arquivo: entre a cobrança e o teleporte não existe nenhum ponto de cancelamento.

- [ ] **Step 2: Rodar o linter**

Run: `python Tools/sqfvalidator/sqflint.py -d A3A/addons`

Expected: nenhum erro apontando para `fn_rally_travelToRallyPoint.sqf`.

- [ ] **Step 3: Verificar os DOIS pontos de entrada in-game**

Com um rally point montado e o jogador a pé no HQ:

1. Pelo menu de fast travel: abrir o menu, clicar no marcador do rally point no mapa. Deve aparecer o diálogo de custo e debitar ao aceitar.
2. Pela bandeira do HQ: usar a `addAction` de viajar para o rally point direto na bandeira, **sem** passar pelo menu de fast travel. Deve aparecer o mesmo diálogo e debitar igual.

O ponto 2 é o que quebra se alguém mover esse gate para o `fastTravelRadio`. Testar os dois.

3. `A3U_ftCostRallyPoint = 0` e repetir os dois: viagem direta, sem diálogo, sem débito.
4. Com saldo zerado: `deniedHint` nos dois caminhos, sem teleporte.

- [ ] **Step 4: Rodar a matriz completa da spec**

Antes do commit final, passar a matriz de verificação da spec inteira, incluindo os cenários que só aparecem em condição específica:

| # | Cenário | Esperado |
|---|---|---|
| 1 | A pé vs. de carro, mesma distância | carro custa exatamente 2× o do a pé |
| 2 | Saldo insuficiente | `deniedHint`, sem teleporte, sem débito |
| 3 | Recusar no diálogo | sem débito, mapa volta ao normal |
| 4 | Rally pelos dois caminhos | ambos cobram |
| 5 | Modo HC | debita `resourcesFIA`, `moneyX` intacto |
| 6 | Cada toggle em Não | viagem correspondente de graça, sem diálogo |
| 7 | `A3U_ftCostPerKm` em 5 e em 50 | custo escala linear |
| 8 | Cancelamento tardio em modo HC (grupo de HC com veículo, 2º jogador entra no veículo durante a contagem, `limitedFT` 1 ou 2, destino que não seja base rebelde/aeroporto/milbase) | `resourcesFIA` estornado integralmente |

O cenário 8 só é alcançável em modo High Command: fora do HC, as guardas de `_isValidTargetLocation` (linhas 113/124 de `fn_fastTravelRadio.sqf`) já barram antes do cancelamento tardio, então o reembolso nunca dispara para viagem individual. Precisa de dois jogadores, um grupo de HC com veículo e `limitedFT` em 1 ou 2, com destino que **não** seja base rebelde/aeroporto/milbase. Se não houver como testar com dois jogadores, registrar isso explicitamente como não verificado em vez de marcar como passou.

- [ ] **Step 5: Commit**

```bash
git add A3A/addons/scrt/Rally/fn_rally_travelToRallyPoint.sqf
git commit -m "feat: Cobrar combustivel na viagem para o rally point"
```

---

## Notas de execução

**Ordem das tasks importa.** Task 1 antes de tudo (os globais), Task 2 e 3 antes da 4 (dependências diretas), Task 4 antes da 5 e 6 (os call sites chamam `charge`). As tasks 5 e 6 são independentes entre si.

**CfgFunctions registra as três funções já na Task 2.** Entre a Task 2 e a Task 4, o `CfgFunctions.hpp` referencia dois `.sqf` que ainda não existem. Se for empacotar/buildar a missão nesse intervalo, criar os arquivos vazios primeiro ou comentar as duas linhas — o build reclama de classe sem arquivo.

**Nada de mexer na GUI.** `A3A/addons/gui/functions/GUI/fn_fastTravelTab.sqf` parece o lugar óbvio para exibir o custo, e não é: aquele conjunto de abas nunca é aberto e chama funções que não existem (`A3A_fnc_fastTravel`, `A3A_fnc_canFastTravelToLocation`, `A3A_fnc_getLocationMarkerName`). Está fora de escopo por decisão da spec.
