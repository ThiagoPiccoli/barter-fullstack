# Guia de arquitetura — Barter (app + api)

Guia de leitura do código **como ele está hoje**. A ideia é abrir este arquivo
ao lado do editor e ir seguindo: cada seção diz o que uma peça faz, por que ela
existe e qual arquivo abrir.

---

## 0. A regra que explica tudo

Antes de qualquer arquitetura, o domínio:

> O produtor **retira insumos** (adubo, defensivo, semente…). Esses insumos
> formam um **custo em R$**. Esse custo é convertido em **sacas de um grão**,
> que o produtor entrega na colheita. Sacas são **consequência** do custo —
> nunca o contrário.

E a conversão continua mais um passo, porque as sacas precisam nascer em algum
lugar:

> As sacas devidas são divididas pela **produção estimada** da cultura (sc/ha) e
> acrescidas de uma **margem de segurança**. O resultado é a **área de lavoura**
> que o produtor dá em **penhor** na cédula — e as matrículas que ele informa
> precisam somar essa área. Hectares são **consequência** das sacas, como as
> sacas são do custo.

E, acima disso, **quem decide os valores é a empresa, não a permuta**:

> O **Barter é lançado**: a empresa abre uma **safra** sobre um grão (`S2026`) e
> publica **versões** dela (`S2026.01`, `S2026.02`…). Cada versão carrega o
> valor da saca e a tabela de preço/custo dos insumos, e vale por um período. A
> permuta do consultor nasce **dentro da versão vigente** e guarda os valores
> dela para sempre.

```
Safra  S2026 "Soja 2026"          (um grão, uma temporada — uma aberta por vez)
 ├─ Barter S2026.01  encerrada     (tabela de valores + vigência + metas)
 └─ Barter S2026.02  VIGENTE       ← só existe uma; publicar a próxima encerra esta
      ├─ Permuta PRM-2026-014
      └─ Permuta PRM-2026-015
```

Consequências que aparecem no código inteiro:

- o consultor **não escolhe grão** (era a etapa 3 da tela de permuta) nem vê
  preço: ele escolhe produtor e insumos, e o servidor faz o resto;
- **insumo fora da tabela da versão não é permutável** — a versão define o que
  está na mesa;
- publicar a próxima versão **não reescreve** o que já foi acordado: os itens da
  permuta guardam preço **e custo** do momento;
- sem Barter aberto, `POST /barters` responde 422 e o app mostra "Barter
  fechado". Não é erro, é estado.

E, uma vez montada, a permuta entra numa **linha de produção de cinco postos**:

```
Rascunho ──▶ No gerente ──▶ No comitê ──▶ A faturar ──────────▶ Faturada ──▶
(consultor)  (parecer)      (decide)      (faturista)                      │
                                ├──▶ Aprovada com ressalva ────┘           │
                                └──▶ Negada                                │
     ┌─────────────────────────────────────────────────────────────────────┘
     ▼
CPR emitida ──▶ CPR assinada ──▶ CPR registrada
  (emissor)       (emissor)        (emissor)
```

Cada posto tem UM dono e UMA pergunta: o **consultor** monta a permuta, escreve
o parecer DELE sobre o próprio cliente e **preenche a cédula** — enquanto não
encaminhar, ela é `draft` e não está na mesa de ninguém; o **gerente** conhece o
produtor e a negociação e escreve o parecer técnico (não decide); o **comitê** lê
o pedido e os dois pareceres e **decide** — é a única instância que aprova,
aprova COM RESSALVA ou nega; o **faturista** recebe o que as etapas anteriores
produziram, **fatura** o que foi aprovado e **anexa as notas fiscais**; o
**emissor** confere a cédula que o consultor preencheu, **emite** o título,
**colhe as assinaturas** (anexando o papel assinado) e o **leva a registro**.

**Faturar deixou de ser o fim da linha.** Uma permuta faturada ainda deve o
título que formaliza a entrega do grão, e enquanto a emissão da CPR não teve
etapa ela acontecia "junto com" o faturamento — isto é, sem prazo, sem estado e
sem quem respondesse por ela. Uma permuta parada com a cédula pela metade
aparecia como concluída. Hoje ela diz o que falta, e a quem.

**A emissão é a CONFERÊNCIA do fluxo.** É o único momento em que alguém recusa um
papel: o emissor lê contra o modelo o que os outros postos produziram, e a cédula
com lacuna não sai — a recusa é um 422 com a lista do que falta, cada item
dizendo com quem ele se resolve (o RG é com o consultor, a nota é com o
faturista, o vencimento é com quem cadastra a safra). Ele não devolve a permuta a
ninguém: não há caminho de volta aqui, só um papel que ainda não está pronto.

**O rascunho é do dono.** Registrar e encaminhar viraram dois atos porque montar
os insumos e ter a conversa com o produtor são dois momentos: o consultor guarda
a permuta com os valores da versão já congelados e escreve o parecer quando
tiver o que dizer. Nenhuma fila da retaguarda enxerga um rascunho — `scopeFor`,
no service, o esconde de quem não o registrou.

**A cédula é PRÉ-REQUISITO do encaminhamento**, e o portão está no `forward`
(`requireCprFilledBy`, depois da conferência do parecer). O motivo é o custo de
voltar atrás: o emissor descobrindo que falta a matrícula de uma lavoura com a
permuta já faturada e o insumo já retirado obriga a caçar o produtor semanas
depois do único momento em que a informação estava à mão — a visita. O
encaminhamento é o último instante em que esse custo é zero.

Ele cobra **só as pendências do consultor** (`consultantCprGaps`): a nota fiscal
não existe antes do faturamento, o vencimento é da safra e o número da cédula é
do emissor — exigir qualquer um deles aqui travaria a esteira num impossível. É
para isso que cada pendência tem DONO (`CPR_GAP_OWNER`, em
[cpr.ts](../api/src/barters/cpr.ts)): a mesma lista de lacunas responde a três
perguntas diferentes conforme quem a lê.

A mesa da cédula devolve esse recorte em `consultantGaps`, ao lado de `gaps` (a
lista inteira) e de `creditorGaps` (a do admin). A tela do rascunho avisa com ela
e **desliga o botão** de encaminhar — a recusa do servidor continua lá como
guarda, mas ela é a exceção, não o caminho: um pré-requisito que só se descobre
clicando é uma armadilha, e a pessoa teria escrito o parecer inteiro antes de
saber. No app, o fluxo de criação **emenda na cédula** logo depois de registrar a
permuta (em [send_simulation.dart](../app/lib/screens/send_simulation.dart)), e o
encaminhamento que a cédula barrou é retomado ali mesmo quando ela fecha.

**A ressalva é um estado, e não uma observação.** `approvedWithConditions` está no
MESMO degrau de `approved` (a mesa do faturista) e leva uma exigência escrita
junto — garantia real, seguro obrigatório, aval —, obrigatória na decisão. Fosse
um campo dentro da aprovação, a lista e o cartão diriam "Aprovada — a faturar"
sobre uma permuta que só anda depois de alguém providenciar um aval, e a única
maneira de descobrir isso seria abrir a permuta e ler até o fim. Pelo mesmo
motivo a **negativa** exige texto: é a resposta que o consultor leva ao produtor.

**O admin não decide.** Ele administra o sistema (contas, catálogo, valores,
unidades) e enxerga tudo. A capacidade `barters.review` era dele e foi para o
comitê: quem administra o acesso não pode ser também quem decide o negócio,
porque aí é a mesma pessoa concedendo o poder e usando-o.

**Há UM caminho de volta, e ele tem dono nas duas pontas.** A esteira só anda
para a frente, mas a permuta erra depois de sair da mão de quem a montou — o
produtor troca um insumo na véspera da retirada, a quantidade saiu errada. O
consultor que registrou pode então **pedir alteração** (`POST
/barters/:code/change-request`, com justificativa) em qualquer permuta que não
tenha sido faturada, e quem decide é o **admin** (`.../change-request/decision`):

```
                     ┌─ liberado ─▶ volta a Rascunho (parecer e decisão APAGADOS)
pedido do consultor ─┤
                     └─ recusado ─▶ fica onde estava, com o motivo escrito
```

A alteração **atravessa versões e não atravessa culturas**: a permuta fechada na
primeira versão da soja continua alterável com a terceira no ar (ela não foi
faturada, e o que falta nela é uma correção de insumos), mas com o Barter do
milho aberto uma permuta de soja não se remonta, porque os insumos, os mínimos e
o grão que a paga são outros. Os PREÇOS da remontagem são os da gestão em que a
permuta foi fechada, e é para isso que existe `GET /barters/:code/version`: a
tela precisa da tabela daquela versão, não da vigente.

O pedido **não move a permuta**: ela continua na fila em que estava, com uma
bandeira que todo mundo enxerga — quem a tem na mesa precisa saber que os
insumos podem mudar antes de gastar um parecer sobre eles. Quem decide é o admin
porque o que se julga aqui é o **processo**, e não o negócio: liberar joga fora o
trabalho assinado do gerente e do comitê (a história fica nos `BarterEvent`; o
que é apagado é o estado atual, que passou a ser falso). Liberada, ela é rascunho
de novo — os insumos se reescrevem por `PUT /barters/:code/inputs`, contra as
mesmas travas do registro, e ela percorre a linha inteira outra vez. A regra mora
em [change-request.ts](../api/src/barters/change-request.ts), FORA de
`BARTER_STEPS`: um desvio que quase nenhuma permuta toma não é um degrau da
esteira, e como etapa ele apareceria como pendência em toda permuta do sistema.

**O admin atende sem devolver, quando o que mudou é um número.** A maior parte
dos pedidos que chegam é de uma linha de R$ — o valor da semente saiu diferente
do que foi combinado com o produtor, o fornecedor cotou outro preço para aquela
quantidade. Devolver a permuta ao rascunho por causa disso joga fora dois
pareceres e uma decisão para corrigir o que o admin já tem na mão, e ainda
obriga o consultor a remontá-la e reencaminhá-la. Então há uma **terceira
saída**: `POST /barters/:code/change-request/prices` escreve o valor novo nos
itens, o servidor **recalcula as sacas** e a permuta continua exatamente onde
estava, com quem estava.

Ela só existe **dentro de um pedido em aberto**: sem pedido não há o que
atender, e um admin reprecificando permuta por iniciativa própria estaria
decidindo o negócio — que é justamente o que ele não faz. O item guarda o valor
de TABELA de onde saiu (`BarterItem.listValue`), para a tela poder mostrar
"R$ 110,00 (tabela: R$ 120,00)" em vez de um número sem história, e o evento da
linha do tempo diz o que mudou, de quanto para quanto: é o que o gerente e o
comitê leem para saber que a permuta que eles analisaram não é mais a mesma. O
**grão** fica fora: as sacas são o resultado do custo, e não um campo.

**E há o que a tabela não tem.** A tabela do Barter é uma lista fechada,
publicada de uma vez para a praça inteira; a lavoura não é. O produtor quer o
adjuvante da marca dele, um serviço que ninguém lançou, uma semente sob
encomenda. O consultor **pede um produto de fora do Barter** (`POST
/barters/:code/product-requests` — produto, unidade e quantidade, sem preço: ele
não vê R$, e é justamente o item que ninguém precificou) e o admin **atende com
um valor** (`.../product-requests/:id/decision`), que é a única coisa que ele
decide aqui.

```
                     ┌─ incluído ─▶ entra NESTA permuta, com valor; as sacas são recalculadas
pedido de produto ───┤
                     └─ recusado ─▶ nada entra, com o motivo escrito
```

O item fica amarrado **à permuta**, e a nada mais: ele foi cotado para aquela
quantidade, naquela data, naquele negócio. Ele **não entra no catálogo** — o
catálogo é a lista do fornecedor, e um produto criado a partir de um pedido
apareceria no relatório de preços e na carga seguinte como se fosse da praça.
Outra permuta do mesmo produtor pede de novo, e é assim que se percebe que o
item deixou de ser exceção: quando o mesmo pedido chega pela quinta vez, ele não
é mais um pedido — é uma linha que falta na próxima versão do Barter.

Duas consequências que merecem nome. A primeira: o item de fora **paga em sacas
como qualquer outro** (ele foi retirado) e **não entra em régua nenhuma** — nem
no mínimo por hectare, nem no de classe, nem como denominador deles. Sem classe,
ele nunca somaria no numerador de uma pasta e engordaria o denominador de todas:
um pedido atendido derrubaria, na remontagem, a permuta que ele veio ajudar. A
segunda: a janela vai **do rascunho até a decisão do comitê**, e o rascunho
dentro dela é o oposto do pedido de alteração — é ali que o consultor monta a
permuta e topa com o que falta. Depois da decisão, um insumo a mais mudaria o
que foi aprovado, e o caminho volta a ser o pedido de alteração. Por causa disso
o admin enxerga o rascunho que **pediu alguma coisa a ele**, e só esse: um
rascunho não é fila de ninguém, menos quando ele próprio bate na porta.

A regra mora em [product-request.ts](../api/src/barters/product-request.ts),
FORA de `BARTER_STEPS` pelo mesmo motivo do desvio.

**Onde o pedido é feito, no app.** Ele tem dois pontos de partida, e o segundo
existe porque a falta aparece antes da permuta: no **detalhe** de uma permuta
registrada (o botão ao lado de "Solicitar Alteração") e no **construtor**, que é
onde o consultor procura o adjuvante na lista e não acha. Lá o que existe é uma
*simulação* — ela mora no aparelho, e o servidor não a conhece —, então o botão
faz as duas coisas num ato só: **registra a permuta como rascunho e manda o
pedido** (`registerToRequestProduct`, em
[send_simulation.dart](../app/lib/screens/send_simulation.dart)). Rascunho, e
nunca encaminhada: registrar para pedir não é mandar a permuta ao gerente. O
diálogo diz isso antes de qualquer campo, porque o rodapé daquela tela promete
que nada é enviado agora — e em duas etapas (registrar, pedir depois) o pedido
cancelado deixaria uma permuta registrada que ninguém pediu para registrar.

O caminho inteiro mora em [barter-workflow.ts](../api/src/barters/barter-workflow.ts) —
os estados, quem move o quê e **o que responder a quem chega fora de hora**. Essa
última parte não é enfeite: dizer "já foi decidida" a quem espera o gerente manda
a pessoa procurar uma decisão que ninguém tomou, quando o que ela precisa saber é
com quem a permuta está parada. O JSON da permuta carrega isso resolvido
(`waitingFor`, `nextAction`, `statusLabel`), e é por isso que o app não tem uma
segunda cópia do fluxo em Dart.

O nome técnico da etapa do comitê continua sendo **revisão** — a rota é
`POST /barters/:code/review`, os campos são `reviewedBy`/`reviewedAt` —, e nas
telas ela aparece como **decisão**, que é o que ela é. O que não muda é a
distinção que motivou o vocabulário: o gerente ANALISA, o comitê DECIDE, e dar o
mesmo nome às duas deixava as etapas indistinguíveis para quem lê.

Toda passagem de um estado para o outro vira um **evento** na linha do tempo da
permuta (`BarterEvent`), gravado na mesma transação da mudança: sem evento não há
mudança de estado. É o histórico do documento — quem enxerga a permuta enxerga
por onde ela passou —, e é diferente da trilha de auditoria (`AuditLog`), que é
global, só o admin lê e é best-effort de propósito.

O consultor tem um **gerente**, e é a ele que a permuta chega. O gerente
escreve um **parecer técnico** — texto, e só texto: ele não aprova nem nega — e
é isso que faz a permuta seguir. Duas consequências que aparecem no código:

- o cadastro do consultor **exige um gerente** ([user.dto.ts](../api/src/users/dto/user.dto.ts),
  `CreateConsultantDto`). Um consultor sem gerente registraria permutas
  endereçadas a ninguém: sem erro, sem alarme e sem a quem cobrar;
- a permuta guarda **a quem foi enviada** (`Barter.managerId`, gravado no
  ENCAMINHAMENTO — que é onde o envio acontece). Trocar o gerente de um consultor
  vale para as próximas; as que já estão na mesa de alguém continuam lá — o contrário faria uma permuta mudar de
  mãos sem ninguém ter agido sobre ela.

**A unidade de retirada não tem nada a ver com isso.** Ela é o lugar onde o
produtor busca os insumos, escolhido pelo consultor a cada permuta, e pode ser
qualquer uma — inclusive de outra praça. Ela não tem responsável, não roteia o
parecer e não participa de mínimo nem de preço. Ela existe como cadastro, e não
como o texto livre que era (`branch`), porque "Filial 02", "filial 02" e "F02"
eram três lugares em qualquer lista ou relatório.

Cinco regras derivam disso e aparecem nos dois lados do código:

| Regra | Onde nasce | Onde é imposta de verdade |
|---|---|---|
| Só se permuta com Barter aberto | lançamento da versão | servidor ([seasons.service.ts](../api/src/seasons/seasons.service.ts), `requireOpenVersion`) |
| Preço do insumo e da saca vêm da VERSÃO | planilha publicada | servidor ([barters.service.ts](../api/src/barters/barters.service.ts) passos 1 e 5) |
| Insumo com `requiredPerHa` é obrigatório: `taxa × área` | cadastro do produto | servidor ([barters.service.ts](../api/src/barters/barters.service.ts) passo 3) |
| CLASSE com regra de mínimo trava o envio | regra da classe | servidor ([barters.service.ts](../api/src/barters/barters.service.ts) passo 4) |
| Sacas = custo ÷ valor da saca da versão | — | servidor ([barter-math.ts](../api/src/barters/barter-math.ts)) |

