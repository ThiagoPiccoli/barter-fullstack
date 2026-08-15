# Barter API

Backend do **Barter** (permuta de grãos por insumos) em **NestJS 11** + **Prisma
7**, com PostgreSQL. É a autoridade das regras de negócio:
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
  -d '{"email":"admin@agrobarter.com.br","password":"123456"}'
```

Resposta: `{"data":{"token":"oat_...","user":{...}}}`. Copie o `token`.

**2. Use o token** (exemplos — troque `$TOKEN` pelo valor copiado):

```bash
TOKEN="cole-o-token-aqui"

# Listar produtores (admin vê todos; consultor vê só a própria carteira)
curl http://localhost:3333/api/v1/producers -H "Authorization: Bearer $TOKEN"

# Listar permutas
curl http://localhost:3333/api/v1/barters -H "Authorization: Bearer $TOKEN"

# Catálogo de produtos com histórico de preços
curl http://localhost:3333/api/v1/products -H "Authorization: Bearer $TOKEN"
```

**3. Registrar uma permuta** (logado como um consultor — o servidor calcula as
sacas do grão a partir do custo dos insumos):

```bash
curl -X POST http://localhost:3333/api/v1/barters \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"producerId":1,"grainId":1,"inputs":[
        {"productId":5,"quantity":48},
        {"productId":6,"quantity":300},
        {"productId":7,"quantity":18}]}'
```

> Dica: use o admin para revisar (`POST /barters/:code/review`) e um consultor
> (ex.: `joao.silva@agrobarter.com.br`) para criar. Ver a tabela de rotas abaixo.

---

## Quem já vem cadastrado (senha de todos: `123456`)

| Papel | E-mail | Carteira de produtores |
|---|---|---|
| **Admin** | `admin@agrobarter.com.br` | — (enxerga tudo) |
| Gerente | `gerente@agrobarter.com.br` | — (enxerga tudo, em modo leitura) |
| Comitê | `comite@agrobarter.com.br` | — (enxerga tudo, em modo leitura) |
| Faturista | `faturista@agrobarter.com.br` | — (enxerga tudo, em modo leitura) |
| Consultor | `joao.silva@agrobarter.com.br` | Antônio Carvalho, Sebastião Ramos |
| Consultor | `ana.ferreira@agrobarter.com.br` | Helena Prado, Cláudia Nunes |
| Consultor | `roberto.souza@agrobarter.com.br` | Joaquim Tavares |
| Consultor | `maria.oliveira@agrobarter.com.br` | Osmar Dutra |
| Consultor | `lucas.barros@agrobarter.com.br` | Vanessa Lopes |

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
npm run start:dev      # dev server com watch em http://localhost:3333 (auto-seed se vazio)
npm run db:seed        # (re)carrega o banco com o dataset de demonstração (apaga tudo antes)
npm run db:reset       # apaga o banco, reaplica as migrations do zero e semeia
npm test               # 30 testes de unidade (matemática, throttling, setup, filtro de erro)
npm run test:e2e       # 65 testes funcionais (contra um banco de teste próprio)
npm run lint           # ESLint + Prettier
npm run build          # compila para dist/
npm run start:prod     # roda o build compilado
npm run password:reset # redefine a senha de qualquer conta (saída de emergência do admin)
```

---

## Papéis e regra de acesso

São cinco, definidos num só lugar ([`src/common/roles.ts`](src/common/roles.ts)):

- **admin** — gerencia cadastros (consultores, produtores), valores de
  referência e pastas de insumos; revisa (aprova/nega) permutas. Enxerga tudo.
- **manager (gerente)**, **committee (comitê)** e **biller (faturista)** — a
  RETAGUARDA. Enxergam a operação inteira, como o admin, e **ainda não escrevem
  nada**: o fluxo de cada um entra junto com o contrato entre eles. Toda
  tentativa de escrita hoje devolve 403, e isso é testado
  ([`test/rbac.e2e-spec.ts`](test/rbac.e2e-spec.ts)).
- **consultant (consultor)** — loga no app e registra permutas **apenas para os
  produtores da própria carteira**; nunca vê as carteiras dos colegas.
- **produtor** — não loga: é um cadastro designado pelo consultor nas permutas.

Quem impõe isso é o `AccessGuard` global, e ele **nega por padrão**: toda rota
declara a sua política (`@RequireCapability`, `@AnyRole` ou `@Public`), e rota
sem política é recusada. Quem tem cada capacidade está numa tabela só,
[`src/common/policy.ts`](src/common/policy.ts) — os services consultam a mesma
tabela para decidir o escopo por linha (carteira própria × operação inteira).

Atos sensíveis deixam rastro em `GET /audit-logs`: provisionar, editar, resetar
senha, excluir usuário e revisar permuta.

