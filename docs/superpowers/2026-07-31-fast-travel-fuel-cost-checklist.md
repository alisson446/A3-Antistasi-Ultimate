# Checklist de verificação in-game — custo de combustível no fast travel

Nada disto foi testado. Python não está instalado nesta máquina, então o linter
`Tools/sqfvalidator/sqflint.py` não rodou em nenhum commit, e o jogo não foi
aberto. A revisão de código foi a única barreira até aqui.

A ordem abaixo não é arbitrária: o item 1 é o de maior risco e trava todos os
outros, e o item 2 é o que protege quem não quer a feature.

Referências: spec em `docs/superpowers/specs/2026-07-31-fast-travel-fuel-cost-design.md`,
plano em `docs/superpowers/plans/2026-07-31-fast-travel-fuel-cost.md`.

---

## 0. Parâmetros aparecem no setup

Na tela de setup, dropdown de tipo de parâmetros na opção **4** (agrupa Extender,
Experimental, Development). Sob OPÇÕES EXPERIMENTAIS devem aparecer quatro
entradas novas:

- Fast Travel: charge fuel cost — Não/Sim, default Sim
- Fast Travel: charge for rally point — Não/Sim, default Sim
- Fast Travel: charge for High Command — Não/Sim, default Sim
- Fast Travel: cost per km — 5/10/15/20/30/50, default 20

**Falha:** qualquer texto aparecendo como `STR_params_ftCost...` cru significa
chave de stringtable não encontrada.

Com a missão rodando, no debug console:

```sqf
[A3U_ftCostPlayer, A3U_ftCostRallyPoint, A3U_ftCostHighCommand, A3U_ftCostPerKm]
```

Esperado: `[1,1,1,20]`.

---

## 1. O diálogo de confirmação realmente abre  ← COMECE POR AQUI

Este é o item mais provável de falhar e o mais difícil de diagnosticar depois.

O 4º argumento de `BIS_fnc_guiMessage` foi mudado de `true` para `false` durante
a revisão final. O motivo: `true` foi copiado de `fn_FIAskillAdd.sqf`, que roda
dentro do diálogo do HQ, enquanto o fast travel roda com apenas o **mapa** aberto,
que não é um diálogo. O `fn_popup.sqf` do mod usa `false` em contexto sem diálogo.

Por que importa tanto: se a mensagem não conseguir ser criada, `BIS_fnc_guiMessage`
retorna `false`, que é indistinguível do jogador clicar Não. O sintoma seria fast
travel simplesmente não fazer nada, sem hint, sem erro.

**Teste:** a pé, com dinheiro, fast travel para um destino distante.

Esperado: diálogo com nome do destino, distância em km, custo e saldo restante.
Aceitar → tela preta e timer normais, saldo debitado.

**Se o diálogo não aparecer:** foi a mudança para `false` que errou — reverta para
`true` em `A3A/addons/core/functions/FastTravel/fn_fastTravelCharge.sqf`, na
chamada de `BIS_fnc_guiMessage`. O log `Info_1` adicionado na mesma linha ajuda a
distinguir recusa real de diálogo falho: procure por `fastTravelCharge: viagem
recusada ou dialogo falhou` no RPT.

---

## 2. Toggles desligados são no-op

O que protege quem não quer a feature. Com `A3U_ftCostPlayer = 0` no debug console
(ou Não no setup), viajar normalmente.

Esperado: viagem acontece direto, sem diálogo, sem débito — comportamento
idêntico ao de antes desta branch. Repetir para `A3U_ftCostRallyPoint` e
`A3U_ftCostHighCommand` nos seus caminhos.

---

## 3. Escala do custo: a pé vs. de carro

```sqf
private _p = position player;
[
    [player, _p] call A3A_fnc_fastTravelCost,
    [player, [(_p#0) + 1000, _p#1, 0]] call A3A_fnc_fastTravelCost,
    [player, [(_p#0) + 10000, _p#1, 0]] call A3A_fnc_fastTravelCost
]
```

A pé, com taxa 20, esperado: `[0,10,100]`.

Entrar num Offroad e repetir a mesma linha. Esperado: `[0,20,200]` — exatamente o
dobro, porque o multiplicador vai de 0.5 para 1.0.

**Falha:** valores idênticos nos dois casos significam que `vehicle player` não
está sendo lido.

