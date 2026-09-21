# agroBarter — Permuta de Grãos por Insumos (fullstack)

Monorepo com o app e o backend do agroBarter:

```
barter-fullstack/
├── app/   Flutter (clone do barter-app original, integrado à API)
├── api/   NestJS 11 + Prisma 7 + PostgreSQL — regras de negócio autoritativas
└── docs/  Arquitetura, decisões e o que falta para publicar (RELEASE.md)
```

> O projeto original (`~/Projects/barter-app`) permanece intocado, com dados
> mockados, para testes de interface.

## Regra central do domínio

O produtor **retira insumos** (eles formam um custo em R$) e **paga com sacas
de um grão** — as sacas são calculadas a partir do custo, nunca o inverso.
O cálculo, os mínimos por hectare e os mínimos por categoria ("pastas") são
validados **no servidor**; o app mostra a prévia, mas quem manda é a API.

## Subindo tudo (desenvolvimento)

Terminal 1 — API:

```bash
cd api
npm install         # primeira vez
npm run db:seed     # cria/recarrega o banco com o dataset de demonstração
npm run start:dev   # http://localhost:3333
```

Terminal 2 — App:

```bash
cd app
flutter pub get     # primeira vez
flutter run         # simulador iOS/desktop: localhost funciona direto
```

Rodando em **aparelho físico** ou **emulador Android**, aponte para o IP da
sua máquina:

```bash
flutter run --dart-define=API_URL=http://192.168.0.10:3333   # iPhone na mesma rede
flutter run --dart-define=API_URL=http://10.0.2.2:3333       # emulador Android
```

## Credenciais de demonstração (seed)

| Papel    | E-mail                      | Senha  |
|----------|-----------------------------|--------|
| Admin    | admin@agrobarter.com.br         | demo-2026-agro |
| Gerente  | gerente@agrobarter.com.br       | demo-2026-agro |
| Comitê   | comite@agrobarter.com.br        | demo-2026-agro |
| Faturista | faturista@agrobarter.com.br    | demo-2026-agro |
| Emissor  | emissor@agrobarter.com.br       | demo-2026-agro |

> O acesso do **Comitê** é do órgão, não de uma pessoa: é uma reunião, e quem
> participa entra com o mesmo login.
| Consultor | joao.silva@agrobarter.com.br   | demo-2026-agro |
| Consultor | ana.ferreira@agrobarter.com.br | demo-2026-agro |

(Os demais consultores do dataset também logam com `demo-2026-agro`.)

Isso vale **só para o dataset de demonstração**, que não é carregado com
`NODE_ENV=production`. Consultores criados pelo admin recebem uma senha
sorteada, diferente para cada um, mostrada uma única vez na tela de cadastro —
ver "Senha de primeira entrada" em `api/README.md`. Os atalhos de acesso rápido
na tela de login só existem em build de debug.

## Testes

```bash
cd api && npm test          # 281 testes de unidade (matemática, máquina de estados, desvio e pedido de fora do Barter, seguro por município, senha, sessão, políticas, cédula)
cd api && npm run test:e2e  # 377 testes funcionais da API (auth, escopo, fluxo, seguro do lançamento, dossiê do comitê, notas do faturamento, cédula e emissão, credora, contrato de erro)
cd api && npm run test:cov  # as duas suítes juntas, com cobertura
cd app && flutter test      # 266 testes (matemática espelhada, parsers, formulários, extenso, redação e pacote .docx da cédula)
```

> `test:cov` roda unidade **e** e2e numa execução só, e é isso que torna o
> número honesto: medir apenas a unidade contra o código inteiro devolvia 25%,
> porque os testes que exercitam services e controllers ficavam fora da conta e
> dentro do denominador. É o mesmo comando que o CI usa.

Com a API no ar, dois testes de ponta a ponta:

```bash
cd api && npm run db:seed && npm run start:dev &

# 1. Contrato de dados: sobe os repositórios REAIS do app contra a API e
#    confere paginação, provisionamento de consultor e catálogo. Não precisa
#    de simulador.
cd app && dart run tool/verify_api_contract.dart

# 2. Fluxo de interface completo, num simulador iOS:
xcrun simctl boot 'iPhone 17 Pro' && open -a Simulator
cd app && flutter test integration_test/app_flow_test.dart -d 'iPhone 17 Pro'
```

Use o **simulador iOS**: ele não exige assinatura de código. Em `-d macos` o
build só passa se houver um certificado de desenvolvimento configurado no
Xcode — sem ele, a mensagem é *"Runner has entitlements that require signing
with a development certificate"*, causada pelo `keychain-access-groups` do
`DebugProfile.entitlements`.

O teste de interface cria uma permuta real (PRM-2026-009) no banco de
desenvolvimento — rode `npm run db:seed` para zerar.

### A matemática vive nos dois lados

`api/src/barters/barter-math.ts` e `app/lib/services/barter_math.dart` são a
mesma conta escrita duas vezes: o app precisa recalcular a cada toque enquanto
o consultor monta a permuta, sem consultar o servidor a cada dígito. Os dois
testes (`barter-math.spec.ts` e `barter_math_test.dart`) fixam **os mesmos
números**, inclusive nos casos de arredondamento de meio centavo — mexeu num
lado, o outro tem de concordar. Sem isso a tela promete uma quantidade e o
servidor recusa o envio por ela estar abaixo do mínimo.