**Classe vem da lista de preços.** A coluna `Família` do arquivo do fornecedor é
a taxonomia, e a carga em massa cria a classe que ainda não existe — foi assim
que `FERTILIZANTES FOLIARES`, `OLEOS e ADJUVANTES` e `INOCULANTES` entraram. O
que NÃO existe é criar, renomear ou excluir classe pelo app: quem define o
vocabulário é a lista, não quem cadastra. O casamento é por nome normalizado ou
slug, e é isso que impede "Defensivo", "DEFENSIVOS" e "Defensivos Foliares" de
virarem três classes medindo mínimos diferentes. O que o admin ajusta é a REGRA
de mínimo de cada uma (`PUT /classes/:id/rule`) — decisão comercial, que muda de
safra para safra.

Cada classe tem **figura e cor próprias** no app
([class_avatar.dart](../app/lib/widgets/class_avatar.dart)), indexadas pela
posição dela na paleta da marca. Antes era o mesmo frasco repetido em todas as
linhas: com 656 itens, um ícone que nunca muda ocupa a coluna onde o olho
procura diferença e não oferece nenhuma. Classe nova aparece com o ícone
genérico de insumo até alguém escolher a dela.

**Data trava; meta avisa ou fecha, e isso é opção do lançamento.** A `endsAt` da
versão é uma decisão com hora marcada: passada a data, a API recusa permuta nova.
As metas (vendas, sacas, quantidade) medem, e o efeito de batê-las é escolhido ao
publicar — `closeOnGoal`:

| Modo | O que acontece ao bater a meta |
|---|---|
| Manual (padrão) | o painel do admin acende o aviso; encerrar é um toque dele |
| Automático | a **aprovação que cruzou a meta** encerra a versão, na hora |

O automático **não tem relógio**: quem fecha é `closeIfGoalReached`
([seasons.service.ts](../api/src/seasons/seasons.service.ts)), chamado depois de
cada decisão do comitê — o único ato que faz o realizado crescer. Assim o
fechamento tem hora, ator e motivo (o `closedBy` da versão fica
`Automático — meta de vendas atingida (…)`), em vez de acontecer de madrugada.
Falhando, o Barter só continua aberto com a meta batida: o estado do modo manual.

O admin troca o modo na versão vigente sem republicar a tabela
(`PUT /barter-versions/:code/close-on-goal`); ligar com a meta **já** batida
encerra na hora, e a tela avisa antes. As contas moram em
[version-progress.ts](../api/src/seasons/version-progress.ts), junto de
`isOpenAt` — que segue olhando só data e status, porque no automático a versão já
chega com `status: closed`.

**O Barter mede vendas, não lucro.** A lista de preços do fornecedor traz preço
de VENDA e mais nada — não há custo em lugar nenhum do modelo. Enquanto houve
(com custo zerado), "lucro" e "faturamento" mostravam o mesmo número com nomes
diferentes, que é pior do que um número a menos.

E as regras de acesso — **cinco papéis**, definidos em um só lugar
([roles.ts](../api/src/common/roles.ts)):

| Papel | `role` | Enxerga | Faz hoje |
|---|---|---|---|
| Administrador | `admin` | tudo | cadastros, unidades, catálogo/preços (**não decide permuta**) |
| Gerente | `manager` | **só o time dele** | **parecer técnico** das permutas que recebe |
| Comitê | `committee` | tudo | **decide** as permutas com parecer (aprova, aprova com ressalva ou nega). É um ÓRGÃO: cadastro único |
| Faturista | `biller` | **o que chegou ao faturamento** | **fatura** as permutas aprovadas e **anexa as notas fiscais** |
| Emissor | `emitter` | **o que chegou à emissão** | **emite** a CPR, anexa a **assinada**, e a **registra** |
| Consultor | `consultant` | só a **própria carteira** | registra permuta e **preenche a cédula** dos produtores que atende |

- Cada posto escreve UMA coisa, e nenhum escreve a do outro: o gerente opina, o
  comitê decide, o faturista fatura, o emissor emite. A matriz inteira — quatro
  papéis × quatro atos, mais o admin, que não é dono de nenhum — é varrida em
  ([rbac.e2e-spec.ts](../api/test/rbac.e2e-spec.ts)).

**O EMISSOR nasceu de uma correção.** A cédula era do faturista, com o argumento
de que o posto que emite documento para fora é o mesmo que emite a nota — e o
argumento não se sustentou na prática, por dois motivos que se somam:

1. **nada do que a cédula pede está na mesa de quem fatura.** A matrícula da
   lavoura, o nome do cônjuge, quem é o dono do imóvel arrendado, o SCR do
   produtor: tudo isso quem tem é quem visita a fazenda. O faturista os obtinha
   por telefone, do consultor, e digitava — e cada intermediação dessas é um RG
   com um dígito trocado dentro de um título executável. **Preencher foi para o
   consultor**;
2. **faturar e emitir CPR são dois ofícios.** Faturar é ato fiscal, contra o
   estoque e a nota de venda. Emitir CPR é pôr em circulação um **título de
   crédito**: ele é conferido, assinado por gente (às vezes por um casal, às
   vezes com avalista) e levado a registro, em dias diferentes. **Emitir foi para
   o emissor**, e `creditor.manage` foi junto — o timbre segue quem emite o
   papel, não quem emite a nota.

Quem responde "o que cada papel pode" é **uma tabela só**,
[policy.ts](../api/src/common/policy.ts):

| Capacidade | Quem tem |
|---|---|
| `users.manage` · `producers.manage` · `units.manage` · `catalog.manage` · `barter.manage` · `audit.read` | admin |
| `producers.readAll` | admin, gerente, comitê, faturista, emissor |
| `barters.readAll` | admin, comitê |
| `barters.readTeam` · `barters.opinion` | gerente |
| `barters.readInvoicing` | **faturista** — o que chegou ao faturamento |
| `barters.readIssuance` | **emissor** — o que chegou à emissão, um degrau adiante |
| `barters.review` | **comitê** (era do admin) |
| `barters.investmentPerHa` | admin, comitê, faturista, emissor — o sc/ha, a régua que compara permutas |
| `barters.invoice` | **faturista** — faturar e anexar as notas |
| `barters.cprFill` | **consultor** — preencher a cédula (era do faturista) |
| `barters.cprIssue` | **emissor** — emitir, colher assinaturas e registrar |
| `barters.cprRead` | admin, **consultor** e **emissor** — ler a mesa da cédula e gerar o documento |
| `creditor.manage` | admin **e** emissor (a única dividida — é o timbre, não decisão) |
| `pledge.policy` | **admin** — a margem de segurança do penhor. Separada de `creditor.manage` porque aquela é do emissor também, e isto É decisão |
| `barters.changeReview` | **admin** — decide o pedido de alteração (processo, não negócio) e atende no valor |
| `barters.productReview` | **admin** — atende o pedido de fora do Barter: inclui o item com o valor acertado |
| `barters.register` · `barters.changeRequest` · `barters.productRequest` · `barters.cprFill` | consultor |

`barter.manage` (lançar safra e versões) é separada de `catalog.manage`
(cadastro do produto e regra das classes) de propósito: uma decide **por
quanto** se troca, a outra só mexe em nome, unidade e classe.

**O COMITÊ É UM ÓRGÃO, NÃO UMA PESSOA.** Ele é uma *reunião*: quem decide a
permuta não é o fulano do comitê, é o comitê reunido. O cadastro segue isso — um
só, na rota singular `/committee`, sem `:id` e sem exclusão
(`isSingleAccount` em [roles.ts](../api/src/common/roles.ts)). Uma conta por
integrante criaria três problemas de uma vez: a decisão do colegiado sairia
assinada por um nome, entrar no comitê viraria cadastro de usuário (quando é ata
de reunião) e o admin teria de manter em dia uma lista que muda a cada
composição. A unicidade é do PAPEL e não do e-mail — senão um segundo cadastro
passaria batido e a operação teria dois órgãos decidindo a mesma fila.

O preço é real e está assumido: com o login compartilhado, a trilha registra
"Comitê", não quem estava na sala. Por isso a observação da decisão se chama
**ata** na tela — é ali que se guarda quem participou e o que foi acordado. O dia
em que isso precisar ser estruturado, o caminho é um cadastro de REUNIÃO com
participantes, e não uma conta por pessoa.

Os outros quatro continuam sendo pessoas, com rota plural: consultor, gerente,
faturista e emissor. Faturar é ofício de gente — vários fazem, e cada um responde
pelo que emitiu (o nome dele fica na linha do tempo da permuta). O emissor pelo
mesmo motivo, e com um a mais: quem assina a conferência de um título responde
por ela com o próprio nome.

**O gerente é o único com escopo de TIME.** Ele enxerga as permutas endereçadas
a ele, e não a operação inteira: ele não é auditor — responde por um time, e a
permuta de outro time não é assunto dele. Enquanto teve `barters.readAll`, a
fila que pedia ação dele ficava misturada com tudo, e a tela não tinha como dar
ênfase ao que era dele. Os quatro escopos vivem numa função só
(`scopeFor` em [barters.service.ts](../api/src/barters/barters.service.ts)), e a
listagem e o detalhe leem a MESMA — antes eram duas regras que podiam divergir.

**O faturista enxerga o TRECHO DELE da linha**, e nada antes: as permutas
aprovadas e as já faturadas (`barters.readInvoicing`). Ele também teve
`barters.readAll`, e o preço aparecia na tela — a fila do gerente, a mesa do
comitê e as permutas negadas contadas no painel de quem não participa de nenhuma
dessas etapas. Ele recebe o que as etapas anteriores produziram; negociação em
aberto não é informação de quem emite a nota. QUAIS estados são esses não está
escrito no service: quem responde é `lineFrom(invoice)` em
[barter-workflow.ts](../api/src/barters/barter-workflow.ts), de modo que mexer na
linha mexa no alcance junto.

**O emissor enxerga um degrau adiante**, e é o escopo mais estreito de todos:
`barters.readIssuance` = `lineFrom(cprIssue)`, a faturada e o que já andou na
cédula. A negociação que ainda está no comitê não é trabalho de quem leva um
título a cartório.

**O comitê é o único posto que olha para TRÁS.** Ele mantém `barters.readAll` de
propósito: o que está no gerente é a fila que vai cair na mesa dele. O painel
dele conta esse número ao lado do que já espera decisão e abre um bloco *No
gerente* agrupado **por gerente**, com o total em sacas e há quantos dias a mais
antiga de cada um espera (mesmos cortes de urgência do painel do admin: 7 e 14
dias). Agrupar por pessoa em vez de listar permuta a permuta é a escolha do
painel — a lista completa está a um toque, na aba *No gerente*; o que não estava
em lugar nenhum é **quem está segurando e há quanto tempo**.

**Toda ação confere a LEITURA antes de agir.** `requireBarter` pergunta, nesta
ordem: a permuta existe? você a enxerga? ela está no ponto desta etapa? A do
meio chegou com o escopo do faturista, e é ela que fecha a porta dos fundos —
enquanto a permuta era buscada sem recorte, pedir o faturamento de um código
qualquer respondia *"aguarda o parecer do gerente Fulano"*, isto é, o estado e o
nome de gente de uma etapa que não é dele. A mensagem da etapa continua existindo
para quem ENXERGA a permuta (é o que diz a quem chegou cedo com quem ela está
parada); ela só não é mais a maneira de descobrir o que o escopo esconde.

`barters.opinion` é o caso em que a capacidade **não basta**. Ela diz que gerente
dá parecer; ela não diz que ESTE gerente dá parecer NESTA permuta — isso depende
do recurso. Hoje quem responde é o próprio escopo de leitura dele: o do gerente é
o time (`managerId`), então "fora do escopo" e "endereçada a outro gerente" são a
mesma frase dita de dois jeitos, e o 403 traz o texto certo. Era uma comparação à
parte dentro do `giveOpinion`, e ela saiu quando toda ação passou a conferir a
leitura: duas regras respondendo à mesma pergunta é uma a mais do que se mantém
em dia.

A rota declara a CAPACIDADE de que precisa (`@RequireCapability`), não quem
entra; os services perguntam à mesma tabela (`can(user, ...)`) para decidir o
escopo por linha. Antes disso a autorização morava em dois lugares que não se
falavam — o decorator e um `seesEverything()` dentro dos services —, e não
havia arquivo nenhum onde se lesse o que um faturista pode.
- **Produtor não é usuário** — ele não loga, é um cadastro.
- **Unidade não é papel** — ela é um local de retirada, sem dono e sem alçada.

---

# PARTE 1 — Backend (`api/`)

**Stack:** NestJS 11 · Prisma 7 (adapter `pg`) · PostgreSQL · TypeScript.
Sem JWT, sem Passport, sem bcrypt: autenticação é token opaco em tabela, hash de
senha com `scrypt` nativo do Node.

## 1.1 O caminho de uma requisição

```
HTTP  POST /api/v1/barters
  │
  ├─ 0. middleware ............ helmet, log da requisição, parser com limite
  │                              (256kb) — e o tradutor dos erros do parser
  ├─ 1. ThrottlerGuard ........ limite por IP (antes da auth, de propósito)
  ├─ 2. AuthGuard ............. Bearer → hash → busca no banco → req.user
  │                              (bloqueia quem ainda tem senha provisória)
  ├─ 3. AccessGuard ........... global; NEGA por padrão — toda rota declara a
  │                              sua política (@RequireCapability/@AnyRole/@Public)
  ├─ 4. ValidationPipe ........ DTO com class-validator → 422 se inválido
  │                              (whitelist: campo não declarado é DESCARTADO)
  ├─ 5. Controller ............ fino: só extrai user/params e chama o service
  ├─ 6. Service ............... REGRA DE NEGÓCIO + Prisma
  ├─ 7. Serializer ............ toBarterJson(...) — o contrato com o app
  ├─ 8. EnvelopeInterceptor ... embrulha em { data: ... } (+ meta se paginado)
  └─ ✗. AllExceptionsFilter ... qualquer erro do caminho acima vira
                                 { message, statusCode } em pt-BR
```

Os passos 1, 2, 4, 8 e o filtro são **globais**, registrados num lugar só:
[app.module.ts](../api/src/app.module.ts). O passo 0 fica em
[app.setup.ts](../api/src/app.setup.ts), compartilhado entre o `main.ts` e os
testes e2e. Vale a pena ler esses dois arquivos primeiro — são o índice do
backend.

**O filtro de erro é o que garante o contrato com o app.** O
[api_client.dart](../app/lib/services/api/api_client.dart) mostra `message`
direto para o usuário, então nenhuma falha pode escapar em inglês, com detalhe
interno, ou sem mensagem. Isso inclui o que nasce fora do Nest: JSON
malformado, corpo grande demais e o texto do limitador de requisições. Erro
inesperado (500) devolve só um `requestId`; a pilha fica no log.

O prefixo `/api/v1`, o CORS e o `trust proxy` ficam em
[app.setup.ts](../api/src/app.setup.ts), separado do
[main.ts](../api/src/main.ts) justamente para os testes e2e subirem um servidor
idêntico ao real.

## 1.2 A anatomia de um módulo

Todo recurso segue o mesmo formato de 4 arquivos. Aprendeu um, aprendeu todos:

```
src/barters/
├── barters.module.ts      declara controller + service
├── barters.controller.ts  rotas HTTP (fino, sem regra)
├── barters.service.ts     regra de negócio + acesso ao banco
└── dto/barter.dto.ts      forma do payload de entrada, com validação
```

Os módulos existentes: `auth`, `producers`, `units`, `users`, `classes`,
`products`, `seasons`, `barters`, `audit`. Mais `prisma` (o client como provider
global) e `common` (peças compartilhadas).

`units` é o CRUD mais simples do backend, e isso é uma afirmação sobre o
domínio: a unidade é um lugar (nome + cidade). Se um dia ele ganhar um campo de
responsável, é sinal de que o modelo mudou — não de que faltava um campo.

`seasons` é o lançamento do Barter: **dois controllers, um service** —
`/seasons` (a safra) e `/barter-versions` (a versão vigente e o histórico) —,
mais duas peças puras: [version-import.ts](../api/src/seasons/version-import.ts)
(a planilha) e [version-progress.ts](../api/src/seasons/version-progress.ts)
(vigência e metas). É o único módulo que `barters` importa: a permuta pergunta
a ele por quanto se troca hoje.

`users` também foge do formato: **quatro controllers, um service**. Cada
papel provisionável tem a sua rota (`/consultants`, `/managers`,
`/committee`, `/billers`) para poder ser guardado e evoluir sozinho,
enquanto senha provisória, e-mail único e reset moram uma vez só em
[user-provisioning.service.ts](../api/src/users/user-provisioning.service.ts).
Todo método dele recebe o papel da rota — é o que faz `PUT /managers/2`
responder 404 quando o 2 é consultor.

**Controller fino é regra aqui.** Compare
[producers.controller.ts](../api/src/producers/producers.controller.ts) com
[producers.service.ts](../api/src/producers/producers.service.ts): o controller
não tem um `if` de negócio sequer.

## 1.3 `common/` — as peças transversais

