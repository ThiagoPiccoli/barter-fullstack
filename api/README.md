# Barter API

Backend do Barter (permuta de grãos por insumos) em **AdonisJS** com SQLite em
desenvolvimento/teste e configuração pronta para Postgres em produção.

## Comandos

```bash
npm install                        # dependências
node ace migration:fresh --seed    # (re)cria o banco + dataset de demonstração
npm run dev                        # dev server com HMR em http://localhost:3333
npm test                           # 38 testes (unit + funcionais)
npm run typecheck                  # tsc --noEmit
node ace list:routes               # tabela de rotas
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

Respostas usam o envelope `{ "data": ... }`. Erros: `{ "message": ... }`
(regras de negócio, HTTP 422/403) ou `{ "errors": [{ "message": ... }] }`
(validação de payload).

## O coração do escambo (`app/services/barter_service.ts`)

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
   é ignorado), calcula as sacas do grão (`custo ÷ preço da saca`, 4 casas) e
   cria o item de grão;
5. gera o código sequencial `PRM-<ano>-NNN` dentro de uma transação.

Itens guardam *snapshot* de nome/unidade/preço; permutas antigas não mudam
quando o admin reajusta valores ou exclui cadastros (FKs `SET NULL` +
nomes desnormalizados). A matemática pura fica em
`app/services/barter_math.ts`, coberta por testes unitários.

## Estrutura

```
app/
├── controllers/   # finos: validam payload e delegam
├── services/      # regras de negócio (barter_service, barter_math)
├── models/        # Lucid, estendem as classes geradas de database/schema.ts
├── transformers/  # serialização por recurso (shape da API)
├── validators/    # VineJS na borda de entrada
├── middleware/    # auth (token) + admin (papel)
└── exceptions/    # BusinessException (422, mensagem pt-BR p/ o app)
database/
├── migrations/    # fonte da verdade do schema (gera database/schema.ts)
└── seeders/       # dataset de demonstração (mesmos números do mock do app)
tests/
├── unit/          # matemática da permuta
└── functional/    # auth, escopo de carteira, regras, revisão, catálogo
```

## Produção

- Troque para Postgres: `npm i pg` e descomente a conexão em
  `config/database.ts` (migrations são portáveis).
- Gere um `APP_KEY` novo (`node ace generate:key`) e configure CORS
  (`config/cors.ts`) com a origem real.
- Sirva atrás de HTTPS — o app remove as exceções de HTTP quando a API tiver
  TLS.
