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

Cinco regras derivam disso e aparecem nos dois lados do código:

| Regra | Onde nasce | Onde é imposta de verdade |
|---|---|---|
| Só se permuta com Barter aberto | lançamento da versão | servidor ([seasons.service.ts](../api/src/seasons/seasons.service.ts), `requireOpenVersion`) |
| Preço do insumo e da saca vêm da VERSÃO | planilha publicada | servidor ([barters.service.ts](../api/src/barters/barters.service.ts) passos 1 e 5) |
| Insumo com `requiredPerHa` é obrigatório: `taxa × área` | cadastro do produto | servidor ([barters.service.ts](../api/src/barters/barters.service.ts) passo 3) |
| CLASSE com regra de mínimo trava o envio | regra da classe | servidor ([barters.service.ts](../api/src/barters/barters.service.ts) passo 4) |
| Sacas = custo ÷ valor da saca da versão | — | servidor ([barter-math.ts](../api/src/barters/barter-math.ts)) |

**Classe é lista fixa.** Fungicidas, inseticidas, herbicidas, sementes,
fertilizantes, biológicos, nutrição, seguro agrícola e óleos e adjuvantes — as
nove nascem na migration `20260814140000_classes_fixas_de_produto` e não há
rota que crie, renomeie ou exclua. Elas eram "pastas" que o admin cadastrava à
vontade, e o preço disso aparecia na carga em massa: cada planilha inventava
uma variação ("Defensivo", "DEFENSIVOS", "Defensivos Foliares") e o mínimo por
classe passava a medir um conjunto diferente a cada versão do Barter — a regra
continuava lá, medindo outra coisa. O que **é** editável é a REGRA de mínimo de
cada classe (`PUT /classes/:id/rule`): ela é decisão comercial e muda de safra
para safra. Classe nova entra por migration, junto com a decisão do que fazer
com os produtos já classificados.

**Data trava, meta avisa.** A `endsAt` da versão é uma decisão com hora marcada:
passada a data, a API recusa permuta nova. As metas (vendas, lucro, sacas,
quantidade) só medem — quem encerra é o admin, com um toque. As duas regras
moram juntas em [version-progress.ts](../api/src/seasons/version-progress.ts)
(`isOpenAt`), que é o lugar de inverter isso se um dia a meta precisar travar.

E as regras de acesso — **cinco papéis**, definidos em um só lugar
([roles.ts](../api/src/common/roles.ts)):

| Papel | `role` | Enxerga | Faz hoje |
|---|---|---|---|
| Administrador | `admin` | tudo | cadastros, catálogo/preços, revisão das permutas |
| Gerente | `manager` | tudo | leitura (fluxo próprio em construção) |
| Comitê | `committee` | tudo | leitura (fluxo próprio em construção) |
| Faturista | `biller` | tudo | leitura (fluxo próprio em construção) |
| Consultor | `consultant` | só a **própria carteira** | registra permuta para os produtores dela |

- Gerente, comitê e faturista **ainda não escrevem nada**. O acesso existe e é
  testado ([rbac.e2e-spec.ts](../api/test/rbac.e2e-spec.ts)); as ações de cada
  um entram junto com o contrato entre eles.

Quem responde "o que cada papel pode" é **uma tabela só**,
[policy.ts](../api/src/common/policy.ts):

| Capacidade | Quem tem |
|---|---|
| `users.manage` · `producers.manage` · `catalog.manage` · `barter.manage` · `barters.review` · `audit.read` | admin |
| `producers.readAll` · `barters.readAll` | admin, gerente, comitê, faturista |
| `barters.register` | consultor |

`barter.manage` (lançar safra e versões) é separada de `catalog.manage`
(cadastro do produto e regra das classes) de propósito: uma decide **por
quanto** se troca, a outra só mexe em nome, unidade e classe.

A rota declara a CAPACIDADE de que precisa (`@RequireCapability`), não quem
entra; os services perguntam à mesma tabela (`can(user, ...)`) para decidir o
escopo por linha. Antes disso a autorização morava em dois lugares que não se
falavam — o decorator e um `seesEverything()` dentro dos services —, e não
havia arquivo nenhum onde se lesse o que um faturista pode.
- **Produtor não é usuário** — ele não loga, é um cadastro.

