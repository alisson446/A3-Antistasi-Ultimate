# Checklist de verificação in-game — custo de combustível no abastecimento em posto

Nada disto foi testado. Python não está instalado nesta máquina, então o linter
`Tools/sqfvalidator/sqflint.py` não rodou em nenhum commit, e o jogo não foi
aberto. A revisão de código foi a única barreira até aqui.

As Tasks 1–5 que implementam a mecânica de cobrança foram todas commitadas e
revisadas, mas nenhuma foi verificada in-game ainda. Cada item abaixo está
pendente de execução manual. Não marque nada como "passou" sem ter rodado o
teste no jogo.

A ordem abaixo não é arbitrária: os itens 1 e 2 são os de maior risco — se o
sistema de cobrança não dispara e se o toggle de desligamento não funciona, os
restantes nunca serão verificados. Itens 3–7 testam isolação entre cenários (um
não quebra o outro). Itens 8–10 testam escala e cobrança correta. Itens 11–12
testam toggles e configurações. Itens 13–14 foram adicionados na revisão final
do plano para expor, respectivamente, o bug de reconciliação corrigido nessa
revisão (abastecimento pequeno, abaixo do limiar de commit) e um falso positivo
em potencial das guardas de taxa (tanque grande enchendo rápido).

Referências: spec em
`docs/superpowers/specs/2026-07-31-fuel-station-refuel-cost-design.md`, plano em
`docs/superpowers/plans/2026-07-31-fuel-station-refuel-cost.md`.

---

## 0. Parâmetros aparecem no setup

Na tela de setup, dropdown de tipo de parâmetros na opção **4** (agrupa Extender,
Experimental, Development). Sob OPÇÕES EXPERIMENTAIS devem aparecer duas
entradas novas:

- **Fuel Stations: charge for refuelling** (`A3U_refuelCostEnabled`) — Não/Sim, default Sim
- **Fuel Stations: cost per litre** (`A3U_refuelCostPerLiter`) — 0/1/2/3/5/10, default 2

**Falha:** qualquer texto aparecendo como `STR_params_refuelCost...` cru significa
chave de stringtable não encontrada.

Com a missão rodando, no debug console:

```sqf
hint str [A3U_refuelCostEnabled, A3U_refuelCostPerLiter]
```

Esperado: `[1,2]` com os defaults (ou outra combinação de `{0,1,2,3,5,10}` para
o preço, conforme as configurações escolhidas no setup).

---

## 1. Cobrança dispara apenas ao abastecer, não por proximidade  ← COMECE POR AQUI

Este é o item mais provável de falhar e o mais difícil de diagnosticar depois.

Não há interceptação de nenhum "comando de abastecimento": a arquitetura real
(ver seções "Arquitetura" e "Fluxo do tick" da spec) é um monitor de cliente que
acorda quando o jogador está perto de um posto (`REFUEL_STATION_RANGE`, 40 m) e
amostra `fuel` dos veículos candidatos a cada segundo. A sessão de um veículo
é criada na primeira amostra em que ele é visto perto do posto — essa primeira
amostra só estabelece a linha de base (`_refFuel`/`_lastFuel`) e nunca cobra.
A partir da segunda amostra, qualquer aumento de `fuel` (delta positivo, dentro
das taxas de guarda) vira cobrança. A proximidade sozinha não gera custo porque,
sem abastecimento de verdade, `fuel` não sobe e o delta é zero — não porque
exista um "comando" separado esperado.

**Teste:** com dinheiro suficiente, estacione um veículo **cheio** ao lado de
uma bomba de combustível. Fique próximo do veículo (dentro dos 40 m do posto e
25 m do veículo) por trinta segundos. Não abasteça.

Esperado: **nenhuma cobrança**, nenhum hint, saldo intacto. O veículo continua
cheio.

**Se receber débitos sem abastecer:** o monitor está detectando um delta de
`fuel` que não existe, ou a guarda de taxa (`REFUEL_MAX_LPS`/
`REFUEL_MAX_FRACTION_PER_SEC`) está deixando passar um falso positivo. Procure
em `A3A/addons/core/functions/Refuel/fn_refuelSessionTick.sqf` o cálculo de
`_delta` e as guardas de taxa.

