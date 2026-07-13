# Barter API

Backend do Barter (permuta de grãos por insumos) em **NestJS 11** + **Prisma
7**, com SQLite em desenvolvimento/teste e schema pronto para trocar de banco
em produção.

## Comandos

```bash
npm install              # dependências
npm run db:seed          # (re)carrega o banco com o dataset de demonstração
npm run start:dev        # dev server com watch em http://localhost:3333
npm test                 # 7 testes de unidade (matemática da permuta)
npm run test:e2e         # 33 testes funcionais (contra um banco de teste próprio)
npm run build            # compila para dist/
```

## Papéis e regra de acesso

- **admin** — gerencia cadastros (vendedores, produtores), valores de
  referência e pastas de insumos; revisa (aprova/nega) permutas. Enxerga tudo.
- **seller (vendedor)** — loga no app e registra permutas **apenas para os
  produtores da própria carteira**; nunca vê as carteiras dos colegas.
- **produtor** — não loga: é um cadastro designado pelo vendedor nas permutas.

Não há signup público: vendedores são provisionados pelo admin (nascem com a
senha padrão `123456`).

## Rotas (prefixo `/api/v1`)

| Método | Rota | Acesso | Descrição |
|---|---|---|---|
| POST | `/auth/login` | público | E-mail + senha → token (Bearer) |
| POST | `/auth/logout` | autenticado | Revoga o token atual |
| GET | `/me` | autenticado | Perfil do usuário logado |
| GET | `/producers` | autenticado | Carteira do vendedor; admin vê todas (`?sellerId=`) |
| GET | `/producers/:id` | autenticado | Detalhe (escopado por carteira) |
| POST/PUT/DELETE | `/producers[/:id]` | admin | CRUD de produtores |
| GET | `/products` | autenticado | Catálogo com histórico de valores (`?type=grain\|input`) |
| GET | `/products/:id` | autenticado | Produto + linha do tempo |
| POST/PUT | `/products[/:id]` | admin | Criação/edição de cadastro |
| PUT | `/products/:id/price` | admin | Reajuste (gera ponto no histórico) |
| GET | `/categories` | autenticado | Pastas de insumos e regras vigentes |
| POST/PUT/DELETE | `/categories[/:id]` | admin | CRUD de pastas |
| GET | `/sellers` | admin | Vendedores |
| POST/PUT/DELETE | `/sellers[/:id]` | admin | CRUD de vendedores |
| GET | `/barters` | autenticado | Escopado por papel (`?status=`) |
| GET | `/barters/:code` | autenticado | Detalhe pelo código público (PRM-AAAA-NNN) |
| POST | `/barters` | vendedor | Registra permuta (ver regras abaixo) |
| POST | `/barters/:code/review` | admin | Aprova/nega pendente com observação |

Respostas usam o envelope `{ "data": ... }` (via `EnvelopeInterceptor`). Erros
de negócio: `{ "message": "..." }` (403/404/422); erros de validação de
payload também caem em `{ "message": "<primeira mensagem>" }` — uma string
única, que é o que o app exibe.

## O coração do escambo (`src/barters/barters.service.ts`)

`POST /barters` recebe **apenas produtos e quantidades**:

```json
{
  "producerId": 1,
  "grainId": 1,
  "inputs": [
    { "productId": 5, "quantity": 48 },
    { "productId": 6, "quantity": 300 }
  ]
}
```

O servidor então:

1. confere que o produtor pertence à carteira do vendedor autenticado;
2. exige todo insumo com taxa por hectare em pelo menos `taxa × área` do
   produtor (payload sem um insumo obrigatório é rejeitado);
3. valida as regras de mínimo das pastas (`% do custo total` ou `R$/ha`);
4. **precifica com os valores vigentes do banco** (preço enviado pelo cliente
   é descartado pelo `whitelist` do `ValidationPipe`), calcula as sacas do
   grão (`custo ÷ preço da saca`, 4 casas) e cria o item de grão;
5. gera o código sequencial `PRM-<ano>-NNN` dentro de uma transação Prisma.

Itens guardam *snapshot* de nome/unidade/preço; permutas antigas não mudam
quando o admin reajusta valores ou exclui cadastros (FKs `SetNull` + nomes
desnormalizados no schema). A matemática pura fica em
`src/barters/barter-math.ts`, coberta por testes unitários (Jest).

## Estrutura

```
src/
├── auth/          # login/logout por token opaco (hash SHA-256 no banco),
│                  # hash de senha (scrypt), guard global + @Public()
├── common/        # AdminGuard, @CurrentUser(), EnvelopeInterceptor, ValidationPipe
├── prisma/        # PrismaService (driver adapter better-sqlite3) como provider global
├── producers/      services/products/categories/barters/  # um módulo por recurso:
│                  # controller fino → service com a regra → PrismaService
prisma/
├── schema.prisma  # fonte da verdade do schema (gera o client tipado)
├── migrations/
└── seed-data.ts   # dataset de demonstração (mesmos números do mock do app);
                   # seed.ts (CLI) e test/utils.ts (e2e) reaproveitam esta função
test/
├── *.e2e-spec.ts  # sobem a aplicação real (Test.createTestingModule) contra
│                  # um banco de teste próprio (.env.test); cada teste chama
│                  # resetDb() para voltar ao dataset limpo
```

## Decisões específicas do NestJS

- **Prisma 7** move a `DATABASE_URL` do `schema.prisma` para `prisma.config.ts`
  e exige um *driver adapter* explícito (`@prisma/adapter-better-sqlite3`) — daí
  o `PrismaService` construir o `PrismaClient` com esse adapter.
- **Tokens de acesso** são opacos: o valor cru vai ao cliente, o banco guarda
  só o SHA-256 (`AccessToken.hash`). Logout apaga a linha — revogação real.
- **Senha**: `scrypt` do próprio Node (`src/auth/password.util.ts`), sem
  dependência nativa adicional (equivalente ao hash do Adonis).
- **Testes e2e usam banco próprio** (`.env.test`, `prisma/test.db`) e resetam
  os ids de autoincrement do SQLite a cada teste (`DELETE FROM
  sqlite_sequence`) — sem isso, `deleteMany()` não reinicia o contador e os
  testes que fixam ids do seed quebrariam a partir do segundo teste.

## Produção

- Troque para Postgres: mude `provider` em `prisma/schema.prisma`, troque o
  driver adapter em `src/prisma/prisma.service.ts` (ex.:
  `@prisma/adapter-pg`) e rode `prisma migrate dev`.
- Gere segredos de produção via variáveis de ambiente (nenhum hoje além de
  `DATABASE_URL`/`PORT`) e configure CORS explicitamente em
  `src/app.setup.ts` (`enableCors()` hoje libera tudo, adequado só para dev).
- Sirva atrás de HTTPS — o app remove as exceções de HTTP quando a API tiver
  TLS.
