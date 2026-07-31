# Custo de combustível ao abastecer em postos

Data: 2026-07-31
Branch: `feat/fuel-economy-overhaul`

## Objetivo

Descontar créditos da carteira do jogador quando um veículo é abastecido num posto
de combustível, proporcionalmente à quantidade que entrou no tanque. Veículos
maiores têm tanque maior e por isso pagam mais, sem tabela de classes: o preço sai
dos litros de fato abastecidos.

Funciona igual no reabastecimento nativo do jogo e no do ACE. Quando o saldo acaba
no meio, o combustível para de entrar e o jogador é avisado pelo emissor padrão do
mod.

Companheira da spec `2026-07-31-fast-travel-fuel-cost-design.md`, que cobra o
combustível simulado do fast travel. Esta cobra o combustível real.

## Contexto do código atual

Os postos já são catalogados no init do servidor,
`A3A/addons/core/functions/init/fn_initZones.sqf:300-317`: `A3A_fuelStationTypes`
guarda as classes (do `mapInfo` do mapa ou de uma lista padrão) e `A3A_fuelStations`
os objetos encontrados no mapa. Ambos viram `publicVariable` nas linhas 400-401,
então estão disponíveis em qualquer cliente. Com ACE, cada posto recebe 250 L na
linha 315. O estoque dos postos é salvo e restaurado
(`fn_saveLoop.sqf:507-515` e `fn_loadStat.sqf:463-473`).

O mod **não tem ação própria de abastecer**. Sem ACE, o reabastecimento no posto é o
comportamento nativo do engine, apoiado no estoque de combustível do objeto
(`getFuelCargo` / `setFuelCargo`, que o código de save já manipula). Com ACE, é o
bico do `ace_refuel`. Nos dois casos, o único efeito observável em comum é `fuel`
do veículo subir — e é sobre isso que esta spec constrói.

Peças reaproveitadas:

- carteira do jogador: `player getVariable "moneyX"`, alterada por
  `A3A_fnc_resourcesPlayer` (`fn_resourcesPlayer.sqf`), que corta em zero e faz
  `[] spawn A3A_fnc_statistics` **a cada chamada** (linha 11) — o que proíbe
  chamá-la por tick;
- litros do tanque: o encadeamento `ace_refuel_fuelCapacity` → `fuelCapacity` que
  `A3A/addons/garage/Refuel/fn_refuelVehicleFromSources.sqf:26-30` já usa;
- localidade de `setFuel`: precisa rodar na máquina dona do veículo, como o
  `remoteExecCall ["setFuel", owner _vehicle]` da linha 79-81 do mesmo arquivo;
- mensagens: `A3A_fnc_customHint` para informação, `SCRT_fnc_misc_deniedHint` para
  negativa;
- CBA está disponível e `CBA_fnc_addPerFrameHandler` já é usado no repositório.

## Decisões

| Decisão | Escolha |
|---|---|
| Fonte que cobra | somente postos do mapa (`A3A_fuelStationTypes`) |
| Fontes que não cobram | caminhão-tanque, jerrycan, garagem, barris |
| Fórmula | litros abastecidos × preço por litro |
| Litros | delta de `fuel` × capacidade do tanque, do config |
| Diferença entre veículos | vem da capacidade do tanque, sem multiplicador de classe |
| Quem paga | carteira do jogador (`moneyX`) |
| Preço por território | único no mapa inteiro |
| Momento da cobrança | pós-fato, por combustível já medido no tanque |
| Saldo insuficiente | corta o combustível no nível pago e emite `deniedHint` |
| Acerto final | reconciliação medida, com estorno nos dois sentidos |
| Detecção | monitor de delta no cliente, agnóstico a vanilla/ACE |
| Configuração | 1 toggle + 1 preço por litro, seção `Experimental` |

A escolha de detectar por delta de `fuel`, em vez de interceptar o abastecimento, é
a única que atende vanilla e ACE com o mesmo código e sem depender de função interna
do ACE — dependência que não é verificável fora do jogo, dada a restrição de
verificação do projeto.