| Arquivo | Papel |
|---|---|
| [serializers.ts](../api/src/common/serializers.ts) | **O contrato da API em um só lugar.** Toda resposta passa por um `toXxxJson`. Mudou aqui → mudou o app. |
| [decorators.ts](../api/src/common/decorators.ts) | `@Public()`, `@AllowProvisionalPassword()`, `@Roles()`, `@CurrentUser()` |
| [roles.ts](../api/src/common/roles.ts) | **Os cinco papéis em um só lugar**: identificador, rótulo em pt-BR e `seesEverything()` (o escopo de leitura) |
| [policy.ts](../api/src/common/policy.ts) | **A tabela de capacidades**: o que cada papel pode, em um lugar só. `can(user, capability)` é a única pergunta de autorização do sistema |
| [access.guard.ts](../api/src/common/access.guard.ts) | Aplica a política da rota → 403 dizendo QUEM pode. É **global** e **nega por padrão**: rota sem política declarada é recusada e grita no log |
| [envelope.interceptor.ts](../api/src/common/envelope.interceptor.ts) | `{ data: ... }` em toda resposta de sucesso |
| [validation.ts](../api/src/common/validation.ts) | 422 com **uma** string de mensagem (é o que o app exibe) |
| [throttling.ts](../api/src/common/throttling.ts) | limites de requisição, lidos **por requisição** (não em constante de topo — senão o `.env` seria ignorado) |

## 1.4 Autenticação — como funciona sem JWT

Leia nesta ordem: [token.util.ts](../api/src/auth/token.util.ts) →
[password.util.ts](../api/src/auth/password.util.ts) →
[auth.service.ts](../api/src/auth/auth.service.ts) →
[auth.guard.ts](../api/src/auth/auth.guard.ts).

```
login  → confere se a conta não está de castigo (10 erros seguidos = 15 min)
       → gera 32 bytes aleatórios (base64url)
       → grava no banco APENAS o SHA-256 + expiresAt + lastUsedAt
       → devolve o valor cru ao app, e registra a entrada na trilha

request→ AuthGuard faz SHA-256 do Bearer e procura a linha
       → não achou → 401
       → venceu (prazo OU parada tempo demais) → apaga a linha e 401
       → achou → regrava lastUsedAt (no máximo 1x/hora) e req.user = usuário

logout → apaga a linha (revogação REAL, não é só o cliente esquecer)
```

Consequências que aparecem no app: excluir um consultor derruba as sessões dele
em cascata; trocar a senha derruba as outras sessões e mantém a atual.

### As duas mortes de uma sessão

`expiresAt` e `lastUsedAt` respondem perguntas diferentes, e é por isso que
existem os dois:

| | Responde | Padrão |
|---|---|---|
| `TOKEN_TTL_DAYS` | Esta sessão já é velha demais? | 30 dias |
| `TOKEN_IDLE_DAYS` | Este aparelho ainda está com quem deveria? | 7 dias |

Sem a segunda, um celular perdido no sábado continua sendo uma sessão válida
por até um mês — e é justamente no aparelho perdido que o prazo longo dói. Quem
usa o app na rotina nunca chega perto do limite de inatividade.

A regravação do `lastUsedAt` é **represada** (`TOUCH_INTERVAL_MS`, uma hora):
sem isso, toda requisição autenticada da API viraria também um `UPDATE`, no
caminho crítico, para mover um relógio em alguns milissegundos.

O guard só apaga a sessão de quem TENTA usá-la. A que ninguém tenta de novo
(aparelho trocado, app desinstalado, consultor que saiu) ficaria no banco para
sempre — daí a varredura de seis em seis horas em
[session-cleanup.service.ts](../api/src/auth/session-cleanup.service.ts). Não é
segurança: é não guardar dado de autenticação que não serve mais.

### Quando a conta descansa

Dez senhas erradas seguidas e a conta recusa tentativas por 15 minutos, **até a
senha certa**; acertar antes zera o contador. O limite por IP protege o
*servidor*; este protege a *conta*, que é o alvo de quem sabe um e-mail.

A troca aceita aqui está escrita por inteiro em
[lockout.ts](../api/src/auth/lockout.ts): quem souber um e-mail consegue manter
aquela conta trancada de propósito. A trava dura quinze minutos justamente por
isso — uma trava permanente trocaria o roubo de conta por uma negação de serviço
confiável, o que é um péssimo negócio.

**Definir senha nova destranca.** A trava é escrita em UM lugar (o login que
erra) e apagada em QUATRO: o login que acerta, a troca da própria senha, o reset
do admin e o script de emergência. Enquanto o que apagava era um par de campos
digitado à mão, três desses quatro esqueciam — e o reset entregava uma senha que
o login recusava, porque a trava é conferida antes dela. Por isso o estado
"conta sem histórico de erro" é uma constante exportada (`CLEARED_LOCKOUT`), e
não dois campos repetidos: era exatamente a repetição que divergia.

### O que vale como senha

Uma regra, um arquivo:
[password-policy.ts](../api/src/auth/password-policy.ts), usada pelo cadastro,
pela troca da própria senha, pelo script de emergência e pelo provisionamento do
primeiro admin. Dez caracteres, cinco distintos, fora da lista de conhecidas,
sem corrida de teclado, sem conter o nome do sistema nem o de quem escolhe — e
**nenhuma** exigência de maiúscula/número/símbolo, seguindo o NIST SP 800-63B:
regra de composição não gera senha forte, gera `Senha@123`.

O DTO não alcança a parte contextual (o corpo da troca de senha não traz nome
nem e-mail); quem a completa é o `AuthService`, que sabe de quem é a conta.

### Senha provisória — a trava que atravessa tudo

Usuário criado pelo admin — de qualquer papel — nasce com `mustChangePassword: true`
([user-provisioning.service.ts](../api/src/users/user-provisioning.service.ts)). Enquanto essa
flag estiver ligada, o [AuthGuard](../api/src/auth/auth.guard.ts) devolve **403
em toda a API**, exceto nas três rotas marcadas com
`@AllowProvisionalPassword()`: `GET /me`, `POST /auth/password`,
`POST /auth/logout`. Ou seja: a obrigatoriedade não vive na UI — quem chamasse
a API direto também esbarraria nela.

**A senha em si é sorteada, uma por consultor**
([password.util.ts](../api/src/auth/password.util.ts),
`generateProvisionalPassword`), e devolvida **uma única vez** no corpo da
criação. O app a exibe num diálogo com botão de copiar
([provisional_password_dialog.dart](../app/lib/widgets/provisional_password_dialog.dart)).

Isso é o coração de uma correção de segurança, não um detalhe de UX. Enquanto
essa senha foi um valor fixo compartilhado, a trava acima protegia a *API* mas
não a *posse da conta*: quem soubesse o e-mail de um consultor recém-criado
entrava antes dele, chamava `POST /auth/password` — rota liberada, justamente
porque é a saída da senha provisória — e definia a senha definitiva. E não
havia rota de reset: recuperar a conta exigia excluir o consultor, o que
desfazia a carteira inteira de produtores dele.

Hoje existe `POST /consultants/:id/reset-password`: sorteia outra senha e
**apaga todos os tokens daquela conta** na mesma transação. Sem apagar os
tokens o reset não resolveria o caso que mais importa — o invasor continuaria
dentro, com o token na mão. Para o admin, que não tem ninguém acima dele, a
saída equivalente é
[scripts/reset-password.ts](../api/scripts/reset-password.ts).

## 1.4b Autorização — negar por padrão, e a trilha

Duas decisões que mudam como o resto se comporta.

**Negar por padrão.** Toda rota precisa declarar a sua política:
`@RequireCapability(...)`, `@AnyRole()` ou `@Public()`. Rota que não declara
nada é RECUSADA, com um `ERROR` no log apontando o handler.

Isso inverte o desenho anterior, em que ausência de decorator significava
"liberado para qualquer autenticado". Naquele arranjo, acrescentar um
`@Delete(':id')` e esquecer a linha de acesso nascia funcionando — para todo
consultor da cooperativa. Não havia erro, nem teste vermelho, nem sintoma.

O `@AnyRole()` existe para deixar isso explícito onde a abertura é intencional:
`GET /barters` e `GET /producers` valem para qualquer autenticado porque quem
limita o que cada um enxerga é o SERVICE, linha a linha — não a porta.

A rede de segurança é o
[inventário de rotas](../api/test/route-policy.e2e-spec.ts): ele percorre os
controllers que o Nest registrou de verdade e trava a política de cada rota
numa tabela. Rota nova, ou mudança de quem pode chamar uma existente, quebra a
suíte até alguém escrever a linha — ou seja, até a decisão de acesso ser
tomada de propósito.

**A trilha de auditoria** ([audit/](../api/src/audit/)). Registra o que muda
QUEM tem acesso e o que decide dinheiro: `user.created`, `user.updated`,
`user.password-reset`, `user.deleted`, `unit.*`, `barter.opinion` e
`barter.reviewed`. Lida em
`GET /audit-logs` (capacidade `audit.read`), sem rota que altere ou apague.

Ela existe por causa do reset de senha: ele sorteia uma senha nova e derruba as
sessões abertas do titular — é a primitiva de tomada de conta do sistema. Sem
registro, uma sessão de admin comprometida faria isso com qualquer usuário e
não sobraria como reconstruir o ocorrido; o log HTTP vai para a saída padrão,
é volátil e nem sabe quem chamou.

Duas escolhas dentro dela:

- **Tudo é snapshot em texto**, não relação. A linha precisa continuar legível
  depois que o autor ou o alvo forem excluídos — que é exatamente o caso em que
  alguém vai querer lê-la.
- **Falha de gravação não derruba a operação**: o ato já aconteceu, e abortar a
  resposta por causa do registro transformaria uma falha de auditoria em
  indisponibilidade. A perda vira `ERROR` no log. O preço é que a trilha pode
  parar de gravar sem ninguém notar em produção — por isso
  [audit.e2e-spec.ts](../api/test/audit.e2e-spec.ts) verifica as linhas de
  verdade. Se o faturamento exigir valor legal, essa troca muda: a trilha entra
  na mesma transação do ato.

## 1.5 O coração: criação de permuta

[barters.service.ts](../api/src/barters/barters.service.ts), método `create`.
Vale ler linha a linha; a sequência é:

1. **só o consultor registra permuta** (é ato do consultor da carteira; admin e
   retaguarda levam 403) → a regra é uma *lista de permitidos*, para papel novo
   não entrar por omissão
1b. o consultor **não** precisa ter gerente para REGISTRAR: a permuta nasce
   rascunho, na mão dele. O gerente é lido no ENCAMINHAMENTO, que é onde o envio
   acontece — e é lá que a falta dele recusa o ato, com o rascunho intacto
2. **precisa haver Barter aberto** (`requireOpenVersion`) → é ele que traz o
   grão da safra e a tabela de valores; sem ele, 422 com "aguarde o próximo
   lançamento"
3. **produtor precisa estar na carteira de quem registra** → 403 (a carteira é
   compartilhável: basta ele atender o produtor, não ser o único a atendê-lo)
4. quantidades repetidas no payload são **consolidadas por produto**
5. preços vêm **da versão** — o payload nem tem campo de preço, e o `whitelist`
   do ValidationPipe descartaria se tivesse; insumo fora da tabela da versão é
   recusado ("Fora do Barter S2026.02")
6. **insumos obrigatórios por hectare**: `requiredPerHa × areaHa`, com
   tolerância de 0,005 — só para os insumos que a versão lançou
7. **mínimos por categoria**: `percentOfTotal` ou `valuePerHa`, com tolerância
   de 1 centavo (`MONEY_EPSILON`)
8. `sacksToCover(custo, valorDaSaca)` → o servidor **cria o item de grão**
9. cada item guarda `unitValue` **e** `unitCost`, e a permuta guarda
   `versionId` + `versionCode`
10. tudo dentro de uma transação, com o código público `PRM-<ano>-NNN` gerado ali
    dentro para evitar corrida
11. a permuta nasce em **`draft`**, sem gerente endereçado, com a unidade de
    retirada escolhida gravada (`unitId` + `unitName`) e a **área do produtor
    congelada** (`producerAreaHa` — o denominador do sc/ha)

O passo seguinte é `forward`, no mesmo arquivo: o consultor grava o **parecer
dele** (obrigatório, e salvável antes pela rota `PUT /barters/:code/note`), a
permuta é endereçada ao gerente do momento e passa a `sentToManager`. Depois vem
`giveOpinion`: o gerente **a quem ela foi enviada** escreve o parecer técnico, e
ela passa a `pending`. Um gerente de outro time leva 403 — é a política sobre o
recurso que a tabela de capacidades não alcança.

A matemática pura está separada em
[barter-math.ts](../api/src/barters/barter-math.ts) — sem I/O, testada em
[barter-math.spec.ts](../api/src/barters/barter-math.spec.ts).

### O imposto da entrega — Funrural e Senar

A entrega de grão é **comercialização de produção rural**: o produtor paga os
insumos entregando grão, e essa entrega é uma venda como outra qualquer. Sobre
ela incidem a contribuição previdenciária rural (o "Funrural") e a contribuição
ao Senar.

A forma de recolhimento da parte previdenciária é do **PRODUTOR**, e mora no
cadastro dele (`Producer.taxRegime`): a opção pela folha é feita uma vez, perante
o fisco, e vale para o ano e para todas as entregas. Cada permuta nova a **herda**
no registro e a congela em `Barter.taxRegime` — enquanto a pergunta era feita
permuta a permuta, o consultor respondia de memória a cada fechamento, e duas
permutas do mesmo produtor saíam em regimes diferentes sem nada ter mudado no
mundo real.

O app **não oferece trocar o regime na permuta**: o fechamento mostra um AVISO
com o que o cadastro diz e quanto isso dá em sacas. Dois percentuais lado a lado,
um deles oito vezes menor, convidavam a marcar o barato numa permuta específica,
e isso não é preferência de quem fecha a permuta: é uma declaração ao fisco que
ele não tem como fazer. Quem corrige o regime é o admin, no cadastro, e vale da
próxima permuta em diante. O corpo do `POST /barters` ainda aceita `taxRegime`
(outros clientes da API), mas o app não o envia.

São **duas formas**, e é isso que os dois campos guardam:

| Forma | Produtor CPF | Produtor CNPJ |
| --- | --- | --- |
| `comercializacao` | **1,63%** (1,32 previdência + 0,11 RAT + 0,20 Senar) | **2,23%** (1,98 + 0,25 Senar) |
| `folha` | **0,20%** (só o Senar) | **0,25%** (só o Senar) |

Duas coisas que o desenho leva a sério:

- **Escolher a folha não isenta a entrega.** A previdência muda de base (vai
  para a folha de pagamento, ~23%, que este sistema não conhece), mas o Senar
  continua incidindo sobre a receita da comercialização. Por isso `folha`
  reduz a alíquota da entrega em vez de zerá-la.
- **PF ou PJ não é pergunta.** Sai do documento do produtor da permuta (11
  dígitos = CPF, 14 = CNPJ, ver `producers/document.ts`). Perguntar de novo
  abriria a chance de o cadastro dizer CPF e o imposto ser calculado como PJ.

A tabela vive em [`tax-regime.ts`](../api/src/barters/tax-regime.ts), com o
espelho Dart em [`tax_regime.dart`](../app/lib/services/tax_regime.dart) — mesma
relação (e mesmo par de testes) de `barter-math`.

`Barter.taxRate` é **snapshot**, como `producerName` e o preço do item: as
alíquotas acima valem desde 1º/04/2026 (LC 224/2025), quem decide qual se aplica
é a data da comercialização, e um comprovante reimpresso depois da lei seguinte
não pode passar a mostrar outro imposto. Permutas anteriores ao campo ficam com
`0` — e as telas leem esse zero para **omitir** a linha do imposto, em vez de
afirmar um número que ninguém aplicou.

## 1.5b O lançamento: safra, versões e a planilha

[seasons.service.ts](../api/src/seasons/seasons.service.ts). A invariante que
organiza o arquivo inteiro: **uma safra aberta e, dentro dela, uma versão
vigente**. Publicar a próxima encerra a anterior **na mesma transação** — se as
duas ficassem ativas por um instante, uma permuta registrada nesse intervalo
nasceria na tabela errada, e permuta é registro histórico.

Publicar uma versão é: **planilha .xlsx com os insumos + valor da saca digitado
+ vigência + metas**. O valor da saca não vem do arquivo porque não vem do
fornecedor — é a cotação com que a empresa decide receber.

A leitura da planilha ([version-import.ts](../api/src/seasons/version-import.ts))
é escrita para a planilha REAL do fornecedor — 656 itens, quatro colunas
(`Família`, `Código`, `Descrição`, `Preço Venda (R$)`) e cabeçalho na segunda
linha. Ela aguenta cabeçalho em qualquer ordem, com ou sem acento, **unidade
entre parênteses** (`(R$)` deixava um "r" grudado no nome normalizado e
derrubava o arquivo inteiro), número com vírgula, linha em branco e rodapé no
fim. É dividida em duas partes de propósito — `readWorkbook` (a única que
conhece `exceljs`) e `parseSheet` (a regra, testável sem arquivo). **Erro em
qualquer linha recusa o arquivo inteiro**, com o número da linha na mensagem:
meia-tabela publicada some com insumos sem ninguém perceber.

**A embalagem sai da descrição, em três degraus.**
[unit-from-name.ts](../api/src/seasons/unit-from-name.ts):

1. a **medida no nome** — `emb.20 l` → `20 L`, `10KG` → `10 kg`. Vale a
   **última** do nome (as primeiras são concentração do princípio ativo:
   `SC630`, `480 SL`), e medida seguida de barra é concentração, não embalagem
   (`100g/L`). Resolve 558 dos 656;
2. a **embalagem por extenso** — `BIG-BAG`, `BB`, `B-B`, `mist.` → `big-bag` e
   `granel`. Mais 86;
