# Vestimenta visível dentro de veículo e liberação do roadblock

Data: 2026-08-01
Branch: `refactor/undecover-improvements`

## Objetivo

Duas mudanças no sistema de undercover, independentes entre si mas nos mesmos
arquivos:

1. **Vestimenta dentro do veículo.** Hoje entrar num veículo civil ativa o
   undercover sem olhar para colete, capacete, NVG ou uniforme. Essas peças são
   visíveis pela janela para quem está do lado de fora, então devem bloquear e
   quebrar o disfarce também dentro do veículo. Armas continuam permitidas no
   veículo, por serem consideradas guardadas.

2. **Roadblock deixa de sortear.** Hoje passar por um roadblock inimigo já
   undercover dispara uma rolagem de dados que, com `tierWar` alto, sempre
   descobre o jogador. Essa rolagem é desativada — comentada, não removida.
   Aeroporto, outpost, seaport e milbase seguem intocados.

## Contexto do código atual

### Onde o undercover é ativado

`A3A/addons/core/functions/init/fn_initClient.sqf:331-338` — o event handler
`GetInMan` chama `A3A_fnc_goUndercover` automaticamente ao entrar em qualquer
veículo da lista `undercoverVehicles`, desde que o veículo não esteja
`A3A_reported`.

`undercoverVehicles` é montada em
`A3A/addons/core/functions/init/fn_initVarServer.sqf:471`:
`arrayCivVeh - ["C_Quadbike_01_F"]` mais barcos, helicópteros e aviões civis do
template rebelde. O quadriciclo vanilla é a **única** exclusão por classe em todo
o sistema — não existe outra regra hardcoded por tipo de veículo.

### O bug da vestimenta

`A3A/addons/core/functions/Undercover/fn_canGoUndercover.sqf:60-134` é um
`if/else` sobre `isNull (objectParent player)`:

- **dentro de veículo** (linhas 60-77): valida apenas tipo do veículo,
  `A3A_reported` e cordas de reboque;
- **a pé** (linhas 78-134): valida arma, colete, capacete, NVG, uniforme civil e
  ausência de uniforme.

O bloco de vestimenta está inteiramente dentro do `else`. Entrar no carro pula
tudo.

`A3A/addons/core/functions/Undercover/fn_goUndercover.sqf:97-178` repete a mesma
estrutura no loop de monitoramento, que roda a cada segundo. No ramo de veículo
(linhas 98-145) a roupa nunca é reavaliada; a checagem de vestimenta só existe no
ramo de a pé, na linha 159.

### A divergência do capacete

O critério de capacete blindado está escrito de duas formas diferentes:

- `fn_canGoUndercover.sqf:100` usa `headgear player in allArmoredHeadgear`;
- `fn_goUndercover.sqf:159` usa
  `getNumber (configfile >> "CfgWeapons" >> headgear player >> "ItemInfo" >> "HitpointsProtectionInfo" >> "Head" >> "armor") > 2`.

`allArmoredHeadgear` não é atribuída diretamente em lugar nenhum: é criada
dinamicamente em `A3A/addons/core/functions/Ammunition/fn_configSort.sqf:96`, que
percorre `allCategories` e faz `missionNamespace getVariable ("all" + _x)`. A
categoria `"ArmoredHeadgear"` é atribuída em
`A3A/addons/core/functions/Ammunition/fn_equipmentClassToCategories.sqf:134-138`
com o critério **`armor > 0`**.

Ou seja, a lista curada é mais rígida que o `armor > 2` do loop. O efeito prático
é um buraco: existe capacete com armor 1-2 que **impede ativar** o undercover mas
**não tira** o jogador dele se for vestido depois.

### A rolagem do roadblock

`fn_goUndercover.sqf:184-217`, dentro do loop de 1 segundo:

