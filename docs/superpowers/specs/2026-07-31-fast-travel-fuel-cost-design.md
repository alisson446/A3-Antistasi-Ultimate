# Custo de combustível no Fast Travel

Data: 2026-07-31
Branch: `feat/fuel-economy-overhaul`

## Objetivo

Cobrar créditos por fast travel, proporcionais à distância percorrida, simulando o
combustível que o jogador gastaria se dirigisse até o destino. Quando o saldo não
cobre a viagem, o fast travel é negado com uma mensagem pelo emissor padrão do mod,
antes do teleporte e antes da tela preta com timer.

## Contexto do código atual

O fast travel vivo é `A3A_fnc_fastTravelRadio`
(`A3A/addons/core/functions/Dialogs/fn_fastTravelRadio.sqf`), acionado por
`A3A/addons/scrt/UILayouts/menu.hpp:338`. O fluxo é: clique no mapa via
`onMapSingleClick` (linha 63) → cerca de 12 guardas de validação (linhas 82-140) →
bloco de teleporte com `cutText BLACK` e timer (linhas 142-232).

A GUI em `A3A/addons/gui/functions/GUI/fn_fastTravelTab.sqf` é código WIP inativo:
chama `A3A_fnc_fastTravel` e `A3A_fnc_canFastTravelToLocation`, que não existem, e
o `mainDialog` nunca é aberto de fora do próprio conjunto de abas. **Está fora do
escopo desta spec.**

O rally point tem **dois** pontos de entrada, não um:

1. o desvio em `fn_fastTravelRadio.sqf:74`, que chama
   `SCRT_fnc_rally_travelToRallyPoint` antes de qualquer validação normal;
2. uma `addAction` na bandeira do HQ, em `fn_initClient.sqf:519`, que chama a mesma
   função diretamente.

Por isso a cobrança do rally precisa morar dentro de
`A3A/addons/scrt/Rally/fn_rally_travelToRallyPoint.sqf`, e não no `fastTravelRadio`.

Carteiras existentes:

- jogador: `player getVariable "moneyX"`, alterado por `A3A_fnc_resourcesPlayer`
  (corta em zero, `fn_resourcesPlayer.sqf:8`);
- facção: `server getVariable "resourcesFIA"`, alterado por `A3A_fnc_resourcesFIA`
  via `remoteExec` no servidor (serializa com `waitUntil {!resourcesIsChanging}` e
  também corta em zero).

Emissores de mensagem: `SCRT_fnc_misc_deniedHint` para negativas (é `customHint` +
som de falha) e `BIS_fnc_guiMessage` para confirmação Sim/Não, já usado com preço em
`fn_FIAskillAdd.sqf:27`.

## Decisões

| Decisão | Escolha |
|---|---|
| Fatores do custo | distância × multiplicador de veículo |
| Distância | linha reta (`distance2D`), não rota por estrada |
| Quem paga viagem normal | carteira do jogador (`moneyX`) |
| Quem paga rally point | carteira do jogador (`moneyX`) |
| Quem paga movimento de High Command | caixa da facção (`resourcesFIA`) |
| Saldo suficiente | diálogo de confirmação Sim/Não antes de debitar |
| Saldo insuficiente | bloqueia e emite `SCRT_fnc_misc_deniedHint` |
| Configuração | 3 toggles + taxa por km, seção `Experimental` |

Distância em linha reta porque calcular rota real exigiria `calculatePath` num
clique de mapa; a taxa por km absorve o desvio médio.

## Arquitetura

Pasta nova `A3A/addons/core/functions/FastTravel/`, registrada em
`A3A/addons/core/CfgFunctions.hpp` com `file = QPATHTOFOLDER(functions\FastTravel);`.
Fica em `core` porque o addon `scrt` também precisa chamar, e a dependência
scrt → core já existe.

Três funções, com uma fronteira clara entre cálculo e efeito colateral.

### `A3A_fnc_fastTravelCost` — cálculo puro

```
Args:   [_unit, _destPos]
        _unit    OBJECT   — referência: player, ou leader do grupo em modo HC
        _destPos POSITION — destino final (world pos)
Return: NUMBER — créditos, arredondado, nunca negativo
Env:    Any (unscheduled ok)
```

Sem UI, sem rede, sem `player`, sem escrita de variável. Lê apenas `vehicle _unit`,
`position _unit` e o global `A3U_ftCostPerKm`. É a única parte verificável fora de
jogo real, e é o que a GUI WIP poderá consumir se um dia for reativada.

```sqf
_dist = (position _unit) distance2D _destPos;   // metros
_mult = multiplicador do veículo de _unit;
_cost = round((_dist / 1000) * A3U_ftCostPerKm * _mult);
```

Multiplicadores. **A ordem dos testes importa**, porque tanques também casam com
outras classes:

