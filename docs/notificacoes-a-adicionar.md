# Notificações a adicionar

Fila de avisos que o sistema **ainda não** emite. Nada aqui está implementado: a
decisão de cada item fica para os **testes reais de uso do app**, quando der para
ver quem realmente quer ser avisado e com que frequência — avisar demais treina o
usuário a ignorar, e esse estrago é difícil de desfazer.

Ao implementar um item, tire-o daqui e leve a explicação para o código.

---

## O que já existe hoje (para não reimplementar)

- **A data fecha o Barter.** `endsAt` trava: passada a data, a API recusa permuta
  nova (`isOpenAt` em
  [version-progress.ts](../api/src/seasons/version-progress.ts)).
- **A meta fecha ou avisa, conforme o lançamento escolheu** (`closeOnGoal`). No
  automático, quem encerra é a aprovação que cruzou a meta — sem notificação
  nenhuma envolvida: o Barter simplesmente fecha, e o consultor descobre ao
  tentar registrar a próxima permuta. **É isso que faz o aviso de 85% valer mais
  do que valia:** no automático ele é o único momento em que dá para mudar de
  ideia antes de a operação parar.
- **O `ratio` de cada meta já vem calculado da API** (`goalsOf` em
  [version-progress.ts](../api/src/seasons/version-progress.ts)), 0–1 saturado em
  1, e já chega ao app em `BarterGoal`
  ([models.dart](../app/lib/models/models.dart)).
- **Aviso de meta atingida:** faixa verde no card de metas
  ([barter_program_screen.dart](../app/lib/screens/barter_program_screen.dart)),
  só em 100%, e só para quem abre aquela tela.
- **Exigência de classe:** barra de progresso ao vivo no formulário da permuta
  (`_classProgress` em
  [barter_screen.dart](../app/lib/screens/barter_screen.dart)).

## Pré-requisito comum: escolher o canal

Não existe canal de notificação no projeto — nem `firebase_messaging` no app,
nem envio de push/e-mail na API. Antes do primeiro item, decidir entre:

- **(a) faixa/badge in-app** — zero infra, aparece quando a pessoa abre a tela;
- **(b) push (FCM)** — o Firebase já está no projeto para hosting e App
  Distribution, mas push pede token por dispositivo, permissão no iOS e um
  registro de "já avisei" no servidor;
- **(c) e-mail** — chega sem o app aberto, e é o que o admin costuma ler.

Sugestão: começar em **(a)** para todos os itens e só promover a (b)/(c) o que os
testes mostrarem que precisa chegar com o app fechado.

---

## 1. Meta perto de bater — faltando 15%

O pedido que originou este arquivo.

- **Quem recebe:** admin (é quem encerra o Barter — ou quem escolheu deixar o
  Barter encerrar sozinho, e aí o aviso é o último momento de mudar de ideia).
- **Gatilho:** `ratio >= 0.85 && !met` — o dado já existe, nada precisa ser
  recalculado.
- **O que falta:** um limiar com nome em um lugar só (algo como
  `GOAL_NEAR_RATIO = 0.85` em `version-progress.ts`), um campo `near` no `Goal`
  para o app não repetir a conta, e o texto do aviso.
- **Por meta, não por versão:** o painel mostra as três metas (vendas, sacas,
  quantidade) e elas andam em ritmos diferentes; o aviso deve dizer **qual**
  chegou perto, senão o admin não sabe o que olhar.
- **Cuidado que só o uso real mostra:** o `ratio` anda para os dois lados —
  permuta negada ou estornada faz a barra **descer**. Numa faixa in-app isso é
  inofensivo (ela aparece e desaparece). Em push, é o mesmo aviso chegando várias
  vezes: aí precisa gravar "já avisei nesta meta desta versão" e só rearmar
  quando a versão virar.
- **A definir no teste:** 15% é o número certo? Talvez o admin queira ser avisado
  mais cedo (20–25%) para dar tempo de decidir se encerra ou deixa correr.

## 2. O Barter FECHOU sozinho (nasceu com o encerramento automático)

Item novo, e o mais concreto dos três: com `closeOnGoal` ligado, o Barter fecha
no meio do expediente e **ninguém é avisado**. Hoje quem descobre é:

- o **consultor**, ao tentar registrar a próxima permuta e receber "Não há Barter
  aberto no momento";
- o **admin**, ao abrir a aba de lançamento e ver o cartão de "nenhum Barter
  lançado".

- **Quem recebe:** admin (precisa publicar a próxima versão) e consultores (param
  de vender no mesmo instante).
- **Gatilho:** existe e é exato — `closeIfGoalReached` já sabe a hora, a meta e a
  aprovação que fechou, e já escreve isso no `closedBy` e na trilha.
- **A definir no teste:** o consultor precisa saber na hora, ou a mensagem no
  envio basta? Depende de quanto tempo passa entre o fechamento e a publicação da
  próxima versão — se for minutos, a mensagem basta; se for dias, não.

## 3. Exigência de classe perto do mínimo (candidato — provavelmente descartar)

- **Quem receberia:** consultor, montando a permuta.
- **Gatilho:** `_classProgress(c) >= 0.85 && !_classMet(c)`.
- **Por que provavelmente não vale:** a barra da classe já está na tela, ao vivo,
  a cada insumo digitado — um aviso em cima dela é ruído. Fica registrado só para
  ser decidido (e descartado) com o app na mão, e não esquecido.

---

## Quando for testar de verdade

- [ ] Escolher o canal (a/b/c) antes de escrever a primeira notificação.
- [ ] Confirmar com o admin o limiar do item 1 (15% ou outro).
- [ ] Ver se o aviso repetido incomoda — é isso que decide se precisa de registro
      de "já avisei".
- [ ] Rodar um Barter inteiro com `closeOnGoal` ligado e ver quanto incomoda o
      fechamento silencioso (item 2).
- [ ] Fechar o item 3: implementar ou apagar.