```sqf
private _base = [_secureBases, player] call BIS_fnc_nearestPosition;
private _onDetectionMarker = detectionAreas findIf {...} != -1;
private _onBaseMarker = player inArea _base;
private _baseSide = sidesX getVariable [_base, sideUnknown];
if ((_onBaseMarker || _onDetectionMarker) && (_baseSide != teamPlayer) && (_base != _lastBaseInside)) then
{
    if (_base in airportsX || _onDetectionMarker) exitWith { _reason = "Airport"; };
    if ("outpost" in _base || _onDetectionMarker) exitWith { _reason = "Outpost"; };
    if ("seaport" in _base || _onDetectionMarker) exitWith { _reason = "Seaport"; };
    if ("milbase" in _base || _onDetectionMarker) exitWith { _reason = "Milbase"; };

    private _aggro = if (_baseSide == Occupants) then {aggressionOccupants + (tierWar * 10)} else {aggressionInvaders + (tierWar * 10)};
    if (random 100 < _aggro) exitWith
    {
        private _roadblocks = controlsX select {isOnRoad(getMarkerPos _x)};
        if (_base in _roadblocks || _onDetectionMarker) then { _reason = "Roadblock"; };
    };
    _lastBaseInside = _base;
};
```

Comportamento resultante:

- **Aeroporto, outpost, seaport, milbase: 100%.** Os `exitWith` vêm antes da
  rolagem. Entrar no marcador queima o disfarce sem sorte envolvida.
- **Roadblock: rolagem única** de `random 100 < aggro + tierWar * 10`.
  `aggressionOccupants` vai de 0 a 100
  (`A3A/addons/core/functions/Base/fn_calculateAggression.sqf:30`) e `tierWar` de
  1 a 10 (`A3A/addons/core/functions/OrgPlayers/fn_tierCheck.sqf:19-20`). Com
  `tierWar` 10 o termo vale 100 sozinho: **todo roadblock descobre o jogador,
  sempre**, mesmo com agressão zero. O piso é 10%.
- A rolagem é única por base porque, ao falhar, `_lastBaseInside = _base` executa
  e aquela base não é mais testada. Como `_lastBaseInside` guarda **uma** base
  só, um trajeto A → B → A rola de novo em A.
- `milAdministrationsX` entram na mesma rolagem, mas nenhum dos `if` internos
  casa com elas: a rolagem passa, nenhum motivo é definido, e como o `exitWith`
  impede `_lastBaseInside = _base`, a base é re-rolada a cada segundo sem nunca
  produzir efeito.
- O marcador de roadblock é um retângulo de 30×30 m
  (`A3A/addons/core/functions/init/fn_generateRoadblock.sqf:24`).

### Punições existentes

| Motivo | Marca veículo (`A3A_reported`) | Marca jogador (`compromised` 30 min) |
|---|---|---|
| `Reported` | sim (em veículo) | sim (a pé) |
| `VNoCivil`, `VCompromised`, `VTowRopes` | não | não |
| `SpotBombTruck`, `Highway`, `NoFly` | sim | não |
| `Airport`, `Roadblock`, `Outpost`, `Seaport`, `Milbase` | sim (em veículo) | sim (a pé) |
| `clothes` (a pé, sem inimigo perto) | não | não |
| `clothes2` (a pé, com inimigo perto) | não | sim |

`compromised` expira em 30 minutos in-game. `A3A_reported` **não expira**: só é
limpo passando o veículo pela caixa de veículos
(`A3A/addons/core/functions/Base/fn_vehicleBoxRestore.sqf:68-69`).

O gatilho de "inimigo perto" usado por `clothes2` é
`(_x knowsAbout player > 1.4) || (_x distance player < 350)`, sobre `allUnits`
filtrado por `side` em `Invaders` ou `Occupants`.

### Outras regras por tipo de veículo

Não existe nenhuma outra exclusão por classe além do quadriciclo. As demais
distinções são por categoria:

- `fn_goUndercover.sqf:135` — `isKindOf "Land"` restringe a regra *Highway*
  (fora de estrada com inimigo a menos de 350 m) a veículos terrestres;
- `fn_goUndercover.sqf:182` — `isKindOf "Air"` faz aeronaves pularem toda a
  checagem de marcadores, delegada a `A3A_fnc_airspaceControl`;
- `A3A/addons/core/functions/Base/fn_airspaceControl.sqf:28-54` — separa heli
  civil, heli militar e jato, cada um com alcance e altura próprios;
