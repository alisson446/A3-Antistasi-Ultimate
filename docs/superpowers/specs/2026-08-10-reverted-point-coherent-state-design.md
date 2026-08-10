# Estado coerente do ponto revertido após save com retaliação pendente

Data: 2026-08-10
Branch: `fix/conquest-place-without-fight`

## Objetivo

A correção anterior
(`docs/superpowers/specs/2026-08-07-retaliation-save-exploit-design.md`)
faz o save gravar a posse de um ponto estratégico como sendo ainda do dono
anterior enquanto a retaliação disparada pela captura não for resolvida.
Ela resolve o exploit, mas deixa o ponto revertido num estado incoerente
ao carregar:

1. **Guarnição vazia.** A captura esvazia a guarnição
   (`fn_markerChange.sqf`), e o save grava esse estado vazio. O ponto volta
   inimigo mas sem defensores — exibido como "Decimated" no mapa e
   recapturável de graça, o que enfraquece a própria correção.
2. **Soldados do jogador perdidos.** Soldados que o jogador recrutou para
   guarnecer o ponto ficam gravados no array de guarnição daquele marker.
   Como o ponto volta a ser inimigo, esse investimento (HR + dinheiro) é
   perdido ou fica inconsistente.
3. **Estáticas duplicadas.** A captura move as estáticas do ponto para
   `staticsToSave` como propriedade do jogador. No load, elas são
   recriadas como do jogador **e** o ponto inimigo gera as suas próprias —
   duplicação de armamento no mesmo lugar.

Este design torna o pacote gravado para um ponto pendente internamente
coerente: o ponto volta ao inimigo enfraquecido mas armado, o investimento
do jogador é devolvido, e nada é duplicado.

**Princípio herdado da correção anterior, mantido aqui:** nada disso muda a
sessão viva. Durante o jogo o ponto continua seu, com seus soldados e suas
estáticas. Só o que é *gravado em disco* muda — e portanto só se
materializa no save que for carregado depois.

## Contexto do código atual

### O status "Weakened" já existe, e é derivado

`A3A/addons/core/functions/init/fn_cityinfo.sqf:42-59` define
`_measureGarrison`, que exibe "Garrison: Good / Weakened / Decimated" ao
clicar num marker do mapa, comparando `count (garrison getVariable
[_siteX,[]])` com limiares por tipo de ponto:

```sqf
private _measureGarrison = {
	params ["_siteX", "_textX", "_thresholds"];
	_garrison = count (garrison getVariable [_siteX, []]);
	private _str = switch (true) do {
		case (_garrison >= (_thresholds select 0)): { localize "STR_A3A_cityinfo_garrison_good" };
		case (_garrison >= (_thresholds select 1)): { localize "STR_A3A_cityinfo_garrison_weakened" };
		default { localize "STR_A3A_cityinfo_garrison_decimated" };
	};
	format [_str, _textX]
};
```

Todos os seis tipos de ponto em escopo têm limiares `[good, weakened]`
definidos neste arquivo: aeroporto `[40,20]` (linha 99), resource `[30,10]`
(108), fábrica `[16,8]` (118), outpost `[16,8]` (130), seaport `[20,8]`
(140), base militar `[40,20]` (151). Não existe estado "weakened"
armazenado — é puramente derivado da contagem da guarnição.

**Estes limiares não servem como alvo de dimensionamento.** Eles são
heurísticas de display que não acompanham o tamanho real das guarnições
(ver abaixo): uma guarnição *cheia* de aeroporto frequentemente já exibe
"Weakened". Usá-los como alvo poderia gerar uma guarnição maior que a
cheia. O dimensionamento usa `A3A_fnc_garrisonSize`, não estes números.

### Tamanho nominal de uma guarnição

`A3A/addons/core/functions/CREATE/fn_garrisonSize.sqf:37` retorna
`4 * (_groups max 2)` — uma contagem de **unidades**, derivada do tamanho
do marker, do tipo de ponto e de ser ou não linha de frente. Exemplos:
aeroporto rende 8–56 unidades, outpost 12–36, resource/fábrica/seaport
8–24. Comparando com os limiares acima, fica claro que os dois números não
foram calibrados um contra o outro.