---

## 2. Multiplayer: dois jogadores no mesmo posto

Cenário essencial para garantir isolação: um jogador abastece enquanto outro fica
próximo. Apenas o pagador (motorista do veículo ou jogador vivo mais próximo)
deve ter seu saldo debitado.

**Preparação:** dois jogadores humanos na mesma missão. Um dirige até um posto de
combustível com um veículo vazio (0%). O outro fica estacionado a aproximadamente
5 metros do primeiro jogador (ambos dentro dos 40 m do posto que ativam o
monitor em cada cliente — `REFUEL_STATION_RANGE`).

**Teste:** o primeiro jogador abre o menu de abastecimento e leva o tanque de 0%
a 100% (ex: Offroad ~60L, custo 60 créditos com `A3U_refuelCostPerLiter = 1`).

Esperado antes: anotar `moneyX` de ambos os jogadores antes de começar.
Esperado depois: saldo do jogador que abasteceu cai 60 créditos. Saldo do outro
jogador fica **intacto** — nenhuma cobrança. A regra de pagador é: se o veículo
tem motorista jogador, cobra dele; senão cobra do jogador vivo mais próximo.

Se ambos os saldos caírem ou se o outro jogador sofrer débito, o sistema errou
no critério de quem paga.

---

## 3. Puxar veículo da garagem não dispara cobrança de restauração

Quando um veículo é restaurado na garagem (via `setFuel` ou `setDamage`), esse
combustível não deve ser cobrado. Somente o combustível adicionado pela bomba de
combustível do mapa deve gerar cobrança.

**Teste:** ir para qualquer garagem rebelde, puxar um veículo vazio (0% de
combustível). Observe o nível de combustível subir para o padrão da garagem —
isso é restauração, não abastecimento no posto.

Esperado: **nenhuma cobrança** durante a restauração, saldo intacto. Depois,
dirija até uma bomba de combustível no mapa e abasteça de, digamos, 50% para
100%. Agora sim, deve cobrar apenas pelo abastecimento da bomba (50% do tanque).

Se a restauração da garagem disparar cobrança, o sistema errou no gatilho de
inicialização: está linkando ambos os tipos de `setFuel`. A solução é
desacoplar a sessão para ativar apenas em bombas de combustível válidas (mapas
do mapa, não do script).

---

## 4. Sair do raio no meio do abastecimento finaliza a sessão

O sistema deve encerrar o cálculo de cobrança se o jogador dirigir para longe da
bomba enquanto a sessão de abastecimento ainda está aberta (o tanque ainda está
subindo).

**Teste:** estacione um veículo a 5 metros de uma bomba, com 0% de combustível
e `A3U_refuelCostPerLiter = 1`. Abra o menu de abastecimento e espere o tanque
começar a encher. Assim que vir o nível subir (cerca de 3-5 segundos), dirija
para mais de 40 metros de distância da bomba — além do `REFUEL_STATION_RANGE`
(40 m), que é o maior dos dois raios da mecânica e garante que o monitor pare
de observar o posto.

Esperado: a sessão fecha imediatamente. O resumo de cobrança deve bater com os
litros que entraram na bomba (em créditos: litros × taxa).

Se a sessão continuar aberta quando você sai do raio, o sistema está ignorando
a distância e vai cobrar pela duração total, não pelos litros reais.

---

## 5. Saldo insuficiente no meio do abastecimento para o combustível

O motor deve parar de abastecer e reverter quando o saldo acaba, não deixar o
combustível "em suspenso".

**Teste:** defina `player setVariable ["moneyX", 50, true]` no debug console.
Dirija-se a uma bomba com o tanque quase vazio (ex: 5%). Com `A3U_refuelCostPerLiter = 1`,
você consegue 50 litros antes de ficar sem dinheiro. Abra o menu de abastecimento.

Esperado: o tanque sobe até um ponto (aproximadamente 55%, dependendo da
capacidade do tanque). Depois, o abastecimento para. Um `deniedHint` aparece
citando o custo e saldo **com som de falha** (`A3AP_UiFailure`). O saldo cai a
zero. Se tentar abrir o menu novamente, nada entra; a bomba não funciona sem
dinheiro.