3. o **padrão da classe** — fertilizante a peso é `tonelada`. Os 12 últimos
   (ureia, DAP, cloreto de potássio, calcário). Não é chute: o preço deles está
   na mesma faixa dos que vêm em big-bag, e um big-bag É uma tonelada.

Total: **656 de 656**. O que um arquivo futuro trouxer sem pista entra com
"unidade" e `unitPending` — o item aparece marcado no Histórico, com filtro
próprio e contagem no aviso da publicação. Escrever a unidade encerra a
pendência, e a carga seguinte **não** desfaz a revisão do admin.

**As classes vêm do arquivo.** A coluna `Família` é a taxonomia do fornecedor, e
a carga cria a classe que ainda não existe (foi assim que `FERTILIZANTES
FOLIARES`, `OLEOS e ADJUVANTES` e `INOCULANTES` entraram). O casamento é por
nome normalizado ou slug — é isso que impede "HERBICIDAS", "Herbicidas" e
"herbicidas " de virarem três classes medindo mínimos diferentes. O que não
existe é criar classe pelo app: quem define a taxonomia é a lista de preços.

Todo item tem **código** (`sku`): o do fornecedor quando existe, um gerado
(`INS-0007`, `GRA-0003`) quando o admin não informa — nenhum item fica sem, e é
por ele que se procura na busca do app. Ele é único no catálogo, e repetir um
código devolve 422 dizendo de quem ele já é.

O casamento com o catálogo tenta `sku` primeiro e o nome normalizado depois, e
**cria** o que não existe — a planilha do fornecedor é a fonte do que há para
permutar, e pré-cadastrar item a item transformaria a carga em massa em
digitação.

Duas coisas continuam sendo escritas no catálogo a cada publicação:
`Product.currentPrice` (o *último valor publicado*) e um ponto em
`PriceHistoryEntry` assinado `Barter S2026.02`. É o que mantém o relatório do
produto e o gráfico de preço contando a história por gestão.

Correção pontual: `PUT /barter-versions/:code/prices/:productId` — só na versão
vigente, e o `productId` do grão da safra ajusta o valor da saca pelo mesmo
caminho. **Não existe mais `PUT /products/:id/price`**: com as duas portas
abertas, o catálogo e a versão discordariam, e quem precifica é a versão.

O lançamento tem **duas taxas**, e as duas são obrigatórias: `grainPrice`, que
leva o custo dos insumos a sacas, e `estimatedYield` — a **produtividade
estimada** da cultura (sc/ha), que leva as sacas à área de lavoura do penhor (ver
1.5c). Elas viajam juntas no código (`VersionRates`) justamente para não haver um
caminho de publicação que carregue uma e esqueça a outra: a versão nasceria
vigente, aceitando permuta e sem conseguir dimensionar a garantia dela.

`PUT /barter-versions/:code/estimated-yield` acerta a produtividade de uma versão
**já publicada**. Ela existe pela mesma razão do vencimento da safra: as versões
anteriores ao campo nasceram sem ele e são as que estão vigentes no dia em que a
migration sobe — e a alternativa seria republicar a tabela inteira, o que
encerraria a versão e reiniciaria a contagem do realizado por causa de um número
de dois dígitos.

## 1.5c O documento: a Cédula de Produto Rural (CPR)

O faturamento não encerra o negócio: a entrega do grão é formalizada por uma
**CPR** — o título em que o produtor se obriga a entregar, com a lavoura dada em
penhor, registrado na B3 (Lei 8.929/94). Ela é o desfecho jurídico do que a
permuta acordou, e tem **três mãos**: o **consultor** preenche, o **emissor**
confere e emite, o **admin** lê a segunda via.

A regra que organiza o código inteiro é **de onde vem cada lacuna do modelo**:

| Fonte | O que ela responde | Onde mora |
|---|---|---|
| A PERMUTA | emitente, CPF, sacas, produto, preço da saca, valor total, safra | `knownFrom()`, em [cpr.ts](../api/src/barters/cpr.ts) — resolvido no servidor, **leitura** na tela |
| A SAFRA | o **vencimento** da entrega — ele muda conforme a CULTURA | `Season.cprDueDate`, escrito pelo admin ao abrir a safra |
| O FATURAMENTO | os números das **notas fiscais** e das duplicatas (cláusula VII) | `BarterInvoice`, com o arquivo anexado — **leitura** na cédula |
| A CREDORA | razão social, CNPJ, endereço, foro | CADASTRO ([creditor/](../api/src/creditor/)), do admin **ou do emissor** |
| A PROPOSTA | CNH, filiação, e-mail, RG do cônjuge, avalistas, hipotecas | coletado e **não impresso** — ver abaixo |
| O CONSULTOR | qualificação civil do emitente, lavouras em penhor, padrão do grão, **SCR do produtor** | `BarterCpr` + `CprArea` + `CprAreaOwner` + `BarterFile` |

**Duas linhas trocaram de lado nesta tabela, e as duas pelo mesmo motivo: pedir a
informação a quem a tem, e uma vez só.**

- **o VENCIMENTO** era um campo do formulário, digitado cédula a cédula por quem
  não tinha nada que dissesse qual era a data certa daquela cultura. Soja vence
  na colheita dela, milho safrinha no dele — e todas as cédulas de uma mesma
  safra vencem no mesmo dia, porque é uma decisão comercial tomada uma vez.
  Enquanto foi campo, duas CPRs da mesma safra saíam com vencimentos diferentes e
  a única maneira de descobrir era comparar os papéis. Hoje ele é da SAFRA, o
  servidor o copia para a cédula a cada gravação, e ele **congela na emissão**.
  O admin o acerta em dois momentos, os dois na aba *Lançamento*: ao **abrir a
  safra** (`POST /seasons`, campo opcional — a safra abre antes de a colheita ter
  data fechada) e depois dela, no cartão do vencimento
  (`PUT /seasons/:code/cpr-due-date`). Mudá-lo alcança toda cédula da safra que
  ainda **não** foi emitida, e por isso a tela confirma o alcance antes de
  gravar; as emitidas ficam com a data que congelaram, porque estão assinadas.
  A data viaja como **meio-dia UTC** do dia escolhido: o vencimento é um DIA, e
  meia-noite local a leste de Greenwich cai no dia anterior em UTC — a cédula
  sairia vencendo um dia antes do que o admin escolheu;
- **os NÚMEROS DA NOTA e da DUPLICATA** eram dois campos de texto dentro da
  cédula, e três coisas estavam erradas ao mesmo tempo: quem os digitava não era
  quem emitia a nota, cabia **uma só**, e o documento em si não existia em lugar
  nenhum — só o número. Hoje são `BarterInvoice`, em lista e com o arquivo junto:
  a permuta sai em mais de um carregamento, cada retirada gera a sua nota, e a
  cancelada é reemitida.

**O SCR do produtor é anexo OBRIGATÓRIO**, e é a única exigência de `cprGaps()`
que não vem do modelo do documento. Ela vem da decisão de não assinar título sem
olhar o endividamento de quem o emite: uma CPR é crédito, e o SCR é o relatório
do Banco Central que diz quanto o produtor já deve e a quem. É ARQUIVO e não
campo — o SCR é um documento emitido com data, e transcrever números dele criaria
uma segunda versão da informação, mais nova em aparência e sem autoridade
nenhuma. Ele não é sugerido da cédula anterior pelo mesmo motivo: a fotografia da
safra passada não diz nada sobre o endividamento de hoje.

**A cédula guarda TRÊS anexos**, e os outros dois são os que VOLTAM de fora: a
**cédula assinada** e a **via carimbada pelo registro**. O sistema gera o
documento em branco e o devolve ao mundo; o que volta é papel com assinatura e,
depois, com o carimbo do cartório. Enquanto eles não tinham onde ficar, a permuta
dizia "assinada" e "registrada" sem ter como provar nenhuma das duas — a prova
morava no e-mail de alguém, e a segunda via saía do sistema **em branco**,
diferente da que está na mão do produtor, que é a que vale.

A assinatura **exige** o papel (`POST :code/cpr/signatures` virou `multipart`, e
recusa sem o anexo); o registro **não** exige a via. A diferença é a natureza do
que se lança: na assinatura o papel assinado É o fato, e não há "assinada" sem
ele; no registro o fato é o **número**, que o campo obrigatório já afirma — e
cartório que demora a devolver a via carimbada não pode travar o fim da linha.
Para ela existe `PUT :code/cpr/registry-file`, porque quando o papel chegar o ato
já terá acontecido e não se refaz.

Os três anexos passam pela mesma função (`attachToCpr`), e ela SEMPRE substitui:
cada coluna guarda UM documento, e duas vias penduradas na mesma cédula fariam
alguém conferir a errada — que aqui é um título executável. Só o SCR carimba o
`filledBy` da cédula: anexá-lo é preencher (ele é exigência de `cprGaps`),
enquanto o emissor que junta o papel assinado não escreveu a cédula, e carimbá-lo
como "último a preencher" apagaria da tela o nome de quem de fato a escreveu.

O que a permuta já sabe **não é campo de formulário**, e o `whitelist` do
ValidationPipe descarta se vier no payload: um número na cédula que discorde do
registro é um título cobrando o que não foi acordado. A credora não é campo pelo
motivo oposto — ela aparece em quatro cláusulas do documento e é sempre a mesma
empresa; pedi-la a cada cédula é pedir que alguém digite o CNPJ do próprio
empregador trezentas vezes, e a trezentésima primeira sai com um dígito trocado.

**A credora é cadastro, e tem DOIS DONOS.** `creditor.manage` é do admin *e* do
**emissor** — a única capacidade que o admin divide com um posto da linha. Ela
não decide permuta nem concede acesso, que são as duas coisas que este sistema
mantém longe de quem opera: é o *timbre do papel*, e quem percebe que o CNPJ saiu
com um dígito trocado é quem leva o título a registro. Ela já foi do faturista, e
mudou de mãos junto com a cédula — o timbre segue quem emite o papel, não quem
emite a nota. Mandá-lo abrir chamado com o admin para
corrigir o próprio timbre trocaria um campo de texto por um processo.

**E é por isso que a MARGEM DO PENHOR saiu de dentro dele.** A margem de
segurança (`Creditor.pledgeMarginPercent`) é da EMPRESA, e esta é a única linha
que representa a empresa — então ela nasceu como mais um campo do `CreditorDto`.
Com isso, o emissor passou a decidir, sem que ninguém escolhesse isso, quanta
terra a empresa exige em garantia de toda permuta futura: baixá-la de 20% para
10% corta a garantia pela metade, e a porta era a mesma de corrigir um CNPJ.

A correção não foi mudar de tabela — foi separar por AUTORIDADE dentro dela:
rota própria (`PUT /creditor/pledge-margin`), DTO próprio e capacidade própria
(`pledge.policy`, só do admin). É o mesmo desenho de
`PUT /seasons/:code/cpr-due-date` e `PUT /barter-versions/:code/estimated-yield`:
**o campo que tem dono ou ciclo próprio ganha porta própria**, em vez de viajar
dentro de um formulário cujo dono é outro. A tela da credora é a mesma para os
dois papéis, e o campo simplesmente não existe para quem não tem a capacidade.

O cadastro é
ÚNICO, na rota singular `/creditor`, pelo mesmo desenho do comitê: uma instalação
serve uma empresa, e duas credoras fariam a cédula ter de escolher sem que nada no
documento diga qual. A leitura nunca dá 404 — instalação nova devolve o cadastro
vazio com as pendências, porque a ausência é o estado inicial e não um erro.

O **foro** (cláusula XX) tem uma regra própria: vazio significa "a comarca da
sede", que é o que quase toda credora elege. Ele sai em dois campos no JSON — o
escolhido (`forum`, para o formulário) e o que vale (`effectiveForum`, para o
documento) —, porque obrigar a redigitar a mesma cidade num segundo campo só cria
a chance de os dois discordarem.

**O rascunho é salvável pela metade**, e isso é a decisão de desenho: a
qualificação o consultor tem da visita, a matrícula da lavoura vem por e-mail do
produtor no dia seguinte, o SCR sai depois da consulta. Por isso as colunas nascem com `""`/`0` em vez de `NOT NULL` exigido, o
DTO é inteiro opcional, e a pergunta "está completa?" é de OUTRA função —
`cprGaps()`, que roda sobre o que está **gravado** e devolve a lista em pt-BR, na
ordem em que o documento pede. São duas perguntas diferentes de propósito: o DTO
diz se o que chegou é gravável; `cprGaps` diz se o que está gravado dá um
documento.

Três consequências que aparecem no código:

- **as lavouras são tabela, e não dois blocos de campos.** O modelo enumera
  "(i)", "(ii)" porque o produtor planta em quantas áreas plantar — com campos
  fixos, a terceira não teria onde entrar e a segunda ficaria vazia na maioria
  das cédulas. O mesmo vale para os proprietários de cada uma: imóvel do casal
  tem dois, em espólio tem seis. E o proprietário **não é o emitente** — a
  lavoura penhorada costuma ser arrendada;
- **a anuência do cônjuge é a única exigência condicional**, e ela sai do estado
  civil digitado (`requiresSpouse`, espelhado em Dart só para mostrar/esconder o
  bloco). Cobrar o campo de quem é solteiro transformaria "falta" em ruído;
- **a repetição é resolvida por sugestão, não por cadastro.** O mesmo produtor
  emite cédula a cada safra, e o RG, o endereço e as matrículas são os mesmos da
  vez passada. A sugestão vem da **última cédula dele** (`previousCpr`), e não do
  cadastro de produtor: quem escreve cadastro é o admin (`producers.manage`), e
  resolver a digitação dando a caneta ao consultor trocaria um incômodo por uma
  mudança de quem pode alterar cliente. Ela também só é oferecida enquanto NÃO há
  rascunho — depois disso, o que está na tela é de quem escreveu.

**Coletado e não impresso.** A planilha de proposta que a operação usa
(*Proposta para CPR Barter*) pede coisas que o modelo de cédula não tem cláusula
para dizer: CNH, filiação do pai e da mãe, e-mail, RG do cônjuge, um bloco
completo de **avalista** (com o cônjuge dele) e as **hipotecas** oferecidas. Elas
são gravadas — o cartório individualiza homônimo pela filiação, a assinatura
eletrônica chega pelo e-mail, o aval existe no negócio — e **não entram em
`cprGaps()`**: cobrá-las travaria a geração de um documento que não as usa. A
pergunta daquela função é "dá para emitir?", e não "o cadastro está cheio?". O dia
em que a cláusula de aval existir, ela vai encontrar o dado pronto.

O **local da entrega** é o contraexemplo, e por isso é cobrado: ele É cláusula
(V, "d"). Ele é campo próprio, e não a unidade de retirada da permuta, porque as
duas coisas não são a mesma — retirar insumo na Filial 02 não obriga ninguém a
entregar o grão lá. A unidade entra como sugestão no formulário, que é o caso
comum, e quem confirma é quem assina embaixo.

**O que NÃO é campo, por ser derivado:** os quilos (`sacas × peso da saca`), o
valor total (`sacas × preço da saca`), a quantidade dada em penhor (a mesma da
entrega) e todos os extensos. O modelo recebido mostra por que os extensos
pertencem à geração e não à digitação: ele traz *"367 (quatrocentos e quarenta)
sacas"*, com o algarismo e o extenso discordando — um erro de digitação com
efeito jurídico.

### O penhor — a garantia deixou de ser "existe?" e passou a ser "de quanto?"

`cprGaps()` sempre cobrou **ao menos uma lavoura**: sem a matrícula do imóvel, a
cédula promete um grão e não garante nada. O que ela não perguntava era o
tamanho — e uma permuta de 3.000 sacas passava com uma matrícula de 4 ha anotada.
O penhor ficava do tamanho do que alguém teve tempo de digitar.

A conta que fechou esse buraco é a mesma do escambo, continuada mais um passo:

```
custo dos insumos ──(÷ preço da saca)──▶ sacas ──(÷ produtividade)──▶ hectares
                                                 ──(× 1 + margem)───▶ área EXIGIDA
```

As três parcelas vêm de três lugares, e nenhuma delas é digitada no formulário:

- as **sacas** são o item de grão da permuta;
- a **produtividade estimada** (sc/ha) é da VERSÃO do Barter
  (`BarterVersion.estimatedYield`), ao lado de `grainPrice` — as duas são as
  metades da mesma conversão, decididas no mesmo ato e revisáveis pelo mesmo
  mecanismo (publicar a próxima versão não reescreve o que já foi acordado);
- a **margem de segurança** (%) é da CREDORA (`Creditor.pledgeMarginPercent`) —
  política da empresa, que não muda porque o fornecedor republicou a tabela.

> A margem **não é a reserva legal**, embora a conversa que originou a feature a
> chamasse assim. A reserva legal é do Código Florestal: o percentual do IMÓVEL
> que fica em vegetação nativa, imposto por lei, atributo de cada matrícula, e o
> efeito dela é o oposto — dizer que parte da área registrada não é plantável.
> Esta é apetite de risco da credora, vale igual para todas as matrículas, e muda
> quando a diretoria muda de ideia.

**As duas taxas ficam congeladas na permuta** (`Barter.pledgeYield`,
`pledgeMarginPercent`), pelo mesmo motivo de `taxRate` e `producerAreaHa`: lidas
na hora de conferir, fariam uma permuta já encaminhada passar a exigir mais área
do que as lavouras que o consultor anotou, sem nada nela ter mudado.

