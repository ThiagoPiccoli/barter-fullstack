-- O NÚMERO DA CPR passa a nascer com a PERMUTA, gerado pelo sistema, e sai da
-- cédula. Era texto livre em `BarterCpr.number`, digitado pelo emissor no ato
-- da emissão; agora é `Barter.cprNumber`, `CPR-<ano>-NNN`, sequencial dentro
-- do ano e único.
--
-- A ordem importa pelo mesmo motivo de sempre: a coluna nasce nulável, cada
-- permuta recebe o seu número, e só então ela vira NOT NULL e a coluna antiga
-- sai. O `prisma migrate diff` faria o contrário e perderia os números que os
-- emissores já informaram.
--
-- QUEM RECEBE QUAL NÚMERO:
--
--   1. a permuta cuja cédula já tem número informado o HERDA — inclusive as já
--      emitidas, assinadas e registradas: esse é o número que está no papel, e
--      trocá-lo aqui faria o sistema discordar do cartório;
--   2. o mesmo número informado em mais de uma cédula (o campo não conferia
--      repetição) fica com a permuta de MENOR id, e as outras são numeradas
--      como as do item 3;
--   3. as demais recebem `CPR-<ano do registro>-NNN`, na ordem do registro,
--      continuando DEPOIS do maior número herdado daquele ano — para que a
--      sequência que o servidor retoma a partir de agora não esbarre em nenhum.

-- AlterTable
ALTER TABLE "Barter" ADD COLUMN "cprNumber" TEXT;

-- 1 e 2: o número informado, quando há e não se repete.
UPDATE "Barter" b
SET "cprNumber" = herdado."number"
FROM (
    SELECT DISTINCT ON (btrim(c."number")) c."barterId", btrim(c."number") AS "number"
    FROM "BarterCpr" c
    WHERE btrim(c."number") <> ''
    ORDER BY btrim(c."number"), c."barterId"
) herdado
WHERE b."id" = herdado."barterId";

-- 3: as que ficaram sem número.
WITH maiores AS (
    SELECT substring("cprNumber" FROM 5 FOR 4) AS ano,
           max(substring("cprNumber" FROM 10)::INTEGER) AS maior
    FROM "Barter"
    WHERE "cprNumber" ~ '^CPR-[0-9]{4}-[0-9]{1,9}$'
    GROUP BY 1
),
faltando AS (
    SELECT "id",
           to_char("createdAt", 'YYYY') AS ano,
           row_number() OVER (
               PARTITION BY to_char("createdAt", 'YYYY')
               ORDER BY "createdAt", "id"
           ) AS ordem
    FROM "Barter"
    WHERE "cprNumber" IS NULL
)
UPDATE "Barter" b
SET "cprNumber" = 'CPR-' || f.ano || '-' || lpad((coalesce(m.maior, 0) + f.ordem)::TEXT, 3, '0')
FROM faltando f
LEFT JOIN maiores m ON m.ano = f.ano
WHERE b."id" = f."id";

ALTER TABLE "Barter" ALTER COLUMN "cprNumber" SET NOT NULL;

-- CreateIndex
CREATE UNIQUE INDEX "Barter_cprNumber_key" ON "Barter"("cprNumber");

-- AlterTable
ALTER TABLE "BarterCpr" DROP COLUMN "number";
