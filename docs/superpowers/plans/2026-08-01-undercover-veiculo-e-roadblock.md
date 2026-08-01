# Vestimenta visível em veículo e liberação do roadblock — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer o undercover dentro de veículo respeitar colete, capacete blindado, NVG e uniforme (armas seguem permitidas), e desativar a rolagem de dados que descobre o jogador ao passar por roadblock inimigo.

**Architecture:** A regra de vestimenta, hoje duplicada com critérios divergentes em dois arquivos, é extraída para uma função nova `A3A_fnc_undercoverGearCheck`, parametrizada por `_inVehicle`. Os dois chamadores (`fn_canGoUndercover.sqf`, portão de entrada, e o loop de 1 s de `fn_goUndercover.sqf`) passam a consumir essa única fonte de verdade. A rolagem do roadblock é comentada no lugar, preservando o `case "Roadblock"` do `switch` e a string localizada para reativação futura.

**Tech Stack:** SQF (Arma 3), macros do CBA/ACE via `script_component.hpp`, `CfgFunctions.hpp` para registro de funções, `Stringtable.xml` para localização.

## Global Constraints

- **Não há framework de teste automatizado neste repositório.** Não existe Python nem Node nesta máquina, então `Tools/sqfvalidator/sqflint.py` não roda. A verificação de cada task é revisão de código; a verificação funcional é o checklist in-game da Task 5, executado com o mod empacotado em `build/@A3U`. Nenhuma task pode ser declarada "verificada" sem isso — declare "implementada e revisada".
- Idioma dos comentários de código e das mensagens de commit: português sem acentuação nas mensagens de commit (padrão do repositório: `docs: Spec de vestimenta visivel em veiculo`), comentários de código em inglês (padrão dos arquivos tocados).
- Toda função nova precisa de duas coisas para existir: o arquivo em `A3A/addons/core/functions/<Categoria>/fn_<nome>.sqf` **e** a entrada `class <nome> {};` na categoria correspondente de `A3A/addons/core/CfgFunctions.hpp`. Sem a segunda, `A3A_fnc_<nome>` é `nil` em runtime.
- Todo arquivo `.sqf` em `functions/Undercover/` começa com `#include "..\..\script_component.hpp"`.
- Gatilho canônico de "inimigo perto", copiado literalmente onde for necessário:
  `{((side _x == Invaders) || (side _x == Occupants)) && {(_x knowsAbout player > 1.4) || (_x distance player < 350)}} count allUnits > 0`
- Critério canônico de capacete blindado: `headgear player in allArmoredHeadgear`. Nunca usar o `getNumber ... "armor" > 2`.
- Duração de `compromised`: 30 minutos, escrita como `dateToNumber [date select 0, date select 1, date select 2, date select 3, (date select 4) + 30]`.
- Spec de referência: `docs/superpowers/specs/2026-08-01-undercover-veiculo-e-roadblock-design.md`.

---

## Estrutura de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `A3A/addons/core/functions/Undercover/fn_undercoverGearCheck.sqf` | **novo.** Única fonte de verdade sobre "esta aparência passa como civil?". Não exibe hint, não aplica punição — só devolve dados. |
| `A3A/addons/core/CfgFunctions.hpp` | Registro da função nova em `class Undercover`. |
| `A3A/addons/core/functions/Undercover/fn_canGoUndercover.sqf` | Portão de entrada. Passa a delegar vestimenta à função nova nos dois ramos (veículo e a pé). |
| `A3A/addons/core/functions/Undercover/fn_goUndercover.sqf` | Loop de monitoramento e `switch` de punições. Delega vestimenta à função nova nos dois ramos; ganha os motivos `clothesVeh`/`clothesVeh2`; perde a rolagem do roadblock. |
| `A3A/addons/core/Stringtable.xml` | Duas chaves novas para os hints dos motivos novos. |
| `docs/superpowers/2026-08-01-undercover-veiculo-e-roadblock-checklist.md` | **novo.** Checklist de verificação in-game. |

**Ordem e dependências:** Task 1 → Task 2 → Task 3 → Task 5. A Task 4 (roadblock) é totalmente independente das demais e toca uma região do arquivo que nenhuma outra task altera — pode ser executada em qualquer ponto.