Não há signup público: **usuário é provisionado pelo admin**, cada papel pela
sua rota — `POST /consultants`, `/managers`, `/committee-members`, `/billers`.
O papel vem da ROTA, nunca do corpo, e cada rota só enxerga e altera o próprio
papel (papel alheio responde 404).

`admin` não tem rota: o primeiro vem do `bootstrap-admin` (banco vazio +
variáveis de ambiente) e a senha se recupera por `npm run password:reset`. Não
há ninguém acima do admin para autorizar a criação de outro.

### Senha de primeira entrada

Ao criar um usuário de qualquer papel, o servidor **sorteia uma senha só dele** e a devolve
**uma única vez**, no corpo da resposta (`provisionalPassword`, algo como
`K7NP-4TQX`). O admin dita esse valor para o consultor; depois disso ele não
pode mais ser lido — o banco guarda apenas o hash.

A aleatoriedade não é capricho. Enquanto essa senha foi um valor fixo igual
para todos, quem soubesse o e-mail de um consultor recém-cadastrado podia
entrar antes dele, definir a senha definitiva e ficar com a conta — sem
nenhuma forma de o admin retomá-la.

Perdeu-se a senha (ou a conta caiu em mãos erradas)? `POST
/consultants/:id/reset-password` sorteia outra e **encerra todas as sessões
abertas** daquela conta.

### E se o próprio admin perder a senha?

O admin não tem ninguém acima dele, e o provisionamento inicial só roda com o
banco vazio. A saída é pela linha de comando, no servidor:

```bash
npm run password:reset                        # lista as contas cadastradas
npm run password:reset -- admin@empresa.com   # sorteia uma senha provisória
```

A senha definida por aí também é provisória: exige troca no primeiro login.

## Rotas (prefixo `/api/v1`)

| Método | Rota | Acesso | Descrição |
|---|---|---|---|
| POST | `/auth/login` | público | E-mail + senha → token (Bearer) |
| POST | `/auth/logout` | autenticado | Revoga o token atual |
| GET | `/me` | autenticado | Perfil do usuário logado |
| POST | `/auth/password` | autenticado | Troca da própria senha (derruba as outras sessões) |
| GET | `/producers` | autenticado | Carteira do consultor; admin vê todas (`?consultantId=`) |
| GET | `/producers/:id` | autenticado | Detalhe (escopado por carteira) |
| POST/PUT/DELETE | `/producers[/:id]` | admin | CRUD de produtores |
| GET | `/products` | autenticado | Catálogo com histórico de valores (`?type=grain\|input`) |
| GET | `/products/:id` | autenticado | Produto + linha do tempo |
| POST/PUT | `/products[/:id]` | admin | Criação/edição de cadastro |
| PUT | `/products/:id/price` | admin | Reajuste (gera ponto no histórico) |
| DELETE | `/products/:id` | admin | Tira do catálogo (permutas antigas intactas) |
| GET | `/categories` | autenticado | Pastas de insumos e regras vigentes |
| POST/PUT/DELETE | `/categories[/:id]` | admin | CRUD de pastas |
| GET/POST/PUT/DELETE | `/consultants[/:id]` | admin | Consultores |
| GET/POST/PUT/DELETE | `/managers[/:id]` | admin | Gerentes |
| GET/POST/PUT/DELETE | `/committee-members[/:id]` | admin | Integrantes do comitê |
| GET/POST/PUT/DELETE | `/billers[/:id]` | admin | Faturistas |
| POST | `/<papel>/:id/reset-password` | admin | Nova senha provisória; encerra as sessões dele |
| GET | `/audit-logs` | admin | Trilha de auditoria (`?action=`, `?targetType=`); só leitura |
| GET | `/barters` | autenticado | Escopado por papel (`?status=`) |
| GET | `/barters/:code` | autenticado | Detalhe pelo código público (PRM-AAAA-NNN) |
| POST | `/barters` | consultor | Registra permuta (ver regras abaixo) |
| POST | `/barters/:code/review` | admin | Aprova/nega pendente com observação |

Documentação navegável em **`/api/v1/docs`** (Swagger). Fica aberta fora de
produção; em produção, só com `SWAGGER=on`.

### Formato das respostas

Sucesso vem no envelope `{ "data": ... }` (via `EnvelopeInterceptor`). As
listas que crescem com o uso — `/barters` e `/producers` — são **paginadas** e
trazem um `meta` ao lado:

```json
{ "data": [ ... ], "meta": { "total": 842, "limit": 100, "offset": 0 } }
```

