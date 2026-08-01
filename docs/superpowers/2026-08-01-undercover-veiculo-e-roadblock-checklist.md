# Checklist de verificação in-game — undercover em veículo e roadblock

Nada disto foi testado. Python não está instalado nesta máquina, então o linter
`Tools/sqfvalidator/sqflint.py` não rodou em nenhum commit, e o jogo não foi
aberto. A revisão de código foi a única barreira até aqui.

As Tasks 1–4 que implementam a detecção de vestimenta visível em veículos e a
desabilitação do roadblock foram todas commitadas e revisadas, mas nenhuma foi
verificada in-game ainda. Cada item abaixo está pendente de execução manual. Não
marque nada como "passou" sem ter rodado o teste no jogo.

A ordem abaixo não é arbitrária: o item 1 é o de maior risco — se a detecção de
colete não bloquear a ativação do undercover em veículo, nada mais importa. O item 2 confirma que
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

## 1. Ativar undercover em carro civil com colete ← COMECE POR AQUI

Este é o item mais provável de falhar e o cenário central da mudança. Se a
detecção de colete não funcionar, todos os itens restantes são duvidosos.

Note que **entrar fisicamente num veículo nunca é bloqueado** por este sistema —
`A3A_fnc_goUndercover` só dispara automaticamente depois que o jogador já está
sentado (evento `GetInMan`, ver `A3A/addons/core/functions/init/fn_initClient.sqf:331-338`).
O que é recusado é a **ativação** do disfarce, não a entrada no carro. Por isso
o teste não pode partir de "vestir colete e ativar undercover a pé" — o portão
a pé já bloqueia coletes antes disso, então esse estado nunca seria alcançado.

**Teste:**
1. Sem colete, sem arma na mão. Entre num carro civil (ex: Offroad) e ative
   undercover (tecla de atalho ou `call A3A_fnc_goUndercover` no console).
   Confirme que o disfarce ativa normalmente — isso estabelece a base de
   comparação.
2. Saia do veículo (o disfarce desativa normalmente, ou apenas saia mesmo).
3. Vista um colete corporal (debug console ou ACE).
4. Entre de novo no mesmo carro civil.

Esperado: o jogador **consegue entrar no veículo normalmente** (entrar num
veículo nunca é recusado). Ao tentar ativar undercover sentado, a ativação **é
recusada**, com hint listando "Wearing a vest" — vindo do ramo de veículo de
`A3A_fnc_canGoUndercover`, que agora chama a função de checagem de vestimenta
compartilhada. O jogador permanece visivelmente descoberto (não undercover)
enquanto sentado no carro. Tire o colete (pelo inventário ou console:
`player removeItem "Vest_Carrier_Base"`), e ativar undercover deve funcionar
na hora.

**Se a ativação for aceita mesmo com o colete:** a detecção de vestimenta na
ativação do undercover não funcionou. Procure em
`A3A/addons/core/functions/Undercover/fn_canGoUndercover.sqf` pelo ramo de
veículo e pela chamada a `A3A_fnc_undercoverGearCheck`.

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
- O disfarce quebra em até 1 segundo, com hint exibindo `..._veh_1` (o ramo de
  vestimenta em veículo **sem** inimigos próximos — sem punição; o irmão
  `..._veh_2`, testado no item 4, é o de inimigo próximo, com `compromised` e
  veículo marcado).
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