---

### Task 1: Função `A3A_fnc_undercoverGearCheck`

**Files:**
- Create: `A3A/addons/core/functions/Undercover/fn_undercoverGearCheck.sqf`
- Modify: `A3A/addons/core/CfgFunctions.hpp:825-830`
- Test: não há. Verificação por revisão de código (Step 4) e pelo item 0 do checklist da Task 5.

**Interfaces:**
- Consumes: nada de tasks anteriores. Depende de variáveis globais já existentes no mod: `allArmoredHeadgear` (criada em `fn_configSort.sqf:96`) e `A3A_faction_civ` (HashMap com a chave `"uniforms"`).
- Produces: `A3A_fnc_undercoverGearCheck`, consumida pelas Tasks 2 e 3.
  - Assinatura: `[_inVehicle] call A3A_fnc_undercoverGearCheck`
  - `_inVehicle : BOOL` — default `false`. Quando `true`, armas são ignoradas.
  - Retorno: `ARRAY<BOOL, ARRAY, STRING>` = `[_ok, _reasons, _hintText]`
    - `_ok : BOOL` — `true` se a aparência passa como civil.
    - `_reasons : ARRAY<STRING>` — diagnóstico, ex. `["Vest visible", "Helmet visible"]`. Vazio quando `_ok`.
    - `_hintText : STRING` — texto acumulado pronto para `A3A_fnc_customHint`. **Nunca vazio**: quando `_ok` é `true` contém só o cabeçalho `STR_A3A_fn_undercover_canGoUn_no_while`. O chamador só exibe quando `!_ok`.

- [ ] **Step 1: Criar o arquivo da função**

Criar `A3A/addons/core/functions/Undercover/fn_undercoverGearCheck.sqf` com exatamente este conteúdo:

```sqf
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
```

- [ ] **Step 2: Registrar a função em CfgFunctions.hpp**

Em `A3A/addons/core/CfgFunctions.hpp`, dentro de `class Undercover` (linhas 825-830), acrescentar a entrada em ordem alfabética — ou seja, depois de `class initUndercover {};`:

```cpp
        class Undercover {
            file = QPATHTOFOLDER(functions\Undercover);
            class canGoUndercover {};
            class goUndercover {};
            class initUndercover {};
            class undercoverGearCheck {};
        };
```

- [ ] **Step 3: Conferir que as seis chaves de localização existem**

Todas as strings usadas já existem em `A3A/addons/core/Stringtable.xml`. Nenhuma é criada nesta task. Confirmar que estas seis estão presentes:

- `STR_A3A_fn_undercover_canGoUn_no_while` (cabeçalho, sem `%1`)
- `STR_A3A_fn_undercover_canGoUn_no_reason_weapon`
- `STR_A3A_fn_undercover_canGoUn_no_reason_vest`
- `STR_A3A_fn_undercover_canGoUn_no_reason_helmet`
- `STR_A3A_fn_undercover_canGoUn_no_reason_ngv`
- `STR_A3A_fn_undercover_canGoUn_no_reason_uniform`
- `STR_A3A_fn_undercover_canGoUn_no_reason_naked`

Comando:

```bash
grep -c "STR_A3A_fn_undercover_canGoUn_no_reason_weapon\|STR_A3A_fn_undercover_canGoUn_no_reason_vest\|STR_A3A_fn_undercover_canGoUn_no_reason_helmet\|STR_A3A_fn_undercover_canGoUn_no_reason_ngv\|STR_A3A_fn_undercover_canGoUn_no_reason_uniform\|STR_A3A_fn_undercover_canGoUn_no_reason_naked\|STR_A3A_fn_undercover_canGoUn_no_while" A3A/addons/core/Stringtable.xml
```

Esperado: `7`. Se vier outro número, parar e investigar antes de seguir — os fragmentos exceto `no_while` levam `%1` e são usados com `format`.

- [ ] **Step 4: Revisão de código**

Reler o arquivo criado conferindo, item a item:

