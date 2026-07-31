# Custo de combustível ao abastecer em postos — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Descontar créditos da carteira do jogador por litro abastecido em postos de combustível, funcionando igual no reabastecimento nativo do jogo e no do ACE.

**Architecture:** Um loop de cliente acorda só quando o jogador está perto de um posto, amostra `fuel` dos veículos ali por perto a cada segundo e cobra o aumento medido. Nada intercepta o abastecimento: a cobrança é sempre pós-fato, sobre combustível que já entrou no tanque. Cálculo puro (`fuelTankCapacity`, `refuelCost`) fica separado do efeito colateral (`refuelSessionTick`, `refuelSessionClose`, `refuelMonitor`).

**Tech Stack:** SQF, addon `A3A/addons/core`, macros de log do `script_component.hpp`, parâmetros de missão em `Params.hpp`, textos em `A3A/addons/scrt/Stringtable.xml`.

**Spec:** `docs/superpowers/specs/2026-07-31-fuel-station-refuel-cost-design.md`

## Global Constraints

- **Não há framework de teste de SQF neste projeto.** Onde um plano normal teria TDD, este tem verificação por debug console in-game e uma matriz manual. Escreva o código, confira no console, então commite.
- **O linter não roda nesta máquina:** `Tools/sqfvalidator/sqflint.py` exige Python, que não está instalado. Não tente executá-lo; não invente que passou.
- **O mod roda empacotado**: teste sempre a build de `build/@A3U`, nunca os `.sqf` soltos.
- **Sem acentos em arquivos `.sqf`** — comentários e strings de log em ASCII, como o resto do addon `core`. Acentos só nos `.md` e no `Stringtable.xml`.
- **Símbolo de moeda** sempre via `A3A_faction_civ get "currencySymbol"`, nunca literal.
- **Ordem de argumentos das strings de moeda**: valor primeiro, símbolo depois (`%1%2` vira `500$`), igual às strings de fast travel já existentes.
- **Cabeçalho de função**: todo `.sqf` novo começa com o bloco de comentário no formato de `A3A/addons/core/functions/FastTravel/fn_fastTravelCost.sqf` (Maintainer, descrição, Arguments, Return Value, Scope, Environment, Public, Dependencies, Example), seguido de `#include "..\..\script_component.hpp"` e `FIX_LINE_NUMBERS()`.
- **Nome da variável de estado**: `A3A_refuelSession`, sempre `setVariable` **local** (sem terceiro argumento de broadcast).
- **Ordem do array de estado**, idêntica em todos os arquivos que a leem:
  `[_refFuel, _lastFuel, _pendingCost, _chargedCost, _chargedLiters, _lastSampleTime, _lastRiseTime, _deniedUntil]`

## Estrutura de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `A3A/addons/core/functions/Refuel/fn_fuelTankCapacity.sqf` | litros do tanque, do config, com fallback |
| `A3A/addons/core/functions/Refuel/fn_refuelCost.sqf` | delta de combustível → créditos, fracionário |
| `A3A/addons/core/functions/Refuel/fn_refuelSessionTick.sqf` | uma amostra: guardas, acúmulo, corte por saldo, débito em bloco |
| `A3A/addons/core/functions/Refuel/fn_refuelSessionClose.sqf` | reconciliação medida, acerto, hint de resumo, limpeza |
| `A3A/addons/core/functions/Refuel/fn_refuelMonitor.sqf` | loop do cliente: detecção de posto, veículos, pagador |
| `A3A/addons/core/CfgFunctions.hpp` | registra a pasta `Refuel` |
| `A3A/addons/core/Params.hpp` | `A3U_refuelCostEnabled`, `A3U_refuelCostPerLiter` |
| `A3A/addons/core/functions/init/fn_initClient.sqf` | inicia o monitor |
| `A3A/addons/scrt/Stringtable.xml` | textos de parâmetro e de hint |

---

### Task 1: Parâmetros de missão e seus textos

**Files:**
- Modify: `A3A/addons/core/Params.hpp:3128` (logo depois do fecho de `A3U_ftCostPerKm`, antes de `class DevelopmentParamsSpacer`)
- Modify: `A3A/addons/scrt/Stringtable.xml:8299` (dentro do container `params`, depois de `STR_params_ftCostPerKm_desc`, antes de `STR_params_development`)

**Interfaces:**
- Consumes: nada
- Produces: as variáveis globais `A3U_refuelCostEnabled` (0 ou 1) e `A3U_refuelCostPerLiter` (0, 1, 2, 3, 5 ou 10), lidas pelas Tasks 2, 4 e 5

- [ ] **Step 1: Adicionar as duas classes de parâmetro**

Em `A3A/addons/core/Params.hpp`, imediatamente após o `};` que fecha `class A3U_ftCostPerKm` (linha 3128) e antes da linha em branco que precede `class DevelopmentParamsSpacer`:

```cpp
    class A3U_refuelCostEnabled : ExperimentalParams
    {
        title = $STR_params_refuelCostEnabled;
        tooltip = $STR_params_refuelCostEnabled_desc;
        values[] = {0, 1};
        texts[] = {$STR_antistasi_dialogs_generic_button_no_text, $STR_antistasi_dialogs_generic_button_yes_text};
        default = 1;
        class dependencies
        {
            class A3U_refuelCostPerLiter
            {
                value = 0;
                lockedByDependency = 1;
            };
        };
    };
    class A3U_refuelCostPerLiter : ExperimentalParams
    {
        title = $STR_params_refuelCostPerLiter;
        tooltip = $STR_params_refuelCostPerLiter_desc;
        values[] = {0, 1, 2, 3, 5, 10};
        texts[] = {"0", "1", "2", "3", "5", "10"};
        default = 2;
    };
```