Se o tanque subir acima do esperado ou se o dinheiro não chegar a zero, o
sistema errou no cálculo de quanto combustível cabe no saldo restante.

---

## 6. Saldo zero desde o início: nenhum combustível entra

**Teste:** defina `player setVariable ["moneyX", 0, true]`. Dirija para uma
bomba com o tanque vazio (0%).

Esperado: ao abrir o menu de abastecimento, absolutamente nada entra. O tanque
continua em 0%. Nenhum hint de erro é necessário neste ponto; o sistema apenas
não faz nada. Se você tiver qualquer débito (mesmo que mínimo), o sistema errou
no teste de saldo antes de calcular o custo.

---

## 7. Abastecimento por caminhão-tanque longe da bomba: sem cobrança

Caminhões-tanque (p.ex: `O_Fuel_Truck_F`) podem abastecer veículos a distância,
sem estar acoplados a nenhuma bomba de combustível do mapa. Essa fonte de
combustível **não deve gerar cobrança**.

**Teste:** estacione um caminhão-tanque e um veículo vazio a mais de 40 metros de
qualquer bomba de combustível (além do `REFUEL_STATION_RANGE`, no mapa, longe de
tudo). Use o ACE (ou script) para abastecer o veículo vazio a partir do
caminhão. Observe o tanque subir.

Esperado: **nenhuma cobrança**, saldo intacto. O abastecimento é grátis. O sistema
deve distinguir entre "bomba de combustível do mapa" (cobrada) e "caminhão-tanque
ou fonte remota" (gratuita).

---

## 8. Abastecimento sem ACE no posto: cobrança proporcional

Com a bomba de combustível do jogo (sem ACE), abasteça um veículo e confirme a
cobrança.

**Teste:** defina `player setVariable ["moneyX", 1000, true]` e `A3U_refuelCostPerLiter = 1`.
Dirija para uma bomba com um veículo vazio (ex: Offroad, capacidade ~60 litros).
Abra o menu de abastecimento e leve de 0% a 100%.

Esperado: cobrança de 60 créditos (60 litros × 1 crédito/litro). Saldo fica em
940 créditos. O cálculo deve refletir **apenas** o intervalo de 0% a 100% para
aquele tanque específico, não a duração do abastecimento.

Se a cobrança for maior ou menor, o sistema errou no cálculo de diferença de
combustível (diferença entre o nível final e inicial).

---

## 9. Abastecimento com ACE (a pé, mangueira): mesmo valor do cenário 8

O ACE permite abastecer a pé usando uma mangueira. O custo deve ser idêntico ao
da bomba de combustível automática (cenário 8), desde que seja a mesma quantidade
de combustível no mesmo veículo.

**Teste:** com ACE instalado, use o mesmo veículo do cenário 8 (Offroad, ~60L).
Redefina `player setVariable ["moneyX", 1000, true]` e `A3U_refuelCostPerLiter = 1`.
Posicione-se a pé, use a ação do ACE para abastecer com mangueira de 0% a 100%.

Esperado: cobrança novamente de 60 créditos. O saldo fica em 940 créditos, igual
ao cenário 8. Se a cobrança for diferente (ex: 50 ou 70), o sistema está
contando combustível extra ou ignorando parte dele.

A fonte de combustível (ACE com mangueira vs. bomba de jogo) não deve afetar o
custo — apenas a quantidade de litros importa.

---

## 10. Escalas de preço: carro vs. caminhão (mesma taxa, mesma faixa)

Diferentes veículos têm tanques de diferentes capacidades. A cobrança deve ser
proporcional à quantidade de combustível adicionado, não ao tipo de veículo.

**Teste:** defina `player setVariable ["moneyX", 10000, true]` e `A3U_refuelCostPerLiter = 1`.

1. Abasteça um Offroad vazio (ex: ~60L) de 0% a 100%. Anote o custo.
2. Abasteça um caminhão vazio (ex: Kamaz, ~300L) de 0% a 100%. Anote o custo.

Esperado: a razão entre os dois custos deve ser aproximadamente a razão entre as
capacidades de tanque (300/60 = 5×). Se um caminhão custa 5× mais que um Offroad
para encher do 0% aos 100%, o sistema está escalando corretamente.

