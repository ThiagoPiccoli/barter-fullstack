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

# Listar produtores (admin vê todos; consultor vê só os que atende)
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
| **Admin** | `admin@agrobarter.com.br` | — (enxerga tudo; administra, não decide) |
| Gerente | `gerente@agrobarter.com.br` | — (o time dele; dá o parecer técnico) |
| Comitê | `comite@agrobarter.com.br` | — (o ÓRGÃO, um acesso só; **decide** as permutas) |
| Faturista | `faturista@agrobarter.com.br` | — (só o que chegou ao faturamento; **fatura** as aprovadas) |
| Consultor | `joao.silva@agrobarter.com.br` | Antônio Carvalho, Sebastião Ramos |
| Consultor | `ana.ferreira@agrobarter.com.br` | Helena Prado, Cláudia Nunes |
| Consultor | `roberto.souza@agrobarter.com.br` | Joaquim Tavares |
| Consultor | `maria.oliveira@agrobarter.com.br` | Osmar Dutra |
| Consultor | `lucas.barros@agrobarter.com.br` | Vanessa Lopes |

Além disso, o dataset traz **9 produtos** (4 grãos + 5 insumos, cada um com 7
meses de histórico de preço), **3 categorias** de insumo com regras de mínimo, e
**8 permutas** espalhadas pela linha inteira — duas na mesa do gerente, uma no
comitê, três aprovadas esperando faturamento, uma negada e uma já faturada.
Nenhuma tela do fluxo abre vazia, e cada permuta vem com a linha do tempo dela.

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
  referência e pastas de insumos. Enxerga tudo e **não decide permuta**: quem
  administra o acesso não pode ser também quem decide o negócio, porque aí é a
  mesma pessoa concedendo o poder e usando-o.