| Veículo | Teste | Mult |
|---|---|---|
| A pé | `vehicle _unit isEqualTo _unit` | 0.5 |
| Aéreo | `isKindOf "Air"` | 3.0 |
| Tanque / APC de esteira | `isKindOf "Tank"` | 3.0 |
| Caminhão / APC de roda | `isKindOf "Truck_F"` ou `isKindOf "Wheeled_APC_F"` | 2.0 |
| Fallback (carro, quad, moto) | — | 1.0 |

Não há entrada para `Boat`: `fn_fastTravelRadio.sqf:52-56` já nega fast travel se
qualquer unidade do grupo estiver num barco, e
`fn_rally_travelToRallyPoint.sqf:5` exige o jogador a pé. Um barco cairia no
fallback 1.0, que é um valor sensato — não criar caso especial para código
inalcançável. Anfíbios como o Marshall são `Wheeled_APC_F`, não `Boat`, então passam
pela guarda e pagam 2.0 normalmente.

### `A3A_fnc_fastTravelCharge` — transação

```
Args:   [_unit, _destPos, _mode, _destName]
        _mode     STRING — "player" | "rally" | "hc"
        _destName STRING — nome do destino para o diálogo (opcional, default "")
Return: NUMBER — -1 = abortar a viagem; >= 0 = valor cobrado
Env:    Scheduled (usa BIS_fnc_guiMessage)
```

Sequência:

1. Toggle do `_mode` desligado → retorna `0` sem cobrar.
2. Custo via `A3A_fnc_fastTravelCost`. Custo `<= 0` → retorna `0`, sem diálogo.
3. Seleciona a carteira: `"hc"` → `resourcesFIA` do server; `"player"` e `"rally"`
   → `moneyX` do jogador.
4. Saldo `<` custo → `SCRT_fnc_misc_deniedHint` com custo e saldo, retorna `-1`.
   Saldo exatamente igual ao custo é permitido.
5. `BIS_fnc_guiMessage` com destino, distância, custo e saldo restante.
   "Não" → retorna `-1`, sem mensagem adicional.
6. Debita e retorna o valor cobrado.

Retorna NUMBER em vez de BOOL porque o chamador precisa do valor para o reembolso
(ver abaixo).

É o único lugar do mod que sabe quem paga o quê. Os três call sites não repetem
nenhuma regra de carteira.

Os três call sites já rodam dentro de `spawn`, então nenhum precisa mudar de
ambiente para acomodar o `guiMessage`.

### `A3A_fnc_fastTravelRefund` — estorno

```
Args:   [_amount, _mode]
Return: Nothing
Env:    Any
```

Devolve o valor pela mesma carteira que `fastTravelCharge` usaria para aquele
`_mode`. Existe para manter o conhecimento de carteiras confinado à pasta
`FastTravel`, em vez de duplicar a escolha jogador-vs-facção no `fastTravelRadio`.

## Pontos de inserção

### `fn_fastTravelRadio.sqf` — viagem normal e HC

As guardas de validação terminam na linha 140. A linha 142 abre o bloco que calcula
`_positionX` (143) e o tempo do timer (144). O gate entra **entre as linhas 145 e
147**, imediatamente antes de `disableUserInput true` + `cutText BLACK`:

```sqf
private _ftMode = ["player", "hc"] select _esHC;
private _costUnit = if (_esHC) then {_boss} else {player};
private _charged = [_costUnit, _positionX, _ftMode, [_base] call A3A_fnc_getLocationMarkerName]
                   call A3A_fnc_fastTravelCharge;
if (_charged < 0) exitWith { if (!_esHC) then { openMap false } };
```

Um único ponto cobre os dois modos, porque HC e viagem individual compartilham esse
bloco. O destino é `_positionX`, o mesmo alvo que a linha 144 usa para o timer, e
não `getMarkerPos _base`.

O `openMap false` no abort replica a limpeza da linha 234, que o `exitWith`
pularia. Só se aplica ao caso não-HC, como na linha 234.

`_costUnit` é `player` no caso não-HC, mesmo quando o jogador não é o líder do
grupo. A linha 144 usa `position _boss` para o timer; para o custo o que importa é
de onde o jogador sai.

### `fn_rally_travelToRallyPoint.sqf` — rally point

Entre as linhas 41 e 43, também logo antes de `disableUserInput true`:

```sqf
private _charged = [player, _positionX, "rally", localize "STR_A3AP_rally_header"]
                   call A3A_fnc_fastTravelCharge;
if (_charged < 0) exitWith {};
```

Cobre os dois pontos de entrada do rally de uma vez.

Nenhum `openMap false` aqui: essa função não abre o mapa.

## Reembolso

`fn_fastTravelRadio.sqf:171-173` tem um cancelamento tardio: quando `limitedFT` é 1
ou 2 e outro jogador entra num veículo do grupo durante a contagem regressiva, a
viagem é abortada — mas o dinheiro já saiu. É alcançável em multiplayer. Nesse
`exitWith`, chamar `A3A_fnc_fastTravelRefund` com `_charged` e `_ftMode`.