O bloco `dependencies` é o mesmo padrão de `class autoSave` (`Params.hpp:395-402`): com o toggle em Não, o preço por litro é travado em 0 na tela de parâmetros.

- [ ] **Step 2: Adicionar os quatro textos**

Em `A3A/addons/scrt/Stringtable.xml`, dentro do container `params`, logo após o `</Key>` de `STR_params_ftCostPerKm_desc` (linha 8299):

```xml
            <Key ID="STR_params_refuelCostEnabled">
                <Original>Fuel Stations: charge for refuelling</Original>
            </Key>
            <Key ID="STR_params_refuelCostEnabled_desc">
                <Original>Charges the player's wallet for fuel pumped into a vehicle at a map fuel station. Works with both the vanilla and the ACE refuelling systems.</Original>
            </Key>
            <Key ID="STR_params_refuelCostPerLiter">
                <Original>Fuel Stations: cost per litre</Original>
            </Key>
            <Key ID="STR_params_refuelCostPerLiter_desc">
                <Original>Credits charged per litre pumped. Bigger vehicles have bigger tanks, so they pay more. Zero disables the charge.</Original>
            </Key>
```

- [ ] **Step 3: Verificar in-game**

Empacote e abra a missão. Na tela de parâmetros, seção `Experimental`, confira:
- os dois parâmetros novos aparecem logo abaixo dos quatro de Fast Travel;
- pôr `Fuel Stations: charge for refuelling` em Não trava `Fuel Stations: cost per litre` em 0.

Entre na partida e rode no debug console:

```sqf
hint str [A3U_refuelCostEnabled, A3U_refuelCostPerLiter];
```

Esperado: `[1,2]` com os defaults.

- [ ] **Step 4: Commit**

```bash
git add A3A/addons/core/Params.hpp A3A/addons/scrt/Stringtable.xml
git commit -m "feat: Parametros de custo de combustivel em postos"
```

---

### Task 2: Funções puras de cálculo

**Files:**
- Create: `A3A/addons/core/functions/Refuel/fn_fuelTankCapacity.sqf`
- Create: `A3A/addons/core/functions/Refuel/fn_refuelCost.sqf`
- Modify: `A3A/addons/core/CfgFunctions.hpp:569` (entre o fecho de `class Punishment` e `class REINF`)

**Interfaces:**
- Consumes: `A3U_refuelCostPerLiter` (Task 1)
- Produces:
  - `[_vehicle] call A3A_fnc_fuelTankCapacity` → NUMBER, litros, sempre > 0
  - `[_vehicle, _deltaFuel] call A3A_fnc_refuelCost` → NUMBER, créditos, fracionário, nunca negativo

- [ ] **Step 1: Registrar a pasta no CfgFunctions**

Em `A3A/addons/core/CfgFunctions.hpp`, entre o `};` que fecha `class Punishment` (linha 569) e `class REINF` (linha 571):

```cpp
        class Refuel {
            file = QPATHTOFOLDER(functions\Refuel);
            class fuelTankCapacity {};
            class refuelCost {};
            class refuelMonitor {};
            class refuelSessionClose {};
            class refuelSessionTick {};
        };
```

As três funções que ainda não existem entram já aqui para não precisar mexer neste arquivo de novo. Elas serão criadas nas Tasks 3, 4 e 5 — **o addon não compila até lá**, então este passo e os dois seguintes fazem parte da mesma task e a verificação in-game só acontece no Step 5.

- [ ] **Step 2: Criar `fn_fuelTankCapacity.sqf`**

```sqf
/*
Maintainer: Alisson Oliveira
    Devolve a capacidade do tanque de um veiculo em litros.

    Le ace_refuel_fuelCapacity, cai para fuelCapacity, e por ultimo para uma
    constante. Nunca devolve zero: capacidade zero faria o veiculo abastecer
    de graca, entao veiculo de mod com config incompleto paga um preco
    plausivel em vez de virar brecha.

Arguments:
    <OBJECT> Veiculo

Return Value:
    <NUMBER> Capacidade em litros, sempre maior que zero

Scope: Any, Local Arguments, Local Effect
Environment: Any
Public: Yes
Dependencies:
    Nenhuma

Example:
    [vehicle player] call A3A_fnc_fuelTankCapacity;
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

// * Fallback para veiculo cujo config nao declara capacidade nenhuma.
#define REFUEL_DEFAULT_CAPACITY 100

params [["_vehicle", objNull, [objNull]]];

if (isNull _vehicle) exitWith {
    Error("fuelTankCapacity: veiculo nulo");
    REFUEL_DEFAULT_CAPACITY
};

private _cfg = configOf _vehicle;

// * Mesmo encadeamento de fn_refuelVehicleFromSources.sqf:26-30, com o
// * fallback a mais no fim.
private _capacity = getNumber (_cfg >> "ace_refuel_fuelCapacity");
if (_capacity <= 0) then { _capacity = getNumber (_cfg >> "fuelCapacity") };
if (_capacity <= 0) then { _capacity = REFUEL_DEFAULT_CAPACITY };

_capacity
```

- [ ] **Step 3: Criar `fn_refuelCost.sqf`**