Se os custos forem iguais ou desproporcionais, o sistema errou no cálculo de
delta por veículo — pode estar usando um tanque padrão fictício para todos.

---

## 11. `A3U_refuelCostEnabled` em Não: comportamento pré-feature

Com `A3U_refuelCostEnabled = 0` (ou selecionado Não no setup) e a missão rodando,
abasteça um veículo até 100% múltiplas vezes. Observe a UI de parâmetros no
debug console.

Esperado: abastecimento é de graça, sem nenhum hint ou feedback de cobrança.
A UI de parâmetros mostra `A3U_refuelCostEnabled = 0` (ou pode não mostrar o
parâmetro se foi ocultado). O comportamento é idêntico ao da versão **antes**
desta branch — como se a feature não existisse.

O monitor (`fn_refuelMonitor.sqf`) **loga** uma linha `Info` no RPT ao
constatar o toggle desligado: `"refuelMonitor: cobranca de abastecimento
desligada nos parametros"`. Isso é esperado e correto — é o monitor
confirmando que não iniciou por causa do parâmetro, não um vazamento de
comportamento. A ausência dessa linha é que seria suspeita (indicaria que o
monitor iniciou mesmo com o toggle em Não).

Se você vir hints de "saldo insuficiente" ou preços aparecendo mesmo com o toggle
desligado, a lógica de desativação errou.

---

## 12. `A3U_refuelCostPerLiter` em 0 com o toggle em Sim: de graça com `Info`

Abastecimento de graça (taxa = 0) é um caso válido — qualquer camada acima pode
decidir não cobrar. O sistema deve reconhecer isso explicitamente.

**Teste:** defina `A3U_refuelCostEnabled = 1` e `A3U_refuelCostPerLiter = 0`.
Abasteça um veículo vazio de 0% a 100%. Observe o RPT.

Esperado: abastecimento é de graça, sem hints. Procure no RPT (não no console
in-game, é no arquivo `rpt`) pela linha `Info` de `fn_refuelMonitor.sqf`:
`"refuelMonitor: preco por litro zerado, monitor nao iniciado"`.

O saldo do jogador fica intacto. Se o RPT **não** contiver essa marca de `Info`,
o sistema pode estar silenciosamente ignorando taxa = 0 em vez de reconhecê-lo
como intencional.

---

## 13. Abastecimento pequeno, abaixo do limiar de commit (25 créditos)

Item adicionado na revisão final do plano: expôs um bug real na fórmula de
reconciliação de `fn_refuelSessionClose.sqf`, já corrigido, mas que só
aparece quando o custo total da sessão fica abaixo de `REFUEL_COMMIT_THRESHOLD`
(25 créditos) — ou seja, quando `_chargedCost` nunca sai de zero durante a
sessão inteira e todo o custo fica em `_pendingCost` até o fechamento.

**Teste:** com `A3U_refuelCostPerLiter = 2`, escolha um veículo cujo tanque
some poucos litros por segundo de abastecimento (ex: um carro pequeno) e
abasteça por uma janela curta o bastante para o custo total ficar abaixo de 25
créditos — por exemplo, ~6 litros a 2 créditos/litro = 12 créditos. Pare de
abastecer (saia do raio ou espere o `REFUEL_IDLE_TIMEOUT`) antes que o
acumulado passe de 25.

Esperado: o hint de resumo aparece com o custo total correto (proporcional aos
litros que de fato entraram) e o saldo do jogador cai exatamente esse valor.

**Se nada for cobrado, ou o valor cobrado for zero:** a fórmula de
reconciliação voltou a subtrair `_pendingCost` do acerto (o bug que esta
revisão corrigiu) — confira `fn_refuelSessionClose.sqf`.

---

## 14. Tanque grande enchendo rápido: guardas de taxa não devem disparar por engano

Item adicionado na revisão final do plano. As guardas de taxa
(`REFUEL_MAX_LPS` = 40 L/s, `REFUEL_MAX_FRACTION_PER_SEC` = 0.4) existem para
distinguir abastecimento real de um `setFuel` de script (garagem, spawn, load
de save), mas erram para o lado de "não cobrar" em caso de dúvida — um veículo
de tanque grande que encha rápido de verdade (ex: um caminhão-tanque
reabastecendo a si mesmo, ou um veículo de API grande) pode ultrapassar
`REFUEL_MAX_LPS` e ser tratado como falso positivo, saindo de graça.

