# Checklist de verificação in-game — undercover em veículo e roadblock

Nada disto foi testado. Python não está instalado nesta máquina, então o linter
`Tools/sqfvalidator/sqflint.py` não rodou em nenhum commit, e o jogo não foi
aberto. A revisão de código foi a única barreira até aqui.

As Tasks 1–4 que implementam a detecção de vestimenta visível em veículos e a
desabilitação do roadblock foram todas commitadas e revisadas, mas nenhuma foi
verificada in-game ainda. Cada item abaixo está pendente de execução manual. Não
marque nada como "passou" sem ter rodado o teste no jogo.

A ordem abaixo não é arbitrária: o item 1 é o de maior risco — se a detecção de
colete não bloquear entrada no veículo, nada mais importa. O item 2 confirma que
armas ainda são permitidas (regressão). Itens 3–5 testam as regras novas de
detecção de vestimenta dentro do veículo (colete e capacete). Item 6 é o segundo
maior risco: o roadblock deve **nunca** quebrar o disfarce em tierWar alto, ao
contrário do que acontecia antes. Itens 7–8 confirmam que comportamentos de
outpost e airspace não foram quebrados (regressão). Item 9 confirma que a regra
de Highway, adicionada imediatamente após a nova checagem de veículo, não foi
atropelada.

Referências: spec em
`docs/superpowers/specs/2026-08-01-undercover-veiculo-e-roadblock-design.md`, plano em
`docs/superpowers/plans/2026-08-01-undercover-veiculo-e-roadblock.md`.

---

## 1. Entrar em carro civil com colete ← COMECE POR AQUI

Este é o item mais provável de falhar e o cenário central da mudança. Se a
detecção de colete não funcionar, todos os itens restantes são duvidosos.

**Teste:** coloque-se num acampamento seguro (longe de inimigos, sem patrulhas
próximas). Use o debug console ou ACE para vestir um colete corporal sem
arma na mão. Procure um carro civil (ex: Offroad) a pé. Ative undercover
(pressione a tecla de atalho de undercover ou execute `call A3A_fnc_goUndercover`
no console). Enquanto o disfarce está ativo, aproxime-se do carro civil e entre
como passageiro ou motorista (ação de entrar veículo).

Esperado: **entrada no veículo é recusada**, com hint exibindo "Wearing a vest".
O jogador permanece a pé fora do veículo. O disfarce **não** é quebrado — o
jogador ainda está undercover a pé. Tire o colete (pelo inventário ou console:
`player removeItem "Vest_Carrier_Base"`), e tentar entrar de novo deve
funcionar na hora.

**Se você conseguir entrar no carro com o colete:** a detecção de vestimenta na
entrada do veículo não funcionou. Procure em `A3A/addons/core/functions/Undercover/fn_canGoUndercover.sqf` pelo ramo de
veículo e pela checagem de `uniform`, `vest`, `helmet` visíveis.

---

## 2. Entrar em carro civil com fuzil e sem colete

Confirma que armas na mão (rifles, pistolas) ainda são permitidas dentro do
veículo — a mudança só deve bloquear vestimenta visível, não armamento.

**Teste:** vista-se com uniforme undercover apropriado (ex: civil), equipe um
rifle (ex: Mk20, AK12, qualquer arma). Dirija-se a um acampamento seguro, sem
inimigos próximos. Ative undercover. Com a arma na mão e sem colete, tente entrar
num carro civil.

Esperado: **entrada é aceita**, você consegue entrar no carro com o rifle. O
disfarce permanece ativo dentro do veículo. Este comportamento é idêntico ao de
antes da mudança — a presença de arma não quebra o disfarce em veículo.

**Se a entrada for recusada com hint mencionando arma:** a detecção de
vestimenta foi muito restritiva e está bloqueando rifles. Procure no mesmo
arquivo (`fn_canGoUndercover.sqf`) e verifique se há lógica erroneamente
filtrando por primárias/secundárias na checagem de veículo.

---

## 3. Vestir colete dentro do carro, longe de inimigos

Testa a regra nova: se vestir vestimenta visível **dentro** do veículo em zona
segura (sem inimigos a menos de 350 m), o disfarce quebra sem punição permanente
(sem `compromised`).

**Preparação:** escolha um mapa com zona segura clara e confirmada (ex: acampamento
amigo distante de patrulhas inimigas). Dirija um carro civil até essa zona segura.
Use `call A3A_fnc_goUndercover` no console para ativar o disfarce. Verifique que
está realmente undercover (cor amarela de HUD ou hint de confirmação).

**Teste:** abra o inventário e vista um colete (ex: `Vest_Carrier_Base`).

Esperado:
- O disfarce quebra em até 1 segundo, com hint exibindo `..._veh_1` (referência
  ao ramo de veículo próximo de inimigos).