**Se o capacete não quebrar o disfarce:** a checagem de capacete não
funcionou. Procure em
`A3A/addons/core/functions/Undercover/fn_undercoverGearCheck.sqf` pela linha
`headgear player in allArmoredHeadgear`.

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
não funcionou. Procure em `fn_goUndercover.sqf` o bloco comentado que calcula
`_aggro` e testa `random 100 < _aggro` (logo após o comentário "Roadblock
detection roll disabled on purpose") e confirme que ele continua comentado.

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
Procure em `fn_goUndercover.sqf` pela lógica de `_onBaseMarker` /
`_onDetectionMarker` e pelos testes `_base in airportsX` e `"outpost" in _base`.

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

**Atenção — comportamento novo esperado:** a nova checagem de vestimenta em
veículo fica no ramo genérico de veículo, ANTES do `if (... isKindOf "Air")
then { continue }` que pula os testes de localização em `fn_goUndercover.sqf`.
Isso significa que ela agora também se aplica a helicópteros e aviões. Se o
disfarce quebrar inesperadamente durante o voo, confira primeiro se o piloto
está com capacete blindado (qualquer item em `allArmoredHeadgear`) antes de
assumir que houve regressão em `airspaceControl` — é uma interação esperada
desta mudança, não um bug do sistema de espaço aéreo.

**Se o disfarce quebrar ou se `airspaceControl` mudar (e não for o capacete):**
a mudança de veículo foi acidentalmente aplicada ao ramo de voar de forma
indevida. Procure em `fn_goUndercover.sqf` pelo trecho `isKindOf "Air"` e
confirme onde exatamente a checagem de vestimenta (`A3A_fnc_undercoverGearCheck`)
está posicionada em relação a ele.

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
- Disfarce quebra, com o hint da regra de Highway
  (`STR_A3A_fn_undercover_goUn_no_distance`) — **não** o hint `..._veh_2` da
  checagem de vestimenta em veículo.
- O veículo fica marcado (`A3A_reported`) permanentemente. Se tentar entrar
  nele novamente, será recusado com "In reported vehicle".
- Você **não** recebe o status `compromised` — o `case "Highway"` em
  `fn_goUndercover.sqf` só marca o veículo, não seta `compromised` no jogador.

Este comportamento é **idêntico** ao de antes da mudança. A ordem de checagem
em `fn_goUndercover.sqf` deve ser: (1) detecção de vestimenta em veículo,
(2) Highway rule. Se a regra de Highway ainda funciona (com o hint e a punição
corretos acima), a inserção da nova checagem de vestimenta não a atropelou.

**Se a regra de Highway não funcionar (disfarce não quebra ao sair de estrada,
ou quebra mas com o hint/punição errados):** a nova checagem de vestimenta pode
ter interferido. Procure em `fn_goUndercover.sqf` o bloco da checagem de
vestimenta em veículo (que seta `_reason` como `clothesVeh` ou `clothesVeh2`)
e confirme que ele não está "engolindo" a checagem seguinte do `case "Highway"`.

---

## Efeitos colaterais previstos — não são bugs

Comportamentos novos ou amplificados que aparecerão no teste e **não** indicam
falha:

- **Um passageiro com colete derruba o disfarce de todos no veículo:** quando o
  disfarce de qualquer ocupante quebra (por qualquer motivo, incluindo a nova
  checagem de vestimenta em veículo), o loop `while` de monitoramento em
  `fn_goUndercover.sqf` termina e o bloco logo após ele (hoje nas linhas
  257–265, que usa `assignedCargo(vehicle player) + crew(vehicle player)`) roda
  **uma única vez** para remover `captive` de todos os outros jogadores a bordo.
  Não é uma checagem por tick — é a consequência natural de rodar esse cleanup
  depois que a cobertura de qualquer ocupante já quebrou. Como efeito colateral,
  se um jogador passageiro (não motorista) veste um colete, o sistema detecta
  (agora a cada tick de 1s da checagem de vestimenta, dentro do `while`) e
  quebra o disfarce de todos a bordo — motor + passageiros. Isso é pré-existente
  e correto; está mais visível agora porque a checagem de vestimenta em veículo
  passou a existir e roda continuamente, não apenas na ativação.

- **Um jogador com `compromised` ativo ainda consegue entrar num carro e
  reativar undercover imediatamente:** o ramo de veículo de `fn_canGoUndercover`
  não checa o status de `compromised` do jogador. Esta é uma inconsistência
  pré-existente: o ramo a pé checa `compromised`, o ramo de veículo não. Está
  fora do escopo desta spec (deliberadamente não corrigido). Se você notar que
  um jogador marcado conseguiu se disfarçar dentro de um veículo e fugir sem
  delay, é este efeito — esperado e documentado.

- **Vestir colete dentro do veículo em cima de um outpost/base inimiga dá a
  punição dupla, não a de outpost:** dentro do `while` de monitoramento em
  `fn_goUndercover.sqf`, a checagem de vestimenta em veículo roda ANTES das
  checagens de marcador de base (`_onBaseMarker` / `_onDetectionMarker`). Então
  se um jogador veste um colete dentro do carro enquanto já está parado sobre o
  marcador de um outpost/base inimiga, e há inimigo próximo, o motivo registrado
  é `clothesVeh2` (compromised + veículo marcado), não `Outpost` (que só marca
  o veículo). É um comportamento mais rígido, intencional no design desta
  mudança, mas não documentado antes — não é bug se você observar a punição
  dupla nesse cenário específico.

---

## Checklist de execução

Quando estiver testando, marque cada item com `[x]` enquanto executa:

- [ ] 1. Ativar undercover em carro civil com colete
- [ ] 2. Entrar em carro civil com fuzil e sem colete
- [ ] 3. Vestir colete dentro do carro, longe de inimigos
- [ ] 4. Vestir colete dentro do carro com inimigo a menos de 350 m
- [ ] 5. Capacete leve (armor entre 1 e 2)
- [ ] 6. Atravessar roadblock inimigo undercover (tierWar alto)
- [ ] 7. Entrar em marcador de outpost undercover
- [ ] 8. Voar undercover perto de outpost
- [ ] 9. Dirigir fora de estrada com inimigo a menos de 350 m