`fn_initGarrisons.sqf:8-21` mostra que o array antigo tem exatamente
`garrisonSize` entradas — preenche com grupos aleatórios e faz `resize`.
Portanto "guarnição cheia" = `garrisonSize` entradas, e é essa a referência
correta para enfraquecer.

### O array antigo reflete baixas de combate

`A3A/addons/core/functions/CREATE/fn_garrisonUpdate.sqf:41-44` remove uma
entrada do array a cada unidade de guarnição morta (`_modeX == -1`,
"remove 1 unit (killed EHs etc)"). Consequência importante para este
design: no momento da captura, o array do ponto reflete apenas os
sobreviventes do assalto do jogador — tipicamente perto de zero. Por isso
**não** se pode tirar um snapshot da guarnição antes da captura e
enfraquecê-lo; o dimensionamento tem que partir do valor nominal
(`garrisonSize`), não do estado no momento da captura.

Existe também `A3A/addons/core/functions/Garrison/fn_getGarrisonStatus.sqf`,
que devolve as mesmas três strings a partir do sistema wurzel. Ele está
registrado em `CfgFunctions.hpp` mas **não é chamado em lugar nenhum** —
código morto. Este design não o utiliza nem o remove.

### Formato dos dois sistemas de guarnição

Ambos são salvos e ambos precisam ser gravados de forma coerente:

- **Array antigo** (`garrison getVariable [_marker, []]`): lista plana de
  strings de tipo de unidade. É o que alimenta o display do mapa acima.
  `fn_initGarrisons.sqf:8-21` mostra como é construído para um ponto
  inimigo novo: preenche com grupos aleatórios da facção até atingir
  `[_marker] call A3A_fnc_garrisonSize` e faz `resize` para esse tamanho.
- **Arrays wurzel** (`%1_garrison` / `%1_requested`): alimentam o spawn
  real. `fn_createGarrison.sqf:3-9` aceita um parâmetro `_lose` = `[LAND,
  HELI, AIR]`, "the amount of lines that should be requested by the marker
  instead of already there" — exatamente o mecanismo de enfraquecimento.

`A3A_fnc_createGarrisonLine` (`fn_createGarrisonLine.sqf`) é **pura**:
recebe uma linha de preferência e um lado, e retorna `[_vehicle, _crew,
_cargoGroup]` sem escrever em variável nenhuma. `A3A_fnc_createGarrison`,
em contraste, escreve direto nas variáveis vivas
(`garrison setVariable [...]`, linhas 56-57) — por isso este design usa a
primeira e não a segunda.

### Custo dos soldados recrutados

`A3A/addons/core/functions/REINF/fn_garrisonAdd.sqf` cobra, por soldado:

```sqf
private _costs = server getVariable _unitType;   // linha 15
...
[-1,-_costs] remoteExec ["A3A_fnc_resourcesFIA",2];   // linha 44: -1 HR, -_costs dinheiro
```

Ou seja: 1 de HR e `server getVariable _unitType` de dinheiro por unidade.
O soldado passa a existir como string de tipo em
`garrison getVariable [_markerX,[]]`.

### Estáticas capturadas

`fn_markerChange.sqf:327-334`, no bloco de captura pelo jogador:

```sqf
private _staticWeapons = nearestObjects [_positionX, ["LandVehicle", "Ship"], _size * 1.5, true];
{
    [_x, teamPlayer, true] call A3A_fnc_vehKilledOrCaptured;
    if !(_x in staticsToSave) then {
        staticsToSave pushBack _x;
    };
} forEach _staticWeapons;
```

O guard `if !(_x in staticsToSave)` é importante: coisas que já eram do
jogador antes da captura não são re-adicionadas. Portanto o conjunto
"adicionado por esta captura" é exatamente o que deve reverter, e a
fronteira desejada (não mexer no que é do jogador) sai naturalmente.

