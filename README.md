# Barter — Permuta de Grãos por Insumos (fullstack)

Monorepo com o app e o backend do Barter:

```
barter-fullstack/
├── app/   Flutter (clone do barter-app original, integrado à API)
├── api/   NestJS 11 + Prisma 7 + SQLite (dev) — regras de negócio autoritativas
└── docs/  Revisão de frontend e decisões de arquitetura
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
| Admin    | admin@barter.com.br         | 123456 |
| Vendedor | joao.silva@barter.com.br    | 123456 |
| Vendedor | ana.ferreira@barter.com.br  | 123456 |

(Os demais vendedores do dataset também logam com `123456`.)

## Testes

```bash
cd api && npm test          # 7 testes de unidade (matemática da permuta)
cd api && npm run test:e2e  # 33 testes funcionais da API (auth, escopo, regras)
cd app && flutter test      # smoke test de widgets

# Teste de integração de ponta a ponta (exige a API no ar com seed fresco):
cd api && npm run db:seed && npm run start:dev &
cd app && flutter test integration_test/app_flow_test.dart -d macos
```

O teste de integração cria uma permuta real (PRM-2026-009) no banco de
desenvolvimento — rode `npm run db:seed` para zerar.

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
  simples.
- **SQLite em dev/test, Postgres pronto**: o Prisma schema usa `provider =
  "sqlite"`; trocar para Postgres é mudar o provider, o driver adapter em
  `src/prisma/prisma.service.ts` e rodar `prisma migrate dev` de novo — os
  services não mudam.

## Por que trocamos AdonisJS por NestJS

A primeira versão deste backend foi feita em AdonisJS (ainda visível no
histórico do git, commit `25e706f`). Trocamos para NestJS a pedido do time por
ser o framework Node mais adotado no mercado — maior familiaridade e mais
gente contratável já sabendo o padrão. Tecnicamente o Adonis já resolvia bem o
problema; a migração preservou **o mesmo contrato de API** (rotas, formatos de
resposta, mensagens de erro), então o app Flutter não precisou de nenhuma
mudança.