1. Cada um dos seis blocos `if` faz as três coisas: `format` no `_text`, `_ok = false`, `pushBack` no `_reasons`. Um bloco que esqueça o `_ok = false` vira um bug silencioso.
2. A guarda de arma é a **única** com `!_inVehicle`. Nenhum outro bloco pode ter essa condição.
3. A última linha é `[_ok, _reasons, _text]` sem ponto-e-vírgula — é o valor de retorno.
4. As chaves `{}` do lazy-eval nos `&&` estão balanceadas.
5. O `#include` aponta para `..\..\script_component.hpp` com barras invertidas.

- [ ] **Step 5: Commit**

```bash
git add A3A/addons/core/functions/Undercover/fn_undercoverGearCheck.sqf A3A/addons/core/CfgFunctions.hpp
git commit -m "feat: Adiciona A3A_fnc_undercoverGearCheck como fonte unica da regra de vestimenta"
```

---

### Task 2: `canGoUndercover` passa a delegar a vestimenta

**Files:**
- Modify: `A3A/addons/core/functions/Undercover/fn_canGoUndercover.sqf:50` (remover), `:60-134` (refatorar os dois ramos)
- Test: não há. Verificação por revisão de código (Step 4) e pelos itens 1, 2 e 5 do checklist da Task 5.

**Interfaces:**
- Consumes: `A3A_fnc_undercoverGearCheck` da Task 1, assinatura `[_inVehicle] call A3A_fnc_undercoverGearCheck` → `[_ok, _reasons, _hintText]`.
- Produces: nenhuma interface nova. O retorno de `A3A_fnc_canGoUndercover` continua `ARRAY<BOOL, STRING...>` — `[false, "motivo", ...]` ou `[true, ""]`, exatamente como hoje. Não alterar esse formato: `fn_goUndercover.sqf:38-57` depende dele.

- [ ] **Step 1: Remover a linha morta 50**

Apagar a linha 50 inteira:

```sqf
private _roadblocks = controlsX select {isOnRoad(getMarkerPos _x)};
```

Ela é calculada e nunca usada — a linha 57 recalcula a mesma expressão inline dentro de `_secureBases`. Apagar só essa linha; **não** tocar na linha 57.

- [ ] **Step 2: Acrescentar a checagem de vestimenta ao ramo de veículo**

No ramo `if !(isNull (objectParent player)) then { ... }` (linhas 60-77), acrescentar um quarto `exitWith` **depois** do de cordas de reboque, de modo que o bloco inteiro fique assim:

```sqf
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
```

A ordem importa: tipo de veículo, veículo reportado e cordas continuam com prioridade sobre a vestimenta, para que a mensagem exibida seja sempre a mais específica.

- [ ] **Step 3: Substituir o bloco de vestimenta do ramo de a pé**

No ramo `else` (linhas 78-134), substituir tudo entre a linha 86 (`private _text = ...`) e a linha 129 (fim do bloco de cordas de reboque) pelo trecho abaixo. A checagem de `compromised` das linhas 80-84 e o `if !(_result select 0) then {...customHint...}` das linhas 130-133 **permanecem**.

O bloco `else` inteiro deve ficar assim:

```sqf
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
```

É por isso que `_hintText` nunca volta vazio da função: quando a vestimenta passa mas o jogador está segurando cordas, o `format` acima precisa ter o cabeçalho para acrescentar por cima.

- [ ] **Step 4: Atualizar o cabeçalho de dependências do arquivo**

Na lista `Dependencies:` do comentário de cabeçalho (linhas 14-25), remover a linha:

```
    <ARRAY> allArmoredHeadgear
```

O arquivo não referencia mais essa variável diretamente — quem depende dela agora é `A3A_fnc_undercoverGearCheck`, que já a declara no próprio cabeçalho. As demais linhas de `Dependencies:` ficam como estão.

- [ ] **Step 5: Revisão de código**

Conferir, item a item:

1. **Nenhuma checagem de vestimenta sobrou solta no arquivo.** Rodar:
   ```bash
   grep -n "primaryWeapon\|allArmoredHeadgear\|hmd player\|uniform player\|vest player" A3A/addons/core/functions/Undercover/fn_canGoUndercover.sqf
   ```
   Esperado: **zero linhas**. Qualquer resultado significa que sobrou código duplicado.
