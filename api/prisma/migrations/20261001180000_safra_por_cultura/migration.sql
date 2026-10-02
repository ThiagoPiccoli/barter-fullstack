-- A SAFRA VOLTA A SER DA CULTURA, e cada cultura tem as suas versões.
--
-- O encerramento era por versão do Barter, e a versão juntava as culturas: ao
-- bater a meta de sacas do milho, a soja fechava junto. Agora:
--
--   Season         a safra DE UMA CULTURA ("Soja 26/27", "Canola 2027"), com o
--                  ano digitado pelo admin, o status e o seguro padrão;
--   BarterVersion  uma versão DAQUELA safra (SOJA26/27.01), com a tabela de
--                  insumos própria, a cotação da saca, a produtividade, o
--                  vencimento da CPR, a política de seguro e as metas;
--   VersionGrain   deixa de existir — com uma cultura por versão, os campos dela
--                  voltam para a versão.
--
-- E a ÁREA sai do cadastro do produtor e vai para a permuta: `producerAreaHa`
-- (a área do cadastro, congelada) passa a se chamar `plantedAreaHa` — a área
-- daquela cultura — e mantém o número com que cada permuta foi calculada.
--
-- AS VERSÕES COM MAIS DE UMA CULTURA são divididas: a primeira cultura fica com
-- a versão original (e com as metas de vendas e de permutas dela); cada uma das
-- outras ganha uma cópia da versão, com a tabela de insumos copiada e só a meta
-- de sacas que já era dela. Cada permuta passa a apontar para a versão da sua
-- cultura, lida da linha do grão. Dali em diante nenhuma versão tem duas.

-- ── 1. Colunas novas, ainda aceitando nulo: a conversão é que as preenche ──

ALTER TABLE "Season"
    ADD COLUMN "slug" TEXT,
    ADD COLUMN "grainId" INTEGER,
    ADD COLUMN "grainName" TEXT,
    ADD COLUMN "grainUnit" TEXT,
    ADD COLUMN "startYear" INTEGER,
    ADD COLUMN "endYear" INTEGER,
    ADD COLUMN "insurancePolicy" TEXT NOT NULL DEFAULT 'none',
    ADD COLUMN "closedBy" TEXT,
    ADD COLUMN "closedById" INTEGER;

ALTER TABLE "BarterVersion"
    ADD COLUMN "slug" TEXT,
    ADD COLUMN "grainPrice" DOUBLE PRECISION,
    ADD COLUMN "estimatedYield" DOUBLE PRECISION NOT NULL DEFAULT 0,
    ADD COLUMN "cprDueDate" TIMESTAMP(3),
    ADD COLUMN "targetSacks" DOUBLE PRECISION,
    ADD COLUMN "insurancePolicy" TEXT NOT NULL DEFAULT 'none';

ALTER TABLE "Barter" RENAME COLUMN "producerAreaHa" TO "plantedAreaHa";
ALTER TABLE "Barter"
    ADD COLUMN "seasonId" INTEGER,
    ADD COLUMN "seasonName" TEXT NOT NULL DEFAULT '',
    ADD COLUMN "insuranceChoice" TEXT NOT NULL DEFAULT 'none';

-- Toda versão tem ao menos uma cultura desde a migration que as criou. Uma sem
-- nenhuma é banco mexido à mão, e adivinhar o grão dela seria inventar dado.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM "BarterVersion" v
         WHERE NOT EXISTS (SELECT 1 FROM "VersionGrain" g WHERE g."versionId" = v."id")
    ) THEN
        RAISE EXCEPTION 'Há versão do Barter sem cultura nenhuma; corrija-a antes de migrar.';
    END IF;
END $$;

-- ── 2. O mapa: cada cultura de cada versão vira uma versão de uma cultura ──

CREATE TEMP TABLE vg_map AS
SELECT g."id"             AS vg_id,
       g."versionId"      AS old_version_id,
       v."seasonId"       AS old_season_id,
       s."year"           AS year,
       g."grainId", g."grainName", g."grainUnit",
       g."price", g."estimatedYield", g."cprDueDate", g."targetSacks", g."position",
       -- A CHAVE DA CULTURA: o grão do catálogo, ou o nome congelado quando o
       -- produto foi excluído — o mesmo critério de `cultureOf`.
       COALESCE('id:' || g."grainId", 'name:' || lower(trim(g."grainName"))) AS grain_key,
       NULL::INTEGER      AS new_version_id
  FROM "VersionGrain" g
  JOIN "BarterVersion" v ON v."id" = g."versionId"
  JOIN "Season" s ON s."id" = v."seasonId";

