# Subir um ambiente de teste

O caminho para tirar o agroBarter da máquina de quem desenvolve e pôr na mão de
quem vai testar: **banco no Neon**, **API na Vercel**, **APK pelo Firebase App
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
   ela que vai na Vercel, e não a direta: quem multiplexa as conexões das
   funções é o pooler (o porquê está no comentário de `prisma.service.ts`).
3. Aplicar as migrations, da sua máquina:

   ```bash
   cd api
   DATABASE_URL="postgresql://...-pooler.../neondb?sslmode=require" \
     npx prisma migrate deploy
   ```

`sslmode=require` não é enfeite: sem ele o Postgres gerenciado recusa a conexão.

---

## 2. A API (Vercel)

O projeto já traz o que a Vercel precisa: [`api/vercel.json`](../api/vercel.json)
e a função [`api/api/index.js`](../api/api/index.js).

No painel da Vercel, **Add New → Project**, apontando para este repositório:

| Campo | Valor |
|---|---|
| Root Directory | `api` |
| Framework Preset | Other |
| Build/Install Command | deixar em branco (vêm do `vercel.json`) |

E as variáveis de ambiente:

| Variável | Valor | Por quê |
|---|---|---|
| `DATABASE_URL` | a URL do **pooler** do Neon, com `sslmode=require` | |
| `NODE_ENV` | `production` | fecha o CORS e impede o dataset de demonstração de rodar |
| `TRUST_PROXY` | `1` | **não é opcional aqui.** A Vercel é um proxy; sem isto o limite por IP conta o mundo inteiro como um cliente só, e o primeiro que errar a senha tira os outros do ar |
| `DATABASE_POOL_MAX` | `1` | uma instância por requisição simultânea, cada uma com o pool dela — sem o teto, um pico vira `too many connections` |
| `PASSWORD_COST` | não definir | o padrão (16) é o seguro; defini-lo baixo enfraquece todas as senhas novas |

`CORS_ORIGINS` só é necessária se um dia houver front web. O app mobile não
manda `Origin`, então ele funciona com a política fechada.

Depois do primeiro deploy, a sonda responde sem autenticação:

```bash
curl https://SEU-PROJETO.vercel.app/health
# {"status":"ok","database":"ok"}
```

`database: "ok"` é o que prova que a Vercel alcançou o Neon. Se vier erro aí, o
problema é a `DATABASE_URL` — e não vale seguir para o passo 3.

### O que fica diferente por ser função, e não servidor

A limpeza periódica de sessões vencidas (`SessionCleanupService`) só roda
enquanto uma instância está quente, o que em função é imprevisível. Não é
problema de segurança: sessão vencida é recusada **e apagada** na primeira
tentativa de uso, no `auth.guard`. O serviço é faxina, não a trava.

---

## 3. Os usuários e o catálogo

Com as migrations aplicadas, o banco está vazio. Este comando o deixa pronto
para uso — pessoas e catálogo, sem nenhum movimento:

```bash
cd api
DATABASE_URL="postgresql://...-pooler.../neondb?sslmode=require" \
  npm run provision -- --yes --out=../credenciais.json
```

Ele imprime o host alvo antes de tocar em qualquer coisa e exige `--yes`, porque
apaga o banco inteiro. Ficam usuários dos cinco papéis, unidades, classes,
produtos e a safra vigente com a tabela de preços. Saem produtores, permutas,
histórico de preço e auditoria.

**As senhas são sorteadas e aparecem uma única vez.** A folha de acessos:

```bash
node scripts/credentials-pdf.mjs ../credenciais.json \
  --out=../acessos.pdf --api=https://SEU-PROJETO.vercel.app
```

O JSON e o PDF estão no `.gitignore` — este repositório é público, e eles são a
única cópia legível das senhas.

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
`--dart-define=API_URL=https://SEU-PROJETO.vercel.app`, em **https**: a política
de rede do app recusa texto puro para qualquer host que não seja localhost.