2. A linha 50 sumiu e a linha do `_secureBases` (com `controlsX select {isOnRoad...}`) continua lá:
   ```bash
   grep -c "isOnRoad(getMarkerPos _x)" A3A/addons/core/functions/Undercover/fn_canGoUndercover.sqf
   ```
   Esperado: `1`.
3. O ramo de veículo tem exatamente quatro `exitWith`, com a vestimenta por último.
4. `_result` continua saindo em uma das três formas: `[false, "<string>"]`, `[false] + _gearReasons`, ou `[_gearOk] + _gearReasons`. Nunca um `[false]` sozinho sem motivo.
5. O `exitWith` de `compromised` (linhas 80-84) e o `if !(_result select 0) then {...customHint...}` do fim do ramo de a pé continuam presentes — foram deliberadamente preservados no Step 3.

- [ ] **Step 6: Commit**

```bash
git add A3A/addons/core/functions/Undercover/fn_canGoUndercover.sqf
git commit -m "feat: canGoUndercover valida vestimenta tambem dentro de veiculo"
```

---

### Task 3: Loop e punições de `goUndercover`

**Files:**
- Modify: `A3A/addons/core/functions/Undercover/fn_goUndercover.sqf:78-79` (nova variável), `:135` (inserir antes), `:159-169` (substituir), `:279-287` (inserir depois)
- Modify: `A3A/addons/core/Stringtable.xml`
- Test: não há. Verificação por revisão de código (Step 6) e pelos itens 3, 4 e 5 do checklist da Task 5.

**Interfaces:**
- Consumes: `A3A_fnc_undercoverGearCheck` da Task 1.
- Produces: dois motivos novos no `switch`, `"clothesVeh"` e `"clothesVeh2"`, e as chaves `STR_A3A_fn_undercover_goUn_no_reason_veh_1` e `STR_A3A_fn_undercover_goUn_no_reason_veh_2`. Nada depois depende deles.

- [ ] **Step 1: Declarar `_brokenVeh` antes do loop**

Na linha 78-79, junto de `_lastBaseInside` e `_reason`, acrescentar:

```sqf
private _lastBaseInside = "";
private _reason = "";
// Captured when a vehicle-scoped reason fires, so the switch below does not
// have to re-read objectParent player after the player may have left.
private _brokenVeh = objNull;
```

- [ ] **Step 2: Inserir a checagem de vestimenta no ramo de veículo**

Dentro de `if !(isNull _veh) then { ... }`, imediatamente **antes** de `if (_vehType isKindOf "Land")` (linha 135), inserir:

```sqf
        // Vests, helmets, NVGs and uniforms are visible through the windows.
        // Weapons are considered stowed and stay allowed inside a vehicle.
        ([true] call A3A_fnc_undercoverGearCheck) params ["_gearOk"];
        if (!_gearOk) exitWith
        {
            _brokenVeh = _veh;
            if ({((side _x == Invaders) || (side _x == Occupants)) && {(_x knowsAbout player > 1.4) || (_x distance player < 350)}} count allUnits > 0) then
            {
                _reason = "clothesVeh2";
            }
            else
            {
                _reason = "clothesVeh";
            };
        };
```

Esse `exitWith` sai do bloco `if !(isNull _veh) then {...}`; quem interrompe o `while` é o `if (_reason != "") exitWith {};` da linha 179, que já existe. Não mexer nele.

Posição exata: depois do `if(_veh getVariable ["NoFlyZoneDetected", ""] != "")` e antes do `if (_vehType isKindOf "Land")`.

- [ ] **Step 3: Substituir a checagem de vestimenta do ramo de a pé**

Substituir as linhas 159-169 inteiras — o `if` gigante com o `getNumber ... "armor" > 2` — por:

```sqf
        ([false] call A3A_fnc_undercoverGearCheck) params ["_gearOk"];
        if (!_gearOk) exitWith
        {
            if ({((side _x == Invaders) || (side _x == Occupants)) && {(_x knowsAbout player > 1.4) || (_x distance player < 350)}} count allUnits > 0) then
            {
                _reason = "clothes2"
            }
            else
            {
                _reason = "clothes"
            };
        };
```

É aqui que o critério de capacete muda de `armor > 2` para `allArmoredHeadgear` (`armor > 0`). Os motivos `clothes` e `clothes2` e seus `case` no `switch` não mudam.

