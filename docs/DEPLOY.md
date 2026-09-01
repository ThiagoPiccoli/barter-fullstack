# Subir um ambiente de teste

O caminho para tirar o agroBarter da máquina de quem desenvolve e pôr na mão de
quem vai testar: **banco no Neon**, **API no Fly**, **APK pelo Firebase App
Distribution**.

Isto é um ambiente de **teste de uso** — gente real mexendo, dados descartáveis.
Não é publicação: o que falta para isso continua em [RELEASE.md](RELEASE.md), e
o item 1 de lá (o APK assinado com chave de debug) vale para este ambiente
também.

A ordem importa: o banco existe antes da API, e a API existe antes do APK —
porque o APK precisa saber, em tempo de build, o endereço para onde falar.

---

## 1. O banco (Neon)

1. Criar conta em [neon.tech](https://neon.tech) e um projeto Postgres.
2. Copiar a connection string do **pooler** — o host com `-pooler` no nome. É
   ela que vai no Fly, e não a direta: o pooler é quem multiplexa de verdade, e
   o pool da aplicação passa a ser um teto local sobre um teto que já existe (o
   porquê está no comentário de `prisma.service.ts`).

   A URL do Neon vem com `&channel_binding=require` no fim. Pode deixar: é
   parâmetro do `libpq`, e a API fala com o banco pelo driver `pg`, que o
   ignora.

   Escolha a região do banco **junto** com a do Fly. O app faz uma requisição à
   API e a API faz várias consultas ao banco: separados entre continentes, cada
   uma dessas consultas paga a travessia. O `fly.toml` está em `gru`, então o
   Neon vai em `sa-east-1`.
3. Aplicar as migrations, da sua máquina:

   ```bash
   cd api
   DATABASE_URL="postgresql://...-pooler.../neondb?sslmode=require" \
     npx prisma migrate deploy
   ```

`sslmode=require` não é enfeite: sem ele o Postgres gerenciado recusa a conexão.

---

## 2. A API (Fly)

O projeto já traz o que o Fly precisa: [`api/Dockerfile`](../api/Dockerfile) e
[`api/fly.toml`](../api/fly.toml). Aqui a API roda como sempre rodou — um
processo que sobe, escuta uma porta e fica de pé —, então não há adaptação
nenhuma: é o `main.ts` inteiro, com a limpeza periódica de sessões e tudo.

```bash
cd api
fly auth login                     # abre o navegador
fly apps create agrobarter-api     # o nome precisa estar livre no Fly inteiro
fly secrets set DATABASE_URL="postgresql://...-pooler.../neondb?sslmode=require"
fly deploy --ha=false

# O primeiro deploy pode falhar em alocar os IPs públicos. Ver abaixo.
fly ips list
```

O `fly apps create` vem antes do `fly secrets set` porque o segredo é gravado
NO app: sem ele criado, o `secrets set` responde `Could not find App`.

`--ha=false` porque o padrão cria **duas** máquinas, para deploy sem downtime.
Num ambiente de teste isso é o dobro do custo sem ganho — e o
`min_machines_running = 0` do `fly.toml` não desliga esse comportamento, que é
do comando. Esquecendo o flag, `fly scale count 1` conserta depois.

O `fly secrets set` vem **antes** do deploy porque o `release_command` do
`fly.toml` roda `prisma migrate deploy` num contêiner à parte, antes de a versão
nova receber tráfego — e ele precisa da variável para existir. Falhando ali, o
deploy para e a versão antiga continua no ar, que é o desejado: banco a meio
caminho com código novo em cima é o jeito mais rápido de transformar um deploy
ruim em incidente.

O que **não** entra em secret está no `[env]` do `fly.toml`, versionado:
`NODE_ENV=production` (fecha o CORS e impede o dataset de demonstração de rodar)
e `TRUST_PROXY=1` (o Fly põe um proxy na frente de toda máquina; sem isto o
limite por IP conta o mundo inteiro como um cliente só, e o primeiro que errar a
senha tira os outros do ar).

Não defina `PASSWORD_COST`: o padrão (16) é o valor seguro, e qualquer número
menor enfraquece todas as senhas novas. `CORS_ORIGINS` só é necessária se um dia
houver front web — o app mobile não manda `Origin`, então funciona com a
política fechada.

Depois do deploy, a sonda responde sem autenticação:

```bash
curl https://agrobarter-api.fly.dev/health
# {"status":"ok","database":"ok"}
```

`database: "ok"` é o que prova que a máquina alcançou o Neon — é a mesma sonda
que o `fly.toml` usa para decidir se uma máquina pode receber tráfego. Se vier
erro aí, o problema é a `DATABASE_URL`, e não vale seguir para o passo 3;
`fly logs` mostra a subida inteira.

### Se o app não responder de fora

O primeiro deploy deste app falhou em alocar os IPs públicos, com
`error allocating ipv6 after detecting first deploy and presence of services`.
O resto correu bem — migrations aplicadas, máquinas de pé, health check passando
por dentro —, e o único sintoma era não existir endereço pelo qual chegar. O
deploy **não** falha por causa disso: a mensagem passa no meio do log e o
comando termina dizendo "Visit your newly deployed app".

`fly ips list` vazio é o diagnóstico. A saída:

```bash
fly ips allocate-v6
fly ips allocate-v4 --shared
```

### A máquina dorme

`auto_stop_machines` desliga a máquina quando ninguém usa e a religa na primeira
requisição. Para um ambiente de teste é o arranjo certo — custo perto de zero
enquanto ninguém está testando —, e o preço é a primeira chamada depois de uma
pausa demorar alguns segundos. Ela soma com o banco do Neon acordando, que faz o
mesmo. Não é defeito, e some da segunda em diante.

---

## 3. Os usuários e o catálogo

Com as migrations aplicadas, o banco está vazio. Este comando o deixa pronto
para uso — pessoas e catálogo, sem nenhum movimento:

```bash
cd api
DATABASE_URL="postgresql://...-pooler.../neondb?sslmode=require" \
  npm run provision -- --yes --out=~/credenciais.json
```

Ele imprime o host alvo antes de tocar em qualquer coisa e exige `--yes`, porque
apaga o banco inteiro. Ficam usuários dos cinco papéis, unidades, classes,
produtos e a safra vigente com a tabela de preços. Saem produtores, permutas,
histórico de preço e auditoria.

**As senhas são sorteadas e aparecem uma única vez.** A folha de acessos:

```bash
node scripts/credentials-pdf.mjs ~/credenciais.json \
  --out=~/acessos-agrobarter.pdf --api=https://agrobarter-api.fly.dev
```

Os dois arquivos saem **fora do repositório**, e o `--out` acima é assim de
propósito. Os padrões estão no `.gitignore` da raiz e no de `api/`, mas depender
disso é depender de uma linha estar certa: o repositório é público, e o que
vazaria são as credenciais do ambiente inteiro. Guardar fora não tem como falhar.

A `DATABASE_URL` do Neon também **não vai no `api/.env`** — aquele arquivo é o do
ambiente local, e com ela lá `npm run start:dev` passa a conversar com o banco de
produção e um `npm run db:seed` por hábito apaga o ambiente. O lugar dela é o
`fly secrets set`; para comando avulso, inline, como acima.

---

## 4. O APK (Firebase App Distribution)

O workflow [`distribute.yml`](../.github/workflows/distribute.yml) já constrói e
distribui a cada `main` verde. Faltam duas coisas para ele funcionar:

**A credencial.** Hoje ele passa `--token "${{ secrets.FIREBASE_TOKEN }}"` e o
secret não existe — o log mostra `--token ""` e `Failed to authenticate`. O
`--token` do firebase-tools está descontinuado; o caminho atual é conta de
serviço (item 2 do RELEASE.md).

**O endereço da API.** O build não define `API_URL`, então o APK aponta para
`http://localhost:3333` (item 3 do RELEASE.md) — um aparelho de testador não tem
API nenhuma nesse endereço. Precisa entrar como
`--dart-define=API_URL=https://agrobarter-api.fly.dev`, em **https**: a política
de rede do app recusa texto puro para qualquer host que não seja localhost. O Fly
já serve em https (`force_https` no `fly.toml`).

---

## 5. A versão web (Firebase Hosting)

O mesmo app, no navegador, para quem só quer **ver** sem instalar APK:

**https://barter-app-f6219.firebaseapp.com**

O Hosting serve o site nos **dois** endereços — este e
`https://barter-app-f6219.web.app` —, e o conteúdo é o mesmo arquivo. Compartilhe
o `.firebaseapp.com`: o `.web.app` já recebeu um deploy antigo deste projeto, e
quem abriu aquele endereço na época tem um **service worker** do Flutter
registrado no navegador, que serve o app em cache antes de ir à rede. O sintoma é
inconfundível — abre a primeira versão do app, sem erro nenhum.

Não é o Hosting: dá para conferir comparando o `main.dart.js` servido com o que
saiu do build (`curl -s <url>/main.dart.js | shasum -a 256`), que bate. Quem
esbarrar nisso resolve no próprio navegador, com **Ctrl+Shift+R** (ou DevTools →
Application → Service Workers → *Unregister*). O cache do service worker vence
sozinho depois de uma hora, então o endereço se recupera com o tempo — mas não a
tempo de salvar a primeira impressão de um testador.

Serve para mostrar o produto a quem não tem Android à mão e para testar em tela
grande. Não substitui o APK: é o mesmo código Flutter, mas o navegador não
guarda o token no Keychain do sistema (o `flutter_secure_storage` cai no
armazenamento do próprio navegador) e o compartilhamento do PDF vira download.

Para publicar uma versão nova, da raiz do repositório:

```bash
cd app && flutter build web --release \
  --dart-define=API_URL=https://agrobarter-api.fly.dev
cd .. && firebase deploy --only hosting
```

O `--dart-define` é obrigatório aqui pelo mesmo motivo do APK: sem ele o build
sai apontando para `localhost:3333`. E é um passo manual — `build/web` não é
versionado, então **quem publica constrói antes**; não há workflow fazendo isso.

**O que precisou mudar para a web existir:**

- `api_client.dart` importava `dart:io` só para reconhecer `SocketException`, e
  `dart:io` não compila para o navegador — o `flutter build web` falhava inteiro.
  A distinção foi para trás de um import condicional
  ([`connection_error.dart`](../app/lib/services/api/connection_error.dart)); no
  nativo a mensagem "Verifique sua rede" continua igual.
- `CORS_ORIGINS` no [`fly.toml`](../api/fly.toml). Sem ela, `NODE_ENV=production`
  fecha a API para toda origem, e a versão web tomaria erro de CORS em cada
  chamada. **Mudando o endereço do site, essa variável muda junto** — e ela lista
  os dois domínios que o Hosting serve (`.web.app` e `.firebaseapp.com`), porque
  para o navegador são origens diferentes.

O app nativo não é afetado por nada disso: requisição nativa não manda `Origin`,
então a política fechada nunca valeu para ele.
