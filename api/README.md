# Barter API

Backend do **Barter** (permuta de grãos por insumos) em **NestJS 11** + **Prisma
7**, com SQLite em desenvolvimento/teste. É a autoridade das regras de negócio:
o app Flutter só mostra a prévia, quem valida e calcula é aqui.

## Onde fica

```
~/Projects/barter-fullstack/          ← monorepo
├── api/    ← VOCÊ ESTÁ AQUI (backend NestJS)
├── app/    ← app Flutter que consome esta API
└── docs/   ← revisão de frontend e decisões de arquitetura
```

> O projeto original `~/Projects/barter-app` é outra coisa: continua só com
> dados mockados, para testes de interface. Não confundir com este.

---

## Primeiros passos

**Pré-requisito:** Node 20 ou superior (`node -v` para conferir).

```bash
cd ~/Projects/barter-fullstack/api

npm install          # 1. dependências (só na primeira vez)
npm run start:dev    # 2. sobe a API em http://localhost:3333
```

Na primeira subida o banco está vazio, então a API **carrega o dataset de
demonstração automaticamente** — você verá no terminal:

```
Banco vazio — dataset de demonstração carregado (senha: 123456).
Barter API no ar: http://localhost:3333
```

Pronto, já tem dados para testar. Confirme que está no ar:

```bash
curl http://localhost:3333/
# {"name":"Barter API","docs":"/api/v1"}
```

### Reiniciar mantém seus dados

O auto-seed só roda quando o banco está **vazio**. Registros que você criar
testando sobrevivem a reinícios do servidor. Para voltar ao dataset limpo a
qualquer momento:

```bash
npm run db:seed      # apaga tudo e recarrega o dataset de demonstração
```

---

## Testando a API na mão

Todas as rotas (menos o login) exigem um token no header
`Authorization: Bearer <token>`. Fluxo típico:

**1. Login — pega o token** (senha de todos: `123456`):

```bash
curl -X POST http://localhost:3333/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@barter.com.br","password":"123456"}'
```

Resposta: `{"data":{"token":"oat_...","user":{...}}}`. Copie o `token`.

**2. Use o token** (exemplos — troque `$TOKEN` pelo valor copiado):

```bash
TOKEN="cole-o-token-aqui"

# Listar produtores (admin vê todos; vendedor vê só a própria carteira)
curl http://localhost:3333/api/v1/producers -H "Authorization: Bearer $TOKEN"

# Listar permutas
curl http://localhost:3333/api/v1/barters -H "Authorization: Bearer $TOKEN"

# Catálogo de produtos com histórico de preços
curl http://localhost:3333/api/v1/products -H "Authorization: Bearer $TOKEN"
```

**3. Registrar uma permuta** (logado como um vendedor — o servidor calcula as
sacas do grão a partir do custo dos insumos):

```bash
curl -X POST http://localhost:3333/api/v1/barters \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"producerId":1,"grainId":1,"inputs":[
        {"productId":5,"quantity":48},
        {"productId":6,"quantity":300},
        {"productId":7,"quantity":18}]}'
```

> Dica: use o admin para revisar (`POST /barters/:code/review`) e um vendedor
> (ex.: `joao.silva@barter.com.br`) para criar. Ver a tabela de rotas abaixo.

---

## Quem já vem cadastrado (senha de todos: `123456`)

| Papel | E-mail | Carteira de produtores |
|---|---|---|
| **Admin** | `admin@barter.com.br` | — (enxerga tudo) |
| Vendedor | `joao.silva@barter.com.br` | Antônio Carvalho, Sebastião Ramos |
| Vendedor | `ana.ferreira@barter.com.br` | Helena Prado, Cláudia Nunes |
| Vendedor | `roberto.souza@barter.com.br` | Joaquim Tavares |
| Vendedor | `maria.oliveira@barter.com.br` | Osmar Dutra |
| Vendedor | `lucas.barros@barter.com.br` | Vanessa Lopes |

Além disso, o dataset traz **9 produtos** (4 grãos + 5 insumos, cada um com 7
meses de histórico de preço), **3 categorias** de insumo com regras de mínimo, e
**8 permutas** em estados variados (aprovadas, pendentes e uma negada) para
testar o fluxo de revisão do admin.

---

## Rodando junto com o app Flutter

Suba esta API (`npm run start:dev`) e, noutro terminal:

```bash
cd ../app
flutter run                                              # simulador iOS/desktop (usa localhost)
flutter run --dart-define=API_URL=http://192.168.0.10:3333  # aparelho físico (IP da sua máquina)
flutter run --dart-define=API_URL=http://10.0.2.2:3333      # emulador Android
```

---

## Comandos

```bash
npm run start:dev    # dev server com watch em http://localhost:3333 (auto-seed se vazio)
npm run db:seed      # (re)carrega o banco com o dataset de demonstração (apaga tudo antes)
npm test             # 7 testes de unidade (matemática da permuta)
npm run test:e2e     # 33 testes funcionais (contra um banco de teste próprio)
npm run build        # compila para dist/
npm run start:prod   # roda o build compilado
```

---

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
├── seed-data.ts   # dataset de demonstração (mesmos números do mock do app)
├── seed.ts        # `npm run db:seed` — apaga e recria tudo
└── seed-if-empty.ts  # auto-seed na subida do servidor quando o banco está vazio
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
  dependência nativa adicional.
- **Testes e2e usam banco próprio** (`.env.test`, `prisma/test.db`) e resetam
  os ids de autoincrement do SQLite a cada teste (`DELETE FROM
  sqlite_sequence`) — sem isso, `deleteMany()` não reinicia o contador e os
  testes que fixam ids do seed quebrariam a partir do segundo teste.

## Produção

- Troque para Postgres: mude `provider` em `prisma/schema.prisma`, troque o
  driver adapter em `src/prisma/prisma.service.ts` (ex.: `@prisma/adapter-pg`)
  e rode `prisma migrate dev`.
- Configure CORS explicitamente em `src/app.setup.ts` (`enableCors()` hoje
  libera tudo, adequado só para dev) e sirva atrás de HTTPS.