- [ ] **Step 4: Acrescentar as duas chaves ao Stringtable**

Em `A3A/addons/core/Stringtable.xml`, logo **depois** do bloco `</Key>` que fecha `STR_A3A_fn_undercover_goUn_no_reason_2`, inserir:

```xml
            <Key ID="STR_A3A_fn_undercover_goUn_no_reason_veh_1">
                <Original>You cannot stay Undercover in a vehicle while:&lt;br/&gt;&lt;br/&gt;Wearing a vest&lt;br/&gt;Wearing a helmet&lt;br/&gt;Wearing NVGs&lt;br/&gt;Wearing a mil uniform&lt;br/&gt;Being naked&lt;br/&gt;&lt;br/&gt;They can all be seen through the windows!</Original>
            </Key>
            <Key ID="STR_A3A_fn_undercover_goUn_no_reason_veh_2">
                <Original>You cannot stay Undercover in a vehicle while:&lt;br/&gt;&lt;br/&gt;Wearing a vest&lt;br/&gt;Wearing a helmet&lt;br/&gt;Wearing NVGs&lt;br/&gt;Wearing a mil uniform&lt;br/&gt;Being naked&lt;br/&gt;&lt;br/&gt;The enemy saw you and added you to their Wanted List. Your vehicle is now marked!</Original>
            </Key>
```

Só `<Original>` é preenchido. Os demais idiomas do arquivo (Italian, French, Czech, Russian, Turkish, Korean, Chinesesimp) caem no fallback do `<Original>`, comportamento padrão do engine e já presente em outras chaves do arquivo.

As chaves existentes `STR_A3A_fn_undercover_goUn_no_reason_1` e `_2` não servem porque dizem literalmente "A weapon is visible", que é falso no caso do veículo.

- [ ] **Step 5: Acrescentar os dois `case` ao switch**

No `switch (_reason)`, logo **depois** do `case "clothes2"` (que termina na linha 287), inserir:

```sqf
    case "clothesVeh":
    {
        ["Undercover", localize "STR_A3A_fn_undercover_goUn_no_reason_veh_1"] call A3A_fnc_customHint;
    };
    case "clothesVeh2":
    {
        ["Undercover", localize "STR_A3A_fn_undercover_goUn_no_reason_veh_2"] call A3A_fnc_customHint;
        player setVariable["compromised", dateToNumber[date select 0, date select 1, date select 2, date select 3, (date select 4) + 30]];
        if (!isNull _brokenVeh) then
        {
            _brokenVeh setVariable ["A3A_reported", true, true];
        };
    };
```

`clothesVeh2` é o primeiro motivo do sistema a punir jogador e veículo ao mesmo tempo: `compromised` por 30 minutos e `A3A_reported` permanente no veículo (só limpo passando pela caixa de veículos, `fn_vehicleBoxRestore.sqf:68-69`).

- [ ] **Step 6: Revisão de código**

Conferir, item a item:

1. **A regra antiga de vestimenta sumiu do arquivo.** Rodar:
   ```bash
   grep -n "HitpointsProtectionInfo\|primaryWeapon player" A3A/addons/core/functions/Undercover/fn_goUndercover.sqf
   ```
   Esperado: **zero linhas**.
2. Os quatro motivos de roupa existem e cada um tem exatamente um `case`:
   ```bash
   grep -c "case \"clothes\"\|case \"clothes2\"\|case \"clothesVeh\"\|case \"clothesVeh2\"" A3A/addons/core/functions/Undercover/fn_goUndercover.sqf
   ```
   Esperado: `4`.
3. As duas chaves novas existem no Stringtable e são referenciadas no SQF:
   ```bash
   grep -c "STR_A3A_fn_undercover_goUn_no_reason_veh_1\|STR_A3A_fn_undercover_goUn_no_reason_veh_2" A3A/addons/core/Stringtable.xml A3A/addons/core/functions/Undercover/fn_goUndercover.sqf
   ```
   Esperado: `2` no XML e `2` no SQF.