- barcos não têm regra própria: não são `Land` (escapam do *Highway*) e não são
  `Air` (checagem de marcador normal, inclusive seaports).

## Decisões

| Decisão | Escolha |
|---|---|
| Itens que bloqueiam no veículo | colete, capacete blindado, NVG, uniforme não-civil, ausência de uniforme |
| Armas no veículo | permitidas |
| Caso especial para veículo aberto | nenhum — regra uniforme para todo veículo |
| Critério de capacete | `allArmoredHeadgear` nos dois arquivos |
| Punição no veículo, sem inimigo perto | só perde o disfarce |
| Punição no veículo, com inimigo perto | `compromised` 30 min **e** veículo `A3A_reported` |
| Gatilho de "inimigo perto" | idêntico ao de a pé: `knowsAbout > 1.4` **ou** `distance < 350` |
| Rolagem do roadblock | comentada, não removida |
| Aeroporto, outpost, seaport, milbase | inalterados, seguem em 100% |
| `milAdministrationsX` | sem mudança direta; a re-rolagem inútil some junto |

Descartado: identificar veículos abertos por `isKindOf`, por `crewVulnerable` ou
por lista configurável. O quadriciclo vanilla já está fora de
`undercoverVehicles`, então o caso não se paga.

## Arquitetura

### Componente novo: `A3A_fnc_undercoverGearCheck`

Arquivo `A3A/addons/core/functions/Undercover/fn_undercoverGearCheck.sqf`,
registrado em `A3A/addons/core/CfgFunctions.hpp` dentro de `class Undercover`
(linhas 825-830), ao lado de `canGoUndercover`, `goUndercover` e
`initUndercover`.

Motivo de existir: a regra de vestimenta está escrita duas vezes hoje, com
critérios diferentes, e foi essa duplicação que produziu a divergência do
capacete. Uma função com uma responsabilidade única — *"esta aparência passa como
civil?"* — elimina a classe inteira de bug.

```
Argumentos:
    _inVehicle : BOOL : se true, armas não são consideradas

Retorno:
    [_ok, _reasons, _hintText]
    _ok       : BOOL   : true se a aparência passa como civil
    _reasons  : ARRAY  : strings curtas de diagnóstico, ex. ["Vest visible"]
    _hintText : STRING : texto pronto para A3A_fnc_customHint, vazio se _ok

Escopo: Local
Ambiente: Any
```

Itens verificados:

| Item | Condição | A pé | Em veículo |
|---|---|---|---|
| Arma | `primaryWeapon`, `secondaryWeapon` ou `handgunWeapon` não vazio | bloqueia | permitido |
| Colete | `vest player != ""` | bloqueia | bloqueia |
| Capacete | `headgear player in allArmoredHeadgear` | bloqueia | bloqueia |
| NVG | `hmd player != ""` | bloqueia | bloqueia |
| Uniforme suspeito | `uniform player != ""` e fora de `A3A_faction_civ get "uniforms"` | bloqueia | bloqueia |
| Sem uniforme | `uniform player == ""` | bloqueia | bloqueia |

A função **não exibe hint**. Ela devolve dados; quem decide o que fazer é o
chamador. Isso é o que permite que `canGoUndercover` mostre o texto e recuse,
enquanto o loop de `goUndercover` apenas define um motivo.

`_hintText` é consumido só por `canGoUndercover`, que precisa listar ao jogador
exatamente quais peças o impediram. O loop de `goUndercover` ignora esse retorno
e usa as strings fixas dos motivos (`clothesVeh`, `clothesVeh2`), seguindo o que
o `switch` já faz com todos os outros motivos.

O texto é montado acumulando os fragmentos já existentes no `Stringtable.xml`
(`STR_A3A_fn_undercover_canGoUn_no_reason_weapon`, `..._vest`, `..._helmet`,
`..._ngv`, `..._uniform`, `..._naked`) sobre a base
`STR_A3A_fn_undercover_canGoUn_no_while`, exatamente como
`fn_canGoUndercover.sqf:86-123` já faz. Nenhuma dessas strings é nova.

### `fn_canGoUndercover.sqf`