A proximidade do posto **não** dispara cobrança: ela só decide quando o monitor
observa. Sem subida de `fuel` não há débito. Estacionar ao lado da bomba sem
abastecer não custa nada.

## Arquitetura

Pasta nova `A3A/addons/core/functions/Refuel/`, registrada em
`A3A/addons/core/CfgFunctions.hpp` com `file = QPATHTOFOLDER(functions\Refuel);`,
no mesmo formato do bloco `FastTravel` (linha 360). Fica em `core` porque depende de
`A3A_fuelStationTypes` e da carteira, ambos de `core`.

Quatro funções, com a mesma fronteira da spec de fast travel: cálculo puro separado
de efeito colateral.

### `A3A_fnc_fuelTankCapacity` — cálculo puro

```
Args:   [_vehicle]
        _vehicle OBJECT
Return: NUMBER — capacidade do tanque em litros, sempre > 0
Env:    Any (unscheduled ok)
```

Lê `ace_refuel_fuelCapacity` do config do veículo; se 0, cai para `fuelCapacity`; se
ainda 0, devolve a constante de fallback `REFUEL_DEFAULT_CAPACITY` (100 L).

O fallback existe porque devolver 0 faria o veículo abastecer de graça. Veículo de
mod com config incompleto deve pagar um preço plausível, não virar brecha.

### `A3A_fnc_refuelCost` — cálculo puro

```
Args:   [_vehicle, _deltaFuel]
        _deltaFuel NUMBER — variação de `fuel`, 0..1
Return: NUMBER — custo em créditos, fracionário, nunca negativo
Env:    Any (unscheduled ok)
```

```sqf
_litros = _deltaFuel * ([_vehicle] call A3A_fnc_fuelTankCapacity);
_custo  = _litros * A3U_refuelCostPerLiter;
```

**Não arredonda.** Um tick de abastecimento de caminhão pode custar frações de
crédito; arredondar aqui faria cada tick virar 0 e o abastecimento inteiro sair de
graça. O arredondamento acontece uma única vez, na hora de debitar.

Junto com `fuelTankCapacity`, é a parte conferível no debug console sem gastar
dinheiro.

### `A3A_fnc_refuelMonitorInit` — inicialização do cliente

```
Args:   nenhum
Return: Nothing
Env:    Any
```

Chamada uma vez em `A3A/addons/core/functions/init/fn_initClient.sqf`, junto dos
outros sistemas de cliente (perto dos `spawn` da faixa das linhas 187-193).

Sai sem fazer nada se `A3U_refuelCostEnabled` é 0, se `A3U_refuelCostPerLiter` é 0,
ou se `A3A_fuelStationTypes` não existe (mapa sem postos, ou init do servidor ainda
não propagado). Caso contrário registra o PFH de `REFUEL_TICK` segundos apontando
para `A3A_fnc_refuelMonitorTick`.

Desligado, a mecânica não custa nem um tick.

### `A3A_fnc_refuelMonitorTick` — o trabalho

```
Args:   [_args, _pfhHandle]  (assinatura de CBA_fnc_addPerFrameHandler)
Return: Nothing
Env:    Unscheduled
```

Faz a detecção, a cobrança, o corte e a reconciliação. É a única função com efeito
colateral.

## Estado por sessão de abastecimento

O estado vive no próprio veículo, em `setVariable` **local** (sem broadcast):

```sqf
_veh setVariable ["A3A_refuelSession", [
    _refFuel,        // referência de combustível da sessão (ver Reconciliação)
    _lastFuel,       // amostra do tick anterior
    _pendingCost,    // custo acumulado ainda não debitado (fracionário)
    _chargedCost,    // créditos já debitados nesta sessão
    _chargedLiters,  // litros já cobrados nesta sessão
    _lastSampleTime, // instante da amostra anterior, para calcular a taxa em L/s
    _lastRiseTime,   // instante da última subida de fuel
    _deniedUntil     // cooldown do aviso de saldo insuficiente
]];
```