4. `_brokenVeh` é declarado **fora** do `while` (perto da linha 78) e atribuído **dentro** dele. Se estiver declarado dentro do loop, o `switch` vê `objNull` e o veículo nunca é marcado.
5. O `switch` novo usa `_brokenVeh`, não `objectParent player`.
6. A checagem nova do ramo de veículo está antes do `isKindOf "Land"` e depois do `NoFlyZoneDetected`.
7. Nenhuma alteração acidental no `case "Highway"`, `case "SpotBombTruck"` ou no bloco de `_secureBases`.

- [ ] **Step 7: Commit**

```bash
git add A3A/addons/core/functions/Undercover/fn_goUndercover.sqf A3A/addons/core/Stringtable.xml
git commit -m "feat: Undercover quebra ao vestir colete ou capacete dentro de veiculo"
```

---

### Task 4: Desativar a rolagem de detecção do roadblock

Independente das Tasks 1-3. Toca só as linhas 208-215 de `fn_goUndercover.sqf`, região que nenhuma outra task altera.

**Files:**
- Modify: `A3A/addons/core/functions/Undercover/fn_goUndercover.sqf:208-215`
- Test: não há. Verificação por revisão de código (Step 2) e pelos itens 6 e 7 do checklist da Task 5.

**Interfaces:**
- Consumes: nada.
- Produces: nada. O motivo `"Roadblock"` vira inalcançável, mas o `case "Roadblock"` do `switch` (linha 301) e a string `STR_A3A_fn_undercover_goUn_detect_roadb` continuam existindo intactos, para que descomentar o bloco restaure o comportamento antigo sem nenhuma outra edição.

- [ ] **Step 1: Comentar a rolagem**

Substituir as linhas 208-215 por:

```sqf
        // Roadblock detection roll disabled on purpose.
        //
        // The roll was `random 100 < aggression + (tierWar * 10)`. With tierWar
        // at 10 that term alone reaches 100, so every roadblock broke the
        // player's cover, every time, regardless of aggression. The floor was
        // 10%. Airports, outposts, seaports and milbases are untouched: their
        // exitWith blocks run above this point and still fire at 100%.
        //
        // To restore the old behaviour, uncomment the block below. The
        // "Roadblock" case in the switch and its localized string were left in
        // place precisely for that.
        //
        // private _aggro = if (_baseSide == Occupants) then {aggressionOccupants + (tierWar * 10)} else {aggressionInvaders + (tierWar * 10)};
        // if (random 100 < _aggro) exitWith
        // {
        //     private _roadblocks = controlsX select {isOnRoad(getMarkerPos _x)};
        //     if (_base in _roadblocks || _onDetectionMarker) then {
        //         _reason = "Roadblock";
        //     };
        // };
        _lastBaseInside = _base; // Don't check this base again once we passed the check
```

A linha `_lastBaseInside = _base;` **fica ativa**. Antes ela só executava quando a rolagem falhava; agora executa sempre, que é o comportamento desejado — a base é registrada como visitada e nada acontece.

- [ ] **Step 2: Revisão de código**

Conferir, item a item:

1. `_lastBaseInside = _base;` continua **sem** `//` na frente. Esse é o erro fácil de cometer aqui e ele reintroduz a re-avaliação da mesma base a cada segundo.
2. Os quatro `exitWith` acima (Airport, Outpost, Seaport, Milbase) estão intactos:
   ```bash
   grep -c "_reason = \"Airport\"\|_reason = \"Outpost\"\|_reason = \"Seaport\"\|_reason = \"Milbase\"" A3A/addons/core/functions/Undercover/fn_goUndercover.sqf
   ```
   Esperado: `4`.
3. `_reason = "Roadblock"` só aparece comentado:
   ```bash
   grep -n "_reason = \"Roadblock\"" A3A/addons/core/functions/Undercover/fn_goUndercover.sqf
   ```
   Esperado: uma linha só, começando com `//`.
4. O `case "Roadblock"` do switch continua ativo, sem `//`:
   ```bash
   grep -n "case \"Roadblock\"" A3A/addons/core/functions/Undercover/fn_goUndercover.sqf
   ```
   Esperado: duas linhas ativas (a da lista de `case` encadeados na linha ~301 e a do `switch` interno de `_text` na linha ~308).