- Você **não** recebe o status `compromised`.
- O veículo **não** fica marcado (é seguro entrar nele novamente).
- Você ainda está dentro do carro (não foi expulso).

Depois, remova o colete (console: `player removeItem "Vest_Carrier_Base"`) e
tente reativar o undercover imediatamente (`call A3A_fnc_goUndercover`). Esperado:
reativação funciona na hora, sem delay.

**Se você receber `compromised` ou o veículo for marcado:** a lógica de zona
segura falhou. Procure em `fn_goUndercover.sqf` pela checagem de distância a
inimigos (350 m) que decide entre `_veh_1` e `_veh_2`.

---

## 4. Vestir colete dentro do carro com inimigo a menos de 350 m

Testa a regra inversa: se vestir vestimenta visível **dentro** do veículo
**com** inimigos próximos (a menos de 350 m), recebe punição (compromised + veículo marcado).

**Preparação:** dirija para perto de uma patrulha inimiga confirma (a menos de
350 m — use a distância no mapa). Ative undercover num carro civil.

**Teste:** abra o inventário e vista um colete.

Esperado:
- O disfarce quebra imediatamente, com hint exibindo `..._veh_2`.
- Você recebe o status `compromised` por 30 minutos.
- O veículo fica marcado **permanentemente**. Se você sair e entrar nele de novo,
  será recusado com hint "In reported vehicle" — precisará passar pela caixa de
  veículos (garage) para limpar a marca.

**Se o veículo não for marcado ou se não receber `compromised`:** a lógica de
"com inimigos próximos" falhou. A mesma checagem de distância (350 m) deve
diferenciar o comportamento do item 3. Procure em `fn_goUndercover.sqf`.

---

## 5. Capacete leve (armor entre 1 e 2)

Comportamento novo: capacetes com classe de armadura entre 1 e 2 agora quebram
o disfarce — antes passavam. Teste a pé e dentro do carro.

**Preparação:** procure um capacete leve que qualifique (armor value entre 1 e
2; ex: HelmetIA, HelmetACU, ou similar — não use capacetes pesados/de
operador que têm armor > 2). Acampe numa zona segura sem inimigos.

**Teste — a pé:**
1. Ative undercover a pé.
2. Abra inventário e equipe o capacete leve.

Esperado: disfarce quebra **imediatamente**, sem compromised (zona segura).

**Teste — dentro do veículo:**
1. Dirija um carro civil para a zona segura.
2. Ative undercover dentro do carro.
3. Abra inventário e equipe o capacete leve.

Esperado: disfarce quebra **imediatamente**, sem compromised, veículo não marcado.

Depois, remova o capacete e tente reativar undercover. Esperado: reativação
funciona imediatamente.

**Se o capacete não quebrar o disfarce:** a checagem de armor na classe do
helmet não funcionou. Procure em `fn_canGoUndercover.sqf` pela lógica de
`_helmetClass` e `_armor`.

---

## 6. Atravessar roadblock inimigo undercover (TierWar alto)

Comportamento novo: roadblock **nunca** deve quebrar o disfarce. Antes da mudança,
com `tierWar` 8–10, a checagem de roadblock era sempre acionada e **sempre**
quebrava o disfarce (bug corrigido). Agora, deve estar desabilitada.

**Preparação:** aumente `tierWar` para 8, 9 ou 10 no debug console:
`tierWar = 10; publicVariableServer "tierWar";` Procure vários roadblocks
inimigos no mapa (estradas principais com barricadas inimigas). Tenha dinheiro
suficiente.

**Teste:** dirija um carro civil para cada roadblock em sequência. Ative
undercover **antes** de passar pela barricada. Enquanto undercover, atravesse o
roadblock várias vezes (passe, volte, passe novamente).

Esperado: **nenhuma** quebra de disfarce. O carro não é disparado. O disfarce
permanece ativo durante e depois da passagem. Repita em múltiplos roadblocks na
mesma sessão para garantir que não há um limite oculto de "X vezes".

**Se o disfarce quebrar ou o carro for disparado:** a desabilitação do roadblock
não funcionou. Procure em `fn_goUndercover.sqf` a checagem de `_roadblockCheck`
e confirme que ela está comentada ou removida.

---

## 7. Entrar em marcador de outpost undercover

Comportamento pré-existente, inalterado: entrar no marcador de outpost (zona de
captura) sempre quebra o disfarce imediatamente. Confirma regressão.

**Preparação:** localize um outpost inimigo no mapa. Aproxime-se até a borda
visível da zona de captura (a área circular que aparece no mapa).

**Teste — outpost:**
1. Ative undercover a pé ou dentro de um veículo.
2. Entre no marcador de outpost (zona de captura).

Esperado: disfarce quebra **imediatamente**, antes de dar qualquer passo dentro
da zona.

**Teste — aeroporto, seaport, milbase (se aplicável):**
Repita o mesmo procedimento para aeroporto, seaport (base naval) e qualquer
milbase (instalação militar) que tenha marcador de captura. O comportamento
deve ser idêntico: quebra na entrada.