-- A primeira cultura de cada versão (na ordem do lançamento) fica com a versão
-- original: é ela que as permutas já apontam, e a maioria das versões só tem uma.
UPDATE vg_map m
   SET new_version_id = m.old_version_id
 WHERE m.vg_id = (
        SELECT f.vg_id FROM vg_map f
         WHERE f.old_version_id = m.old_version_id
         ORDER BY f."position", f.vg_id
         LIMIT 1);

-- ── 3. As safras das culturas: uma por (safra antiga × grão) ──

CREATE TEMP TABLE season_map AS
SELECT DISTINCT ON (old_season_id, grain_key)
       old_season_id, grain_key, "grainId", "grainName", "grainUnit", year,
       NULL::TEXT    AS base,
       NULL::TEXT    AS code,
       NULL::INTEGER AS new_id
  FROM vg_map
 ORDER BY old_season_id, grain_key, old_version_id DESC;

-- O CÓDIGO: o grão sem acento nem espaço, em maiúsculas, e os anos da safra. A
-- safra antiga B2026 é a de 26/27 — o ano do código era o do plantio.
UPDATE season_map
   SET base = upper(regexp_replace(
                  translate("grainName",
                            'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
                            'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN'),
                  '[^A-Za-z0-9]', '', 'g'))
              || lpad((year % 100)::TEXT, 2, '0') || '/' || lpad(((year + 1) % 100)::TEXT, 2, '0');

-- Duas safras antigas do mesmo ano (letras diferentes) dariam o mesmo código para
-- o mesmo grão. A segunda em diante ganha um sufixo, em vez de a migração falhar.
UPDATE season_map m
   SET code = CASE WHEN r.rn = 1 THEN m.base ELSE m.base || '-' || r.rn END
  FROM (SELECT old_season_id, grain_key,
               row_number() OVER (PARTITION BY base ORDER BY old_season_id) AS rn
          FROM season_map) r
 WHERE r.old_season_id = m.old_season_id AND r.grain_key = m.grain_key;

INSERT INTO "Season" (
    "code", "slug", "name", "year", "status", "openedAt", "closedAt",
    "grainId", "grainName", "grainUnit", "startYear", "endYear"
)
SELECT m.code,
       replace(m.code, '/', ''),
       trim(m."grainName") || ' ' || lpad((m.year % 100)::TEXT, 2, '0') || '/' || lpad(((m.year + 1) % 100)::TEXT, 2, '0'),
       m.year, s."status", s."openedAt", s."closedAt",
       m."grainId", m."grainName", m."grainUnit", m.year, m.year + 1
  FROM season_map m
  JOIN "Season" s ON s."id" = m.old_season_id;

UPDATE season_map m SET new_id = s."id" FROM "Season" s WHERE s."code" = m.code;

-- ── 4. As versões ──

-- As CÓPIAS, para as culturas que não ficaram com a versão original. Nascem já
-- na safra nova (o número delas repete o da original, e é na safra nova que ele
-- é único). Metas de vendas e de permutas ficam com a original: copiá-las
-- dobraria o alvo. A de sacas é da cultura, e vem junto.
INSERT INTO "BarterVersion" (
    "seasonId", "number", "code", "slug", "status", "startsAt", "endsAt",
    "targetSales", "targetBarters", "closeOnGoal", "insuranceRequired",
    "sourceFile", "note", "closedAt", "closedBy", "closedById"
)
SELECT sm.new_id, v."number", 'tmp-' || m.vg_id, 'tmp-' || m.vg_id, v."status", v."startsAt", v."endsAt",
       NULL, NULL, v."closeOnGoal" AND m."targetSacks" IS NOT NULL, v."insuranceRequired",
       v."sourceFile", v."note", v."closedAt", v."closedBy", v."closedById"
  FROM vg_map m
  JOIN "BarterVersion" v ON v."id" = m.old_version_id
  JOIN season_map sm ON sm.old_season_id = m.old_season_id AND sm.grain_key = m.grain_key
 WHERE m.new_version_id IS NULL;

UPDATE vg_map m SET new_version_id = v."id" FROM "BarterVersion" v WHERE v."code" = 'tmp-' || m.vg_id;

-- A tabela de insumos copiada: o insumo custava o mesmo em R$ para as culturas
-- da versão dividida, e a cópia diz exatamente isso.
INSERT INTO "VersionPrice" ("versionId", "productId", "productName", "unit", "price")
SELECT m.new_version_id, p."productId", p."productName", p."unit", p."price"
  FROM vg_map m
  JOIN "VersionPrice" p ON p."versionId" = m.old_version_id
 WHERE m.new_version_id <> m.old_version_id;