**A área exigida NÃO é coluna.** Ela é derivada, como os quilos e o valor total —
e aqui isso não é estética: deferir um produto de fora do Barter recalcula a
linha do grão (`repriceGrain`), as sacas crescem, e um número gravado continuaria
dizendo o valor da semana passada num campo com cara de atual. A conferência
refaz a conta a cada leitura, e é assim que o penhor que bastava ontem é acusado
hoje.

**Onde trava:** no encaminhamento, junto com o resto de `consultantCprGaps` — o
último instante em que voltar atrás custa zero. Foi essa lacuna que obrigou
`consultantCprGaps` a receber contexto: até ela, tudo o que o consultor devia
estava dentro do rascunho.

**`pledgeYield` 0 é a marca do legado.** A partir desta regra, `POST /barters`
recusa versão sem produtividade (o portão gêmeo do de `grainPrice`), então toda
permuta nova nasce com a taxa preenchida — e zero passa a significar "nasceu
antes de o penhor ser dimensionado", não "faltou preencher". Sem esse portão, a
migration travaria a emissão de todo título já aprovado.

**O que avisa sem travar** (`pledgeWarningsFor`): a mesma matrícula em penhor
noutra permuta da mesma gestão, e a soma das lavouras passando da área cultivável
do produtor. São os dois jeitos conhecidos de a área fechar na conta e não fechar
no mundo — e nenhum dos dois é certeza (há arrendamento que o cadastro não
reflete, há matrícula grande repartida de boa-fé). Travar recusaria operação boa;
calar deixaria passar a operação que a feature existe para pegar. Por isso eles
saem em `pledgeWarnings`, fora de `gaps`, que é a lista que o portão lê.

A cédula continua **editável depois de a permuta ser faturada**, e não é
contradição com "não existe desfaturar": o que o estado fecha é o **ato**; a
cédula é papel que vem depois, e corrigir uma matrícula nela não desfatura nada.
O alcance das duas rotas é o mesmo do faturamento (`lineFrom(invoice)` — aprovada
ou faturada), pela mesma porta de escopo do detalhe.

Preencher a cédula entra na **trilha de auditoria** (`barter.cpr-saved`) pelo
critério dos outros atos que decidem dinheiro, e com folga: é um título
executável, pode ser reescrito quantas vezes for preciso, e a linha do tempo da
permuta não o alcança (`BarterEvent` guarda mudança de ESTADO, e preencher cédula
não move a permuta de posto). A trilha registra **o que faltou**, e não o
conteúdo: despejar ali a qualificação civil de um produtor espalharia dado
pessoal por um registro que ninguém apaga.

### A geração do documento

O documento sai em **.docx**, montado no app, em duas peças:

- [cpr_text.dart](../app/lib/services/cpr_text.dart) — a REDAÇÃO. As cláusulas
  fixas são transcritas literalmente do modelo, com as referências de lei que ele
  traz, e não são parametrizadas: um "gerador de cláusula" convidaria alguém a
  editar texto jurídico por engano. O que varia entra pela mesa da cédula;
- [cpr_docx.dart](../app/lib/services/cpr_docx.dart) — a FORMA: fonte, margem,
  recuo e as linhas de assinatura. Um `.docx` é um ZIP de XML, escrito à mão aqui
  (com o `archive` fechando o pacote) em vez de por um pacote de template — um
  template seria um segundo lugar onde o texto da cédula mora, e a redação de um
  título de crédito não deve depender de um binário que ninguém revisa.

**Word, e não PDF**, porque a cédula ainda passa por gente: o jurídico revisa, o
cartório pede um ajuste de redação, um negócio específico ganha uma cláusula à
mão. Um PDF obrigaria a redigitar o documento inteiro fora do sistema para mudar
uma linha — e é exatamente aí que a versão que vai a registro deixa de ser a que
o sistema conhece. Pelo mesmo motivo a numeração de página usa os campos `PAGE`/
`NUMPAGES` do Word: eles se recalculam quando alguém edita.

A separação é a mesma de `barter-math`: a redação se testa sem abrir um arquivo
binário ([cpr_text_test.dart](../app/test/cpr_text_test.dart)), e um ajuste de
margem não pode alcançar o texto de uma cláusula. O pacote em si tem os testes
dele ([cpr_docx_test.dart](../app/test/cpr_docx_test.dart)), e eles guardam o modo
de falha do formato: um `.docx` com uma parte faltando ou um `&` não escapado não
dá erro na geração — ele gera, e o Word recusa abrir na mão de quem ia assinar.

**Os extensos são derivados** ([extenso.dart](../app/lib/services/extenso.dart)),
e é aqui que o defeito do modelo se fecha: algarismo e extenso saem sempre do
MESMO valor. Duas caixas de texto lado a lado são duas oportunidades de escrever
"367 (quatrocentos e quarenta)"; uma caixa e uma função são uma.

O botão de **Gerar** só acende com a cédula `complete` — e "completa" inclui o
cadastro da credora. Um PDF com lacunas produziria um documento que parece pronto
e não é, que é pior do que um botão desabilitado com o motivo ao lado.

## 1.6 Modelo de dados

[schema.prisma](../api/prisma/schema.prisma). Dois padrões merecem atenção:

**Enums são `String`**: `role`, `type`, `kind`, `status`, `ruleType`. Foi o que
permitiu `sentToManager` — e depois `invoiced` — entrarem sem migration de tipo;
e como o app tolera status desconhecido, as versões instaladas continuaram
carregando a lista (mostrando a permuta na etapa errada: impreciso, mas visível
e sem ação indevida). São `String` de propósito, e não `enum` do Postgres: a
validação mora nos DTOs (`@IsIn`), e um valor novo não pede migration nem deploy
coordenado entre banco e aplicação.

O que o app deixou de deduzir foi o RÓTULO: `statusLabel`, `waitingFor` e
`nextAction` vêm resolvidos no JSON, do mesmo lugar em que o fluxo está escrito
([barter-workflow.ts](../api/src/barters/barter-workflow.ts)). Uma etapa nova
aparece com o nome certo nas telas já instaladas.

**Permuta é registro histórico.** `BarterItem` guarda `productName`, `unit`,
`unitValue` e `unitCost` como *snapshot*; `Barter` guarda `consultantName`,
`producerName`, `reviewedBy`, `invoicedBy` e `versionCode`; e cada passagem de
etapa vira um `BarterEvent` — a linha do tempo da permuta, gravada na mesma
transação da mudança de estado e nunca reescrita. Os FKs usam `onDelete: SetNull`.
Resultado: excluir um produto, um produtor ou um consultor **não** reescreve nem
apaga o histórico — e publicar uma versão nova não altera permutas antigas.

O `unitCost` está lá por causa da meta de lucro: sem o custo congelado no item,
corrigir um custo hoje reescreveria a margem apurada ontem.

```
User ─┬─< AccessToken        (sessões revogáveis)
      ├─< ProducerConsultant (carteira; Cascade — some o vínculo, não o produtor)
      ├─< User               (time: o gerente e os consultores dele)
      ├─< Barter             (registrou; SetNull)
      └─< Barter             (recebeu para parecer; SetNull)
Unit ─┬─< User               (lotação)
      └─< Barter             (local de retirada; SetNull, unitName fica)
Producer ─┬─< ProducerConsultant   (quem o atende — N:N com User)
          └─< Barter
Season ─< BarterVersion ─┬─< VersionPrice >─ Product   (a tabela de valores)
                         └─< Barter                     (SetNull; versionCode fica)
ProductClass ─< Product ─┬─< PriceHistoryEntry
                          └─< BarterItem >─ Barter
Barter ─ BarterCpr ─< CprArea ─< CprAreaOwner  (a cédula; 1:1, Cascade)
Barter ─< BarterInvoice ─ BarterFile           (as notas do faturamento)
BarterCpr ─ BarterFile ×3                      (SCR, cédula assinada, via do registro)
```

`BarterFile` guarda os ANEXOS — a nota fiscal, o SCR, a cédula assinada e a via
carimbada pelo registro — com o conteúdo em `Bytes`, no banco. É escolha, e não falta de opção: os dois são pequenos, poucos
por permuta e são PROVA (precisam existir enquanto o título existir). Guardá-los
aqui os põe dentro do mesmo backup, da mesma transação e do mesmo controle de
acesso do resto; um bucket exigiria credencial, ciclo de vida próprio e uma
segunda resposta para "quem pode ler este arquivo?" — que é justamente a pergunta
que já tem dono (o escopo da permuta). É TABELA À PARTE da nota pelo motivo
oposto do de sempre: `Bytes` numa tabela lida em lista viria junto em toda
consulta, e a listagem de permutas carregaria megabytes de PDF para desenhar uma
linha de tabela.

`BarterCpr` é a única parte do registro que **não** é snapshot, e de propósito:
ela é rascunho até o documento sair — o consultor digita, confere, corrige o RG
que veio errado. O congelamento acontece na EMISSÃO: do ato do emissor em diante
a cédula não aceita mais escrita, porque o documento existe no mundo e
reescrevê-lo por baixo faria a segunda via sair diferente da primeira — que é a
que está com o produtor. É a diferença entre o que ainda se está escrevendo e o
que já foi assinado (ver 1.5c).

`Season` guarda `grainName`/`grainUnit` desnormalizados pelo mesmo motivo:
excluir o produto do catálogo não pode apagar a memória de que aquela temporada
era de soja.

`Producer` guarda o documento duas vezes: `document` como o admin digitou (é o
que aparece na tela e no comprovante) e `documentDigits`, só os dígitos, com
índice único. A unicidade precisa morar na forma canônica — sobre o texto cru,
"CPF 123.456.789-00" e "12345678900" passariam como produtores diferentes, que
é justamente o cadastro em duplicidade que a regra existe para impedir. Um
produtor duplicado divide a carteira ao meio e faz a área contar em dobro nos
mínimos por hectare.

Esse mesmo `documentDigits` é metade da conta do imposto da permuta: é a
contagem de dígitos que diz se o produtor é pessoa física ou jurídica, e disso
depende a alíquota do Funrural. A outra metade — a forma de recolhimento — é
escolhida no fechamento da permuta (ver *O imposto da entrega*, em 1.5).

### A carteira é N:N

`ProducerConsultant` liga produtor e consultor, e a carteira deixou de ser uma
coluna (`Producer.consultantId`) por causa da operação: **consultores dividem
região e atendem o mesmo produtor**. Com um consultor por produtor, a única
forma de representar isso era cadastrar o produtor duas vezes — exatamente o
cadastro em duplicidade do parágrafo acima, com a área contando em dobro e as
permutas do mesmo cliente partidas entre dois registros.

Os vínculos são **iguais entre si**: não há dono nem principal. Todo consultor
vinculado enxerga o produtor e registra permuta para ele; quem responde "de
quem foi esta venda?" é a permuta, que guarda o consultor que a registrou
(`Barter.consultantId`). Escrever a lista é ato do admin
(`CAPABILITY.producersManage`) — o consultor não se acrescenta a uma carteira,
nem tira alguém dela.

A exclusão é `Cascade` dos dois lados: sai o consultor, sai o vínculo dele — não
o produtor. Um produtor pode ficar **sem nenhum** consultor e esperar
realocação (é o estado que o antigo `SetNull` produzia); até lá, só a retaguarda
o enxerga. O caminho contrário, criar um produtor sem consultor, é recusado no
DTO: cadastro que ninguém vê é cadastro perdido.

A migration
[`20260818141058_produtor_em_varias_carteiras`](../api/prisma/migrations/20260818141058_produtor_em_varias_carteiras/migration.sql)
copia os vínculos existentes para a tabela nova **antes** de dropar a coluna —
na ordem inversa da que o `prisma migrate diff` gera, que deixaria todo produtor
sem consultor nenhum.

## 1.7 Ambiente, seed e primeiro acesso

[main.ts](../api/src/main.ts) bifurca por `NODE_ENV`:

- **dev** → [seed-if-empty.ts](../api/prisma/seed-if-empty.ts): banco vazio
  recebe o dataset de demonstração (senha `demo-2026-agro`). Banco com dados não é tocado.
- **produção** → [bootstrap-admin.ts](../api/prisma/bootstrap-admin.ts): nada de
  dataset público; o primeiro admin vem de `ADMIN_EMAIL`/`ADMIN_PASSWORD` e
  nasce com senha provisória.

O dataset em si está em [seed-data.ts](../api/prisma/seed-data.ts); `npm run
db:seed` ([seed.ts](../api/prisma/seed.ts)) apaga e recria tudo.

O dataset também conta a história do fluxo: **dois gerentes** com times
distintos (Beatriz responde por João e Ana; Gustavo, por Roberto, Maria e
Lucas) e duas permutas paradas em `sentToManager` — uma na fila de cada um.
Há também um **rascunho** na mão do João (`PRM-2026-009`, a única permuta que
nenhuma tela da retaguarda enxerga) e uma **aprovada com ressalva**
(`PRM-2026-006`), para o selo e a exigência existirem antes de alguém aprovar
com ressalva na demonstração.
Com um gerente só, "cada um vê a sua fila" e "todo mundo vê tudo" produziriam
exatamente a mesma tela. E a `PRM-2026-008` é retirada na Matriz, embora seja do
Roberto: é o dataset mostrando que a retirada não tem relação com quem analisa.

E conta a história do modelo de valores: duas safras **encerradas** (`T2025`
de trigo e `M2026` de milho — é delas que vêm as permutas antigas pagas nesses
grãos) e a safra de soja `S2026` **aberta**, com `S2026.01` encerrada logo após
a publicação (o caso de quem republica antes de alguém usar) e `S2026.02`
vigente, com as quatro metas definidas. Em produção nada disso existe: o admin
abre a safra e publica a primeira versão pela planilha.

Variáveis: [.env.example](../api/.env.example) documenta todas
(`TOKEN_TTL_DAYS`, `CORS_ORIGINS`, `TRUST_PROXY`, `LOGIN_RATE_LIMIT`,
`PASSWORD_COST`, `SWAGGER`).

A **credora da CPR** já morou aqui, como `CREDITOR_*`, e saiu: corrigir um dígito
do CNPJ virava deploy, e quem percebe o erro — o emissor, conferindo a cédula —
não tinha como resolvê-lo. Hoje ela é cadastro no app (ver 1.5c).

Perdida a senha do admin, o caminho é
[scripts/reset-password.ts](../api/scripts/reset-password.ts)
(`npm run password:reset`): o `bootstrap-admin` só roda com o banco vazio, e
não há ninguém acima do admin para redefini-la pela aplicação.

## 1.8 Rotas (todas sob `/api/v1`, exceto `/`)

