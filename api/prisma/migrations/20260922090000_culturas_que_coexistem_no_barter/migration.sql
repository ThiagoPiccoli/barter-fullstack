-- AS CULTURAS COEXISTEM: o grão sai da safra e vira uma LISTA na versão.
--
-- A safra ERA a cultura ("soja 2026"), e toda permuta registrada nela só podia
-- ser paga em soja. A lavoura não é assim: na mesma janela o produtor planta
-- soja e milho, e o Barter precisa aceitar as duas ao mesmo tempo, com o cliente
-- escolhendo em qual delas paga. Enquanto o grão morou na safra, a única forma
-- de oferecer duas culturas era abrir duas safras — e aí "em qual gestão esta
-- permuta caiu?" voltava a ter duas respostas.
--
-- O que muda de lugar, e por quê:
--
--   Season.grainId/grainName/grainUnit  →  VersionGrain (uma linha por cultura)
--   Season.cprDueDate                   →  VersionGrain.cprDueDate
--   BarterVersion.grainPrice            →  VersionGrain.price
--   BarterVersion.estimatedYield        →  VersionGrain.estimatedYield
--   BarterVersion.targetSacks           →  VersionGrain.targetSacks
--
-- O que NÃO muda de lugar: a tabela de insumos (o preço em R$ não muda com o
-- grão), o seguro agrícola (é do lançamento, cotado por praça) e a vigência.
--
-- E o que NÃO GANHA COLUNA NENHUMA é a cultura da permuta: ela é a linha do grão
-- que a permuta já tem (`BarterItem` de `kind = 'grain'`), com o produto, o nome,
-- a unidade e a cotação congelados desde o registro. Uma coluna ao lado seria um
-- segundo lugar dizendo o mesmo.

-- A CULTURA DO LANÇAMENTO.
CREATE TABLE "VersionGrain" (
    "id" SERIAL NOT NULL,
    "versionId" INTEGER NOT NULL,
    "grainId" INTEGER,
    "grainName" TEXT NOT NULL,
    "grainUnit" TEXT NOT NULL,
    "price" DOUBLE PRECISION NOT NULL,
    "estimatedYield" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "cprDueDate" TIMESTAMP(3),
    "targetSacks" DOUBLE PRECISION,
    "position" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "VersionGrain_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "VersionGrain_versionId_grainId_key" ON "VersionGrain"("versionId", "grainId");

ALTER TABLE "VersionGrain" ADD CONSTRAINT "VersionGrain_versionId_fkey"
    FOREIGN KEY ("versionId") REFERENCES "BarterVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "VersionGrain" ADD CONSTRAINT "VersionGrain_grainId_fkey"
    FOREIGN KEY ("grainId") REFERENCES "Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- A CONVERSÃO: cada versão já publicada vira uma versão de UMA cultura — a da
-- safra dela, com a cotação, a produtividade, o vencimento e a meta de sacas que
-- ela já tinha. É a leitura literal do que essas versões são: elas foram
-- lançadas quando só havia uma cultura possível, e não há nada a adivinhar.
INSERT INTO "VersionGrain" (
    "versionId", "grainId", "grainName", "grainUnit",
    "price", "estimatedYield", "cprDueDate", "targetSacks", "position"
)
SELECT v."id", s."grainId", s."grainName", s."grainUnit",
       v."grainPrice", v."estimatedYield", s."cprDueDate", v."targetSacks", 0
  FROM "BarterVersion" v
  JOIN "Season" s ON s."id" = v."seasonId";

-- O que saiu da safra e da versão. Depois da conversão acima, e não antes: são
-- essas colunas que a conversão leu.
ALTER TABLE "Season" DROP CONSTRAINT IF EXISTS "Season_grainId_fkey";
ALTER TABLE "Season" DROP COLUMN "grainId",
                     DROP COLUMN "grainName",
                     DROP COLUMN "grainUnit",
                     DROP COLUMN "cprDueDate";

ALTER TABLE "BarterVersion" DROP COLUMN "grainPrice",
                            DROP COLUMN "estimatedYield",
                            DROP COLUMN "targetSacks";