**Se o disfarce não quebrar ao entrar:** a checagem de outpost foi quebrada.
Procure em `fn_goUndercover.sqf` pela lógica de `_inOutpost` ou `_inAirport`.

---

## 8. Voar undercover perto de outpost

Comportamento pré-existente, inalterado: voar num helicóptero civil undercover
perto de um outpost não deve quebrar o disfarce (controle de espaço aéreo é
separado).

**Teste:**
1. Dirija até um outpost inimigo num helicóptero civil (ex: Hummingbird ou
   helicóptero civil padrão).
2. Ative undercover no ar.
3. Sobrevoe o outpost várias vezes (suba a ~50–100 m acima, voe em volta).

Esperado: disfarce **permanece ativo** durante todo o sobrevoo. Nenhuma quebra.
Nenhuma mudança no sistema de `airspaceControl` (as regras de espaço aéreo devem
ser idênticas às de antes).

**Se o disfarce quebrar ou se `airspaceControl` mudar:** a mudança de veículo
foi acidentalmente aplicada ao ramo de voar. Procure em `fn_goUndercover.sqf`
para ver se o ramo de `_typeVehicle == "helicopter"` foi afetado pela nova
checagem de vestimenta.

---

## 9. Dirigir fora de estrada com inimigo a menos de 350 m

Comportamento pré-existente, inalterado: sair de estrada (Highway rule) quebra o
disfarce se houver inimigos próximos. Confirma que a regra não foi atropelada
pela nova checagem de veículo.

**Preparação:** dirija um veículo offroad (qualquer viatura) em terreno acidentado,
longe de estradas. Procure uma zona com patrulha inimiga a menos de 350 m. Ative
undercover.

**Teste:**
1. Dirija propositalmente fora de estrada (na terra, no mato, em declive), com
   inimigos próximos (< 350 m).
2. Observe o disfarce.

Esperado:
- Disfarce quebra, com hint `..._veh_2` (identif a regra de Highway, não veículo
  em si).
- Você recebe `compromised` por 30 min.
- O veículo fica marcado permanentemente.
- Se tentar entrar no veículo novamente, será recusado com "In reported vehicle".

Este comportamento é **idêntico** ao de antes da mudança. A ordem de checagem
em `fn_goUndercover.sqf` deve ser: (1) detecção de vestimenta em veículo,
(2) Highway rule. Se a regra de Highway ainda funciona, a inserção da nova
regra não a atropelou.

**Se a regra de Highway não funcionar (disfarce não quebra ao sair de estrada):**
a nova checagem de vestimenta pode ter interferido. Procure em `fn_goUndercover.sqf`
a inserção de `_veh_1` / `_veh_2` e confirme que não está usando um `else` que
bloqueia a checagem de Highway.

---

## Efeitos colaterais previstos — não são bugs

Comportamentos novos ou amplificados que aparecerão no teste e **não** indicam
falha:

- **Um passageiro com colete derruba o disfarce de todos no veículo:** a lógica
  de `fn_goUndercover.sqf` linhas 225–233 (checagem de visibilidade de
  equipamento no veículo) agora dispara com muito mais frequência, porque está
  sendo executada a cada tick em veículos, em vez de apenas na entrada. Como
  efeito colateral, se um jogador passageiro (não motorista) veste um colete
  enquanto o veículo está em movimento, o sistema detecta e quebra o disfarce
  de todos a bordo — motor + passageiros. Isso é pré-existente e correto; está
  mais visível agora porque a checagem corre constantemente, não apenas uma vez.

- **Um jogador com `compromised` ativo ainda consegue entrar num carro e
  reativar undercover imediatamente:** o ramo de veículo de `fn_canGoUndercover`
  não checa o status de `compromised` do jogador. Esta é uma inconsistência
  pré-existente: o ramo a pé checa `compromised`, o ramo de veículo não. Está
  fora do escopo desta spec (deliberadamente não corrigido). Se você notar que
  um jogador marcado conseguiu se disfarçar dentro de um veículo e fugir sem
  delay, é este efeito — esperado e documentado.

---

## Checklist de execução

Quando estiver testando, marque cada item com `[x]` enquanto executa:

- [ ] 1. Entrar em carro civil com colete
- [ ] 2. Entrar em carro civil com fuzil e sem colete
- [ ] 3. Vestir colete dentro do carro, longe de inimigos
- [ ] 4. Vestir colete dentro do carro com inimigo a menos de 350 m
- [ ] 5. Capacete leve (armor entre 1 e 2)
- [ ] 6. Atravessar roadblock inimigo undercover (tierWar alto)
- [ ] 7. Entrar em marcador de outpost undercover
- [ ] 8. Voar undercover perto de outpost
- [ ] 9. Dirigir fora de estrada com inimigo a menos de 350 m