```sqf
/*
Maintainer: Alisson Oliveira
    Converte um aumento de combustivel em creditos.

    Funcao pura: nao le `player`, nao escreve variavel, nao abre UI e nao faz
    rede. Pode ser chamada livremente para exibir um preco.

Arguments:
    <OBJECT> Veiculo abastecido
    <NUMBER> Variacao de `fuel`, 0..1

Return Value:
    <NUMBER> Custo em creditos, fracionario, nunca negativo

Scope: Any, Local Arguments, Local Effect
Environment: Any
Public: Yes
Dependencies:
    A3A_fnc_fuelTankCapacity, A3U_refuelCostPerLiter (parametro de missao)

Example:
    [vehicle player, 0.5] call A3A_fnc_refuelCost;
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

params [["_vehicle", objNull, [objNull]], ["_deltaFuel", 0, [0]]];

if (isNull _vehicle) exitWith {
    Error("refuelCost: veiculo nulo");
    0
};

if (_deltaFuel <= 0) exitWith { 0 };

// * getVariable com default em vez de acesso direto: a funcao e publica e
// * pode ser chamada do debug console antes dos parametros existirem.
private _perLiter = missionNamespace getVariable ["A3U_refuelCostPerLiter", 0];
private _liters = _deltaFuel * ([_vehicle] call A3A_fnc_fuelTankCapacity);

// * Sem arredondar de proposito. Um tick de abastecimento custa fracoes de
// * credito; arredondar aqui faria cada tick virar zero e o abastecimento
// * inteiro sair de graca. O arredondamento acontece uma vez so, na hora de
// * debitar.
(_liters * _perLiter) max 0
```

- [ ] **Step 4: Criar os outros três arquivos como esqueleto temporário**

Para o addon compilar antes das Tasks 3-5, crie `fn_refuelSessionTick.sqf`, `fn_refuelSessionClose.sqf` e `fn_refuelMonitor.sqf` com corpo mínimo:

```sqf
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
```

Cada um será substituído inteiro pela sua task. Não commite este esqueleto sozinho — ele entra no mesmo commit do Step 6.

- [ ] **Step 5: Verificar no debug console**

Empacote, entre na partida a pé perto de um veículo qualquer e rode:

```sqf
private _veh = vehicle player;
if (_veh isEqualTo player) then { _veh = nearestObject [player, "LandVehicle"] };
private _cap = [_veh] call A3A_fnc_fuelTankCapacity;
hint format [
    "%1%4Capacidade: %2 L%4Meio tanque: %3 creditos",
    typeOf _veh, _cap, [_veh, 0.5] call A3A_fnc_refuelCost, toString [10]
];
```

Esperado, com `A3U_refuelCostPerLiter` no default 2: capacidade compatível com o veículo (dezenas para carro, centenas para caminhão) e custo igual a `capacidade × 0.5 × 2`, ou seja, exatamente a capacidade em créditos.

Confira também os casos de borda:

```sqf
hint str [
    [objNull] call A3A_fnc_fuelTankCapacity,        // 100, com Error no log
    [vehicle player, 0] call A3A_fnc_refuelCost,    // 0
    [vehicle player, -0.3] call A3A_fnc_refuelCost  // 0
];
```

- [ ] **Step 6: Commit**

```bash
git add A3A/addons/core/CfgFunctions.hpp A3A/addons/core/functions/Refuel/
git commit -m "feat: Funcoes puras de custo de abastecimento"
```

---

### Task 3: Cobrança de uma amostra

**Files:**
- Modify (substituir inteiro): `A3A/addons/core/functions/Refuel/fn_refuelSessionTick.sqf`
- Modify: `A3A/addons/scrt/Stringtable.xml:17466` (novo container após o fecho de `A3A_Dialogs`)

**Interfaces:**
- Consumes: `A3A_fnc_fuelTankCapacity`, `A3A_fnc_refuelCost` (Task 2); `A3A_fnc_resourcesPlayer`, `SCRT_fnc_misc_deniedHint` (já existentes)
- Produces:
  - `[_vehicle] call A3A_fnc_refuelSessionTick` → Nothing
  - a variável local `A3A_refuelSession` no veículo, no formato `[_refFuel, _lastFuel, _pendingCost, _chargedCost, _chargedLiters, _lastSampleTime, _lastRiseTime, _deniedUntil]`, lida pelas Tasks 4 e 5

- [ ] **Step 1: Adicionar o container de textos**

Em `A3A/addons/scrt/Stringtable.xml`, logo após o `</Container>` que fecha `A3A_Dialogs` (linha 17466) e antes de `<Container name="A3A_OrgPlayers">`:

```xml
        <Container name="A3A_Refuel">
            <Key ID="STR_A3A_refuel_header">
                <Original>Fuel Station</Original>
            </Key>
            <Key ID="STR_A3A_refuel_denied">
                <Original>Not enough credits to keep fuelling. You have %1%2.</Original>
            </Key>
            <Key ID="STR_A3A_refuel_charged">
                <Original>Pumped %1 L for %2%3.&lt;br/&gt;Balance: %4%3</Original>
            </Key>
        </Container>
```

`STR_A3A_refuel_charged` só é usado na Task 4, mas os três textos entram juntos para não voltar neste arquivo.

- [ ] **Step 2: Escrever `fn_refuelSessionTick.sqf`**