| Método | Rota | Quem pode | Observação |
|---|---|---|---|
| GET | `/` | público | sinal de vida, sem envelope |
| GET | `/health` | público | sonda: toca o banco (`SELECT 1`) ou 503. Fora do prefixo e sem envelope |
| POST | `/auth/login` | público | throttle apertado |
| POST | `/auth/logout` | autenticado* | revoga o token |
| GET | `/me` | autenticado* | é aqui que o app vê `mustChangePassword` |
| POST | `/auth/password` | autenticado* | exige a senha atual |
| GET | `/producers` `?consultantId=` | escopado | consultor: os que atende; retaguarda: todos |
| GET | `/producers/:id` | escopado | |
| POST/PUT/DELETE | `/producers` | admin | |
| GET/POST/PUT/DELETE | `/consultants` | admin | consultores |
| GET/POST/PUT/DELETE | `/managers` | admin | gerentes |
| GET/POST/PUT | `/committee` | admin | o comitê — cadastro ÚNICO, sem `:id` e sem DELETE |
| POST | `/committee/reset-password` | admin | nova senha da conta da reunião |
| GET/POST/PUT/DELETE | `/billers` | admin | faturistas |
| GET/POST/PUT/DELETE | `/emitters` | admin | emissores — sem um, toda permuta faturada para em "a emitir a CPR" |
| POST | `/<papel>/:id/reset-password` | admin | nova provisória + derruba as sessões dele |
| GET | `/audit-logs` `?action=` `?targetType=` | admin | trilha, mais recentes primeiro; só leitura |
| GET | `/products` `?type=` | autenticado | cadastro + **resumo** do histórico (`firstPrice`, `priceHistoryCount`) |
| GET | `/products/:id` | autenticado | o mesmo, com a linha do tempo INTEIRA (`priceHistory`) |
| POST/PUT/DELETE | `/products`, `/products/:id` | admin | (sem rota de preço: valor é da versão) |
| GET | `/classes` | autenticado | a lista FIXA das nove classes |
| PUT | `/classes/:id/rule` | admin | só a regra de mínimo; nome e lista não se alteram |
| GET | `/barter-versions/current` | autenticado | a versão VIGENTE com a tabela; `null` = Barter fechado |
| GET | `/barter-versions/:code` | admin | detalhe + metas × realizado |
| PUT | `/barter-versions/:code/prices/:productId` | admin | correção pontual (o grão da safra ajusta a saca) |
| PUT | `/barter-versions/:code/estimated-yield` | admin | produtividade estimada (sc/ha) da versão vigente — a taxa do penhor |
| POST | `/barter-versions/:code/close` | admin | encerra o Barter, mantém a safra |
| GET/POST | `/seasons` | admin | safras com o histórico de versões |
| POST | `/seasons/:code/close` | admin | encerra safra + versão vigente |
| POST | `/seasons/:code/versions` | admin | publica versão com a tabela no corpo (seed/testes) |
| POST | `/seasons/:code/versions/import` | admin | publica versão pela planilha .xlsx (multipart, 5 MB) |
| GET | `/barters` `?status=` `?unitId=` `?managerId=` | escopado | consultor: as dele; gerente: as do time; retaguarda: todas |
| GET | `/barters/:code` | escopado | `code` = PRM-2026-001 |
| GET | `/units` | autenticado | os locais de retirada (o consultor escolhe um por permuta) |
| POST/PUT/DELETE | `/units`, `/units/:id` | admin | cadastro dos locais |
| POST | `/barters` | consultor | com `unitId`; sem `grainId`; 422 se não há Barter aberto |
| PUT | `/barters/:code/note` | consultor | o parecer DELE, salvo no rascunho; só enquanto é rascunho |
| GET | `/barters/:code/version` | escopado | a tabela com que a permuta foi fechada (a remontagem é precificada por ela) |
| PUT | `/barters/:code/inputs` | consultor | remonta os insumos; lista inteira, só no rascunho e só na mesma cultura |
| POST | `/barters/:code/change-request` | consultor | pede alteração (justificativa obrigatória); vale até o faturamento |
| POST | `/barters/:code/change-request/decision` | **admin** | libera (volta a rascunho) ou recusa (motivo obrigatório) |
| POST | `/barters/:code/change-request/prices` | **admin** | atende o pedido no VALOR: reescreve o de itens, recalcula as sacas e a permuta não sai do lugar; exige pedido em aberto |
| POST | `/barters/:code/product-requests` | consultor | pede um produto que a tabela não tem (sem preço); do rascunho até a decisão do comitê |
| POST | `/barters/:code/product-requests/:id/decision` | **admin** | inclui o item na permuta com o valor acertado, ou recusa (motivo obrigatório) |
| POST | `/barters/:code/forward` | consultor | encaminha ao gerente, com o parecer junto (obrigatório) |
| POST | `/barters/:code/opinion` | gerente | parecer técnico; só na permuta endereçada a ele |
| POST | `/barters/:code/review` | comitê | decide: aprova, aprova com ressalva (texto obrigatório) ou nega (idem) |
| POST | `/barters/:code/invoice` | faturista | fatura: só permuta aprovada, e só com nota anexada |
| POST | `/barters/:code/invoices` | faturista | anexa uma NOTA FISCAL (multipart: o arquivo + número, série, duplicata, data, valor) |
| DELETE | `/barters/:code/invoices/:id` | faturista | remove a nota (o arquivo vai junto); **não** desfatura |
| GET | `/barters/:code/invoices/:id/file` | escopado | baixa o arquivo da nota — quem alcança a permuta alcança os documentos dela |
| GET | `/barters/:code/cpr` | consultor, emissor, admin | a mesa da cédula: rascunho + o que a permuta já sabe + credora + o que falta (`gaps`, `consultantGaps`, `creditorGaps`) |
| PUT | `/barters/:code/cpr` | **consultor** | grava o preenchimento, inteiro ou pela metade; recusa depois de emitida |
| PUT | `/barters/:code/cpr/scr` | **consultor** e **emissor** | anexa o SCR do produtor (multipart); o novo substitui o anterior |
| GET | `/barters/:code/cpr/scr` | consultor, emissor, admin | baixa o SCR anexado |
| POST | `/barters/:code/cpr/issue` | **emissor** | EMITE: confere e gera. Cédula com lacuna leva 422 com a lista do que falta |
| POST | `/barters/:code/cpr/signatures` | **emissor** | lança as assinaturas (multipart) — a **cédula assinada** é anexo obrigatório |
| POST | `/barters/:code/cpr/registration` | **emissor** | lança o registro, com o número (obrigatório); a via carimbada é anexo opcional |
| PUT | `/barters/:code/cpr/registry-file` | **emissor** | a via carimbada que o cartório devolveu DEPOIS do ato |
| GET | `/barters/:code/cpr/signed` | consultor, emissor, admin | baixa a cédula assinada |
| GET | `/barters/:code/cpr/registry-file` | consultor, emissor, admin | baixa a via registrada |
| PUT | `/seasons/:code/cpr-due-date` | admin | o VENCIMENTO da CPR daquela safra — ele muda conforme a cultura |
| GET/PUT | `/creditor` | admin **e** emissor | a credora dos documentos — cadastro ÚNICO, sem `:id` e sem DELETE |
| PUT | `/creditor/pledge-margin` | **admin** | a margem de segurança do penhor (%) — rota à parte porque a autoridade é outra |

As cinco rotas de usuário seguem o mesmo desenho e **só alcançam o próprio
papel**: papel diferente responde 404, e o admin não é gerenciado por nenhuma
delas (ver `ManagedRole` em [roles.ts](../api/src/common/roles.ts)) — ele nasce
do `bootstrap-admin` e se recupera por script.

"Escopado" = consultor vê a própria carteira; gerente vê o time dele (as
permutas endereçadas a ele); admin e comitê veem tudo; faturista e emissor veem
o próprio trecho da linha, um degrau um do outro. As rotas de escrita da permuta
são de papéis diferentes — é a linha de produção, e nenhuma delas é do admin.

\* também liberadas com senha provisória.

Documentação navegável: **`/api/v1/docs`** (Swagger, gerado dos próprios DTOs
pelo plugin em [nest-cli.json](../api/nest-cli.json)). Fechada em produção até
`SWAGGER=on`.

### Paginação — e por que ela não aparece nas telas

`/barters` e `/producers` aceitam `?limit=` (padrão 100, máximo 500) e
`?offset=`, e respondem `{ data, meta: { total, limit, offset } }`
([pagination.ts](../api/src/common/pagination.ts)). São as duas coleções que
crescem a cada safra; o catálogo e a lista de consultores não são paginados
porque têm teto natural e o app precisa deles inteiros.

O app, porém, foi construído sobre um cache completo — o painel do admin soma
sacas, valores e rankings sobre TODAS as permutas. Então
[ApiClient.getAll](../app/lib/services/api/api_client.dart) remonta as páginas
numa lista só. A paginação protege o servidor hoje (nenhuma resposta carrega a
base inteira) e deixa pronto o dia em que as telas passarem a carregar sob
demanda — o que exige antes decidir o que o painel mostra quando "tudo" não
cabe mais.

Filtro que a API não entende (`?status=lixo`, `?consultantId=abc`) é **recusado
com 422**, nunca ignorado: ignorar devolvia a coleção inteira com aparência de
lista filtrada, e quem olhasse não tinha como perceber.

## 1.9 Testes

- `npm test` → unidade, ao lado do código (`*.spec.ts`): matemática da permuta,
  a leitura da planilha ([version-import.spec.ts](../api/src/seasons/version-import.spec.ts)),
  metas e vigência ([version-progress.spec.ts](../api/src/seasons/version-progress.spec.ts)),
  a política de senha ([password-policy.spec.ts](../api/src/auth/password-policy.spec.ts)),
  a validade da sessão ([token.util.spec.ts](../api/src/auth/token.util.spec.ts)),
  throttling, setup do app e o filtro de exceção.
- `npm run test:e2e` → [test/](../api/test/), banco próprio (`barter_test` via
  `.env.test`), sobe a app com o mesmo `setupApp`. Cobre auth, escopo por
  papel, as regras de permuta, o lançamento do Barter
  ([seasons.e2e-spec.ts](../api/test/seasons.e2e-spec.ts): publicar, uma vigente
  só, permuta antiga intacta, planilha com erro, encerramento), o contrato de
  erro e — em [auth.e2e-spec.ts](../api/test/auth.e2e-spec.ts) — o cenário
  completo de sequestro e retomada de conta.
- Vale destacar dois que não seguem o formato dos outros:
  [route-policy.e2e-spec.ts](../api/test/route-policy.e2e-spec.ts) percorre a
  árvore de controllers que o Nest registrou de verdade e exige que a política
  de acesso de **cada rota** seja exatamente a da tabela escrita nele — rota
  nova só passa depois que alguém decide, por escrito, quem pode chamá-la; e o
  bloco `sessão` de [audit.e2e-spec.ts](../api/test/audit.e2e-spec.ts), que
  prende o rastro de entrada, falha e bloqueio de conta.
- `.env.test` baixa `PASSWORD_COST` para a suíte rodar em segundos: o custo
  real do scrypt (~170ms por login) é proposital em produção, mas cem logins
  de teste não podem pagá-lo.

### O que obriga isso a passar

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) roda, a cada push e a
cada PR, as duas pontas: lint + build + unidade + e2e na API, `flutter analyze`
+ `flutter test` no app.

Ele mora na **raiz** porque é o único lugar que o GitHub Actions lê. O workflow
que distribui o APK vivia em `app/.github/workflows/` — herança de quando o app
era repositório próprio — e por isso nunca chegou a rodar. Agora ele está na
raiz também, e atrás de um `workflow_run`: o APK só vai para os testadores
depois que o CI passou, no commit que o CI aprovou.

`dart format` fica de fora do portão de propósito: o código de hoje segue outro
estilo de quebra de linha, e exigi-lo reprovaria 42 dos 47 arquivos por
formatação, não por defeito.

---

# PARTE 2 — Frontend (`app/`)

**Stack:** Flutter · Material 3 · `http` · `flutter_secure_storage` · `pdf`/`printing`.
**Sem** gerenciador de estado (Provider/Riverpod/Bloc): o estado é um cache
estático global + `setState` nas telas.

## 2.1 As camadas

```
screens/          widgets, navegação, validação de UX
   │  lê síncrono ↓        ↑ chama assíncrono
data/app_data.dart         cache em memória + orquestração
   │
repositories/              1 por recurso: JSON ⇄ modelos
   │
services/api/api_client.dart   HTTP, token, envelope, erros
   │
                          API
```

Regra de ouro do design: **leitura é síncrona, escrita é assíncrona.** As telas
leem `AppData.barters`, `AppData.inputs` etc. direto no `build()`; toda mutação
passa pela API e só depois atualiza o cache com **a resposta do servidor**.

## 2.2 `ApiClient` — o funil

[api_client.dart](../app/lib/services/api/api_client.dart). Instância única
global (`final ApiClient api = ApiClient()`). Concentra:

- **base URL** por `--dart-define=API_URL=...` (padrão `localhost:3333`;
  emulador Android usa `10.0.2.2`)
- `Authorization: Bearer` quando há token
- desembrulha o `{ data: ... }`
- converte erro em `ApiException(statusCode, message)`, extraindo a mensagem
  pt-BR que o backend mandou — é ela que aparece na SnackBar
- timeout de 15s e mensagens amigáveis para queda de rede
- **callback `onSessionExpired`**: num 401 o token é descartado *antes* de
  avisar, para várias chamadas simultâneas não dispararem o retorno ao login
  várias vezes

O `signalSessionLoss: false` existe para os dois casos em que um 401 é
esperado: o `GET /me` da abertura e o `logout`.

## 2.3 Ciclo de vida da sessão

```
main.dart
  └─ installSessionExpiryHandler()   liga o ApiClient à navegação
  └─ BootstrapScreen
        └─ AppData.restoreSession()
              └─ AuthRepository.restore()
                    ├─ TokenStorage.read()  (Keychain / cofre do Android)
                    └─ GET /me
        ├─ null           → LoginScreen
        ├─ erro de rede   → OfflineCache.load()
        │                     ├─ pacote gravado → entra OFFLINE (isOffline = true)
        │                     └─ sem pacote     → "tentar novamente" (NÃO descarta o token)
        └─ usuário        → destinationFor(user)
                              ├─ mustChangePassword → ChangePasswordScreen(forced)
                              ├─ admin              → AdminMainScreen
                              └─ consultor           → ConsultantMainScreen
```

Arquivos: [main.dart](../app/lib/main.dart) ·
[session.dart](../app/lib/services/session.dart) ·
[bootstrap_screen.dart](../app/lib/screens/bootstrap_screen.dart) ·
[destination.dart](../app/lib/screens/destination.dart) ·
[token_storage.dart](../app/lib/services/token_storage.dart)

Dois detalhes que explicam decisões do código:

- [destination.dart](../app/lib/screens/destination.dart) é curto e existe
  só para o login e a retomada de sessão **não duplicarem** a decisão de destino
  — duplicada, uma das duas deixaria passar quem ainda tem senha provisória. É
  também onde cada papel encontra a sua casa, num `switch` sem `default`: papel
  novo em `UserRole` vira erro de compilação aqui, e não uma tela aberta por
  engano no painel de outro.
- [session.dart](../app/lib/services/session.dart) usa `GlobalKey` do Navigator
  e do ScaffoldMessenger porque quem descobre o 401 é a camada de dados, que não
  tem `BuildContext`.
- **Um 401 nunca chega ao desvio offline.** `AuthRepository.restore()` já o trata
  esquecendo a sessão e devolvendo `null`, então o que sobra no `catch` é falta
  de rede ou API fora do ar — e nenhuma das duas invalida sessão. Isso é o que
  torna o desvio seguro: ele não transforma "sua conta foi revogada" em "entre
  offline". Ver 2.4b.

## 2.4 `AppData` — o cache

[app_data.dart](../app/lib/data/app_data.dart). Classe estática com listas
públicas (`currentUser`, `consultants`, `producers`, `grains`, `inputs`,
`categories`, `barters`).

- **Hidratação**: no login (ou na retomada) `refreshAll()` dispara, em paralelo,
  o `syncOfflinePackage()` (versão, catálogo, classes, carteira, unidades — e é
  ele que grava o cache do aparelho, ver 2.4b), as permutas e — se admin —
  consultores, gerentes e safras. O dataset é pequeno (cooperativa), então
  carregar tudo de uma vez deixa o app instantâneo.
- **Com senha provisória não hidrata**: o servidor recusaria com 403, e o erro
  apareceria na cara de quem ainda vai definir a senha (`_hydrateIfCleared`).
- **Mutações**: sempre `API primeiro, cache depois` — `createBarter`,
  `reviewBarter`, `saveProducer`, `deleteConsultant`, `updatePrice`…
- Quando a mutação tem **efeito colateral no servidor**, o cache é recarregado
  em vez de remendado: excluir consultor → `refreshProducers()` (produtores
  ficaram sem dono); excluir categoria → `refreshCatalog()` (insumos foram
  desvinculados).

## 2.4b O pacote offline — o Barter guardado no aparelho

[offline_cache.dart](../app/lib/services/offline_cache.dart). Montar uma permuta
exige **cinco** coisas, e nenhuma delas é a simulação:

| dado | para quê |
| --- | --- |
| versão vigente (tabela + `grainPrice`) | converter insumos em sacas |
| catálogo de insumos | unidade, classe e `requiredPerHa` de cada item |
| classes de produto | as regras de mínimo |
| carteira de produtores | a **área**, que define os mínimos por hectare |
| unidades | a etapa de retirada |

Enquanto elas só existiam em memória, a simulação vivia offline mas **montar**
uma não: fechar o app apagava o cache, e reabrir sem sinal parava na tela de
abertura — o trabalho guardado estava a salvo e o consultor não alcançava nem
ele.

**As cinco viajam juntas, e só `AppData.syncOfflinePackage()` escreve o cache.**
Uma versão cuja tabela referencia um catálogo de outro momento produz um número
de sacas que nunca existiu; buscá-las na mesma viagem é o que impede o pacote de
ficar internamente incoerente. Os refreshes avulsos (`refreshCatalog`,
`refreshProducers`, …) continuam existindo e mexem **só na memória**.

**O que é guardado é o JSON CRU, não os modelos.** Os dois caminhos — servidor e
aparelho — atravessam o mesmo `fromJson`, e o app não ganha uma segunda gramática
para o mesmo dado. Por isso os repositórios expõem pares
`listProdutosRaw()` / `parseProducts()`: um endereço só, duas formas. Um `toJson`
escrito à mão poderia divergir do parser em silêncio, e o sintoma seria a permuta
montada offline sair com outro número.

**Só o consultor grava o pacote** — é ele que vai a campo. Gravar para o admin
encheria o cofre com a base inteira sem que nada fosse usar.

**Sair apaga o pacote, não as simulações.** Carteira e tabela não têm por que
continuar no aparelho depois que a pessoa se desconectou; a simulação é trabalho
dela, e reaparece no próximo login.

### O que uma sessão offline vale

Ela é o cache dizendo **quem estava logado**, não o servidor confirmando que
ainda está — offline essa confirmação não existe. O que se ganha é ler os
próprios dados e montar simulação; o que continua impossível é **encaminhar**,
que sempre exigiu rede. Conta revogada nesse meio-tempo aparece como 401 na
primeira chamada real, e o app volta ao login: a permuta não entra, e é isso que
precisa ser verdade.

Senha ainda provisória **não** abre offline: defini-la é uma conversa com o
servidor, e deixar entrar só levaria a uma tela incapaz de concluir nada.

### "Fechado" e "não baixei" são telas diferentes

`currentVersion == null` significa duas coisas opostas, e confundi-las é caro:
"o servidor respondeu que não há Barter aberto" é fato do negócio; "ninguém nunca
perguntou" é pendência do aparelho, e só ela se resolve conectando. Quem separa é
**`AppData.lastSyncAt`** — null só antes da primeira sincronização bem-sucedida.
O construtor usa isso para mostrar *"Baixe o Barter uma vez"* com um botão
**Baixar agora**, em vez de mandar embora quem só precisava de sinal por um
minuto.

A [`OfflineBanner`](../app/lib/widgets/common_widgets.dart) mostra a **data da
tabela**, e não só o aviso de que não há rede: a diferença entre "estou sem
sinal" e "estou simulando com os valores de terça" é a segunda, e é ela que o
consultor precisa antes de dizer um número ao produtor.