Escolhido em vez de um hashmap global porque morre junto com o veículo, é
naturalmente por cliente (cada jogador tem sua própria visão) e não precisa de
código de limpeza próprio.

## Fluxo do tick

Constantes do arquivo, não parâmetros de missão:

| Constante | Valor | Papel |
|---|---|---|
| `REFUEL_TICK` | 1 s | período do PFH |
| `REFUEL_STATION_RANGE` | 40 m | jogador → posto, para acordar o monitor |
| `REFUEL_VEHICLE_RANGE` | 25 m | posto → veículo acompanhado |
| `REFUEL_MAX_LPS` | 40 L/s | acima disso é `setFuel` de script |
| `REFUEL_IDLE_TIMEOUT` | 3 s | sem subida, fecha a sessão |
| `REFUEL_COMMIT_THRESHOLD` | 25 créditos | pendente que dispara o débito |
| `REFUEL_DENIED_COOLDOWN` | 15 s | entre avisos de saldo insuficiente |

1. **Acordar.** `nearestObjects [player, A3A_fuelStationTypes, REFUEL_STATION_RANGE]`
   — teste do motor, não varredura de `A3A_fuelStations`. Vazio: fecha as sessões
   abertas e sai. É o caminho de quase todos os ticks da partida.
2. **Candidatos.** Veículos a até `REFUEL_VEHICLE_RANGE` de um posto encontrado.
3. **Pagador.** Se há jogador no assento de motorista, é ele; senão, o jogador vivo
   mais próximo do veículo. O cliente só continua se o resultado for `player`.
4. **Delta.** `fuel _veh` menos `_lastFuel`.
   - `<= 0` (motor consumindo): desloca `_refFuel` no mesmo tanto, re-baseia
     `_lastFuel`, não cobra;
   - taxa acima de `REFUEL_MAX_LPS`, medida como litros do delta divididos pelo
     tempo desde `_lastSampleTime` (e não pelo `REFUEL_TICK` nominal, que não se
     sustenta sob queda de FPS): trata como `setFuel` de script (garagem, spawn,
     load de save), desloca `_refFuel`, re-baseia, não cobra;
   - `> 0` dentro da taxa: segue para o passo 5.
5. **Custo.** `[_veh, _delta] call A3A_fnc_refuelCost` entra em `_pendingCost`;
   os litros entram em `_chargedLiters`. `_lastRiseTime` recebe o instante atual.
6. **Saldo disponível.** `(player getVariable ["moneyX", 0]) - _pendingCost`. É o que
   mantém a bomba pré-paga mesmo com o débito acontecendo em blocos.
7. **Corte por falta de saldo.** Se o custo do tick passa do saldo disponível,
   calcula quantos litros o dinheiro ainda cobria, devolve o combustível a esse nível
   com `setFuel`, ajusta `_pendingCost` e `_chargedLiters` para o que foi coberto e
   emite `SCRT_fnc_misc_deniedHint`, respeitando `_deniedUntil`. Saldo zero: nenhum
   combustível entra.
8. **Débito.** Chama `A3A_fnc_resourcesPlayer` com `-(floor _pendingCost)` quando o
   pendente passa de `REFUEL_COMMIT_THRESHOLD`, soma o mesmo valor em `_chargedCost`
   e guarda o resto fracionário em `_pendingCost`. A
   chamada é rara de propósito: `resourcesPlayer` faz `spawn A3A_fnc_statistics` toda
   vez, e uma chamada por segundo sujaria o scheduler.
9. **Fechamento.** `REFUEL_IDLE_TIMEOUT` sem subida, veículo fora do raio, jogador
   longe do posto ou veículo destruído: executa a reconciliação, debita o saldo
   final, emite um hint com litros e créditos totais por `A3A_fnc_customHint` e
   apaga `A3A_refuelSession`. Um hint por abastecimento, não por tick.

