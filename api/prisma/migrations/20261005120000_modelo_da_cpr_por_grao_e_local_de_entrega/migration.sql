-- Duas mudanças na cédula, as duas trocando digitação por cadastro:
--
-- 1. O MODELO DA CPR POR GRÃO. Cada grão ganha o seu padrão de recebimento —
--    peso da saca, umidade e impurezas máximas, teor de óleo —, e a CPR nova
--    nasce com ele preenchido. A cédula continua guardando os números dela: o
--    modelo é o ponto de partida, e mudá-lo não reescreve cédula nenhuma.
--
-- 2. O LOCAL DA ENTREGA vira uma das FILIAIS cadastradas (`Unit`). O texto
--    continua na cédula, como o nome congelado da unidade escolhida; as cédulas
--    do tempo do texto livre ficam com o texto que têm.

-- AlterTable
ALTER TABLE "Product" ADD COLUMN "cprSackWeightKg" DOUBLE PRECISION NOT NULL DEFAULT 60,
ADD COLUMN "cprMaxMoisture" DOUBLE PRECISION NOT NULL DEFAULT 0,
ADD COLUMN "cprMaxImpurities" DOUBLE PRECISION NOT NULL DEFAULT 0,
ADD COLUMN "cprOilContent" DOUBLE PRECISION NOT NULL DEFAULT 0;

-- O modelo de cada grão nasce da ÚLTIMA cédula preenchida dele, quando há uma:
-- é o padrão que alguém já digitou e conferiu. Sem cédula (ou só com cédula sem
-- o padrão preenchido), o grão fica com os defaults e o admin define na aba.
UPDATE "Product" AS p
   SET "cprSackWeightKg" = l."sackWeightKg",
       "cprMaxMoisture" = l."maxMoisture",
       "cprMaxImpurities" = l."maxImpurities",
       "cprOilContent" = l."oilContent"
  FROM (
        SELECT DISTINCT ON (s."grainId")
               s."grainId", c."sackWeightKg", c."maxMoisture", c."maxImpurities", c."oilContent"
          FROM "BarterCpr" AS c
          JOIN "Barter" AS b ON b."id" = c."barterId"
          JOIN "BarterVersion" AS v ON v."code" = b."versionCode"
          JOIN "Season" AS s ON s."id" = v."seasonId"
         WHERE s."grainId" IS NOT NULL
           AND c."maxMoisture" > 0
         ORDER BY s."grainId", c."updatedAt" DESC
       ) AS l
 WHERE p."id" = l."grainId"
   AND p."type" = 'grain';

-- AlterTable
ALTER TABLE "BarterCpr" ADD COLUMN "deliveryUnitId" INTEGER;

-- AddForeignKey
ALTER TABLE "BarterCpr" ADD CONSTRAINT "BarterCpr_deliveryUnitId_fkey" FOREIGN KEY ("deliveryUnitId") REFERENCES "Unit"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- O texto livre que já é o nome de uma filial passa a apontar para ela. A
-- comparação é pela forma canônica de `Unit.nameKey` até onde o SQL alcança
-- (caixa e espaços; acento não): "FILIAL 02" acha a "Filial 02", e o que não
-- casa fica como estava — texto, sem unidade.
UPDATE "BarterCpr" AS c
   SET "deliveryUnitId" = u."id"
  FROM "Unit" AS u
 WHERE lower(regexp_replace(btrim(c."deliveryPlace"), '\s+', ' ', 'g')) = u."nameKey";
