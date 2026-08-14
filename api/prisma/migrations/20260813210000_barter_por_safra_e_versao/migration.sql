-- AlterTable
ALTER TABLE "Product" ADD COLUMN "sku" TEXT;

-- CreateTable
CREATE TABLE "Season" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "year" INTEGER NOT NULL,
    "grainId" INTEGER,
    "grainName" TEXT NOT NULL,
    "grainUnit" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'open',
    "openedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "closedAt" DATETIME,
    CONSTRAINT "Season_grainId_fkey" FOREIGN KEY ("grainId") REFERENCES "Product" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "BarterVersion" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "seasonId" INTEGER NOT NULL,
    "number" INTEGER NOT NULL,
    "code" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'active',
    "grainPrice" REAL NOT NULL,
    "startsAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endsAt" DATETIME,
    "targetSales" REAL,
    "targetProfit" REAL,
    "targetSacks" REAL,
    "targetBarters" INTEGER,
    "sourceFile" TEXT,
    "note" TEXT,
    "closedAt" DATETIME,
    "closedBy" TEXT,
    "closedById" INTEGER,
    CONSTRAINT "BarterVersion_seasonId_fkey" FOREIGN KEY ("seasonId") REFERENCES "Season" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "VersionPrice" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "versionId" INTEGER NOT NULL,
    "productId" INTEGER,
    "productName" TEXT NOT NULL,
    "unit" TEXT NOT NULL,
    "price" REAL NOT NULL,
    "cost" REAL NOT NULL DEFAULT 0,
    CONSTRAINT "VersionPrice_versionId_fkey" FOREIGN KEY ("versionId") REFERENCES "BarterVersion" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "VersionPrice_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_Barter" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "code" TEXT NOT NULL,
    "versionId" INTEGER,
    "versionCode" TEXT NOT NULL DEFAULT '',
    "consultantId" INTEGER,
    "producerId" INTEGER,
    "consultantName" TEXT NOT NULL,
    "consultantBranch" TEXT NOT NULL DEFAULT '',
    "producerName" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "adminNote" TEXT,
    "reviewedBy" TEXT,
    "reviewedById" INTEGER,
    "reviewedAt" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Barter_versionId_fkey" FOREIGN KEY ("versionId") REFERENCES "BarterVersion" ("id") ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT "Barter_consultantId_fkey" FOREIGN KEY ("consultantId") REFERENCES "User" ("id") ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT "Barter_producerId_fkey" FOREIGN KEY ("producerId") REFERENCES "Producer" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);
INSERT INTO "new_Barter" ("adminNote", "code", "consultantBranch", "consultantId", "consultantName", "createdAt", "id", "producerId", "producerName", "reviewedAt", "reviewedBy", "reviewedById", "status") SELECT "adminNote", "code", "consultantBranch", "consultantId", "consultantName", "createdAt", "id", "producerId", "producerName", "reviewedAt", "reviewedBy", "reviewedById", "status" FROM "Barter";
DROP TABLE "Barter";
ALTER TABLE "new_Barter" RENAME TO "Barter";
CREATE UNIQUE INDEX "Barter_code_key" ON "Barter"("code");
CREATE INDEX "Barter_versionId_idx" ON "Barter"("versionId");
CREATE TABLE "new_BarterItem" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "barterId" INTEGER NOT NULL,
    "productId" INTEGER,
    "kind" TEXT NOT NULL,
    "productName" TEXT NOT NULL,
    "unit" TEXT NOT NULL,
    "quantity" REAL NOT NULL,
    "unitValue" REAL NOT NULL,
    "unitCost" REAL NOT NULL DEFAULT 0,
    CONSTRAINT "BarterItem_barterId_fkey" FOREIGN KEY ("barterId") REFERENCES "Barter" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "BarterItem_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);
INSERT INTO "new_BarterItem" ("barterId", "id", "kind", "productId", "productName", "quantity", "unit", "unitValue") SELECT "barterId", "id", "kind", "productId", "productName", "quantity", "unit", "unitValue" FROM "BarterItem";
DROP TABLE "BarterItem";
ALTER TABLE "new_BarterItem" RENAME TO "BarterItem";
PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;

-- CreateIndex
CREATE UNIQUE INDEX "Season_code_key" ON "Season"("code");

-- CreateIndex
CREATE UNIQUE INDEX "BarterVersion_code_key" ON "BarterVersion"("code");

-- CreateIndex
CREATE UNIQUE INDEX "BarterVersion_seasonId_number_key" ON "BarterVersion"("seasonId", "number");

-- CreateIndex
CREATE UNIQUE INDEX "VersionPrice_versionId_productId_key" ON "VersionPrice"("versionId", "productId");

-- CreateIndex
CREATE UNIQUE INDEX "Product_sku_key" ON "Product"("sku");