**Teste:** abasteça no posto um veículo de tanque grande (ex: caminhão-tanque,
ou outro veículo com `fuelCapacity`/`ace_refuel_fuelCapacity` bem acima de
~100 L) e observe a taxa de enchimento. Se o RPT tiver `LogLevel` alto o
bastante para nível `Debug`, procure pela linha de
`fn_refuelSessionTick.sqf`: `"refuelSessionTick: guarda de taxa disparou,
litersPerSecond=... fractionPerSecond=..."` — ela loga sempre que a guarda
descarta uma amostra com delta positivo, permitindo distinguir "guarda filtrou
um falso positivo real" de "a cobrança quebrou".

Esperado: se a taxa de enchimento real fica abaixo dos limiares, a cobrança
acontece normalmente, proporcional aos litros. Se a guarda disparar (linha de
`Debug` aparece no RPT) para um abastecimento genuíno de posto, é sinal de que
os limiares (`REFUEL_MAX_LPS`/`REFUEL_MAX_FRACTION_PER_SEC`) estão calibrados
baixo demais para aquele veículo — registre o veículo e a taxa observada.

---

## Casos deliberadamente sem reembolso

Não são bugs; estão marcados no código. A política de reembolso é definida
conservadoramente: somente o carregamento de combustível que não ocorreu é
reembolsado. Uma vez que o combustível entra no tanque, o custo fica.

- **Saldo zero durante o abastecimento:** o tanque pára no ponto onde o dinheiro
  acabou. Nenhum reembolso (o combustível que entrou já foi pago).
- **Combustível que o motor consome durante o abastecimento:** a reconciliação
  desconta o consumo de motor da cobrança. Nenhum reembolso além disso.

**Limitação conhecida, não um comportamento garantido:** perda de conexão ou
crash do cliente no meio de uma sessão **não** fecha a sessão nem aciona a
reconciliação — nada no código roda nesse caso. `_pendingCost` (o resto
fracionário ainda não debitado) é simplesmente perdido a favor do jogador; o
que já tinha sido debitado em bloco (`_chargedCost`) permanece cobrado. Não
teste isso esperando que "o custo bate" — o resultado esperado é justamente
que o pendente não seja cobrado.

---

## Pontos em aberto para você decidir

Levantados na implementação, deixados como estão de propósito:

- **Limitação conhecida:** um jogador sem dinheiro consegue drenar um combustível
  compartilhado (posto ou caminhão-tanque) sem pagar nada. O combustível é
  removido do estoque do mapa/caminhão antes do pagamento ser validado. A spec
  marca isso como limitação aceitável, não é um bug a ser corrigido.

---

## Checklist de execução

Quando estiver testando, marque cada item com `[x]` enquanto executa:

- [ ] 0. Parâmetros aparecem no setup
- [ ] 1. Cobrança dispara apenas ao abastecer, não por proximidade
- [ ] 2. Multiplayer: dois jogadores no mesmo posto, só um paga
- [ ] 3. Puxar veículo da garagem não dispara cobrança de restauração
- [ ] 4. Sair do raio no meio do abastecimento finaliza a sessão
- [ ] 5. Saldo insuficiente no meio do abastecimento para o combustível
- [ ] 6. Saldo zero desde o início: nenhum combustível entra
- [ ] 7. Abastecimento por caminhão-tanque longe da bomba: sem cobrança
- [ ] 8. Abastecimento sem ACE no posto: cobrança proporcional
- [ ] 9. Abastecimento com ACE (a pé, mangueira): mesmo valor do cenário 8
- [ ] 10. Escalas de preço: carro vs. caminhão (mesma taxa, mesma faixa)
- [ ] 11. `A3U_refuelCostEnabled` em Não: comportamento pré-feature
- [ ] 12. `A3U_refuelCostPerLiter` em 0 com o toggle em Sim: de graça com `Info`
- [ ] 13. Abastecimento pequeno, abaixo do limiar de commit (25 créditos)
- [ ] 14. Tanque grande enchendo rápido: guardas de taxa não disparam por engano