---

# PARTE 1 — Backend (`api/`)

**Stack:** NestJS 11 · Prisma 7 (adapter `better-sqlite3`) · SQLite · TypeScript.
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

Os módulos existentes: `auth`, `producers`, `users`, `classes`, `products`,
`seasons`, `barters`, `audit`. Mais `prisma` (o client como provider global) e
`common` (peças compartilhadas).

`seasons` é o lançamento do Barter: **dois controllers, um service** —
`/seasons` (a safra) e `/barter-versions` (a versão vigente e o histórico) —,
mais duas peças puras: [version-import.ts](../api/src/seasons/version-import.ts)
(a planilha) e [version-progress.ts](../api/src/seasons/version-progress.ts)
(vigência e metas). É o único módulo que `barters` importa: a permuta pergunta
a ele por quanto se troca hoje.

`users` também foge do formato: **quatro controllers, um service**. Cada
papel provisionável tem a sua rota (`/consultants`, `/managers`,
`/committee-members`, `/billers`) para poder ser guardado e evoluir sozinho,
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
login  → gera 32 bytes aleatórios (base64url)
       → grava no banco APENAS o SHA-256 + expiresAt (TOKEN_TTL_DAYS, padrão 30)
       → devolve o valor cru ao app

request→ AuthGuard faz SHA-256 do Bearer e procura a linha
       → não achou → 401 · venceu → apaga a linha e 401
       → achou → req.user = usuário

logout → apaga a linha (revogação REAL, não é só o cliente esquecer)
```

Consequências que aparecem no app: excluir um consultor derruba as sessões dele
em cascata; trocar a senha derruba as outras sessões e mantém a atual.

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
`user.password-reset`, `user.deleted` e `barter.reviewed`. Lida em
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

1. **só o consultor registra permuta** (é ato do dono da carteira; admin e
   retaguarda levam 403) → a regra é uma *lista de permitidos*, para papel novo
   não entrar por omissão
2. **precisa haver Barter aberto** (`requireOpenVersion`) → é ele que traz o
   grão da safra e a tabela de valores; sem ele, 422 com "aguarde o próximo
   lançamento"
3. **produtor precisa ser da carteira de quem registra** → 403
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

A matemática pura está separada em
[barter-math.ts](../api/src/barters/barter-math.ts) — sem I/O, testada em
[barter-math.spec.ts](../api/src/barters/barter-math.spec.ts).

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
é escrita para planilha de gente: cabeçalho em qualquer ordem, com ou sem
acento, número com vírgula e "R$", linha em branco e rodapé no fim. Ela é
dividida em duas partes de propósito — `readWorkbook` (a única que conhece
`exceljs`) e `parseSheet` (a regra, testável sem arquivo). **Erro em qualquer
linha recusa o arquivo inteiro**, com o número da linha na mensagem: meia-tabela
publicada some com insumos sem ninguém perceber.

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

## 1.6 Modelo de dados

[schema.prisma](../api/prisma/schema.prisma). Dois padrões merecem atenção:

**Enums são `String`** (SQLite não tem enum): `role`, `type`, `kind`, `status`,
`ruleType`. A validação de valores fica nos DTOs (`@IsIn`).

**Permuta é registro histórico.** `BarterItem` guarda `productName`, `unit`,
`unitValue` e `unitCost` como *snapshot*; `Barter` guarda `consultantName`,
`producerName`, `reviewedBy` e `versionCode`. Os FKs usam `onDelete: SetNull`.
Resultado: excluir um produto, um produtor ou um consultor **não** reescreve nem
apaga o histórico — e publicar uma versão nova não altera permutas antigas.

O `unitCost` está lá por causa da meta de lucro: sem o custo congelado no item,
corrigir um custo hoje reescreveria a margem apurada ontem.

```
User ─┬─< AccessToken        (sessões revogáveis)
      ├─< Producer           (carteira; SetNull se o consultor sai)
      └─< Barter             (SetNull)