```sqf
/*
Maintainer: Alisson Oliveira
    Processa uma amostra de combustivel de um veiculo que esta num posto.

    Calcula o delta desde a amostra anterior, descarta o que nao e
    abastecimento, acumula o custo, corta o combustivel quando o saldo nao
    cobre e debita em bloco. E o coracao da mecanica.

    Nao decide quem paga nem quais veiculos observar: isso e do
    A3A_fnc_refuelMonitor. Aqui o pagador ja e `player`.

Arguments:
    <OBJECT> Veiculo sendo abastecido

Return Value:
    Nothing

Scope: Clients, Local Arguments, Global Effect
Environment: Any
Public: No
Dependencies:
    A3A_fnc_fuelTankCapacity, A3A_fnc_refuelCost, A3A_fnc_resourcesPlayer,
    SCRT_fnc_misc_deniedHint

Example:
    [vehicle player] call A3A_fnc_refuelSessionTick;
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

// * Acima de qualquer uma destas taxas nao e bomba: e setFuel de script
// * (garagem, spawn de veiculo, load de save). A de litros cobre tanque
// * grande; a de fracao cobre tanque pequeno, onde encher tudo de uma vez sao
// * poucos litros e passaria pelo limite em litros. O par erra para o lado
// * seguro: no maximo deixa de cobrar, nunca cobra combustivel que o jogador
// * nao comprou.
#define REFUEL_MAX_LPS 40
#define REFUEL_MAX_FRACTION_PER_SEC 0.4
// * Pendente que dispara a chamada de resourcesPlayer, que faz
// * `[] spawn A3A_fnc_statistics` toda vez (fn_resourcesPlayer.sqf:11) e por
// * isso nao pode ser chamada por tick.
#define REFUEL_COMMIT_THRESHOLD 25
// * O ACE e o refuel nativo continuam bombeando depois do corte, entao o
// * aviso de saldo se repetiria a cada amostra sem este cooldown.
#define REFUEL_DENIED_COOLDOWN 15

params [["_vehicle", objNull, [objNull]]];

if (isNull _vehicle) exitWith { Error("refuelSessionTick: veiculo nulo") };

private _fuel = fuel _vehicle;
private _now = time;

// * Estado da sessao: [_refFuel, _lastFuel, _pendingCost, _chargedCost,
// * _chargedLiters, _lastSampleTime, _lastRiseTime, _deniedUntil].
// * setVariable local de proposito - cada cliente tem a sua propria visao.
private _session = _vehicle getVariable ["A3A_refuelSession", []];

if (_session isEqualTo []) exitWith {
    // * Primeira amostra so estabelece a linha de base. Nunca cobra: nao ha
    // * delta anterior para comparar, e cobrar aqui seria cobrar por
    // * combustivel que ja estava no tanque.
    _vehicle setVariable ["A3A_refuelSession", [_fuel, _fuel, 0, 0, 0, _now, _now, 0]];
};

_session params [
    "_refFuel", "_lastFuel", "_pendingCost", "_chargedCost",
    "_chargedLiters", "_lastSampleTime", "_lastRiseTime", "_deniedUntil"
];

private _delta = _fuel - _lastFuel;
private _capacity = [_vehicle] call A3A_fnc_fuelTankCapacity;

// * Taxa medida contra o tempo real desde a amostra anterior, nao contra o
// * intervalo nominal do loop: sob queda de FPS o sleep estica e um
// * abastecimento normal pareceria um salto de script.
private _elapsed = (_now - _lastSampleTime) max 0.001;
private _litersPerSecond = (_delta * _capacity) / _elapsed;
private _fractionPerSecond = _delta / _elapsed;

if (
    _delta <= 0
    || {_litersPerSecond > REFUEL_MAX_LPS}
    || {_fractionPerSecond > REFUEL_MAX_FRACTION_PER_SEC}
) exitWith {
    // * Consumo do motor ou escrita de script. Desloca a referencia no mesmo
    // * tanto para que a reconciliacao do fechamento nao veja isso como
    // * divergencia, e re-baseia sem cobrar.
    _vehicle setVariable ["A3A_refuelSession", [
        _refFuel + _delta, _fuel, _pendingCost, _chargedCost,
        _chargedLiters, _now, _lastRiseTime, _deniedUntil
    ]];
};

private _cost = [_vehicle, _delta] call A3A_fnc_refuelCost;
private _chargedFuel = _delta;

// * Saldo disponivel desconta o pendente ainda nao debitado. E isso que
// * mantem a bomba pre-paga mesmo com o debito acontecendo em bloco.
private _available = (player getVariable ["moneyX", 0]) - _pendingCost;

if (_cost > _available) then {
    private _affordableCost = _available max 0;
    private _affordableFuel = if (_cost > 0) then { _delta * (_affordableCost / _cost) } else { 0 };
    private _cappedFuel = _lastFuel + _affordableFuel;

    // * setFuel precisa rodar na maquina dona do veiculo, como em
    // * fn_refuelVehicleFromSources.sqf:79-81.
    if (local _vehicle) then {
        _vehicle setFuel _cappedFuel;
    } else {
        [_vehicle, _cappedFuel] remoteExecCall ["setFuel", _vehicle];
    };

    _chargedFuel = _affordableFuel;
    _cost = _affordableCost;
    _fuel = _cappedFuel;

    if (_now >= _deniedUntil) then {
        _deniedUntil = _now + REFUEL_DENIED_COOLDOWN;
        [
            localize "STR_A3A_refuel_header",
            format [
                localize "STR_A3A_refuel_denied",
                round (player getVariable ["moneyX", 0]),
                A3A_faction_civ get "currencySymbol"
            ]
        ] call SCRT_fnc_misc_deniedHint;
    };
};

_pendingCost = _pendingCost + _cost;
_chargedLiters = _chargedLiters + (_chargedFuel * _capacity);
if (_chargedFuel > 0) then { _lastRiseTime = _now };

if (_pendingCost >= REFUEL_COMMIT_THRESHOLD) then {
    private _commit = floor _pendingCost;
    [-_commit] call A3A_fnc_resourcesPlayer;
    _chargedCost = _chargedCost + _commit;
    _pendingCost = _pendingCost - _commit;
};

_vehicle setVariable ["A3A_refuelSession", [
    _refFuel, _fuel, _pendingCost, _chargedCost,
    _chargedLiters, _now, _lastRiseTime, _deniedUntil
]];
```