**Sobre o tamanho:** um catálogo de cooperativa dá algumas centenas de KB de
JSON, que o cofre guarda sem reclamar. Se crescer a ponto de incomodar, muda só
o de dentro do `OfflineCache` — o contrato (grava tudo, lê tudo) é o mesmo de um
banco local.

## 2.5 Modelos

[models.dart](../app/lib/models/models.dart) — 419 linhas, o arquivo mais
documentado do app. Cada modelo tem `fromJson` com conversões defensivas
(`_asDouble`, `_asId`, `_asDate`).

Duas coisas que o app faz na tradução do JSON:

- `BarterModel.id` **é o `code`** (PRM-2026-001), não o id numérico.
- O servidor manda `items` numa lista única; o modelo separa em `grains` e
  `inputs` pelo campo `kind`.

E os getters concentram a narrativa do domínio: `inputCost`, `sacksToDeliver`,
`referenceGrainName`, `balance`. Nenhuma tela recalcula isso na mão.

## 2.6 Telas

```
BootstrapScreen ──▶ LoginScreen ──▶ ChangePasswordScreen(forced) ──┐
                                                                   ▼
                    ┌──────────────────────────────────────────────┴────┐
              AdminMainScreen                                  ConsultantMainScreen
              (BottomNav, IndexedStack)                        (BottomNav, IndexedStack)
              ├ Dashboard                                      ├ Início (dashboard)
              ├ Permutas   → BartersScreen(isAdmin: true)       ├ Permutas → BartersScreen(isAdmin: false)
              ├ Barter     → PricesScreen (4 abas)              ├ Nova Permuta → NewBarterScreen
              └ Cadastros  → ConsultantsScreen                      └ Perfil
```

A aba **Barter** do admin é [prices_screen.dart](../app/lib/screens/prices_screen.dart)
(nome herdado), com quatro abas na ordem da operação:

| Aba | O que é |
|---|---|
| Lançamento | [barter_program_screen.dart](../app/lib/screens/barter_program_screen.dart) — safra, **vencimento da CPR** da safra, versão vigente, metas, publicar nova versão pela planilha, encerrar |
| Valores | a tabela da versão vigente: valor da saca + preço/custo/margem de cada insumo, com correção pontual. Filtra por pasta e ordena por preço ou margem (inclusive **menor margem**, que é a pergunta real ao revisar um lançamento) |
| Histórico | como o valor de cada item andou entre as versões: último valor publicado, variação e quantos pontos tem a linha do tempo. Filtra por grão/insumo e ordena por maior alta, maior queda ou maior valor. Marca quem está **fora do Barter** vigente |
| Classes | as nove classes do negócio, só leitura, com a regra de mínimo de cada uma |

**Histórico é leitura.** O cadastro do item (pasta, exigência/ha, exclusão) mora
na tela do próprio produto ([product_report_screen.dart](../app/lib/screens/product_report_screen.dart),
seção "Cadastro do item"), junto do gráfico e da linha do tempo dele. Ficava
repetido em cada cartão de uma lista que se lê para consultar valor — e, com a
planilha criando os insumos, cadastrar à mão virou ato raro: sobrou como o "+"
no cabeçalho, que existe porque o **grão** precisa estar cadastrado antes de a
safra ser aberta.

| Arquivo | O que é |
|---|---|
| [admin_main_screen.dart](../app/lib/screens/admin_main_screen.dart) | casca do admin + dashboard (herói de sacas a receber, mix por grão, rankings, fila de pendentes) |
| [consultant_main_screen.dart](../app/lib/screens/consultant_main_screen.dart) | casca do consultor + dashboard + aba de perfil |
| [back_office_main_screen.dart](../app/lib/screens/back_office_main_screen.dart) | casca de **gerente, comitê, faturista e emissor**, parametrizada pelo POSTO de cada um (`_Post`): cada um abre na fila que pede ação dele — parecer, decisão, faturamento ou cédula —, com selo de pendências na navegação, na cor da etapa |
| [invoicing_screen.dart](../app/lib/screens/invoicing_screen.dart) | a mesa do **faturista**: as notas fiscais (anexar, baixar, remover) e o ato de faturar. Ela era o formulário da CPR — e nada daquilo era trabalho dele |
| [cpr_form_screen.dart](../app/lib/screens/cpr_form_screen.dart) | a mesa da **cédula**: formulário para quem preenche (consultor), conferência e os três atos para quem emite (emissor), documento para quem só lê (admin) |
| [barter_screen.dart](../app/lib/screens/barter_screen.dart) | **o construtor de permuta** (a tela mais complexa) |
| [barters_screen.dart](../app/lib/screens/barters_screen.dart) | listagem com abas por status + busca |
| [barter_detail_screen.dart](../app/lib/screens/barter_detail_screen.dart) | detalhe (com a versão do Barter), a ação da etapa de quem abre (parecer, decisão ou faturamento), a **linha do tempo** da permuta e o PDF |
| [prices_screen.dart](../app/lib/screens/prices_screen.dart) | ⚠️ é a aba **Barter** inteira (lançamento, valores, histórico, pastas) |
| [barter_program_screen.dart](../app/lib/screens/barter_program_screen.dart) | o lançamento: versão vigente, metas, publicação por planilha, encerramento |
| [product_report_screen.dart](../app/lib/screens/product_report_screen.dart) | relatório de um produto + diálogos de preço/categoria/exigência |
| [consultants_screen.dart](../app/lib/screens/consultants_screen.dart) | ⚠️ é a aba **Cadastros** (Produtores · Consultores · Gerentes · Unidades) |
| [producer_profile_screen.dart](../app/lib/screens/producer_profile_screen.dart) | perfil do **produtor** visto pelo admin |
| [consultant_profile_screen.dart](../app/lib/screens/consultant_profile_screen.dart) | perfil do **consultor** visto pelo admin |
| [edit_forms.dart](../app/lib/screens/edit_forms.dart) | os formulários: produtor, **pessoal** (`EditStaffScreen`, consultor ou gerente), unidade, produto |
| [change_password_screen.dart](../app/lib/screens/change_password_screen.dart) | troca obrigatória (`forced: true`) ou voluntária |

O ⚠️ é nome herdado do protótipo: `consultants_screen.dart` não lista só
consultores, é a aba **Cadastros** inteira.

## 2.7 O construtor de permuta, passo a passo

[barter_screen.dart](../app/lib/screens/barter_screen.dart). O fluxo espelha a
regra do domínio:

- **Barter fechado** — se `AppData.currentVersion` for null ou não estiver
  aberta, a tela inteira vira o aviso "Barter fechado", com um puxar-para-
  atualizar. Não há o que montar sem tabela de valores.
- **Faixa do Barter vigente** no topo: `S2026.02 • pagamento em soja`, sem R$.
- **Etapa 1 — produtor**. Vem primeiro porque a **área da propriedade** define
  quais insumos são obrigatórios e em que quantidade. A lista é
  `AppData.producersForConsultant(consultantId)` — a carteira, incluindo os
  produtores que ele divide com outros consultores.
- **Etapa 2 — unidade de retirada**. Onde o produtor vai buscar os insumos.
  Qualquer uma serve, inclusive de outra praça: é um combinado com o produtor, e
  não muda quem analisa a permuta. É etapa própria, e não um campo no rodapé da
  lista de insumos, justamente para não virar algo que se preenche no fim sem
  pensar.
- **Etapa 3 — insumos**. A lista é `AppData.barterInputs`: só o que a versão
  vigente precificou. Insumos com exigência já vêm pré-preenchidos no mínimo e
  não descem abaixo dele (`_setInput` trava). Barras de progresso das classes
  mostram o quanto falta **em proporção** — e ficam em zero enquanto a permuta
  está vazia: exigência percentual sobre custo zero é cumprida na matemática,
  mas "atingida" antes do primeiro insumo é a tela dizendo que ele terminou sem
  ter começado.
- **Achar o insumo entre centenas** é o problema real da lista do fornecedor.
  Além da busca por nome **ou código**, a mesma barra de filtros do admin
  ([filter_bar.dart](../app/lib/widgets/filter_bar.dart)): chips por CLASSE — que
  é como quem monta a permuta pensa — e um chip **"Escolhidos (N)"**, que é a
  revisão do que já entrou sem caçar item por item. A ordenação alterna entre
  nome e "escolhidos primeiro"; não há ordenar por preço, porque o consultor não
  vê R$. Lista vazia diz QUAL recorte a esvaziou e oferece limpar.
- **Não há etapa de grão.** Ele é o da safra; as sacas saem de
  `version.grainPrice`.