Aceitam `?limit=` (padrão 100, máximo 500) e `?offset=`. `data` continua sendo
o array puro, então quem já lia a lista não muda nada — o `meta` diz o que
existe além da página. O catálogo (`/products`, `/categories`) e
`/consultants` não são paginados de propósito: são limitados pelo tamanho da
operação, e o app precisa deles inteiros para montar a tela de permuta.

**Todo** erro sai como `{ "message": "<frase em pt-BR>", "statusCode": N }` —
uma string única, que é o que o app exibe direto ao usuário. Vale para regra de
negócio (403/404/422), validação de payload, corpo malformado (400), corpo
grande demais (413) e excesso de tentativas (429). Erros inesperados (500) não
carregam detalhe interno: devolvem um `requestId` que aparece no log do
servidor junto com a pilha.

**Filtro que a API não entende é RECUSADO com 422**, nunca ignorado
(`?status=lixo`, `?consultantId=abc`). Ignorar devolvia a base inteira com
aparência de lista filtrada.

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

1. confere que o produtor pertence à carteira do consultor autenticado;
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
├── prisma/        # PrismaService (driver adapter pg) como provider global
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
  e exige um *driver adapter* explícito (`@prisma/adapter-pg`) — daí
  o `PrismaService` construir o `PrismaClient` com esse adapter.
- **Tokens de acesso** são opacos: o valor cru vai ao cliente, o banco guarda
  só o SHA-256 (`AccessToken.hash`). Logout apaga a linha — revogação real.
- **Senha**: `scrypt` do próprio Node (`src/auth/password.util.ts`), sem
  dependência nativa adicional. O hash guarda os PARÂMETROS de custo junto
  (`scrypt:N:r:p:salt:hash`) — é o que permite encarecer o cálculo mais tarde
  sem invalidar as senhas já cadastradas: quem entra com um hash antigo sai com
  um hash no custo de hoje, sem precisar trocar de senha. Ajustável por
  `PASSWORD_COST` (padrão 16, ~170ms); os testes baixam para a suíte caber, e o
  servidor avisa na subida se encontrar valor abaixo do padrão.
- **Login não denuncia quem existe**: e-mail desconhecido paga o mesmo custo de
  scrypt de uma verificação real. Sem isso a resposta voltaria rápido demais e
  o tempo diria o que a mensagem genérica esconde.
- **Testes e2e usam banco próprio** (`.env.test` → `barter_test`) e reiniciam
  as sequências de id a cada teste (ver `resetDb` em `test/utils.ts`) — sem
  isso, `deleteMany()` não volta o contador e os testes que fixam ids do seed
  (produtor 1 = Antônio) passariam a apontar para outro registro.

## Produção

Copie `.env.example` para `.env` — ele documenta cada variável. O essencial:

| Variável | Para quê |
|---|---|
| `NODE_ENV=production` | Desliga o dataset de demonstração (ele criaria contas com senha pública) |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | Primeiro acesso, criado só se o banco estiver vazio |
| `CORS_ORIGINS` | Origens liberadas. Sem ela, nenhuma origem externa passa (o app mobile não depende disso) |
| `TRUST_PROXY` | **Obrigatório atrás de nginx/Cloudflare/PaaS.** Sem isto o limite por IP conta o IP do proxy e todos os usuários somados disputam as mesmas 10 tentativas de login por minuto |
| `PASSWORD_COST` | Custo do scrypt (padrão 16). Nunca abaixe em produção |
| `SWAGGER=on` | Abre a documentação, que em produção fica fechada por padrão |

Já vem resolvido: cabeçalhos de segurança (helmet), limite de corpo (256kb),
CORS fechado por padrão em produção, limite de requisições por IP, log de uma
linha por requisição e filtro global de erro que não vaza detalhe interno.

### Banco de dados

**PostgreSQL.** A troca aconteceu ANTES da primeira carga real, de propósito:
sem dado de produção, o custo foi reescrever as migrations; com dado, seria
janela de parada e script de transferência. O que o SQLite não dava não era
desempenho — era operação: ele roda dentro do processo, então duas instâncias
da API sobre o mesmo arquivo não se coordenam, e sem isso não há deploy sem
downtime, réplica de leitura nem backup online.

Local, com o cluster da própria máquina:

```bash
createdb barter_dev && createdb barter_test
cp .env.example .env          # ajuste DATABASE_URL com seu usuário
npx prisma migrate deploy && npm run db:seed
```

Em produção, aponte `DATABASE_URL` para o banco gerenciado **com TLS**
(`?sslmode=require`). O pool é o do `pg` (10 conexões por instância); atrás de
um PaaS que multiplique instâncias, some as conexões antes de escolher o plano
do banco.

Referência de carga real: publicar a lista de preços do fornecedor — 656 itens,
com criação de produto, classe e ponto de histórico para cada um — leva **~400
ms**, e os 656 entram com unidade lida do próprio arquivo.
