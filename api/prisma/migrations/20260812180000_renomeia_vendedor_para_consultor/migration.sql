/*
  "Vendedor" vira "Consultor" em todo o produto. Aqui isso significa renomear
  as colunas que carregavam o termo antigo (Producer.sellerId, Barter.sellerId,
  Barter.sellerName, Barter.sellerBranch) e trocar o papel gravado em
  User.role de 'seller' para 'consultant'.

  Os dados são PRESERVADOS: permuta é registro histórico e a carteira de
  produtores é a designação real de cada consultor — nada disso pode ser
  recriado do zero. O SQLite não altera coluna no lugar, então usamos o mesmo
  padrão de tabela nova + cópia das migrations anteriores.
*/

-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;

CREATE TABLE "new_Barter" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "code" TEXT NOT NULL,
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
    CONSTRAINT "Barter_consultantId_fkey" FOREIGN KEY ("consultantId") REFERENCES "User" ("id") ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT "Barter_producerId_fkey" FOREIGN KEY ("producerId") REFERENCES "Producer" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);
INSERT INTO "new_Barter" ("adminNote", "code", "consultantBranch", "consultantId", "consultantName", "createdAt", "id", "producerId", "producerName", "reviewedAt", "reviewedBy", "reviewedById", "status") SELECT "adminNote", "code", "sellerBranch", "sellerId", "sellerName", "createdAt", "id", "producerId", "producerName", "reviewedAt", "reviewedBy", "reviewedById", "status" FROM "Barter";
DROP TABLE "Barter";
ALTER TABLE "new_Barter" RENAME TO "Barter";
CREATE UNIQUE INDEX "Barter_code_key" ON "Barter"("code");

CREATE TABLE "new_Producer" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "name" TEXT NOT NULL,
    "consultantId" INTEGER,
    "document" TEXT NOT NULL,
    "phone" TEXT,
    "farmName" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "areaHa" REAL NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "Producer_consultantId_fkey" FOREIGN KEY ("consultantId") REFERENCES "User" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);
INSERT INTO "new_Producer" ("areaHa", "city", "consultantId", "createdAt", "document", "farmName", "id", "name", "phone", "updatedAt") SELECT "areaHa", "city", "sellerId", "createdAt", "document", "farmName", "id", "name", "phone", "updatedAt" FROM "Producer";
DROP TABLE "Producer";
ALTER TABLE "new_Producer" RENAME TO "Producer";

CREATE TABLE "new_User" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "fullName" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "password" TEXT NOT NULL,
    "role" TEXT NOT NULL DEFAULT 'consultant',
    "phone" TEXT,
    "branch" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    "mustChangePassword" BOOLEAN NOT NULL DEFAULT false
);
INSERT INTO "new_User" ("branch", "createdAt", "email", "fullName", "id", "mustChangePassword", "password", "phone", "role", "updatedAt") SELECT "branch", "createdAt", "email", "fullName", "id", "mustChangePassword", "password", "phone", "role", "updatedAt" FROM "User";
DROP TABLE "User";
ALTER TABLE "new_User" RENAME TO "User";
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;

-- Papel gravado nas linhas existentes: 'seller' -> 'consultant'.
UPDATE "User" SET "role" = 'consultant' WHERE "role" = 'seller';