**Requisito de código:** a política de reembolso deve ficar marcada com comentários
de âncora nos três lugares que a decidem — o ponto que estorna e os dois que
deliberadamente não estornam — de forma que um grep encontre todos de uma vez.
A política é provisória e deve ser fácil de revisitar.

Casos deliberadamente sem reembolso:

- `fn_fastTravelRadio.sqf:194-196`, `findEmptyPosition` falhando: aborta no meio do
  teleporte, com parte do grupo já movida. A viagem parcial aconteceu.
- Custo arredondando para 0: nunca houve cobrança.

## Parâmetros

Seção `Experimental` de `A3A/addons/core/Params.hpp` (herdam `lockOnSave = 0` da
classe `ExperimentalParams`, então nenhum trava saves). Viram variáveis globais pelo
nome da classe, como `A3U_AITakeFromArsenal` já faz.

| Classe | Valores | Textos | Default |
|---|---|---|---|
| `A3U_ftCostPlayer` | `{0,1}` | Não / Sim | 1 |
| `A3U_ftCostRallyPoint` | `{0,1}` | Não / Sim | 1 |
| `A3U_ftCostHighCommand` | `{0,1}` | Não / Sim | 1 |
| `A3U_ftCostPerKm` | `{5,10,15,20,30,50}` | idem | 20 |

Sem subclasse `class difficulty`, seguindo `A3U_AITakeFromArsenal`.

Multiplicadores de veículo ficam como constantes no código, não como parâmetros.

Escala com o default de 20/km, tendo a caixa de revive (2100 créditos) como
referência: 5 km de carro = 100; 15 km de carro = 300; 25 km de APC = 1000; 25 km de
tanque = 1500.

## Strings

Todas em `A3A/addons/scrt/Stringtable.xml`, onde já vivem tanto os `STR_params_*`
quanto os `STR_A3A_Dialogs_fast_travel_*`.

- 4 pares título/tooltip para os parâmetros novos;
- `STR_A3A_Dialogs_fast_travel_cost_confirm` — destino, distância, custo, saldo
  restante;
- `STR_A3A_Dialogs_fast_travel_cost_denied` — custo e saldo do jogador;
- `STR_A3A_Dialogs_fast_travel_cost_denied_hc` — custo e caixa da facção.

Símbolo de moeda sempre via `A3A_faction_civ get "currencySymbol"`, nunca literal.

## Concorrência

`A3A_fnc_resourcesPlayer` corta em zero. `A3A_fnc_resourcesFIA` serializa com
`waitUntil {!resourcesIsChanging}` e também corta em zero. Dois jogadores cobrando a
facção ao mesmo tempo podem ler um saldo levemente defasado no passo 4, mas nenhum
consegue deixar o caixa negativo. Nenhum lock adicional será implementado.

## Verificação

Não há framework de teste unitário para SQF no projeto. O que existe é o linter
`Tools/sqfvalidator/sqflint.py -d A3A/addons`, invocado por
`Tools/validate_antistasi.ps1`.

**Estático:** rodar o linter depois de cada arquivo novo. Pega erro de sintaxe, que
em SQF de outra forma só apareceria como falha silenciosa em runtime.

**Fórmula:** `fastTravelCost` é pura, então pode ser chamada no debug console em
jogo — `[player, [X,Y,0]] call A3A_fnc_fastTravelCost` com posições de distância
conhecida — conferindo contra a tabela de multiplicadores, sem abrir diálogo e sem
gastar dinheiro.

**Matriz manual in-game:**

| # | Cenário | Esperado |
|---|---|---|
| 1 | A pé vs. de carro, mesma distância | carro custa exatamente 2× o do a pé |
| 2 | Saldo insuficiente | `deniedHint`, sem teleporte, sem débito |
| 3 | Recusar no diálogo | sem débito, mapa volta ao normal |
| 4 | Rally pelos dois caminhos (menu FT e `addAction` da bandeira) | ambos cobram |
| 5 | Modo HC | debita `resourcesFIA`, `moneyX` intacto |
| 6 | Cada toggle em Não | viagem correspondente de graça, sem diálogo |
| 7 | `A3U_ftCostPerKm` em 5 e em 50 | custo escala linear |
| 8 | Cancelamento tardio (2º jogador entra no veículo, `limitedFT` 1 ou 2) | reembolso integral |

Os cenários 4, 5 e 8 só aparecem em condições específicas e são os que a
implementação tende a quebrar sem ninguém notar.

## Fora de escopo

- A GUI WIP `fn_fastTravelTab.sqf` e o `mainDialog`, inativos.
- Rota por estrada em vez de linha reta.
- Consumo de combustível de veículos fora do fast travel, apesar do nome da branch.
- Multiplicadores de veículo como parâmetro de missão.