## Decisões de arquitetura (resumo)

- **NestJS** no backend: módulos por recurso (controller fino → service com a
  regra → Prisma), DTOs com `class-validator` na borda, guards para
  autenticação/papel e um interceptor global para o envelope `{ data: ... }`
  que o app espera. Prisma como ORM (schema declarativo, migrations, client
  tipado). Detalhes em `api/README.md`.
- **O comitê é um ÓRGÃO, não uma pessoa**: ele é uma reunião, e o cadastro dele é
  um só (`/committee`, no singular, sem exclusão) — quem participa entra com o
  mesmo acesso, e a decisão sai assinada pelo comitê. Consultor, gerente,
  faturista e emissor continuam sendo pessoas, cada um com a sua conta. Detalhes
  em `api/README.md`.
- **A permuta tem uma linha de produção, e ela mora no servidor**: gerente →
  comitê → faturista → **emissor**. O gerente escreve o parecer técnico, o
  **comitê** decide (aprova ou nega), o **faturista** fatura o que foi aprovado e
  anexa as notas fiscais, e o **emissor** confere a cédula, emite o título, colhe
  as assinaturas e o leva a registro. Faturar não é mais o fim da linha: uma
  permuta faturada ainda deve o título que formaliza a entrega, e enquanto a
  emissão não teve etapa ela aparecia como concluída com a cédula pela metade. O
  admin
  administra o sistema e **não decide permuta** — quem concede o acesso não pode
  ser quem decide o negócio. O caminho inteiro (estados, transições e o que
  responder a quem chega fora de hora) está em `api/src/barters/barter-workflow.ts`,
  e cada permuta guarda a própria linha do tempo, gravada na mesma transação da
  mudança de estado. O app pergunta ao servidor o que cada pessoa pode fazer
  (`capabilities`) em vez de manter uma segunda cópia das regras em Dart.
- **Há um caminho de volta, e ele tem dono nas duas pontas**: a esteira só anda
  para a frente, mas a permuta erra depois de sair da mão de quem a montou. O
  consultor **pede alteração** e o admin decide — liberar (ela volta a rascunho,
  e o parecer do gerente e a decisão do comitê são apagados), recusar, ou
  **atender no valor**: corrigir a linha de R$ que motivou o pedido, com as
  sacas recalculadas e a permuta parada onde estava. A terceira saída existe
  porque devolver a permuta inteira por causa de um número joga fora dois
  pareceres e uma decisão. O admin só altera valor ATENDENDO a um pedido — sem
  pedido em aberto, ele estaria decidindo o negócio.
- **O que a tabela não tem entra por pedido, e fica preso à permuta**: a tabela
  do Barter é uma lista fechada e a lavoura não é. O consultor **pede um produto
  de fora** (do rascunho até a decisão do comitê) e o admin o inclui com o valor
  que acertou — naquela permuta, e em nenhuma outra. O item não entra no
  catálogo (o catálogo é a lista do fornecedor), paga em sacas como qualquer
  insumo retirado e **não entra em régua nenhuma**: sem classe, ele engordaria o
  denominador de todas as pastas e derrubaria a permuta que veio ajudar.
- **O seguro é opcional, é do LANÇAMENTO e é precificado pelo LUGAR**: o admin
  diz, ao publicar o Barter, se aquela safra leva seguro agrícola (e liga ou
  desliga depois, sem republicar a tabela). Quanto custa não é do cliente, é da
  praça — o que a seguradora cota é o risco do lugar —, e por isso existe uma
  **base por município** (R$/ha), mantida linha a linha ou pela planilha da
  seguradora — que vem com três valores por hectare (sem subvenção, com
  subvenção e o reajustado para a safra) e é lida pelo último, o que a empresa
  de fato adianta; a carga responde de qual coluna leu. O município casa com o
  cadastro do produtor mesmo sem a UF ("TUPANCIRETÃ" é "Tupanciretã/RS"), que é
  como a seguradora manda quando a planilha é de um estado só. Cada permuta pega a **área cultivável do produtor × a taxa do
  município dele**, e o resultado entra no custo e é pago em sacas, como os
  insumos: o seguro é dinheiro que a empresa adianta. A taxa é **congelada** no
  registro (recotar a praça não reescreve o que foi combinado), a linha do
  seguro é marcada no comprovante (e não entra nas réguas das pastas), e o
  município sem taxa **recusa o registro** nomeando a praça — a recusa acontece
  onde ela é grátis, e não com o insumo já na fazenda.
- **O comitê decide com o dossiê na mão, e a exigência deixou de ser prosa**: a
  consulta ao Serasa e o extrato do endividamento do produtor dentro da
  cooperativa agora ficam **anexados à permuta**, em vez de circularem por
  e-mail entre quem foi à reunião. É a única leitura de anexo **restrita** do
  sistema (comitê e admin, e mais ninguém: o consultor leva ao produtor a
  decisão, não o dossiê), e a janela de mexer nela fecha na decisão — depois
  dela, o que fundamentou uma aprovação é prova. O comitê também passou a abrir
  o **SCR** sem receber a cédula junto. E o que a reunião exige — **avalista,
  garantia real, seguro** — virou três campos ao lado do texto da decisão: as
  caixas dizem O QUÊ, e o texto continua dizendo QUAL.
