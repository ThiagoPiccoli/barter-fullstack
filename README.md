# Barter — Permuta de Grãos por Insumos (fullstack)

Monorepo com o app e o backend do Barter:

```
barter-fullstack/
├── app/   Flutter (clone do barter-app original, integrado à API)
├── api/   AdonisJS 6/7 + SQLite (dev) — regras de negócio autoritativas
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
npm install                       # primeira vez
node ace migration:fresh --seed   # cria o banco e carrega o dataset de demonstração
npm run dev                       # http://localhost:3333
```

Terminal 2 — App:

```bash
cd app
flutter pub get                   # primeira vez
flutter run                       # simulador iOS/desktop: localhost funciona direto
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
cd api && npm test        # 38 testes (unit da matemática da permuta + funcionais da API)
cd app && flutter test    # smoke test de widgets

# Teste de integração de ponta a ponta (exige a API no ar com seed fresco):
cd api && node ace migration:fresh --seed && npm run dev &
cd app && flutter test integration_test/app_flow_test.dart -d macos
```

O teste de integração cria uma permuta real (PRM-2026-009) no banco de
desenvolvimento — rode `node ace migration:fresh --seed` para zerar.

## Decisões de arquitetura (resumo)

- **AdonisJS** no backend: TypeScript de ponta a ponta com validação (VineJS),
  ORM + migrations (Lucid), auth por access tokens e testes (Japa) integrados
  no framework — o conjunto certo para uma API REST deste porte sem colar 10
  bibliotecas à mão. Detalhes em `api/README.md`.
- **Servidor é a autoridade**: o payload de criação de permuta leva apenas
  produtos e quantidades; preços saem do banco, mínimos são revalidados e as
  sacas são recalculadas no servidor. Itens guardam *snapshots* de preço/nome
  — reajustes futuros não alteram permutas registradas.
- **App com cache em memória** (`app/lib/data/app_data.dart`): os dados são
  carregados no login e as telas continuam com leituras síncronas (mesmos
  contratos do antigo `mock_data.dart`); toda mutação chama a API e atualiza o
  cache com a resposta oficial. Dataset pequeno ⇒ app instantâneo e código
  simples.
- **SQLite em dev/test, Postgres pronto**: basta instalar `pg` e descomentar a
  conexão em `api/config/database.ts`.