`setFuel` do passo 7 roda direto se o veículo é local; senão,
`[_veh, _nivel] remoteExecCall ["setFuel", _veh]`, que entrega ao dono do objeto.

## Reconciliação

`_refFuel` **não** é simplesmente o combustível do início da sessão: é uma
referência que se desloca junto com toda variação que o monitor decidiu não cobrar
(consumo do motor, salto identificado como `setFuel` de script). Com isso,
`fuel _veh - _refFuel` equivale exatamente à soma dos deltas cobrados enquanto nada
anômalo acontece.

No fechamento:

```sqf
_litrosReais  = ((fuel _veh - _refFuel) max 0) * ([_veh] call A3A_fnc_fuelTankCapacity);
_custoDevido  = _litrosReais * A3U_refuelCostPerLiter;
_acerto       = round (_custoDevido - _chargedCost - _pendingCost);
```

O `round` incide uma única vez, sobre a diferença: `_chargedCost` já é inteiro (o
passo 8 sempre debita `floor`) e `_pendingCost` é o resto fracionário ainda não
debitado, então arredondar aqui fecha a conta inteira da sessão de uma vez.

`_acerto` negativo estorna, positivo debita, ambos por `A3A_fnc_resourcesPlayer`. O
jogador termina pagando pelos litros que o tanque de fato ganhou, medidos no
veículo.

Isso fecha a janela em que já se debitou um bloco de créditos por combustível que
depois some — correção de `fuel` vinda do servidor, dessincronia de MP, load de save
no meio, ou o próprio corte do passo 7. Qualquer anomalia entre amostras vira um
acerto no fim, em vez de dinheiro perdido.

## Pagador em multiplayer

Regra determinística, avaliada igual em todas as máquinas: motorista jogador, se
houver; senão o jogador vivo mais próximo do veículo. Cada cliente aplica a regra e
só cobra se ela apontar para ele mesmo. Não há lista compartilhada nem servidor no
caminho.

Uma dessincronia de posição pode fazer dois clientes se acharem os mais próximos por
alguns ticks, ou nenhum. O prejuízo é limitado a poucos créditos porque o débito é
pequeno por tick, e a reconciliação do cliente que fechar a sessão acerta a conta
pelo combustível realmente medido.

## Guardas e falsos positivos

- **`setFuel` por script** (garagem, spawn de veículo, load de save): pega pela taxa
  acima de `REFUEL_MAX_LPS`. Abastecimento real fica muito abaixo disso em qualquer
  veículo.
- **Caminhão-tanque estacionado dentro dos 25 m de uma bomba**: o abastecimento é
  cobrado como se fosse do posto. Aceito. Distinguir a fonte exigiria ler estado
  interno do ACE, que é a dependência que esta arquitetura evita.
- **IA e civis abastecendo sem jogador por perto**: o passo 3 não encontra pagador,
  então nada acontece — nem cobrança, nem corte.
- **Veículo cheio**: delta zero, nenhum custo.

## Parâmetros

Seção `Experimental` de `A3A/addons/core/Params.hpp`, logo abaixo dos `A3U_ft*`
(linha 3121), herdando `lockOnSave = 0` de `ExperimentalParams`. Viram variáveis
globais pelo nome da classe.

| Classe | Valores | Textos | Default |
|---|---|---|---|
| `A3U_refuelCostEnabled` | `{0,1}` | Não / Sim | 1 |
| `A3U_refuelCostPerLiter` | `{0,1,2,3,5,10}` | idem | 2 |

`A3U_refuelCostEnabled` declara `class dependencies` travando
`A3U_refuelCostPerLiter` em 0 com `lockedByDependency = 1` quando está em Não —
mesmo padrão de `autoSave` / `autoSaveInterval` (`Params.hpp:395-402`). Assim o preço
some da UI quando a mecânica está desligada.

O monitor exige as duas condições: toggle em Sim **e** preço maior que zero.

