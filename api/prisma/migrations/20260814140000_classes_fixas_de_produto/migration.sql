-- As "pastas" de insumo (InputCategory), que o admin criava e renomeava à
-- vontade, viram CLASSES: uma lista fixa do negócio, criada aqui e sem rota
-- que a altere. O que continua editável é a regra de mínimo de cada uma.

-- CreateTable
CREATE TABLE "ProductClass" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "slug" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "position" INTEGER NOT NULL DEFAULT 0,
    "ruleType" TEXT NOT NULL DEFAULT 'none',
    "ruleValue" REAL NOT NULL DEFAULT 0
);

-- CreateIndex
CREATE UNIQUE INDEX "ProductClass_slug_key" ON "ProductClass"("slug");

-- A LISTA. Entra pela migration de propósito: é vocabulário do negócio, não
-- dado de demonstração — precisa existir igual em dev, em teste e em produção.
INSERT INTO "ProductClass" ("slug", "name", "position", "ruleType", "ruleValue") VALUES
    ('fungicidas',       'Fungicidas',         1, 'none', 0),
    ('inseticidas',      'Inseticidas',        2, 'none', 0),
    ('herbicidas',       'Herbicidas',         3, 'none', 0),
    ('sementes',         'Sementes',           4, 'none', 0),
    ('fertilizantes',    'Fertilizantes',      5, 'none', 0),
    ('biologicos',       'Biológicos',         6, 'none', 0),
    ('nutricao',         'Nutrição',           7, 'none', 0),
    ('seguro-agricola',  'Seguro agrícola',    8, 'none', 0),
    ('oleos-adjuvantes', 'Óleos e adjuvantes', 9, 'none', 0);

-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_Product" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "name" TEXT NOT NULL,
    "unit" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "currentPrice" REAL NOT NULL,
    "requiredPerHa" REAL NOT NULL DEFAULT 0,
    "classId" INTEGER,
    "sku" TEXT,
    CONSTRAINT "Product_classId_fkey" FOREIGN KEY ("classId") REFERENCES "ProductClass" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- A classificação antiga é preservada onde o nome da pasta coincide com o de
-- uma classe (Fertilizantes, Sementes...). Pasta que não existe mais na lista
-- (a genérica "Defensivos", por exemplo) deixa o produto SEM classe, em vez de
-- ser encaixada num palpite: quem sabe se aquele item é fungicida, inseticida
-- ou herbicida é quem cadastrou, não esta migration.
INSERT INTO "new_Product" ("id", "name", "unit", "type", "currentPrice", "requiredPerHa", "sku", "classId")
SELECT
    p."id", p."name", p."unit", p."type", p."currentPrice", p."requiredPerHa", p."sku",
    (
        SELECT c."id"
        FROM "ProductClass" c
        JOIN "InputCategory" cat ON cat."id" = p."categoryId"
        WHERE lower(c."name") = lower(cat."name")
    )
FROM "Product" p;

DROP TABLE "Product";
ALTER TABLE "new_Product" RENAME TO "Product";
CREATE UNIQUE INDEX "Product_sku_key" ON "Product"("sku");
PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;

-- DropTable
PRAGMA foreign_keys=off;
DROP TABLE "InputCategory";
PRAGMA foreign_keys=on;