Esta função é pura — não abre diálogo e não gasta dinheiro, então dá para chamar à
vontade.

---

## 4. Saldo insuficiente bloqueia

```sqf
player setVariable ["moneyX", 5, true];
```

Tentar viajar para um destino que custe mais que 5.

Esperado: `deniedHint` com som de falha citando custo e saldo. **Sem** tela preta,
sem teleporte, sem débito.

---

## 5. Recusar no diálogo

Viajar, e clicar Não.

Esperado: nada acontece, saldo intacto, mapa volta ao normal.

---

## 6. Rally point pelos DOIS caminhos

Com rally point montado e o jogador a pé no HQ. Este é o item que quebra se alguém
mover o gate de lugar, e é fácil testar só metade dele.

1. **Pelo menu de fast travel:** abrir o menu, clicar no marcador do rally no mapa.
2. **Pela bandeira do HQ:** usar a `addAction` de viajar para o rally direto na
   bandeira, **sem** passar pelo menu de fast travel.

Esperado: os dois mostram o diálogo de custo e debitam igual.

Depois, `A3U_ftCostRallyPoint = 0` e repetir os dois: viagem direta, sem diálogo.

---

## 7. High Command debita a facção

Selecionar um grupo pela barra de High Command e mandar viajar.

Esperado: `server getVariable "resourcesFIA"` cai, e `player getVariable "moneyX"`
fica **intacto**.

Efeito colateral esperado, não é bug: o comandante recebe uma notificação de rádio
do Petros a cada movimento de HC, porque `A3A_fnc_resourcesFIA` emite `commsMP` em
qualquer alteração do caixa. É como todo gasto de fundos da facção já se comporta.

---

## 8. Taxa por km escala linear

Rodar o bloco do item 3 com `A3U_ftCostPerKm = 5` e depois `= 50`.

Esperado: custos proporcionais — a 50 o custo é 10× o de 5.

---

## 9. Reembolso no cancelamento tardio — SOMENTE High Command

Deixe por último: precisa de dois jogadores e de configuração específica.

A descrição original deste cenário no plano estava errada e foi corrigida na
revisão final. O caminho de cancelamento tardio é **inalcançável fora do modo HC**:
para viagem normal, `fn_fastTravelRadio.sqf:29` só liga `_checkForPlayer` quando
`limitedFT` é 1 ou 2, mas as linhas 113 e 124 já abortam nesses casos quando o
destino é inválido — então quem chega na linha 182 sempre tem destino válido e a
condição nunca se satisfaz.

**Montagem:** modo High Command, `limitedFT` em 1 ou 2, um grupo de HC com veículo,
destino que **não** seja base rebelde, aeroporto ou milbase. Durante a contagem
regressiva, um segundo jogador entra no veículo do grupo.

Esperado: viagem cancelada e `resourcesFIA` restaurado integralmente. Nunca
`moneyX` — o estorno neste caminho é sempre da facção.

Se não houver como testar com dois jogadores, registre como **não verificado** em
vez de marcar como passou.

---

## Casos deliberadamente sem reembolso

Não são bugs; estão marcados no código. `grep -rn "ANCORA-REEMBOLSO" A3A/addons`
encontra a política inteira.

- Falha de `findEmptyPosition` no meio do teleporte: parte do grupo já se moveu, a
  viagem aconteceu em parte.
- Custo arredondando para 0: nunca houve cobrança.
- Rally point: não existe ponto de cancelamento entre a cobrança e o teleporte.

---

## Pontos em aberto para você decidir

Levantados na revisão final, deixados como estão de propósito:

- **Paraquedas custa 3×.** `ParachuteBase` herda de `Air`, então quem desce de
  paraquedas paga o multiplicador aéreo. É alcançável. Se achar estranho, o ajuste
  é uma condição a mais no `case` de `Air` em `fn_fastTravelCost.sqf`.
- **`markerText` pode mostrar id cru.** Marcadores sem texto definido caem no nome
  interno, então o diálogo pode dizer "Travel to Synd_HQ?". Cosmético.
- **Globais sem fallback.** `A3U_ftCostPerKm` e os toggles são lidos direto. É o
  idioma do codebase (`limitedFT` faz igual), mas se algum fosse nil o fast travel
  quebraria inteiro.
