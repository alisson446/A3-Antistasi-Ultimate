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
testam toggles e configurações.

Referências: spec em `docs/superpowers/specs/2026-07-31-fuel-economy-design.md`,
plano em `docs/superpowers/plans/2026-07-31-fuel-economy.md`.

---

## 0. Parâmetros aparecem no setup

Na tela de setup, dropdown de tipo de parâmetros na opção **4** (agrupa Extender,
Experimental, Development). Sob OPÇÕES EXPERIMENTAIS devem aparecer duas
entradas novas:

- Refuel: charge cost — Não/Sim, default Sim
- Refuel: cost per liter — 0/1/2/5/10, default 1

**Falha:** qualquer texto aparecendo como `STR_params_refCost...` cru significa
chave de stringtable não encontrada.

Com a missão rodando, no debug console:

```sqf
[A3U_refuelCostEnabled, A3U_refuelCostPerLiter]
```

Esperado: `[1,1]` (ou `[1,2]`, `[1,5]`, `[1,10]`, `[1,0]` conforme as
configurações escolhidas).

---

## 1. Cobrança dispara apenas ao abastecer, não por proximidade  ← COMECE POR AQUI

Este é o item mais provável de falhar e o mais difícil de diagnosticar depois.

A sessão de abastecimento só deve iniciar quando `setFuel` é invocado — não por
mera proximidade do jogador com a bomba de combustível. Se o sistema cobrasse por
proximidade, qualquer jogador estacionado ao lado da bomba levaria débitos
constantes.

**Teste:** com dinheiro suficiente, estacione um veículo **cheio** ao lado de
uma bomba de combustível. Fique próximo do veículo (dentro do raio de 30 metros)
por trinta segundos. Não abra nenhum menu de abastecimento.

Esperado: **nenhuma cobrança**, nenhum hint, saldo intacto. O veículo continua
cheio.

**Se receber débitos sem abrir o menu:** foi a inicialização que errou —
a sessão está disparando por proximidade em vez de por `setFuel`. Procure em
`A3A/addons/.../functions/.../fn_*.sqf` pelo inicializador da sessão; deve
aguardar explicitamente um comando de abastecimento, não apenas a presença
do jogador.

---

## 2. Desligamento do toggle é no-op

O que protege quem não quer a feature. Com `A3U_refuelCostEnabled = 0` no debug
console (ou Não no setup), abasteça um veículo vazio até 100%.

Esperado: abastecimento acontece direto, sem hints, sem débito — comportamento
idêntico ao de antes desta branch. Saldo fica intacto.

Com `A3U_refuelCostEnabled = 1`, repetir o mesmo abastecimento: agora deve cobrar.

---

## 3. Puxar veículo da garagem não dispara cobrança de restauração

Quando um veículo é restaurado na garagem (via `setFuel` ou `setDamage`), esse
combustível não deve ser cobrado. Somente o combustível adicionado pela bomba de
combustível do mapa deve gerar cobrança.

**Teste:** ir para qualquer garagem rebelde, puxar um veículo vazio (0% de
combustível). Observe o nível de combustível subir para o padrão da garagem —
isso é restauração, não abastecimento no posto.

Esperado: **nenhuma cobrança** durante a restauração, saldo intacto. Depois,
dirija até uma bomba de combustível no mapa e abastça de, digamos, 50% para
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
para mais de 30 metros de distância (raio padrão).

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
citando o custo e saldo (**sem** som — isso é para a revisão). O saldo cai a
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

**Teste:** estacione um caminhão-tanque e um veículo vazio a mais de 30 metros de
qualquer bomba de combustível (no mapa, longe de tudo). Use o ACE (ou script)
para abastecer o veículo vazio a partir do caminhão. Observe o tanque subir.

Esperado: **nenhuma cobrança**, saldo intacto. O abastecimento é grátis. O sistema
deve distinguir entre "bomba de combustível do mapa" (cobrada) e "caminhão-tanque
ou fonte remota" (gratuita).

---

## 8. Abastecimento sem ACE no posto: cobrança proporcional

Com a bomba de combustível do jogo (sem ACE), abasteça um veículo e confirme a
cobrança.

**Teste:** defina `player setVariable ["moneyX", 1000, true]` e `A3U_refuelCostPerLiter = 1`.
Dirija para uma bomba com um veículo vazio (ex: Offroad, capacidade ~60 litros).
Abra o menu de abastecimento e lleve de 0% a 100%.

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

1. Abastça um Offroad vazio (ex: ~60L) de 0% a 100%. Anote o custo.
2. Abastça um caminhão vazio (ex: Kamaz, ~300L) de 0% a 100%. Anote o custo.

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

Nenhum `Info` no RPT citando custo ou cobrança.

Se você vir hints de "saldo insuficiente" ou preços aparecendo mesmo com o toggle
desligado, a lógica de desativação errou.

---

## 12. `A3U_refuelCostPerLiter` em 0 com o toggle em Sim: de graça com `Info`

Abastecimento de graça (taxa = 0) é um caso válido — qualquer camada acima pode
decidir não cobrar. O sistema deve reconhecer isso explicitamente.

**Teste:** defina `A3U_refuelCostEnabled = 1` e `A3U_refuelCostPerLiter = 0`.
Abastça um veículo vazio de 0% a 100%. Observe o RPT.

Esperado: abastecimento é de graça, sem hints. Procure no RPT (não no console
in-game, é no arquivo `rpt`) por uma linha `Info` (não `Warning` ou `Error`)
citando o custo zero — algo como "taxa configurada em 0, nenhuma cobrança".

O saldo do jogador fica intacto. Se o RPT **não** contiver uma marca de `Info`,
o sistema pode estar silenciosamente ignorando taxa = 0 em vez de reconhecê-lo
como intencional.

---

## Casos deliberadamente sem reembolso

Não são bugs; estão marcados no código. A política de reembolso é definida
conservadoramente: somente o carregamento de combustível que não ocorreu é
reembolsado. Uma vez que o combustível entra no tanque, o custo fica.

- **Saldo zero durante o abastecimento:** o tanque pára no ponto onde o dinheiro
  acabou. Nenhum reembolso (o combustível que entrou já foi pago).
- **Perda de conexão ou crash no meio:** a sessão fecha e o custo final bate com
  o que já entrou. Nenhum reembolso.
- **Combustível que o motor consome durante o abastecimento:** a reconciliação
  desconta o consumo de motor da cobrança. Nenhum reembolso além disso.

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
- [ ] 2. Desligamento do toggle é no-op
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