- [ ] **Step 3: Verificar o caminho normal no debug console**

O monitor ainda não existe, então a amostragem é manual. Entre num veículo, e rode **uma linha por vez**, com alguns segundos entre elas (o intervalo importa: é o que alimenta a guarda de L/s):

```sqf
// 1. prepara: tanque em 20%, dinheiro suficiente
veh = vehicle player; veh setFuel 0.2; player setVariable ["moneyX", 5000, true];
veh setVariable ["A3A_refuelSession", nil];
[veh] call A3A_fnc_refuelSessionTick;
hint str (veh getVariable "A3A_refuelSession");
```

Esperado: array com `_refFuel` e `_lastFuel` iguais a 0.2 e todos os acumuladores em zero.

```sqf
// 2. simula um tick de bomba: +10% de tanque
veh setFuel 0.3;
[veh] call A3A_fnc_refuelSessionTick;
hint str [veh getVariable "A3A_refuelSession", player getVariable "moneyX"];
```

Esperado: `_pendingCost` igual a `0.1 × capacidade × 2` e `_chargedLiters` igual a `0.1 × capacidade`. Se esse valor passou de 25, o dinheiro caiu do `floor` correspondente e `_pendingCost` guardou só o resto; senão o dinheiro está intacto.

```sqf
// 3. consumo: fuel cai. Nao cobra e desloca a referencia.
veh setFuel 0.25;
[veh] call A3A_fnc_refuelSessionTick;
hint str (veh getVariable "A3A_refuelSession");
```

Esperado: `_refFuel` caiu 0.05, `_pendingCost` e `_chargedLiters` inalterados.

```sqf
// 4. salto de script: tanque cheio de uma vez, dentro de um mesmo tick.
// O `set [5, time]` reposiciona _lastSampleTime para agora, senao os
// segundos que voce levou para colar a linha diluiriam a taxa e o salto
// passaria como abastecimento normal.
_s = veh getVariable "A3A_refuelSession"; _s set [5, time];
veh setVariable ["A3A_refuelSession", _s];
veh setFuel 1;
[veh] call A3A_fnc_refuelSessionTick;
hint str [veh getVariable "A3A_refuelSession", player getVariable "moneyX"];
```

Esperado: `_pendingCost` e `_chargedLiters` inalterados, `_refFuel` deslocado para cima, dinheiro intacto.

- [ ] **Step 4: Verificar o corte por falta de saldo**

```sqf
veh = vehicle player; veh setFuel 0.2; player setVariable ["moneyX", 10, true];
veh setVariable ["A3A_refuelSession", nil];
[veh] call A3A_fnc_refuelSessionTick;
```

Depois, numa segunda execução:

```sqf
veh setFuel 1;
[veh] call A3A_fnc_refuelSessionTick;
hint str [fuel veh, player getVariable "moneyX", veh getVariable "A3A_refuelSession"];
```

Esperado: `fuel veh` **voltou** para um valor muito abaixo de 1 — exatamente `0.2 + (10 / (2 × capacidade))` —, o hint de saldo insuficiente apareceu com som de falha, e o pendente ficou em 10 no máximo. Com `moneyX` em 0, `fuel veh` volta a exatamente 0.2 e nada é debitado.

- [ ] **Step 5: Commit**

```bash
git add A3A/addons/core/functions/Refuel/fn_refuelSessionTick.sqf A3A/addons/scrt/Stringtable.xml
git commit -m "feat: Cobranca por amostra de combustivel abastecido"
```

---

### Task 4: Fechamento e reconciliação

**Files:**
- Modify (substituir inteiro): `A3A/addons/core/functions/Refuel/fn_refuelSessionClose.sqf`

**Interfaces:**
- Consumes: `A3A_refuelSession` (Task 3), `A3A_fnc_fuelTankCapacity` (Task 2), `A3A_fnc_resourcesPlayer` e `A3A_fnc_customHint` (já existentes)
- Produces: `[_vehicle] call A3A_fnc_refuelSessionClose` → Nothing. Chamada pela Task 5.

- [ ] **Step 1: Escrever `fn_refuelSessionClose.sqf`**

