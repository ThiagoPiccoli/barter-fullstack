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
cd api && npm test          # 131 testes de unidade (matemática, senha, sessão, throttling, setup)
cd api && npm run test:e2e  # 141 testes funcionais da API (auth, escopo, regras, contrato de erro)
cd api && npm run test:cov  # as duas suítes juntas, com cobertura (92% de statements)
cd app && flutter test      # 35 testes (matemática espelhada, parsers, abertura do app)
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
  banco (Prisma 7 + driver adapter `@prisma/adapter-pg`). Antes era SQLite
  embutido no processo, e a troca aconteceu **antes da primeira carga real** de
  propósito: sem dado de produção, o custo foi reescrever migrations; com dado,
  seria janela de parada e script de transferência. O que o SQLite não dava não
  era desempenho — era operação: duas instâncias sobre o mesmo arquivo não se
  coordenam, então não havia deploy sem downtime, réplica de leitura nem backup
  online.
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