-- Todas as versões, originais e cópias: a safra nova, o código novo e os campos
-- da cultura que moravam no VersionGrain.
UPDATE "BarterVersion" v
   SET "seasonId"        = sm.new_id,
       "code"            = sm.code || '.' || lpad(v."number"::TEXT, 2, '0'),
       "slug"            = replace(sm.code, '/', '') || '.' || lpad(v."number"::TEXT, 2, '0'),
       "grainPrice"      = m."price",
       "estimatedYield"  = m."estimatedYield",
       "cprDueDate"      = m."cprDueDate",
       "targetSacks"     = m."targetSacks",
       "insurancePolicy" = CASE WHEN v."insuranceRequired" THEN 'required' ELSE 'none' END
  FROM vg_map m
  JOIN season_map sm ON sm.old_season_id = m.old_season_id AND sm.grain_key = m.grain_key
 WHERE v."id" = m.new_version_id;

-- O SEGURO PADRÃO da safra é o da última versão dela.
UPDATE "Season" s
   SET "insurancePolicy" = (
        SELECT v."insurancePolicy" FROM "BarterVersion" v
         WHERE v."seasonId" = s."id"
         ORDER BY v."number" DESC
         LIMIT 1)
 WHERE s."id" IN (SELECT new_id FROM season_map);

-- ── 5. As permutas ──

-- Cada uma vai para a versão da SUA cultura, lida da linha do grão. Sem linha de
-- grão (permutas anteriores a ela), fica na versão original — a da primeira
-- cultura, que era a única que existia quando ela nasceu.
UPDATE "Barter" b
   SET "versionId" = m.new_version_id
  FROM vg_map m
 WHERE m.old_version_id = b."versionId"
   AND m.new_version_id <> m.old_version_id
   AND EXISTS (
        SELECT 1 FROM "BarterItem" i
         WHERE i."barterId" = b."id" AND i."kind" = 'grain'
           AND COALESCE('id:' || i."productId", 'name:' || lower(trim(i."productName"))) = m.grain_key);

UPDATE "Barter" b
   SET "versionCode" = v."code",
       "seasonId"    = s."id",
       "seasonName"  = s."name"
  FROM "BarterVersion" v
  JOIN "Season" s ON s."id" = v."seasonId"
 WHERE v."id" = b."versionId";

-- COMO o seguro chegou a ela: até aqui ele só podia ser obrigatório.
UPDATE "Barter"
   SET "insuranceChoice" = CASE WHEN "insuranceRatePerHa" > 0 THEN 'required' ELSE 'none' END;

-- ── 6. O que saiu ──

-- As safras antigas (o ciclo do programa). As versões já foram todas para as
-- safras novas; a que sobrar aqui é safra sem versão nenhuma — sem grão, não há
-- de que cultura ela seria.
DELETE FROM "Season" WHERE "id" NOT IN (SELECT new_id FROM season_map);

DROP TABLE "VersionGrain";

ALTER TABLE "BarterVersion" DROP COLUMN "insuranceRequired";
ALTER TABLE "Season" DROP COLUMN "year";
ALTER TABLE "Producer" DROP COLUMN "areaHa";

-- ── 7. Os NOT NULL, os índices e as chaves, agora que tudo está preenchido ──

ALTER TABLE "Season"
    ALTER COLUMN "slug" SET NOT NULL,
    ALTER COLUMN "grainName" SET NOT NULL,
    ALTER COLUMN "grainUnit" SET NOT NULL,
    ALTER COLUMN "startYear" SET NOT NULL,
    ALTER COLUMN "endYear" SET NOT NULL;

ALTER TABLE "BarterVersion"
    ALTER COLUMN "slug" SET NOT NULL,
    ALTER COLUMN "grainPrice" SET NOT NULL;

CREATE UNIQUE INDEX "Season_slug_key" ON "Season"("slug");
CREATE INDEX "Season_grainId_status_idx" ON "Season"("grainId", "status");
CREATE UNIQUE INDEX "BarterVersion_slug_key" ON "BarterVersion"("slug");

ALTER TABLE "Season" ADD CONSTRAINT "Season_grainId_fkey"
    FOREIGN KEY ("grainId") REFERENCES "Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "Barter" ADD CONSTRAINT "Barter_seasonId_fkey"
    FOREIGN KEY ("seasonId") REFERENCES "Season"("id") ON DELETE SET NULL ON UPDATE CASCADE;