```sqf
/*
Maintainer: Alisson Oliveira
    Fecha a sessao de abastecimento de um veiculo e acerta a conta.

    Compara o combustivel que o tanque de fato ganhou com o que foi cobrado e
    debita ou estorna a diferenca. E isso que fecha a janela em que se pagou
    por combustivel que depois some - correcao de fuel vinda do servidor,
    dessincronia de MP, load de save no meio, ou o proprio corte por falta de
    saldo.

    Chamada de mais de um lugar do monitor (fim por inatividade, veiculo fora
    do raio, jogador longe do posto), por isso e funcao propria.

Arguments:
    <OBJECT> Veiculo com sessao aberta

Return Value:
    Nothing

Scope: Clients, Local Arguments, Local Effect
Environment: Any
Public: No
Dependencies:
    A3A_fnc_fuelTankCapacity, A3A_fnc_resourcesPlayer, A3A_fnc_customHint

Example:
    [vehicle player] call A3A_fnc_refuelSessionClose;
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

params [["_vehicle", objNull, [objNull]]];

if (isNull _vehicle) exitWith {};

private _session = _vehicle getVariable ["A3A_refuelSession", []];
if (_session isEqualTo []) exitWith {};

// * Limpa antes de qualquer outra coisa: se algo abaixo falhar, a proxima
// * amostra recomeca de uma linha de base limpa em vez de reprocessar esta.
_vehicle setVariable ["A3A_refuelSession", nil];

_session params [
    "_refFuel", "_lastFuel", "_pendingCost", "_chargedCost",
    "_chargedLiters", "_lastSampleTime", "_lastRiseTime", "_deniedUntil"
];

if (!alive _vehicle) exitWith {
    // * `fuel` de destroco nao serve de medida. Cobra o pendente e encerra,
    // * sem resumo: o veiculo explodiu, o jogador tem o que olhar.
    private _commit = round _pendingCost;
    if (_commit > 0) then { [-_commit] call A3A_fnc_resourcesPlayer };
};

private _perLiter = missionNamespace getVariable ["A3U_refuelCostPerLiter", 0];
private _capacity = [_vehicle] call A3A_fnc_fuelTankCapacity;

// * _refFuel acompanhou toda variacao nao cobrada, entao (fuel - _refFuel) e
// * exatamente a soma dos deltas cobrados quando nada anomalo aconteceu.
// * Qualquer divergencia aqui e o que escapou da amostragem.
private _realLiters = (((fuel _vehicle) - _refFuel) max 0) * _capacity;

// * round uma vez so, sobre a diferenca: _chargedCost ja e inteiro (o tick
// * sempre debita floor) e _pendingCost e o resto fracionario nunca debitado.
private _settle = round ((_realLiters * _perLiter) - _chargedCost - _pendingCost);

if (_settle isNotEqualTo 0) then { [-_settle] call A3A_fnc_resourcesPlayer };

private _total = _chargedCost + _settle;

// * Sessao sem cobranca nenhuma nao gera hint. E o caso do veiculo parado no
// * posto sem abastecer e do jogador sem dinheiro, que fecha e reabre sessao
// * enquanto a bomba continua ligada.
if (_total <= 0) exitWith {};

[
    localize "STR_A3A_refuel_header",
    format [
        localize "STR_A3A_refuel_charged",
        round _realLiters,
        _total,
        A3A_faction_civ get "currencySymbol",
        round (player getVariable ["moneyX", 0])
    ]
] call A3A_fnc_customHint;
```

- [ ] **Step 2: Verificar o acerto normal**

Uma linha por vez, com alguns segundos entre elas:

```sqf
veh = vehicle player; veh setFuel 0.2; player setVariable ["moneyX", 100000, true];
veh setVariable ["A3A_refuelSession", nil];
[veh] call A3A_fnc_refuelSessionTick;
antes = player getVariable "moneyX";
```

```sqf
veh setFuel 0.4;
[veh] call A3A_fnc_refuelSessionTick;
[veh] call A3A_fnc_refuelSessionClose;
hint format ["Gasto: %1 | Esperado: %2", antes - (player getVariable "moneyX"), round (0.2 * ([veh] call A3A_fnc_fuelTankCapacity) * A3U_refuelCostPerLiter)];
```

Esperado: os dois números batem, o hint de resumo aparece com os litros e o `A3A_refuelSession` do veículo sumiu (`isNil` ao consultar).

- [ ] **Step 3: Verificar o estorno**

O caso que a reconciliação existe para cobrir — combustível cobrado que some antes do fechamento:

```sqf
veh = vehicle player; veh setFuel 0.2; player setVariable ["moneyX", 100000, true];
veh setVariable ["A3A_refuelSession", nil];
[veh] call A3A_fnc_refuelSessionTick;
antes = player getVariable "moneyX";
```

```sqf
veh setFuel 0.9;
[veh] call A3A_fnc_refuelSessionTick;
hint str (antes - (player getVariable "moneyX"));
```

Anote o valor cobrado. Agora force o combustível de volta **sem passar pelo tick**, simulando uma correção externa, e feche:

```sqf
veh setFuel 0.3;
[veh] call A3A_fnc_refuelSessionClose;
hint format ["Gasto liquido: %1 | Esperado: %2", antes - (player getVariable "moneyX"), round (0.1 * ([veh] call A3A_fnc_fuelTankCapacity) * A3U_refuelCostPerLiter)];
```

Esperado: os dois números batem — o jogador pagou só pelos 0.1 de tanque que sobraram, e a diferença voltou para a carteira.

- [ ] **Step 4: Commit**

```bash
git add A3A/addons/core/functions/Refuel/fn_refuelSessionClose.sqf
git commit -m "feat: Reconciliacao medida ao fim do abastecimento"
```

---

### Task 5: Monitor do cliente e ligação no init

**Files:**
- Modify (substituir inteiro): `A3A/addons/core/functions/Refuel/fn_refuelMonitor.sqf`
- Modify: `A3A/addons/core/functions/init/fn_initClient.sqf:190` (depois de `[] spawn A3A_fnc_clientIdleChecker;`)