5. As chaves `{}` do bloco `if ((_onBaseMarker || _onDetectionMarker) && ...)` continuam balanceadas — comentar linhas com `{` e `}` dentro é onde isso costuma quebrar. Conferir visualmente que o `};` que fecha esse `if` (linha 217 original) continua lá.

- [ ] **Step 3: Commit**

```bash
git add A3A/addons/core/functions/Undercover/fn_goUndercover.sqf
git commit -m "feat: Desativa rolagem de deteccao em roadblock, mantendo o codigo comentado"
```

---

### Task 5: Checklist de verificação in-game

**Files:**
- Create: `docs/superpowers/2026-08-01-undercover-veiculo-e-roadblock-checklist.md`
- Test: o próprio documento é o teste. Nada aqui foi executado no momento em que o plano foi escrito.

**Interfaces:**
- Consumes: o comportamento entregue pelas Tasks 1-4.
- Produces: nada em código.

- [ ] **Step 1: Escrever o checklist**

Criar `docs/superpowers/2026-08-01-undercover-veiculo-e-roadblock-checklist.md` seguindo o formato dos checklists existentes em `docs/superpowers/`: um aviso inicial explícito de que nada foi testado, referência à spec e ao plano, e um item por cenário com passos concretos e resultado esperado.

Os nove cenários, na ordem — do maior risco para o menor:

1. **Entrar em carro civil com colete.** Vestir colete, sem arma na mão, entrar num carro civil. Esperado: undercover **recusado**, hint listando "Wearing a vest". Este é o cenário central da mudança; se falhar, nada mais importa.
2. **Entrar em carro civil com fuzil e sem colete.** Esperado: undercover **ativa** normalmente. Confirma que a arma segue permitida no veículo.
3. **Vestir colete dentro do carro, longe de inimigos.** Ativar undercover num carro, dirigir para longe de qualquer inimigo, vestir colete pelo inventário. Esperado: perde o disfarce em até 1 s, hint `..._veh_1`, **sem** `compromised`, veículo **não** marcado. Tirar o colete e reativar o undercover deve funcionar na hora.
4. **Vestir colete dentro do carro com inimigo a menos de 350 m.** Mesmo teste, mas parado perto de patrulha inimiga. Esperado: perde o disfarce, hint `..._veh_2`, `compromised` por 30 min, e o carro fica marcado permanentemente — entrar nele de novo é recusado com "In reported vehicle" até passar pela caixa de veículos.
5. **Capacete leve (armor entre 1 e 2).** A pé, com undercover ativo, vestir um capacete que antes passava. Esperado: **quebra** o disfarce, comportamento novo. Repetir dentro do carro: também quebra.
6. **Atravessar roadblock inimigo undercover.** Com `tierWar` alto (ideal: 8-10), passar de carro por vários roadblocks inimigos, várias vezes cada. Esperado: **nunca** quebra o disfarce. Antes da mudança, com `tierWar` 10, quebrava sempre.
7. **Entrar em marcador de outpost undercover.** Esperado: quebra na hora, exatamente como antes. Repetir com aeroporto, seaport e milbase.
8. **Voar undercover perto de outpost.** Heli civil, undercover, sobrevoar outpost inimigo. Esperado: `airspaceControl` inalterado — o comportamento deve ser idêntico ao de antes da mudança.
9. **Dirigir fora de estrada com inimigo a menos de 350 m.** Esperado: regra *Highway* inalterada — quebra o disfarce e marca o veículo, como antes. Confirma que a checagem nova, inserida logo acima dessa regra, não a atropelou.

Anotar também, como observação no documento, dois efeitos colaterais previstos que aparecerão nos testes e **não** são bugs:

- Um passageiro de colete derruba o disfarce de todos no veículo. Comportamento pré-existente do bloco `fn_goUndercover.sqf:225-233`, que agora dispara com muito mais frequência.
- Um jogador com `compromised` ativo ainda consegue entrar num carro e reativar o undercover na hora, porque o ramo de veículo de `canGoUndercover` não checa `compromised`. Inconsistência pré-existente, deliberadamente fora do escopo desta spec.

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/2026-08-01-undercover-veiculo-e-roadblock-checklist.md
git commit -m "docs: Checklist de verificacao in-game do undercover em veiculo e roadblock"
```