No load, `fn_loadStat.sqf:370-406` recria cada entrada de `staticsX` com
`createVehicle` e a inicializa como do jogador
(`[_veh, teamPlayer] call A3A_fnc_AIVEHinit`), sem checar se já existe algo
equivalente no local — daí a duplicação.

## Design

### Estrutura de dados

A entrada de `A3A_pendingCaptures` ganha um quarto campo:

```
[_marker : STRING, _previousOwner : SIDE, _startTime : NUMBER, _capturedStatics : ARRAY of OBJECT]
```

`_capturedStatics` são os objetos que aquela captura especificamente
adicionou a `staticsToSave`. Acrescentar um quarto elemento é seguro: todas
as leituras existentes usam `#0`, `#1` e `#2`
(`fn_pendingCaptureRemove.sqf`, a poda por idade em `fn_saveLoop.sqf`, e a
construção do HashMap de posse).

`A3A_pendingCaptures` continua **não sendo persistido** — é estado de
sessão apenas.

### O pacote revertido gravado no save

Em `fn_saveLoop.sqf`, para cada marker ainda pendente no momento de salvar
(após a poda por idade já existente), quatro coisas são gravadas de forma
coerente entre si:

1. **Posse** → dono anterior. Já implementado, sem mudança.

2. **Guarnição enfraquecida.** Gera uma guarnição do lado `_previousOwner`
   dimensionada em **metade da força nominal do ponto** —
   `round (([_marker] call A3A_fnc_garrisonSize) / 2)` — e grava no lugar
   do estado vazio atual:
   - array antigo: mesma construção de `fn_initGarrisons.sqf` (preenche com
     grupos aleatórios da facção correspondente e faz `resize`), usando
     esse tamanho pela metade;
   - arrays wurzel: linhas construídas com `A3A_fnc_createGarrisonLine`,
     distribuídas entre `%1_garrison` e `%1_requested` de modo que
     aproximadamente metade das linhas fique como "requisitada" (ausente),
     espelhando o efeito do parâmetro `_lose` de `fn_createGarrison.sqf`.

   Metade da força nominal é imune tanto às baixas de combate quanto à
   calibragem dos limiares de display. O texto exibido no mapa será uma
   faixa abaixo do normal daquele ponto, que em pontos pequenos pode ser
   "Decimated" em vez de "Weakened" — o efeito de jogo pretendido (voltar
   parcial, nem vazio nem cheio) é garantido; a string exata não é.

   A guarnição é gravada como parcial, e a lógica normal de reforço do jogo
   volta a enchê-la ao longo do tempo — não há bloqueio de reforço nem
   estado "weakened" persistente.

3. **Reembolso.** Para cada string de tipo de unidade em
   `garrison getVariable [_marker, []]` pertencente ao jogador, acumula 1
   de HR e `server getVariable _unitType` de dinheiro, e soma esses totais
   aos valores `hr` e `resourcesFIA` que estão sendo gravados. Reembolso
   integral, igual ao que foi cobrado em `fn_garrisonAdd.sqf`.

4. **Estáticas.** Remove `_capturedStatics` da lista de objetos que será
   convertida em `staticsX`, antes da conversão para arrays de
   propriedades. No load, o ponto inimigo gera as suas próprias estáticas
   normalmente.

Todas as quatro operam sobre as cópias locais do que está sendo gravado.
Nenhuma variável viva (`sidesX`, `garrison`, `staticsToSave`, `server`) é
modificada.

## Riscos, efeitos colaterais e mitigações

**Reembolso duplicado (risco principal).** `fn_saveLoop.sqf:147` já soma ao
HR gravado as unidades vivas que satisfaçam
`(_x getVariable ["spawner",false]) and (group _x in (hcAllGroups theBoss)
or (isPlayer (leader _x))) and (side group _x == teamPlayer)`. Se as
unidades de guarnição spawnadas satisfizerem esse filtro, o reembolso
creditaria em cima do que já foi contado — um exploit invertido, gerando
HR e dinheiro a cada save. A leitura do código indica que guarnições não
entram nesse filtro (não são grupos de High Command nem liderados por
jogador), **mas isso deve ser confirmado antes de creditar qualquer
valor**, testando in-game o save com o ponto spawnado e despawnado e
comparando os totais.