**Interfaces:**
- Consumes: `A3A_fnc_refuelSessionTick` (Task 3), `A3A_fnc_refuelSessionClose` (Task 4), `A3U_refuelCostEnabled` e `A3U_refuelCostPerLiter` (Task 1), `A3A_fuelStationTypes` (já publicado por `fn_initZones.sqf:401`)
- Produces: `[] spawn A3A_fnc_refuelMonitor` → Nothing. Último elo: depois desta task a mecânica funciona sozinha.

- [ ] **Step 1: Escrever `fn_refuelMonitor.sqf`**

```sqf
/*
Maintainer: Alisson Oliveira
    Loop do cliente que observa abastecimento em postos de combustivel.

    Fica dormindo enquanto o jogador nao esta perto de um posto. Perto de um,
    escolhe os veiculos candidatos, resolve quem paga e delega a cobranca ao
    A3A_fnc_refuelSessionTick.

    A proximidade do posto nao dispara cobranca: ela so decide quando olhar.
    Sem subida de `fuel` nenhum credito sai.

Arguments:
    Nenhum

Return Value:
    Nothing

Scope: Clients, Local Arguments, Global Effect
Environment: Spawned
Public: No
Dependencies:
    A3A_fnc_refuelSessionTick, A3A_fnc_refuelSessionClose,
    A3A_fuelStationTypes, A3U_refuelCostEnabled, A3U_refuelCostPerLiter

Example:
    [] spawn A3A_fnc_refuelMonitor;
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

#define REFUEL_TICK 1
// * Jogador -> posto: acorda o monitor. Folgado o bastante para cobrir a
// * mangueira do ACE esticada e o veiculo estacionado atras da bomba.
#define REFUEL_STATION_RANGE 40
// * Posto -> veiculo observado.
#define REFUEL_VEHICLE_RANGE 25
// * Sem subida por este tempo, o abastecimento acabou.
#define REFUEL_IDLE_TIMEOUT 3

if (!hasInterface) exitWith {};

if ((missionNamespace getVariable ["A3U_refuelCostEnabled", 0]) isEqualTo 0) exitWith {
    Info("refuelMonitor: cobranca de abastecimento desligada nos parametros");
};

if ((missionNamespace getVariable ["A3U_refuelCostPerLiter", 0]) <= 0) exitWith {
    Info("refuelMonitor: preco por litro zerado, monitor nao iniciado");
};

if (isNil "A3A_fuelStationTypes") exitWith {
    Error("refuelMonitor: A3A_fuelStationTypes indefinido, monitor nao iniciado");
};

private _tracked = [];

while {true} do {
    sleep REFUEL_TICK;

    private _now = time;

    if (isNull player || {!alive player}) then {
        { [_x] call A3A_fnc_refuelSessionClose } forEach _tracked;
        _tracked = [];
        continue;
    };

    // * nearestObjects e teste do motor. Varrer A3A_fuelStations em SQF
    // * custaria uma passada pelo array inteiro a cada segundo de partida.
    private _stations = nearestObjects [player, A3A_fuelStationTypes, REFUEL_STATION_RANGE];

    private _current = [];
    {
        private _station = _x;
        {
            private _veh = _x;
            if !(_veh in _current) then {
                // * Pagador: motorista jogador, se houver; senao o jogador
                // * vivo mais proximo. Cada cliente aplica a mesma regra e so
                // * cobra se ela apontar para ele mesmo - sem lista
                // * compartilhada e sem servidor no caminho.
                private _payer = driver _veh;
                if (!isPlayer _payer) then {
                    _payer = objNull;
                    private _bestDist = 1e10;
                    {
                        private _dist = _x distance _veh;
                        if (_dist < _bestDist) then {
                            _bestDist = _dist;
                            _payer = _x;
                        };
                    } forEach (allPlayers select {alive _x && {!(_x isKindOf "HeadlessClient_F")}});
                };
                if (_payer isEqualTo player) then { _current pushBack _veh };
            };
        } forEach ((nearestObjects [_station, ["LandVehicle", "Air", "Ship"], REFUEL_VEHICLE_RANGE]) select {alive _x});
    } forEach _stations;

    // * Saiu da condicao (veiculo se afastou, jogador saiu do posto, outro
    // * jogador virou o pagador): fecha e acerta a conta.
    {
        if !(_x in _current) then { [_x] call A3A_fnc_refuelSessionClose };
    } forEach _tracked;

    {
        [_x] call A3A_fnc_refuelSessionTick;

        private _session = _x getVariable ["A3A_refuelSession", []];
        if (_session isNotEqualTo []) then {
            _session params [
                "_refFuel", "_lastFuel", "_pendingCost", "_chargedCost",
                "_chargedLiters", "_lastSampleTime", "_lastRiseTime"
            ];
            if (_now - _lastRiseTime > REFUEL_IDLE_TIMEOUT) then {
                // * Fecha para dar o resumo logo depois da bomba parar. O
                // * veiculo continua em _current e a proxima amostra abre uma
                // * sessao nova, que nao cobra nada enquanto nada subir.
                [_x] call A3A_fnc_refuelSessionClose;
            };
        };
    } forEach _current;

    _tracked = _current;
};
```

- [ ] **Step 2: Ligar no init do cliente**

Em `A3A/addons/core/functions/init/fn_initClient.sqf`, logo após a linha 190 (`[] spawn A3A_fnc_clientIdleChecker;`):

```sqf
[] spawn A3A_fnc_refuelMonitor;
```