- **Guardar é o único desfecho.** O construtor não envia mais nada: ele grava a
  simulação no aparelho, sem falar com o servidor. Encaminhar ao gerente — com a
  checagem de serviço, a conferência dos valores e o `POST` — é um ato próprio na
  aba de simulações, ver [2.7b](#27b-simulações--o-carrinho-e-o-único-caminho-até-o-gerente).

### Por que a matemática está duplicada

[barter_math.dart](../app/lib/services/barter_math.dart) é o espelho de
[barter-math.ts](../api/src/barters/barter-math.ts): mesmos nomes de função,
mesmas contas, mesmo arredondamento. **É intencional** — o app precisa reagir a
cada dígito digitado, sem ida ao servidor. Mas o app é *prévia*; o servidor é
*autoridade* e revalida tudo no envio.

O que segura as duas cópias juntas é um par de testes:
[barter-math.spec.ts](../api/src/barters/barter-math.spec.ts) e
[barter_math_test.dart](../app/test/barter_math_test.dart) fixam **os mesmos
números**. Mudou uma regra, mude nos dois lugares — um dos testes vai cair se
você esquecer.

A tabela de alíquotas do Funrural/Senar segue a mesma disciplina, e pelo mesmo
motivo: o consultor escolhe a forma de recolhimento e mostra o imposto da
entrega **na fazenda, sem sinal**. [`tax-regime.ts`](../api/src/barters/tax-regime.ts) e
[`tax_regime.dart`](../app/lib/services/tax_regime.dart) têm os mesmos números,
com os mesmos testes dos dois lados — e quem grava a alíquota na permuta
continua sendo o servidor, no envio.

**O arredondamento é parte do contrato, não detalhe.** A tela usava
`toStringAsFixed(2)`, o caminho natural em Dart; o servidor usa
`Math.round(v * 100) / 100`. Eles arredondam por bases diferentes (decimal vs
binário) e discordam em 4,2% dos valores — sempre em meio centavo. Meio centavo
é exatamente o bastante para a tela mostrar a quantidade mínima de um insumo e
o servidor recusar o envio por ela estar abaixo do mínimo. Por isso o espelho
Dart reproduz a fórmula do servidor em vez de usar o idioma local.

## 2.7b Simulações — o carrinho, e o único caminho até o gerente

O consultor monta a permuta **na fazenda**, e é exatamente lá que pode não haver
sinal. Enquanto o `POST /barters` era o único caminho, o trabalho dele dependia
de rede no momento em que ele estava mais longe dela — e uma falha de envio
jogava fora tudo o que ele tinha montado, item por item.

Por isso **toda permuta agora nasce como simulação**. O construtor tem um só
desfecho — guardar, no aparelho, sem falar com o servidor. Encaminhar ao gerente
é um ato próprio, feito na aba **Simulações**, e é lá que a rede entra.

| peça | papel |
| --- | --- |
| [barter_simulation.dart](../app/lib/models/barter_simulation.dart) | o modelo, com itens de nome congelado e parse tolerante |
| [simulation_storage.dart](../app/lib/services/simulation_storage.dart) | um documento JSON no cofre do sistema |
| [simulation_check.dart](../app/lib/services/simulation_check.dart) | a conferência de pré-envio (pura) e o `SendResult` |
| `AppData.reviewSimulation` / `sendSimulation` | busca os dados frescos e encaminha |
| aba **Simulações** em [barters_screen.dart](../app/lib/screens/barters_screen.dart) | a lista, o resumo, o envio e o descarte |
| `NewBarterScreen(simulation:)` | retomar uma simulação no construtor |

**Simulação não é permuta, e a diferença é o ponto.** Nada nela vale como
acordo: `simulatedSacks` é o que se via no dia em que foi montada. O que vale é
o que o servidor devolve no envio. Guardar o número simulado não é redundância —
é o que permite **perceber** que a conta mudou enquanto a simulação esperava.

### Os três tempos do encaminhamento

1. **O serviço responde?** `reviewSimulation` busca versão, carteira, unidades e
   catálogo. É essa a "checagem de disponibilidade", e ela é feita **buscando os
   dados**, não perguntando ao sistema operacional se há rede: um aparelho num
   wi-fi sem rota para a API passa num teste de conectividade e falha no envio
   logo depois. A única pergunta que interessa é "o servidor respondeu?", e a
   resposta vem junto com os dados de que a conferência precisa.
2. **O que mudou?** — [`checkSimulation`](../app/lib/services/simulation_check.dart).
   O que **impede** o envio é dito e para por ali (Barter fechado, produtor fora
   da carteira, unidade desativada, insumo que saiu da tabela). O que apenas
   **muda o número** é mostrado lado a lado — *Simulado: 58 sc → Agora: 69,6 sc*
   — e quem decide é o consultor, que foi quem combinou o número com o produtor.
3. **Envia**, e só depois do sucesso a simulação some.

**A conferência é sobre o RESULTADO, não sobre a causa.** Trocar a versão do
Barter é de longe o motivo mais comum de a conta mudar, mas quem decide se há
algo a avisar é a comparação das sacas. Isso não é preciosismo: `updatePrice`
altera o valor **dentro** da versão vigente, inclusive a cotação da saca
([seasons.service.ts](../api/src/seasons/seasons.service.ts)) — comparar só o
`versionCode` deixaria esse caso passar em silêncio.

**Barter novo não bloqueia: refaz.** Quando a versão virou, a simulação é
reconstruída com os mesmos insumos e quantidades na tabela vigente, e a versão
refeita é **gravada antes de perguntar** — se o consultor recuar no diálogo, o
trabalho não se perde.

### As regras que não são óbvias

- **`sendSimulation` apaga a simulação só depois do sucesso.** Rede caída,
  Barter encerrado ou mínimo de classe faltando deixam tudo intacto para
  corrigir e tentar de novo.
- **Existe um terceiro desfecho: o incerto.** O `POST` chega, a permuta é criada
  e a *resposta* se perde. O app veria um erro e o consultor tocaria "Encaminhar"
  de novo — duas permutas idênticas na mesa do gerente. Quando o erro é de
  transporte (`statusCode == 0`, e só nele: uma recusa de negócio veio com
  resposta e portanto não gravou nada), `sendSimulation` **confere no servidor**
  se a permuta entrou, casando por produtor e horário. Não dando para afirmar,
  `SendResult.uncertain` manda conferir a aba "No gerente" antes de reenviar.
  **A correção definitiva é uma chave de idempotência no `POST`** — o servidor
  reconheceria o reenvio —, e ela exige uma coluna nova; até lá, é melhor
  perguntar do que duplicar em silêncio.
- **`SimulationStorage.saveAll` devolve `bool`, e ele é olhado.** É o único
  lugar do app em que engolir a falha seria pior que o erro: o consultor veria a
  confirmação e perderia a permuta ao fechar o app.
- **`mySimulations` filtra por dono.** O aparelho é compartilhado em algumas
  praças, e a permuta nasce em nome de quem envia.
- **Logout não apaga o disco**, só a cópia em memória (`_clearCache`).
- **`_canSave` não exige as classes cumpridas.** Guardar permuta incompleta é o
  ponto; quem cobra o mínimo é o envio, e antes dele o servidor.
- **`ConsultantMainScreen._go` recria a aba de permutas a cada acesso.** O
  `IndexedStack` guarda a instância viva e não roda o `build` de novo — a aba
  abriria com a contagem anterior, sem a simulação recém-guardada.
- **Barter fechado com simulação aberta** diz que ela continua guardada. Sem essa
  frase, a tela em branco no lugar da permuta montada afirma o contrário, e o
  consultor remonta tudo do zero quando o Barter reabrir.

**Abrir o app do zero sem sinal funciona** desde que o aparelho tenha
sincronizado uma vez — ver [2.4b](#24b-o-pacote-offline--o-barter-guardado-no-aparelho).
O consultor baixa o pacote num login com rede e, a partir daí, monta e guarda
simulações offline quantas vezes quiser.

**O que ainda não é offline:** as permutas JÁ ENVIADAS não são cacheadas, de
propósito — elas são do servidor, e uma lista velha de permutas alheias vale
menos que a ausência dela; o que o consultor precisa em campo são as simulações,
que vêm de outro lugar.

O pacote **não grava R$ nenhum** no aparelho do consultor. Chegou a gravar: o
`/products` devolvia preço a qualquer autenticado, e depois do cache offline a
tabela do fornecedor passava a existir em disco. Foi o que a **lente de valor**
resolveu (ver [2.8](#28-privacidade-por-papel)) — o servidor converte antes de
enviar, e o que é gravado já vem em sacas.

## 2.8 Privacidade por papel

O **consultor nunca vê R$**. Para ele a permuta é "insumos retirados → sacas do
grão". Isso é decidido em DOIS lugares, e a ordem importa:

**1. Na API — a lente de valor.** É a regra de verdade, e é de segurança, não de
apresentação. A capacidade `prices.read` ([policy.ts](../api/src/common/policy.ts))
decide quem recebe R$; para quem não a tem, o servidor converte antes de enviar
(`lensFor` / `inSacks` em [serializers.ts](../api/src/common/serializers.ts)):

| Campo | Com `prices.read` | Sem |
|---|---|---|
| Tabela da versão | `price` (R$) | `sacksPerUnit` |
| Cotação da saca | `grainPrice` | *ausente* |
| Regra da classe | `ruleValue` em R$/ha | em sacas/ha, com `ruleUnit` |
| Item da permuta | `unitValue` | *ausente* |
| Cadastro do produto | `currentPrice`, `priceHistory` | *ausentes* |

A cotação **não** acompanha a tabela em sacas de propósito: junto com ela, uma
multiplicação devolveria os R$ e a conversão não teria servido para nada.

**O sc/ha é um recorte à parte, e não é sigilo.** O investimento por hectare
(`sacksPerHa`, com a área congelada em `producerAreaHa`) sai sob a capacidade
`barters.investmentPerHa` — admin, comitê, faturista e emissor —, e o gerente NÃO a tem,
embora veja R$. A diferença não é confiança: é para que serve o número. Ele é a
única medida que compara duas permutas de tamanhos diferentes (R$ 400 mil numa
fazenda de 2.000 ha e numa de 300 ha são negócios distintos), e quem trabalha
uma permuta de cada vez não tem com quem compará-la — uma régua sem régua ao
lado é ruído na tela. A área é **snapshot**, pelo mesmo motivo do preço do item:
o produtor arrenda mais terra na safra seguinte, e quem aprovou 12 sc/ha não pode
ver 9 no dia da auditoria. Sem área registrada o campo vem `null`, e não zero —
zero seria afirmar um investimento que ninguém fez.

**2. No app — o `showValue` das telas.** Continua existindo, e agora é o que ele
sempre deveria ter sido: acabamento, e não a defesa. As telas do consultor
(`barter_screen` → sempre `false`; `barter_detail_screen` e `barter_pdf` →
`widget.isAdmin`) não teriam R$ para mostrar mesmo que quisessem.

**O lado de cá precisa LER a lente**, e é o que
[`VersionPriceModel.perUnit`](../app/lib/models/models.dart) e
[`BarterVersionModel.costPerSack`](../app/lib/models/models.dart) fazem: o valor
por unidade chega na moeda da lente, e o divisor é a cotação em R$ ou **1** em
sacas — a mesma conta de `barter_math.dart` atravessa as duas, porque
`Σ(qtd × preço/cotação)` é `Σ(qtd × preço)/cotação`.

> Essa metade demorou a chegar. A API passou a converter e o app continuou lendo
> `price`, que para o consultor não vem: `_asDouble(null)` devolvia zero, e a
> prévia dele mostrava **0 saca** para qualquer permuta, com o detalhe anunciando
> "0 sc" em TOTAL A ENTREGAR. As duas suítes estavam verdes o tempo todo — os
> e2e conferiam o formato do JSON, os testes do app escreviam `price` à mão nos
> fixtures, e nada amarrava os dois. O grupo *"a lente de valor"* em
> [models_test.dart](../app/test/models_test.dart) é esse laço: os fixtures dele
> são cópias do que os e2e provam que a API devolve.

## 2.9 Widgets e tema

[common_widgets.dart](../app/lib/widgets/common_widgets.dart) (795 linhas) é o
vocabulário visual do app: `StatusBadge`, `TypeBadge`, `BarterBalanceBar`,
`SearchField`, `InfoTile`, `DashboardHeader`, `MiniBarterCard`, `BarterLogo`,
os formatadores (`formatCurrency`, `formatSacks`), a SnackBar de erro padrão e
os fluxos compartilhados de `confirmLogout` / troca de senha.

[app_theme.dart](../app/lib/theme/app_theme.dart) tem a semântica de cor:
verde institucional, **âmbar = grão**, **verde-azulado = insumo**, e o par
cor/fundo de cada status. Nenhuma tela inventa cor própria.

[price_chart.dart](../app/lib/widgets/price_chart.dart) é um `CustomPainter`
próprio (sem lib de gráfico), que vira sparkline no modo `mini`.

## 2.10 Testes do app

- [test/barter_math_test.dart](../app/test/barter_math_test.dart) — espelho do
  spec do servidor; é o que impede as duas cópias da matemática de divergirem.
- [test/models_test.dart](../app/test/models_test.dart) — o parse do JSON,
  inclusive o que acontece quando o servidor manda um valor que este app não
  conhece (não pode derrubar a lista inteira).
- [test/widget_test.dart](../app/test/widget_test.dart) — abertura do app e
  retomada de sessão.
- [tool/verify_api_contract.dart](../app/tool/verify_api_contract.dart) — sobe
  os **repositórios reais** contra a API no ar e confere o encontro das duas
  pontas: paginação, provisionamento de consultor, catálogo. `dart run`, sem
  simulador. É o teste que pega um campo renomeado ou um envelope alterado.
- [integration_test/app_flow_test.dart](../app/integration_test/app_flow_test.dart)
  — fluxo de interface ponta a ponta **contra a API real no ar**; cria uma
  permuta de verdade no banco de dev (rode `npm run db:seed` depois). Rode num
  **simulador iOS** (`-d 'iPhone 17 Pro'`): ele não exige assinatura de código,
  enquanto `-d macos` só builda com um certificado de desenvolvimento
  configurado no Xcode, por causa do `keychain-access-groups` das
  entitlements.

---

# PARTE 3 — O contrato entre os dois

Estes pares andam juntos. Mudou de um lado, procure o outro:

| Backend | Frontend |
|---|---|
| [serializers.ts](../api/src/common/serializers.ts) | [models.dart](../app/lib/models/models.dart) (`fromJson`) |
| [envelope.interceptor.ts](../api/src/common/envelope.interceptor.ts) | `_send` em [api_client.dart](../app/lib/services/api/api_client.dart) |
| [validation.ts](../api/src/common/validation.ts) (422, string única) | `_errorMessage` em [api_client.dart](../app/lib/services/api/api_client.dart) |
| [exception.filter.ts](../api/src/common/exception.filter.ts) (todo erro vira `message`) | idem — é o texto que aparece na tela |
| [pagination.ts](../api/src/common/pagination.ts) (`meta`) | `getAll`/`_page` em [api_client.dart](../app/lib/services/api/api_client.dart) |
| `provisionalPassword` em [consultants.controller.ts](../api/src/users/consultants.controller.ts) | [provisional_password_dialog.dart](../app/lib/widgets/provisional_password_dialog.dart) |
| DTOs (`dto/*.ts`) | `_payload(...)` nos [repositories/](../app/lib/repositories/) |
| `mustChangePassword` no [AuthGuard](../api/src/auth/auth.guard.ts) | [destination.dart](../app/lib/screens/destination.dart) |
| 401 (token morto/vencido) | `onSessionExpired` em [session.dart](../app/lib/services/session.dart) |
| [barter-math.ts](../api/src/barters/barter-math.ts) | [barter_math.dart](../app/lib/services/barter_math.dart) — espelho, com testes espelhados |
| `toBarterVersionJson` / `toSeasonJson` ([serializers.ts](../api/src/common/serializers.ts)) | `BarterVersionModel` / `SeasonModel` em [models.dart](../app/lib/models/models.dart) |
| `GET /barter-versions/current` devolvendo `null` | estado "Barter fechado" em [barter_screen.dart](../app/lib/screens/barter_screen.dart) |
| `BARTER_STATUSES` em [barter.dto.ts](../api/src/barters/dto/barter.dto.ts) | `enum BarterStatus` em [models.dart](../app/lib/models/models.dart) — os nomes precisam bater, é `status.name` que compara |
| `POST /barters/:code/opinion` | `giveBarterOpinion` em [common_widgets.dart](../app/lib/widgets/common_widgets.dart) |
| [change-request.ts](../api/src/barters/change-request.ts) (quem pede, até quando, o que o aceite apaga) | `canBeChangedBy` / `hasOpenChangeRequest` em [models.dart](../app/lib/models/models.dart) + `ChangeRequestCard` em [common_widgets.dart](../app/lib/widgets/common_widgets.dart) |
| [product-request.ts](../api/src/barters/product-request.ts) (até quando se pede, o que o item de fora acrescenta) | `canRequestProductBy` / `BarterProductRequest` em [models.dart](../app/lib/models/models.dart) + `ProductRequestsCard` em [common_widgets.dart](../app/lib/widgets/common_widgets.dart) |
| `offBarterCost` somando nas sacas e em régua nenhuma (`pricedItemsFor`) | `_offBarterCost` em [barter_screen.dart](../app/lib/screens/barter_screen.dart) — a prévia precisa dar o mesmo número que o servidor grava |
| `PUT /barters/:code/inputs` | `NewBarterScreen.draft` em [barter_screen.dart](../app/lib/screens/barter_screen.dart) — a mesma tela do registro, com produtor e unidade congelados |
| upload multipart de `/versions/import` | `ApiClient.upload` + `file_picker` em [barter_program_screen.dart](../app/lib/screens/barter_program_screen.dart) |

**As mensagens de erro do backend estão em pt-BR de propósito** — elas vão
direto para a tela, sem tradução no cliente.

---

# PARTE 4 — Roteiro de leitura

Se for ler tudo em ordem, sugiro:

**Backend (≈1h)**
1. [schema.prisma](../api/prisma/schema.prisma) — o vocabulário
2. [app.module.ts](../api/src/app.module.ts) — o índice
3. [serializers.ts](../api/src/common/serializers.ts) — o contrato
4. [auth.guard.ts](../api/src/auth/auth.guard.ts) + [token.util.ts](../api/src/auth/token.util.ts) — como a sessão funciona
5. [seasons.service.ts](../api/src/seasons/seasons.service.ts) — o lançamento
   (quem decide os valores)
6. [barter-math.ts](../api/src/barters/barter-math.ts) → [barters.service.ts](../api/src/barters/barters.service.ts) — o domínio
7. um módulo CRUD qualquer (`categories/`) para ver o padrão simples

**Frontend (≈1h30)**
1. [models.dart](../app/lib/models/models.dart) — o domínio no cliente
2. [api_client.dart](../app/lib/services/api/api_client.dart) — o funil
3. um repositório (`barter_repository.dart`) — a tradução
4. [app_data.dart](../app/lib/data/app_data.dart) — o estado
5. [main.dart](../app/lib/main.dart) → [bootstrap_screen.dart](../app/lib/screens/bootstrap_screen.dart) → [destination.dart](../app/lib/screens/destination.dart) — a entrada
6. [barter_screen.dart](../app/lib/screens/barter_screen.dart) — a tela que exercita tudo

---

# PARTE 5 — "Onde eu mexo se eu quiser…"

| Quero… | Backend | Frontend |
|---|---|---|
| um campo novo em produtor | `schema.prisma` + migration, `producer.dto.ts`, `toProducerJson` | `ProducerModel` + `_payload`, `edit_forms.dart` |
| uma regra nova de classe | `barter-math.ts` (`classRequired`), `class.dto.ts` | `ClassRuleType`, `_classRequired` em `barter_screen.dart`, `edit_forms.dart` |
| a figura de uma classe nova | nada | `iconForClass` em `class_avatar.dart` |
| aceitar outra coluna na planilha | `COLUMNS` em `version-import.ts` (+ spec) | nada |
| uma meta nova (ex.: hectares) | `schema.prisma`, `Targets`/`goalsOf` em `version-progress.ts`, `VersionLimitsDto` | `GoalKind`, campo no `_PublishSheet` |
| mudar QUANDO a meta encerra sozinha | `closeIfGoalReached` em `seasons.service.ts` (o gatilho é a decisão do comitê, em `barters.service.ts`) | nada (o app lê `isOpen` e `closeOnGoal`) |
| mudar validade da sessão | `TOKEN_TTL_DAYS` no `.env` | nada |
| um endpoint novo | módulo (controller+service+dto) + serializer | repositório novo + campo no `AppData` |
| uma etapa nova no fluxo da permuta | valor em `BARTER_STATUSES`, transição no `barters.service.ts`, capacidade em `policy.ts` | `BarterStatus`, `statusLabel`, `StatusBadge`, `statusColor`, cor na paleta da marca, aba em `barters_screen.dart` |
| trocar quem dá o parecer | `managerId` em `CreateConsultantDto` + `resolveManager` | dropdown de gerente em `EditStaffScreen` |
| mudar o que um papel enxerga | `scopeFor` em `barters.service.ts` + a capacidade em `policy.ts` | nada (o servidor já filtra) |
| deixar o consultor ver R$ | nada (já vem no JSON) | trocar as flags `showValue` |
| ler outra coluna da planilha | `COLUMNS` em `version-import.ts` (+ spec) | nada |
| outro padrão de embalagem no nome | `UNITS`/`PACKAGES` em `unit-from-name.ts` (+ spec) | nada |
| mudar mensagem de erro | a exceção no service | nada (o app só exibe) |

---

# PARTE 6 — Pontos frágeis conhecidos

Coisas verdadeiras sobre o código hoje, para você não interpretar como bug:

- **Estado global estático.** `AppData` é conveniente e simples, mas as telas em
  `IndexedStack` são construídas uma vez: um dashboard pode mostrar dado
  defasado até um pull-to-refresh. Foi decisão consciente (dataset pequeno);
  virar um problema quando o app crescer.
- **Matemática duplicada** app/servidor (ver 2.7) — por design, presa pelos
  testes espelhados, mas ainda exige mexer nos dois lados ao alterar regras.
- **O app carrega tudo em memória.** A API já é paginada; o cache do app não.
  Enquanto o painel do admin somar sacas e valores sobre TODAS as permutas, ele
  precisa de todas. Trocar isso é uma decisão de produto antes de ser técnica:
  o que o painel mostra quando "tudo" não cabe mais? Uma safra? Um período?
- **`BartersScreen._filtered`** roda várias vezes por rebuild (contadores das
  abas + listas). Irrelevante no volume atual.
- **`nextCode`** carrega todos os códigos do ano para achar o próximo. É O(n)
  por permuta criada. A corrida entre ler e gravar está tratada com retry
  (`createWithCode`), mas a leitura continua crescendo com o ano.
- **Nome de arquivo enganoso** no app (`consultants_screen`) — ver 2.6.
- **Uma dúzia de itens entra sem embalagem.** `unit-from-name.ts` lê 644 dos
  656 da lista real; o que sobra é adubo vendido a peso (ureia, DAP, calcário),
  cujo nome não diz embalagem nenhuma. Eles entram como "unidade" e se acertam
  um a um na tela do item. Chutar seria pior: unidade errada vai para o
  comprovante do produtor.
- **Paginação por offset.** Se registros forem criados entre uma página e a
  seguinte, a janela desloca. Autocorrige no refresh seguinte; para volume
  maior, o caminho é cursor.
- **A planilha é lida inteira na memória** (multer em memória + `exceljs`), com
  teto de 5 MB por upload **e** de 20 mil linhas depois de aberta. Os dois tetos
  não são o mesmo: 5 MB medem o arquivo COMPRIMIDO, e `.xlsx` é um zip — 20 mil
  linhas cabem em 300 KB. O teto de linhas protege tudo o que vem depois
  (matriz, `parseSheet`, um upsert por linha); o pico da própria leitura
  continua limitado só pelos 5 MB, porque fechar isso pediria leitura em fluxo,
  que o `exceljs` não faz a partir de buffer em memória. Como a rota exige um
  admin autenticado, o que sobra é o arquivo grande por engano — e esse os tetos
  pegam.
- **Produto criado pela importação sobrevive a uma publicação que falhe *dentro
  da transação*.** O casamento com o catálogo continua acontecendo antes dela —
  é o que permite a planilha cadastrar item novo. O que mudou é que as
  precondições que não dependem da tabela (safra aberta, data de encerramento no
  futuro) passaram a ser conferidas **antes** de qualquer escrita, em
  `assertPublishable`: os dois motivos de recusa que apareciam no dia a dia não
  sujam mais o cadastro. Sobra a falha dentro da transação (erro de banco), que
  ainda deixaria o insumo cadastrado sem preço — visível, não permutável e
  removível pela aba Produtos. Coberto em `seasons.e2e-spec.ts`, "publicação
  recusada não deixa rastro no catálogo".
- **`User.branch` é derivado.** Ele guarda o NOME da unidade da pessoa, escrito
  a partir de `unitId` num lugar só
  ([user-provisioning.service.ts](../api/src/users/user-provisioning.service.ts)).
  Existe porque é o que as telas mostram, o que os rankings agrupam e o que a
  permuta congela — ler pela relação obrigaria todo `findUnique` de usuário,
  inclusive o do AuthGuard em cada requisição, a carregar um join. O preço é o
  de sempre: renomear uma unidade não reescreve o que já foi congelado (que é o
  comportamento certo, como `Barter.producerName`, mas continua sendo duas
  cópias do mesmo dado).
- **O destinatário do parecer é snapshot.** `Barter.managerId` é gravado no
  envio, não lido do vínculo atual do consultor. Trocar o gerente de alguém
  vale para as próximas permutas — decisão consciente, e a saída de um gerente
  é barrada enquanto ele tiver time ou fila
  ([`ensureManagerIsFree`](../api/src/users/user-provisioning.service.ts)).
  O custo é que reatribuir em massa (férias, desligamento) exige esvaziar a fila
  antes.
- **`Product.currentPrice` é derivado.** Ele guarda o último valor publicado
  para o relatório e o gráfico; quem precifica é a versão. A rota que o editava
  direto foi removida justamente para os dois não divergirem, mas o campo
  continua lá e ainda é escrito por dois caminhos (publicar versão e corrigir
  preço).