- **A permuta mostra o caminho inteiro, e não só o já andado**: o detalhe traz
  um `steps` com as quatro etapas sempre — a cumprida com quem a assinou e o que
  escreveu, a de agora com o que ela espera ("aguarda o parecer do gerente
  Fulano"), as que faltam com quem vai ter de agir. É linha do tempo e checklist
  na mesma lista, porque "por onde ela passou" e "o que falta" são a mesma
  pergunta feita dos dois lados — e a segunda é a que o produtor faz ao
  consultor. Quem monta a lista é a máquina de estados (`progressOf`), pelo mesmo
  motivo das capacidades: uma etapa nova aparece nas telas já instaladas. Permuta
  negada marca o faturamento e os três degraus da cédula como `halted`, e não
  como pendentes — ela não vai ser faturada nem virar título, e uma tela de
  acompanhamento não pode prometer passos que ninguém vai dar.
- **A CPR tem três mãos, e o documento é derivado**: a permuta registra o
  negócio; a **Cédula de Produto Rural** o formaliza como título. O **consultor**
  preenche (a qualificação civil do emitente, as lavouras em penhor, o padrão do
  grão e o **SCR do produtor**, que é anexo obrigatório) — é ele quem visita a
  fazenda, e pedir isso a quem fatura significava obter tudo por telefone e
  digitar; o **emissor** confere e emite, e cédula com lacuna não sai; o **admin**
  tira a segunda via. O que a permuta já sabe não é campo de formulário — e isso
  cresceu: o **vencimento** agora é da SAFRA (ele muda conforme a cultura, e vale
  para todas as cédulas dela) e os **números das notas** vêm do faturamento, em
  lista e com o arquivo junto. Quem diz o que ainda falta é o servidor, e cada
  pendência diz com quem ela se resolve. A **credora** é cadastro à parte
  (`/creditor`), mantido pelo admin *e* pelo **emissor**: é o timbre do papel,
  não decisão de negócio. Os **extensos** são
  gerados a partir dos números, nunca digitados — o modelo que originou tudo
  trazia "367 (quatrocentos e quarenta) sacas". O documento sai em **.docx**, e
  não em PDF, porque a cédula ainda passa pelo jurídico e pelo cartório antes de
  ser assinada. Detalhes em `docs/arquitetura.md` (seção 1.5c).
- **Servidor é a autoridade**: o payload de criação de permuta leva apenas
  produtos e quantidades; preços saem do banco, mínimos são revalidados e as
  sacas são recalculadas no servidor. Itens guardam *snapshots* de preço/nome
  — reajustes futuros não alteram permutas registradas.
- **App com cache em memória** (`app/lib/data/app_data.dart`): os dados são
  carregados no login e as telas continuam com leituras síncronas (mesmos
  contratos do antigo `mock_data.dart`); toda mutação chama a API e atualiza o
  cache com a resposta oficial. Dataset pequeno ⇒ app instantâneo e código
  simples. As listas que crescem (`/barters`, `/producers`) são **paginadas no
  servidor** — nenhuma resposta carrega a base inteira de uma vez — e o app
  remonta as páginas para manter o cache completo, porque o painel do admin
  soma sacas e valores sobre todas as permutas. Quando isso deixar de caber, a
  API já está pronta para as telas carregarem sob demanda.
- **PostgreSQL, em todos os ambientes**: dev, teste e produção usam o mesmo
  banco (Prisma 7 + driver adapter `@prisma/adapter-pg`), e o que se testa é o
  banco que roda em produção. A escolha não é por desempenho — é por
  **operação**: um servidor de banco à parte coordena várias instâncias da API
  sobre o mesmo dado, e é isso que sustenta deploy sem downtime, réplica de
  leitura e backup online.
- **A conta é do servidor, a sessão tem fim**: senha com `scrypt` (parâmetros
  gravados junto ao hash, reescrita sozinha quando o custo sobe) e política
  única em `api/src/auth/password-policy.ts`; token opaco guardado só como
  SHA-256, que morre por prazo **e** por inatividade; conta que erra a senha dez
  vezes descansa quinze minutos; entrar, falhar e ser bloqueado deixam rastro na
  trilha de auditoria. Detalhes em `api/README.md`.

## Por que trocamos AdonisJS por NestJS

A primeira versão deste backend foi feita em AdonisJS (ainda visível no
histórico do git, commit `25e706f`). Trocamos para NestJS a pedido do time por
ser o framework Node mais adotado no mercado — maior familiaridade e mais
gente contratável já sabendo o padrão. Tecnicamente o Adonis já resolvia bem o
problema; a migração preservou **o mesmo contrato de API** (rotas, formatos de
resposta, mensagens de erro), então o app Flutter não precisou de nenhuma
mudança.