Producer ─< Barter
Season ─< BarterVersion ─┬─< VersionPrice >─ Product   (a tabela de valores)
                         └─< Barter                     (SetNull; versionCode fica)
ProductClass ─< Product ─┬─< PriceHistoryEntry
                          └─< BarterItem >─ Barter
```

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

## 1.7 Ambiente, seed e primeiro acesso

[main.ts](../api/src/main.ts) bifurca por `NODE_ENV`:

- **dev** → [seed-if-empty.ts](../api/prisma/seed-if-empty.ts): banco vazio
  recebe o dataset de demonstração (senha `123456`). Banco com dados não é tocado.
- **produção** → [bootstrap-admin.ts](../api/prisma/bootstrap-admin.ts): nada de
  dataset público; o primeiro admin vem de `ADMIN_EMAIL`/`ADMIN_PASSWORD` e
  nasce com senha provisória.

O dataset em si está em [seed-data.ts](../api/prisma/seed-data.ts); `npm run
db:seed` ([seed.ts](../api/prisma/seed.ts)) apaga e recria tudo.

O dataset conta a história do modelo novo: duas safras **encerradas** (`T2025`
de trigo e `M2026` de milho — é delas que vêm as permutas antigas pagas nesses
grãos) e a safra de soja `S2026` **aberta**, com `S2026.01` encerrada logo após
a publicação (o caso de quem republica antes de alguém usar) e `S2026.02`
vigente, com as quatro metas definidas. Em produção nada disso existe: o admin
abre a safra e publica a primeira versão pela planilha.

Variáveis: [.env.example](../api/.env.example) documenta todas
(`TOKEN_TTL_DAYS`, `CORS_ORIGINS`, `TRUST_PROXY`, `LOGIN_RATE_LIMIT`,
`PASSWORD_COST`, `SWAGGER`).

Perdida a senha do admin, o caminho é
[scripts/reset-password.ts](../api/scripts/reset-password.ts)
(`npm run password:reset`): o `bootstrap-admin` só roda com o banco vazio, e
não há ninguém acima do admin para redefini-la pela aplicação.

## 1.8 Rotas (todas sob `/api/v1`, exceto `/`)

| Método | Rota | Quem pode | Observação |
|---|---|---|---|
| GET | `/` | público | sinal de vida, sem envelope |
| POST | `/auth/login` | público | throttle apertado |
| POST | `/auth/logout` | autenticado* | revoga o token |
| GET | `/me` | autenticado* | é aqui que o app vê `mustChangePassword` |
| POST | `/auth/password` | autenticado* | exige a senha atual |
| GET | `/producers` `?consultantId=` | escopado | consultor: só a carteira; retaguarda: todas |
| GET | `/producers/:id` | escopado | |
| POST/PUT/DELETE | `/producers` | admin | |
| GET/POST/PUT/DELETE | `/consultants` | admin | consultores |
| GET/POST/PUT/DELETE | `/managers` | admin | gerentes |
| GET/POST/PUT/DELETE | `/committee-members` | admin | integrantes do comitê |
| GET/POST/PUT/DELETE | `/billers` | admin | faturistas |
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
| POST | `/barter-versions/:code/close` | admin | encerra o Barter, mantém a safra |
| GET/POST | `/seasons` | admin | safras com o histórico de versões |
| POST | `/seasons/:code/close` | admin | encerra safra + versão vigente |
| POST | `/seasons/:code/versions` | admin | publica versão com a tabela no corpo (seed/testes) |
| POST | `/seasons/:code/versions/import` | admin | publica versão pela planilha .xlsx (multipart, 5 MB) |
| GET | `/barters` `?status=` | escopado | |
| GET | `/barters/:code` | escopado | `code` = PRM-2026-001 |
| POST | `/barters` | consultor | sem `grainId`; 422 se não há Barter aberto |
| POST | `/barters/:code/review` | admin | só permuta pendente |

As quatro rotas de usuário seguem o mesmo desenho e **só alcançam o próprio
papel**: papel diferente responde 404, e o admin não é gerenciado por nenhuma
delas (ver `ManagedRole` em [roles.ts](../api/src/common/roles.ts)) — ele nasce
do `bootstrap-admin` e se recupera por script.

"Escopado" = consultor vê a própria carteira, retaguarda (admin, gerente,
comitê, faturista) vê tudo. "admin" nas linhas de escrita é o estado de hoje:
é onde os papéis novos vão ganhar as próprias ações.

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
  throttling, setup do app e o filtro de exceção.
- `npm run test:e2e` → [test/](../api/test/), banco próprio (`prisma/test.db`
  via `.env.test`), sobe a app com o mesmo `setupApp`. Cobre auth, escopo por
  papel, as regras de permuta, o lançamento do Barter
  ([seasons.e2e-spec.ts](../api/test/seasons.e2e-spec.ts): publicar, uma vigente
  só, permuta antiga intacta, planilha com erro, encerramento), o contrato de
  erro e — em [auth.e2e-spec.ts](../api/test/auth.e2e-spec.ts) — o cenário
  completo de sequestro e retomada de conta.
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
        ├─ erro de rede   → tela de "tentar novamente" (NÃO descarta o token)
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

## 2.4 `AppData` — o cache

[app_data.dart](../app/lib/data/app_data.dart). Classe estática com listas
públicas (`currentUser`, `consultants`, `producers`, `grains`, `inputs`,
`categories`, `barters`).

- **Hidratação**: no login (ou na retomada) `refreshAll()` dispara catálogo,
  produtores, permutas e — se admin — consultores, em paralelo. O dataset é
  pequeno (cooperativa), então carregar tudo de uma vez deixa o app instantâneo.
- **Com senha provisória não hidrata**: o servidor recusaria com 403, e o erro
  apareceria na cara de quem ainda vai definir a senha (`_hydrateIfCleared`).
- **Mutações**: sempre `API primeiro, cache depois` — `createBarter`,
  `reviewBarter`, `saveProducer`, `deleteConsultant`, `updatePrice`…
- Quando a mutação tem **efeito colateral no servidor**, o cache é recarregado
  em vez de remendado: excluir consultor → `refreshProducers()` (produtores
  ficaram sem dono); excluir categoria → `refreshCatalog()` (insumos foram
  desvinculados).

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
| Lançamento | [barter_program_screen.dart](../app/lib/screens/barter_program_screen.dart) — safra, versão vigente, metas, publicar nova versão pela planilha, encerrar |
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
| [back_office_main_screen.dart](../app/lib/screens/back_office_main_screen.dart) | casca de **gerente, comitê e faturista** — uma tela parametrizada pelo papel, em modo leitura, até cada um ganhar as próprias ações |
| [barter_screen.dart](../app/lib/screens/barter_screen.dart) | **o construtor de permuta** (a tela mais complexa) |
| [barters_screen.dart](../app/lib/screens/barters_screen.dart) | listagem com abas por status + busca |
| [barter_detail_screen.dart](../app/lib/screens/barter_detail_screen.dart) | detalhe (com a versão do Barter), revisão do admin, PDF |
| [prices_screen.dart](../app/lib/screens/prices_screen.dart) | ⚠️ é a aba **Barter** inteira (lançamento, valores, histórico, pastas) |
| [barter_program_screen.dart](../app/lib/screens/barter_program_screen.dart) | o lançamento: versão vigente, metas, publicação por planilha, encerramento |
| [product_report_screen.dart](../app/lib/screens/product_report_screen.dart) | relatório de um produto + diálogos de preço/categoria/exigência |
| [consultants_screen.dart](../app/lib/screens/consultants_screen.dart) | ⚠️ é a aba **Cadastros** (alterna Produtores ↔ Consultores) |
| [producer_profile_screen.dart](../app/lib/screens/producer_profile_screen.dart) | perfil do **produtor** visto pelo admin |
| [consultant_profile_screen.dart](../app/lib/screens/consultant_profile_screen.dart) | perfil do **consultor** visto pelo admin |
| [edit_forms.dart](../app/lib/screens/edit_forms.dart) | três formulários: produtor, consultor, categoria |
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
  `AppData.producersForConsultant(consultantId)` — a carteira.
- **Etapa 2 — insumos**. A lista é `AppData.barterInputs`: só o que a versão
  vigente precificou. Insumos com exigência já vêm pré-preenchidos no mínimo e
  não descem abaixo dele (`_setInput` trava). Barras de progresso das categorias
  mostram o quanto falta **em proporção**.
- **Não há etapa de grão.** Ele é o da safra; as sacas saem de
  `version.grainPrice`.
- **Envio**: `AppData.createBarter` manda só `producerId` e
  `[{productId, quantity}]`. O diálogo de sucesso mostra **a permuta devolvida
  pelo servidor**, não a prévia local. Se o Barter tiver fechado no meio do
  caminho, o erro do servidor aparece e a tela recarrega a vigência.

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

**O arredondamento é parte do contrato, não detalhe.** A tela usava
`toStringAsFixed(2)`, o caminho natural em Dart; o servidor usa
`Math.round(v * 100) / 100`. Eles arredondam por bases diferentes (decimal vs
binário) e discordam em 4,2% dos valores — sempre em meio centavo. Meio centavo
é exatamente o bastante para a tela mostrar a quantidade mínima de um insumo e
o servidor recusar o envio por ela estar abaixo do mínimo. Por isso o espelho
Dart reproduz a fórmula do servidor em vez de usar o idioma local.

## 2.8 Privacidade por papel

O **consultor nunca vê R$**. Para ele a permuta é "insumos retirados → sacas do
grão". A flag `showValue` / `showValues` atravessa telas e PDF:

- [barter_screen.dart](../app/lib/screens/barter_screen.dart) → sempre `false`
- [barter_detail_screen.dart](../app/lib/screens/barter_detail_screen.dart) → `widget.isAdmin`
- [barter_pdf.dart](../app/lib/services/barter_pdf.dart) → mesmo critério

Note que isso é **regra de apresentação, não de segurança**: os preços vêm no
JSON de `/products` para qualquer autenticado.

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
| uma CLASSE nova na lista | migration nova (a lista é fixa; decida o que fazer com os produtos já classificados) | nada |
| aceitar outra coluna na planilha | `COLUMNS` em `version-import.ts` (+ spec) | nada |
| uma meta nova (ex.: hectares) | `schema.prisma`, `Targets`/`goalsOf` em `version-progress.ts`, `VersionLimitsDto` | `GoalKind`, campo no `_PublishSheet` |
| fazer a meta ENCERRAR sozinha | `isOpenAt` em `version-progress.ts` | nada (o app lê `isOpen`) |
| mudar validade da sessão | `TOKEN_TTL_DAYS` no `.env` | nada |
| um endpoint novo | módulo (controller+service+dto) + serializer | repositório novo + campo no `AppData` |
| deixar o consultor ver R$ | nada (já vem no JSON) | trocar as flags `showValue` |
| trocar SQLite por Postgres | `datasource` no schema, trocar o adapter em `prisma.service.ts`, rodar migrations | nada |
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
- **Uma instância só.** `better-sqlite3` roda dentro do processo: duas
  instâncias da API sobre o mesmo arquivo não se coordenam. Adequado para uma
  cooperativa, e escolhido de propósito — mas é o teto de escala horizontal
  hoje. O caminho de saída é Postgres (ver "Produção" no `api/README.md`).
- **Paginação por offset.** Se registros forem criados entre uma página e a
  seguinte, a janela desloca. Autocorrige no refresh seguinte; para volume
  maior, o caminho é cursor.
- **A planilha é lida inteira na memória** (multer em memória + `exceljs`), com
  teto de 5 MB por upload. Suficiente para tabela de fornecedor; um arquivo de
  centenas de milhares de linhas pediria leitura em fluxo.
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
- **`Product.currentPrice` é derivado.** Ele guarda o último valor publicado
  para o relatório e o gráfico; quem precifica é a versão. A rota que o editava
  direto foi removida justamente para os dois não divergirem, mas o campo
  continua lá e ainda é escrito por dois caminhos (publicar versão e corrigir
  preço).