O `if/else` das linhas 60-134 passa a chamar `A3A_fnc_undercoverGearCheck` nos
**dois** ramos:

- ramo de veículo: mantém as checagens de tipo, `A3A_reported` e cordas de
  reboque, e acrescenta a chamada com `_inVehicle = true`;
- ramo de a pé: mantém `compromised` e cordas de reboque, e substitui as linhas
  88-123 pela chamada com `_inVehicle = false`.

A ordem dos `exitWith` do ramo de veículo não muda: tipo de veículo, veículo
reportado e cordas continuam tendo prioridade sobre a vestimenta, para que a
mensagem mostrada seja a mais específica.

Também sai a linha 50, `private _roadblocks = controlsX select {...}`, que é
calculada e nunca usada — a linha 57 recalcula a mesma expressão inline.

### `fn_goUndercover.sqf`

**Loop, ramo de veículo (linhas 98-145).** Acrescentar a chamada de
`A3A_fnc_undercoverGearCheck` com `_inVehicle = true` logo antes da regra
*Highway* (linha 135), ou seja, depois de tipo de veículo, `A3A_reported`,
cordas, explosivos ACE e no-fly zone. Ao falhar, define:

- `clothesVeh2` se
  `{((side _x == Invaders) || (side _x == Occupants)) && {(_x knowsAbout player > 1.4) || (_x distance player < 350)}} count allUnits > 0`;
- `clothesVeh` caso contrário.

No momento em que o motivo é definido, o veículo é guardado numa variável do
escopo externo ao loop. Os casos `Highway` e `SpotBombTruck` existentes releem
`objectParent player` lá no `switch` e quebrariam se o jogador saísse do veículo
nesse intervalo; os motivos novos não repetem esse padrão. Os antigos ficam como
estão, fora do escopo desta spec.

**Loop, ramo de a pé (linha 159).** Substituir a condição inline pela chamada com
`_inVehicle = false`. É aqui que o critério de capacete muda de `armor > 2` para
`allArmoredHeadgear` (`armor > 0`), alinhando o loop ao portão de entrada que já
era mais rígido.

**`switch` (linhas 239-334).** Dois `case` novos:

- `clothesVeh` — exibe o hint e nada mais;
- `clothesVeh2` — exibe o hint, aplica
  `player setVariable ["compromised", dateToNumber [..., (date select 4) + 30]]`
  e `_veh setVariable ["A3A_reported", true, true]` no veículo capturado.

**Rolagem do roadblock (linhas 208-215).** Comentar o cálculo de `_aggro` e o
`if (random 100 < _aggro) exitWith { ... }` inteiro, com um comentário explicando
o motivo e como reativar.

A linha seguinte, `_lastBaseInside = _base;`, **fica**. Hoje ela só executa
quando a rolagem falha; sem a rolagem passa a executar sempre, que é o
comportamento desejado — a base é registrada como visitada e nada acontece.

O motivo `"Roadblock"` vira inalcançável. O `case "Roadblock"` do `switch` e a
string `STR_A3A_fn_undercover_goUn_detect_roadb` ficam intactos: descomentar o
bloco restaura o comportamento antigo sem nenhuma outra edição.

Os `exitWith` de aeroporto, outpost, seaport e milbase estão **antes** do trecho
comentado e não são afetados. As `detectionAreas` também não mudam: elas já caem
no `exitWith` de aeroporto na linha 191.

### `Stringtable.xml`

Duas chaves novas em `A3A/addons/core/Stringtable.xml`:

- `STR_A3A_fn_undercover_goUn_no_reason_veh_1` — para `clothesVeh`;
- `STR_A3A_fn_undercover_goUn_no_reason_veh_2` — para `clothesVeh2`, incluindo o
  aviso de que o veículo foi marcado.

As chaves existentes `STR_A3A_fn_undercover_goUn_no_reason_1` e `_2` não servem
porque dizem literalmente *"A weapon is visible"*, falso no caso do veículo.

Só o elemento `<Original>` é preenchido, em inglês, seguindo o padrão do arquivo.
Os demais idiomas presentes no arquivo (Italian, French, Czech, Russian, Turkish,
Korean, Chinesesimp) caem no fallback do `<Original>`.