Sem subclasse `class difficulty`, seguindo `A3U_AITakeFromArsenal` e os `A3U_ft*`.

Escala com o default de 2 créditos/litro, tendo o dinheiro inicial do jogador (500) e
a caixa de revive (2100) como referência. Encher do zero: quad ~40, offroad ~120,
Hunter ~240, caminhão ~600, helicóptero ~1400, tanque ~2400. Os litros exatos saem do
config de cada veículo, então esses números são ordem de grandeza, não promessa.

## Strings

Todas em `A3A/addons/scrt/Stringtable.xml`, onde já vivem os `STR_params_*` e o
`STR_fuelstation`.

- `STR_params_refuelCostEnabled` e `_desc`;
- `STR_params_refuelCostPerLiter` e `_desc`;
- `STR_A3A_refuel_header` — título dos dois hints;
- `STR_A3A_refuel_charged` — litros abastecidos, créditos cobrados, saldo restante;
- `STR_A3A_refuel_denied` — créditos que faltaram e saldo do jogador.

Símbolo de moeda sempre via `A3A_faction_civ get "currencySymbol"`, nunca literal.

## Verificação

Não há framework de teste unitário para SQF no projeto, e o linter
(`Tools/sqfvalidator/sqflint.py`) não roda nesta máquina por falta de Python. A
verificação é revisão de código mais teste in-game com o mod empacotado de
`build/@A3U`.

**Fórmula:** `A3A_fnc_fuelTankCapacity` e `A3A_fnc_refuelCost` são puras e podem ser
chamadas no debug console — `[vehicle player] call A3A_fnc_fuelTankCapacity`,
`[vehicle player, 0.5] call A3A_fnc_refuelCost` — sem cobrar nada.

**Matriz manual in-game:**

| # | Cenário | Esperado |
|---|---|---|
| 1 | Ficar parado no posto sem abastecer | nada é cobrado |
| 2 | Sem ACE: abastecer no posto | cobra proporcional aos litros |
| 3 | Com ACE: abastecer com o bico, a pé | cobra igual ao cenário 2 |
| 4 | Carro e caminhão do mesmo 0% ao mesmo 100% | caminhão custa na proporção das capacidades |
| 5 | Saldo acaba no meio | combustível para no nível pago, `deniedHint`, saldo em zero |
| 6 | Saldo zero desde o início | nenhum combustível entra |
| 7 | `A3U_refuelCostEnabled` em Não | abastece de graça, sem hints, preço travado na UI |
| 8 | `A3U_refuelCostPerLiter` em 0 com toggle em Sim | abastece de graça, sem hints |
| 9 | Abastecer por caminhão-tanque longe de qualquer posto | não cobra |
| 10 | Puxar veículo da garagem e abastecer no posto | só o abastecimento do posto é cobrado |
| 11 | Sair do raio no meio do abastecimento | sessão fecha, conta bate com os litros ganhos |
| 12 | MP: dois jogadores no posto, um abastecendo | só um paga |

Os cenários 5, 10, 11 e 12 são os que a implementação tende a quebrar sem ninguém
notar.

## Limitações conhecidas

Devolver o combustível não impede o ACE nem o engine de já terem tirado aquele
combustível do estoque do posto (250 L com ACE, persistido no save). Um jogador sem
dinheiro consegue drenar um posto sem receber combustível. Impedir de verdade
exigiria desconectar o bico do ACE por função interna, que é a dependência que esta
arquitetura evita de propósito.

## Fora de escopo

- Consumo de combustível ao dirigir, apesar do nome da branch.
- Cobrança da caixa da facção (`resourcesFIA`) em vez da carteira do jogador.
- Cobrar reabastecimento por caminhão-tanque, jerrycan, barris ou garagem.
- Preço variável por controle de território.
- Reembolsar o estoque do posto quando o combustível é devolvido por falta de saldo.
- Ação própria de abastecer, com diálogo de confirmação antes do gasto.
