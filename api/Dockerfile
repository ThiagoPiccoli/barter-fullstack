# A API em contêiner — é isto que roda no Fly.
#
# Duas etapas: a primeira instala tudo e compila; a segunda leva só o que o
# servidor precisa para subir. O `prisma generate` roda AQUI DENTRO de
# propósito: o client traz um engine nativo, e gerá-lo na máquina de quem
# desenvolve (macOS/arm64) produziria um binário que não roda no contêiner
# (linux). Gerado na mesma imagem que vai executar, a plataforma casa sozinha.

FROM node:24-slim AS build

WORKDIR /app

# O engine do Prisma é ligado ao OpenSSL; sem ele o `generate` até passa e a
# primeira consulta é que falha, com erro sobre biblioteca compartilhada.
RUN apt-get update \
  && apt-get install -y --no-install-recommends openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# As dependências antes do código: enquanto o package-lock não muda, esta
# camada é reaproveitada e o build não reinstala nada.
COPY package.json package-lock.json ./
RUN npm ci

COPY . .

# O `prisma.config.ts` exige DATABASE_URL só por existir, e o `generate` o
# carrega. Nada é conectado aqui — o valor é um lugar-comum para o comando ter
# o que ler. A URL de verdade entra como secret, em tempo de execução.
ENV DATABASE_URL="postgresql://build:build@localhost:5432/build"
RUN npx prisma generate && npm run build


FROM node:24-slim AS runtime

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production
ENV PORT=3333

# node_modules vem INTEIRO, com as dependências de desenvolvimento junto, e
# isso é escolha: o `release_command` do fly.toml roda `prisma migrate deploy`
# nesta mesma imagem, o Prisma CLI é dependência de desenvolvimento, e ele
# ainda precisa carregar o `prisma.config.ts` — que é TypeScript, e portanto
# depende do ts-node. Podar aqui economizaria alguns megabytes e custaria a
# capacidade de aplicar migration no deploy, que é o que mantém banco e código
# em passo.
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/prisma ./prisma
COPY --from=build /app/prisma.config.ts ./prisma.config.ts
COPY --from=build /app/tsconfig.json ./tsconfig.json
COPY --from=build /app/package.json ./package.json

# Não roda como root: se algo escapar do processo, escapa sem privilégio. A
# imagem do Node já traz o usuário `node`.
USER node

EXPOSE 3333

CMD ["node", "dist/src/main"]