## Fluxo de dados

```
GetInMan (fn_initClient.sqf:331-338)
  └─> A3A_fnc_goUndercover
        ├─> A3A_fnc_canGoUndercover
        │     ├─> A3A_fnc_undercoverGearCheck [_inVehicle]
        │     └─> hint + recusa, ou libera
        └─> loop 1s
              ├─> ramo veículo: tipo, reported, cordas, ACE,
              │     A3A_fnc_undercoverGearCheck [true], Highway
              ├─> ramo a pé: ACE medic,
              │     A3A_fnc_undercoverGearCheck [false], compromised, cordas
              ├─> Air? pula checagem de marcador (airspaceControl assume)
              └─> marcador: aeroporto/outpost/seaport/milbase = 100%
                            roadblock = [rolagem comentada]
                    └─> switch de motivos: hint + punições
```

## Efeitos colaterais aceitos

- **Passageiro queima o carro inteiro.** O bloco de
  `fn_goUndercover.sqf:225-233` já remove o `captive` de todos os jogadores do
  veículo quando o disfarce de um cai. Um passageiro de colete passa a derrubar o
  disfarce de todos. Comportamento pré-existente, mantido — mas agora dispara com
  muito mais frequência.
- **Loop a pé fica mais rígido.** Capacete com armor 1-2, que hoje não tira o
  jogador do undercover, passa a tirar. É o preço de fechar a divergência, e
  alinha o loop ao portão de entrada.
- **Punição dupla é inédita.** `clothesVeh2` é o primeiro motivo do sistema a
  marcar o jogador (`compromised`, 30 min) e o veículo (`A3A_reported`,
  permanente) ao mesmo tempo. Com o gatilho de 350 m sem exigência de linha de
  visão, dirigindo isso dispara com facilidade.

## Fora de escopo

- `fn_canGoUndercover.sqf:141-147` continua impedindo **ativar** o undercover
  perto de base inimiga, e roadblocks entram nessa lista. O marcador é um
  retângulo 30×30, então `A3A_fnc_sizeMarker`
  (`A3A/addons/core/functions/Base/fn_sizeMarker.sqf`) devolve
  `vectorMagnitude [30,30]` ≈ 42, e o raio de bloqueio `_size * 2` é ≈ 85 m.
  Passar por um roadblock já undercover fica livre, mas ligar o undercover a
  menos de ~85 m de um continua barrado.
- A checagem de `compromised` do jogador não existe no ramo de veículo de
  `fn_canGoUndercover`: um jogador marcado pode entrar num carro e reativar o
  undercover na hora. Inconsistência pré-existente, não tratada aqui.
- Os casos `Highway` e `SpotBombTruck` continuam relendo `objectParent player` no
  `switch`.
- Nenhuma mudança em `A3A_fnc_airspaceControl`, na regra *Highway* ou nos
  critérios de aeroporto, outpost, seaport e milbase.

## Verificação

Não há Python nem Node neste ambiente e o linter do repositório não roda, então a
verificação é revisão de código mais teste in-game com o mod empacotado em
`build/@A3U`. O checklist in-game acompanha a implementação, no mesmo formato dos
checklists já existentes em `docs/superpowers/`:

1. Entrar em carro civil **com colete** → undercover recusado, com hint.
2. Entrar **com fuzil e sem colete** → undercover ativa normalmente.
3. Undercover no carro, vestir colete longe de inimigos → perde o disfarce, sem
   `compromised`, carro **não** marcado; tirar o colete reativa.
4. Undercover no carro, vestir colete com inimigo a menos de 350 m → perde o
   disfarce, `compromised` 30 min, carro marcado permanentemente.
5. Capacete com armor 1-2 → bloqueia nos dois casos, a pé e no carro.
6. Atravessar roadblock inimigo undercover, várias vezes, com `tierWar` alto →
   **nunca** quebra.
7. Entrar em marcador de outpost undercover → quebra na hora, como antes.
8. Voar undercover perto de outpost → `airspaceControl` inalterado.
9. Dirigir fora de estrada com inimigo a menos de 350 m → regra *Highway*
   inalterada.