- **manager (gerente)** — dá o **parecer técnico** das permutas do time dele
  (só as endereçadas a ele, ver [a linha de produção](#a-linha-de-produção-da-permuta)).
- **committee (comitê)** — **decide**: aprova ou nega, lendo o pedido do
  consultor e o parecer do gerente. É a única instância que decide, e é um
  ÓRGÃO: uma reunião, com um cadastro só (ver "O comitê é um cadastro só").
- **biller (faturista)** — **fatura** o que foi aprovado. É o último posto da
  linha, e o mais simples: ele não avalia e não devolve. Enxerga só o trecho
  dele — aprovadas e faturadas (`barters.readInvoicing`); o que ainda está no
  gerente ou no comitê não aparece para ele.
- Cada um dos três escreve UMA coisa, e nenhum escreve a do outro — a matriz
  inteira é varrida em [`test/rbac.e2e-spec.ts`](test/rbac.e2e-spec.ts).
- **consultant (consultor)** — loga no app e registra permutas **apenas para os
  produtores que atende**. A carteira é compartilhável: consultores dividem
  região, e o mesmo produtor pode ser atendido por vários — mas nenhum deles vê
  os produtores que não atende. Quem monta a lista é o admin.
- **produtor** — não loga: é um cadastro designado pelo consultor nas permutas.

Quem impõe isso é o `AccessGuard` global, e ele **nega por padrão**: toda rota
declara a sua política (`@RequireCapability`, `@AnyRole` ou `@Public`), e rota
sem política é recusada. Quem tem cada capacidade está numa tabela só,
[`src/common/policy.ts`](src/common/policy.ts) — os services consultam a mesma
tabela para decidir o escopo por linha (carteira própria × operação inteira).

Atos sensíveis deixam rastro em `GET /audit-logs`: provisionar, editar, resetar
senha, excluir usuário, decidir e faturar permuta. Cada permuta ainda tem a
PRÓPRIA linha do tempo (ver abaixo) — são trilhas diferentes de propósito.

Não há signup público: **usuário é provisionado pelo admin**, cada papel pela
sua rota — `POST /consultants`, `/managers`, `/billers` e `/committee`. O papel
vem da ROTA, nunca do corpo, e cada rota só enxerga e altera o próprio papel
(papel alheio responde 404).

### O comitê é um cadastro só

As três primeiras rotas cadastram PESSOAS e são plurais. A do comitê é
**singular**, e a diferença é de domínio: o comitê é uma **reunião**. Quem decide
a permuta não é o fulano do comitê — é o comitê reunido.

```bash
GET  /committee                  # o cadastro, ou null enquanto não existe
POST /committee                  # cria; 422 no segundo ("é único e já existe")
PUT  /committee                  # corrige nome, e-mail de acesso, unidade
POST /committee/reset-password   # nova senha; derruba as sessões abertas
```

Não há `:id` em lugar nenhum (não há qual comitê escolher) e **não há DELETE**: a
conta é a ETAPA, e sem ela nenhuma permuta é decidida. Para tirar o acesso de
quem está com ela, redefine-se a senha — é o mesmo ato que se usa quando a
composição da reunião muda.

A unicidade é do PAPEL, não do e-mail (`isSingleAccount` em
[`src/common/roles.ts`](src/common/roles.ts)): um segundo comitê com outro
endereço passaria pela conferência de e-mail sem esbarrar em nada, e a operação
passaria a ter dois órgãos decidindo a mesma fila sem saber um do outro.

O que se perde com o login compartilhado, e vale dizer: a trilha registra
"Comitê", não quem estava na sala. É por isso que a observação da decisão é o
lugar da **ata** — e a tela do comitê pede o texto com esse nome.

`admin` não tem rota: o primeiro vem do `bootstrap-admin` (banco vazio +
variáveis de ambiente) e a senha se recupera por `npm run password:reset`. Não
há ninguém acima do admin para autorizar a criação de outro.

### O que vale como senha

A regra mora em um arquivo só — [`src/auth/password-policy.ts`](src/auth/password-policy.ts) —
e vale para os três caminhos que definem senha: o cadastro de usuário, a troca
da própria senha e o script de emergência do servidor.

| Regra | Por quê |
|---|---|
| No mínimo **10 caracteres** | Comprimento é o que protege; abaixo disso não há o que discutir |
| No mínimo **5 caracteres diferentes** | `ababababab` tem dez caracteres e a força de dois |
| Fora da **lista de senhas conhecidas** | Senha vazada não é fraca por ser curta, é fraca por ser conhecida |
| Sem **corrida de teclado** (`qwertyuiop`, `9876543210`) | O que a mão faz sozinha, o atacante tenta primeiro |
| Sem o **nome do sistema** nem o **seu próprio nome/e-mail** | É o primeiro chute contra uma conta específica |
| **Nenhuma exigência** de maiúscula, número ou símbolo | Regra de composição não gera senha forte, gera `Senha@123` |

O desenho segue o [NIST SP 800-63B](https://pages.nist.gov/800-63-3/sp800-63b.html)
(§5.1.1.2). O passo seguinte — conferir contra a base do *Have I Been Pwned* —
está anotado no próprio arquivo: ele exige dar acesso de saída à internet para
a API, que é decisão de operação.

### Senha de primeira entrada

Ao criar um usuário de qualquer papel, o servidor **sorteia uma senha só dele** e a devolve
**uma única vez**, no corpo da resposta (`provisionalPassword`, algo como
`K7NP-4TQX-M9BD`). O admin dita esse valor para o consultor; depois disso ele não
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

A senha definida por aí também é provisória: exige troca no primeiro login, e
passa pela mesma política das outras.

### Quanto tempo uma sessão dura

Duas mortes, respondendo perguntas diferentes:

- **Prazo absoluto** (`TOKEN_TTL_DAYS`, padrão 30): esta sessão já é velha demais.
- **Inatividade** (`TOKEN_IDLE_DAYS`, padrão 7): este aparelho ainda está com
  quem deveria? É a que resolve o celular perdido — sem ela, um aparelho
  esquecido no sábado seguiria valendo por até um mês.

Quem usa o app na rotina nunca esbarra na segunda: cada requisição regrava o
"visto por último" (no máximo uma vez por hora, para não pôr um `UPDATE` no
caminho crítico de toda chamada). O que expira é apagado na primeira tentativa
de uso e, para as sessões que ninguém tenta usar de novo — aparelho trocado, app
desinstalado —, uma varredura a cada seis horas limpa a sobra
([`session-cleanup.service.ts`](src/auth/session-cleanup.service.ts)).

### Quando a conta descansa

Dez senhas erradas seguidas e a conta recusa tentativas por 15 minutos — **até a
senha certa**. Acertar antes disso zera o contador.

Isto existe porque o limite por IP protege o *servidor*, não a *conta*: dez
tentativas por minuto por IP viram muitas por minuto quando saem de muitos IPs,
e a conta do admin é alvo conhecido de qualquer um que veja a tela de login.

A troca que este desenho aceita, dita por inteiro: **quem souber um e-mail
consegue manter aquela conta trancada** errando a senha de propósito. É por isso
que a trava dura quinze minutos e não "até o admin liberar" — o incômodo passa
sozinho e a adivinhação não sobrevive a ele. Uma trava permanente trocaria o
roubo de conta por uma negação de serviço confiável.

**Definir uma senha nova destranca a conta na hora** — pelo reset do admin, pelo
`npm run password:reset` ou pela troca da própria senha. Os três provam a
identidade do titular, e sem isso o reset entregaria uma credencial que não
entra: a trava é conferida *antes* da senha, então a provisória recém-ditada ao
telefone seria recusada por até quinze minutos sem que nada explicasse por quê.
O contador de tentativas zera junto, senão o primeiro engano ao digitar a senha
nova trancaria tudo outra vez. A regra mora em
[`src/auth/lockout.ts`](src/auth/lockout.ts), num arquivo só, porque a trava é
escrita em um lugar e apagada em quatro.

Entrar, falhar e ser bloqueado deixam rastro em `GET /audit-logs?targetType=session`.

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
| GET/POST/PUT | `/committee` | admin | O comitê — **um cadastro só** (ver abaixo) |
| POST | `/committee/reset-password` | admin | Nova senha da conta do comitê |
| GET/POST/PUT/DELETE | `/billers[/:id]` | admin | Faturistas |
| POST | `/<papel>/:id/reset-password` | admin | Nova senha provisória; encerra as sessões dele |
| GET | `/audit-logs` | admin | Trilha de auditoria (`?action=`, `?targetType=`); só leitura |
| GET | `/barters` | autenticado | Escopado por papel (`?status=`) |
| GET | `/barters/:code` | autenticado | Detalhe pelo código público (PRM-AAAA-NNN) |
| POST | `/barters` | consultor | Registra permuta (ver regras abaixo) |
| POST | `/barters/:code/opinion` | gerente | Parecer técnico (move para o comitê) |
| POST | `/barters/:code/review` | comitê | Aprova/nega, com observação |
| POST | `/barters/:code/invoice` | faturista | Fatura a aprovada — fim da linha |

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

## A linha de produção da permuta

Uma permuta atravessa **três postos** antes de virar nota, e cada posto tem um
dono e uma pergunta:

```
                    ┌──────────┐
(registro)          │ invoiced │  fim da linha
    │               └──────────┘
    ▼                     ▲
sentToManager ──▶ pending ──▶ approved ──▶ (fatura)
 (gerente)       (comitê)    (faturista)
                    │
                    └──▶ denied   (fim da linha)
```

| Posto | Quem | O que faz | Rota |
|---|---|---|---|
| 1 | **gerente** do consultor | Escreve o **parecer técnico**. Não decide. | `POST /barters/:code/opinion` |
| 2 | **comitê** | **Decide**: lê o pedido e o parecer, aprova ou nega. | `POST /barters/:code/review` |
| 3 | **faturista** | **Fatura** o que foi aprovado. Não avalia, não devolve. | `POST /barters/:code/invoice` |

O caminho inteiro mora em um arquivo só,
[`src/barters/barter-workflow.ts`](src/barters/barter-workflow.ts): os estados,
quem move o quê, e **o que responder a quem chega fora de hora**. Essa última
parte é metade do valor — as três recusas dizem coisas diferentes de propósito:

```bash
# comitê tentando decidir o que ainda está no gerente
422 "Esta permuta aguarda o parecer do gerente Beatriz Nogueira"
# comitê tentando decidir o que já decidiu
422 "Esta permuta já foi decidida pelo comitê"
# comitê tentando decidir uma negada
422 "Esta permuta foi negada pelo comitê"
```

Dizer "já foi decidida" a quem espera o gerente mandaria a pessoa procurar uma
decisão que ninguém tomou; o que ela precisa saber é **com quem a permuta está
parada**. O JSON da permuta carrega isso pronto (`waitingFor`, `nextAction`,
`statusLabel`), para o app não manter uma segunda cópia do fluxo em Dart.

Repare no ator dos três exemplos: o **comitê**, que enxerga a linha inteira. A
mensagem da etapa é para quem PODE LER a permuta — toda ação confere o escopo
antes (`requireBarter`: existe? você enxerga? está no ponto?). O faturista
pedindo a nota de algo que ainda está no gerente recebe `403 "Você não tem acesso
a esta permuta"`, e não o andamento dela: sem essa ordem, a recusa vira a porta
dos fundos do recorte de leitura.

**O admin não decide.** Ele administra o sistema — contas, catálogo, valores,
unidades — e enxerga tudo; a capacidade `barters.review` saiu dele e foi para o
comitê. Quem administra o acesso não pode ser também quem decide o negócio: é a
mesma pessoa concedendo o poder e usando-o. Um teste segura isso
([`src/common/policy.spec.ts`](src/common/policy.spec.ts)).

### O histórico de cada permuta

Toda passagem de um estado para o outro vira uma linha em `BarterEvent`, gravada
**na mesma transação** da mudança: sem o evento não há mudança de estado. O
detalhe (`GET /barters/:code`) devolve a linha do tempo pronta:

```json
"events": [
  { "action": "register", "fromStatus": null,            "toStatus": "sentToManager", "actorName": "João Silva",       "actorRoleLabel": "Consultor" },
  { "action": "opinion",  "fromStatus": "sentToManager", "toStatus": "pending",       "actorName": "Beatriz Nogueira", "actorRoleLabel": "Gerente", "note": "Estoque conferido…" },
  { "action": "review",   "fromStatus": "pending",       "toStatus": "approved",      "actorName": "Comitê de Permutas", "actorRoleLabel": "Comitê" },
  { "action": "invoice",  "fromStatus": "approved",      "toStatus": "invoiced",      "actorName": "Patrícia Lemos",   "actorRoleLabel": "Faturista" }
]
```

São **duas trilhas**, e a diferença é deliberada:

- `AuditLog` (`GET /audit-logs`) responde *"quem mexeu no sistema"*: é global,
  só o admin lê, e a gravação é best-effort — perder uma linha não pode derrubar
  o ato;
- `BarterEvent` responde *"por onde esta permuta passou"*: é parte do documento,
  quem enxerga a permuta enxerga a história dela, e ele é transacional.

É essa segunda que o faturista recebe pronta das etapas anteriores — e é ela que
mantém o parecer do gerente visível depois que a decisão o sucede, porque os
campos da permuta são sobrescritos e os eventos não. A listagem **não** carrega
histórico: lista mostra estado, não trajetória.

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

1. confere que o produtor está na carteira do consultor autenticado (basta que
   ele o atenda — o produtor pode ser atendido também por outros);
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
├── common/        # AccessGuard + a tabela de capacidades (policy.ts),
│                  # @CurrentUser(), EnvelopeInterceptor, ValidationPipe
├── prisma/        # PrismaService (driver adapter pg) como provider global
├── barters/       # a permuta: barter-math.ts (a conta), tax-regime.ts (o
│                  # imposto) e barter-workflow.ts (a LINHA DE PRODUÇÃO —
│                  # estados, transições e as recusas de cada etapa)
├── producers/      services/products/categories/  # um módulo por recurso:
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

  O `.env.test` é versionado e traz o padrão `postgres:postgres`. Se o seu
  cluster local atende por outro usuário, crie `api/.env.test.local` (não
  versionado) com a sua `DATABASE_URL` — ela vence a do arquivo padrão, e a
  variável de ambiente vence as duas, que é como o CI aponta para o Postgres
  dele.

## Produção

Copie `.env.example` para `.env` — ele documenta cada variável. O essencial:

| Variável | Para quê |
|---|---|
| `NODE_ENV=production` | Desliga o dataset de demonstração (ele criaria contas com senha pública) |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | Primeiro acesso, criado só se o banco estiver vazio |
| `CORS_ORIGINS` | Origens liberadas. Sem ela, nenhuma origem externa passa (o app mobile não depende disso) |
| `TRUST_PROXY` | **Obrigatório atrás de nginx/Cloudflare/PaaS.** Sem isto o limite por IP conta o IP do proxy e todos os usuários somados disputam as mesmas 10 tentativas de login por minuto. O servidor avisa na subida se ela faltar em produção |
| `PASSWORD_COST` | Custo do scrypt (padrão 16). Nunca abaixe em produção |
| `TOKEN_TTL_DAYS` / `TOKEN_IDLE_DAYS` | Prazo absoluto (30) e inatividade (7) da sessão |
| `SWAGGER=on` | Abre a documentação, que em produção fica fechada por padrão |

Já vem resolvido: cabeçalhos de segurança (helmet), limite de corpo (256kb),
CORS fechado por padrão em produção, limite de requisições por IP, bloqueio
temporário da conta que erra a senha, sessão que morre por prazo e por
inatividade, log de uma linha por requisição, trilha de auditoria dos atos
sensíveis (inclusive entradas e tentativas) e filtro global de erro que não
vaza detalhe interno.

**O que ainda falta para publicar** — assinatura do APK, credencial de
distribuição e o resto da esteira de release — está em
[`docs/RELEASE.md`](../docs/RELEASE.md).

### Sonda de saúde

`GET /health` (fora do `/api/v1`, pública) toca o banco com um `SELECT 1` e
responde `{"status":"ok","database":"ok"}` — ou **503** se o Postgres não
responder. Aponte o balanceador e o orquestrador para ela, e não para `/`: a
raiz devolve 200 com o processo de pé e o banco inalcançável, que é o pior
estado possível para uma verificação de saúde.

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