- [ ] **Step 3: Verificar o caminho feliz in-game**

Empacote, entre na partida e:

1. dirija um carro até um posto marcado no mapa e esvazie o tanque com `vehicle player setFuel 0.1;`;
2. anote `player getVariable "moneyX"`;
3. deixe abastecer — sem ACE, parado ao lado da bomba; com ACE, com a mangueira;
4. quando o combustível parar de subir, espere três segundos.

Esperado: o hint de resumo aparece com os litros e o valor, e o dinheiro caiu na proporção de `litros × A3U_refuelCostPerLiter`.

- [ ] **Step 4: Verificar que proximidade sozinha não cobra**

Estacione ao lado da bomba com o tanque cheio, saia do veículo, espere trinta segundos e confira `player getVariable "moneyX"`.

Esperado: valor idêntico ao do início, nenhum hint na tela. Este é o cenário que a arquitetura promete e o que mais assusta em revisão.

- [ ] **Step 5: Verificar o desligamento**

Reinicie a missão com `A3U_refuelCostEnabled` em Não. Abasteça no posto.

Esperado: abastecimento normal, sem cobrança e sem hint. No log do RPT deve haver a linha de `Info` dizendo que o monitor não iniciou.

- [ ] **Step 6: Commit**

```bash
git add A3A/addons/core/functions/Refuel/fn_refuelMonitor.sqf A3A/addons/core/functions/init/fn_initClient.sqf
git commit -m "feat: Monitor de abastecimento em postos de combustivel"
```

---

### Task 6: Checklist de verificação in-game

**Files:**
- Create: `docs/superpowers/2026-07-31-fuel-station-refuel-cost-checklist.md`

**Interfaces:**
- Consumes: tudo das Tasks 1-5
- Produces: documento de verificação, no mesmo formato de `docs/superpowers/2026-07-31-fast-travel-fuel-cost-checklist.md`

- [ ] **Step 1: Escrever o checklist**

Documento com os doze cenários da spec, ordenados por risco, cada um com preparação, ação e resultado esperado. Ordem, com os mais frágeis primeiro:

1. **Cobrança por proximidade sem abastecer** — estacionar cheio ao lado da bomba trinta segundos. Esperado: nada cobrado, nenhum hint.
2. **MP: dois jogadores no posto** — um abastece, o outro fica a cinco metros. Esperado: só um paga; conferir `moneyX` dos dois antes e depois.
3. **Puxar veículo da garagem e abastecer no posto** — a restauração de combustível da garagem não pode virar cobrança. Esperado: só o combustível da bomba é cobrado.
4. **Sair do raio no meio do abastecimento** — dirigir para longe com o tanque subindo. Esperado: sessão fecha, resumo bate com os litros ganhos.
5. **Saldo acaba no meio** — `player setVariable ["moneyX", 50, true]` com tanque quase vazio. Esperado: combustível para no nível pago, `deniedHint` com som de falha, saldo em zero.
6. **Saldo zero desde o início** — Esperado: nenhum combustível entra.
7. **Abastecer por caminhão-tanque longe de qualquer posto** — Esperado: não cobra.
8. **Sem ACE: abastecer no posto** — Esperado: cobra proporcional aos litros.
9. **Com ACE: abastecer com a mangueira, a pé** — Esperado: mesmo valor do cenário 8 para o mesmo veículo e o mesmo intervalo de combustível.
10. **Carro e caminhão, ambos de 0% a 100%** — Esperado: a razão dos preços é a razão das capacidades de tanque.
11. **`A3U_refuelCostEnabled` em Não** — Esperado: de graça, sem hints, preço travado na UI de parâmetros.
12. **`A3U_refuelCostPerLiter` em 0 com o toggle em Sim** — Esperado: de graça, sem hints, `Info` no RPT.

Registre no documento, com honestidade, o que foi testado e o que não foi — o checklist de fast travel abre exatamente assim, e ele existe para não deixar dúvida sobre o que foi só revisado no papel.

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/2026-07-31-fuel-station-refuel-cost-checklist.md
git commit -m "docs: Checklist de verificacao in-game do custo de abastecimento"
```

---

## Notas de revisão

Pontos que a implementação tende a errar em silêncio, todos já cobertos acima mas que valem um segundo olhar na revisão:

- **`round` só na diferença.** Arredondar por tick zera o custo de abastecimentos lentos. Arredondar duas vezes (no tick e no fechamento) erra por alguns créditos em toda sessão.
- **`setFuel` remoto.** Esquecer o `remoteExecCall` faz o corte por falta de saldo simplesmente não funcionar em veículo de outro jogador ou do servidor — e falhar em silêncio.
- **`_refFuel` deslocando.** Se o caminho de "não cobrar" re-baseia `_lastFuel` mas esquece `_refFuel`, a reconciliação passa a estornar combustível legitimamente pago sempre que o motor consome durante o abastecimento.
- **Hint de resumo com total zero.** Sem a saída antecipada, o jogador sem dinheiro leva um hint a cada três segundos enquanto a bomba estiver ligada.
- **Primeira amostra.** Se a criação da sessão não sair antes do cálculo do delta, a primeira amostra cobra o tanque inteiro que já estava lá.

## Limitação conhecida, não é bug

Devolver o combustível não impede o ACE nem o motor do jogo de já terem tirado aquele combustível do estoque do posto. Um jogador sem dinheiro consegue drenar um posto sem receber nada. Está na spec, seção "Limitações conhecidas", e não deve ser "consertado" durante a implementação.