**Referências nulas.** `_capturedStatics` guarda referências de objetos que
podem ser destruídos durante a retaliação. A exclusão deve ocorrer enquanto
ainda há identidade de objeto — antes da conversão para arrays de
propriedades em `fn_saveLoop.sqf` (~linha 230) — e tolerar objetos já
destruídos ou nulos.

**String exibida no mapa.** Como o dimensionamento parte de
`A3A_fnc_garrisonSize` e não dos limiares de `fn_cityinfo.sqf`, o texto
exibido para um ponto revertido pode ser "Decimated" em pontos pequenos, e
não literalmente "Weakened". Isso é aceito: o requisito real é o ponto
voltar parcial em vez de vazio ou cheio. Não há acoplamento a constantes de
display, o que também elimina o risco de os dois números saírem de sincronia
no futuro.

**Propriedade do jogador preservada.** Só objetos registrados em
`_capturedStatics` são excluídos. Um veículo estacionado no ponto depois da
captura, ou uma estática comprada/construída ali, continua sendo do jogador
e reaparece no load dentro de território inimigo — comportamento aceito,
equivalente a estacionar em qualquer área inimiga.

**Recapturas sucessivas.** Cada captura cria uma entrada nova com seu
próprio `_capturedStatics` e seu próprio token; o casamento por token já
implementado garante que a resolução de uma retaliação antiga não interfira
numa entrada mais nova.

**Entradas podadas por idade.** A poda de entradas com mais de 3000s já
existente continua valendo e tem precedência: uma entrada podada não recebe
nenhum dos quatro tratamentos, e o ponto salva normalmente como do jogador.

**Performance.** Desprezível — tudo roda uma vez por save, sobre uma lista
de markers pendentes que na prática tem 0 a 2 entradas.

## Verificação

Sem framework de testes automatizados neste ambiente (sem Python/Node; o
linter do repositório não roda aqui). A verificação é revisão de código
mais teste in-game no build empacotado (`build/@A3U`), estendendo
`docs/superpowers/2026-08-07-retaliation-save-exploit-checklist.md`:

- Guarnecer um ponto com retaliação pendente, salvar e recarregar:
  confirmar que HR e dinheiro voltaram integralmente ao pool.
- Confirmar que o mesmo cenário, com o ponto **spawnado** e com o ponto
  **despawnado**, produz o mesmo total — expondo qualquer contagem dupla.
- Confirmar que o ponto revertido volta com guarnição **parcial**: nem
  vazio (recaptura de graça) nem cheio. Conferir clicando no marker que a
  contagem caiu em relação ao normal daquele ponto; a string exibida pode
  ser "Weakened" ou "Decimated" dependendo do tamanho do ponto, e ambas são
  aceitáveis desde que a guarnição exista e seja menor que a cheia.
- Confirmar que o ponto revertido tem estáticas (não está desarmado) e que
  não há estáticas duplicadas/sobrepostas no local.
- Confirmar que um veículo do jogador estacionado no ponto após a captura
  continua sendo do jogador após o load.
- Confirmar que a guarnição enfraquecida volta a crescer com o tempo pela
  lógica normal de reforço.

## Pendência de processo

A branch tem, no momento da escrita deste spec, uma alteração
**TEMP-DEBUG não commitada** em
`A3A/addons/core/functions/Base/fn_markerChange.sqf` que força o envio de
retaliação em toda captura (piso de recursos + checagem de mínimo
comentada). Ela é útil para testar este trabalho também, mas **deve ser
revertida antes de finalizar a branch**:

```
git checkout -- "A3A/addons/core/functions/Base/fn_markerChange.sqf"
```
