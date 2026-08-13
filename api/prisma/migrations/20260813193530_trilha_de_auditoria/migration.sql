-- CreateTable
CREATE TABLE "AuditLog" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "actorId" INTEGER,
    "actorName" TEXT NOT NULL,
    "actorRole" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "targetType" TEXT NOT NULL,
    "targetId" INTEGER,
    "targetLabel" TEXT NOT NULL,
    "detail" TEXT,
    "at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_Producer" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "name" TEXT NOT NULL,
    "consultantId" INTEGER,
    "document" TEXT NOT NULL,
    "documentDigits" TEXT NOT NULL,
    "phone" TEXT,
    "farmName" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "areaHa" REAL NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "Producer_consultantId_fkey" FOREIGN KEY ("consultantId") REFERENCES "User" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);
INSERT INTO "new_Producer" ("areaHa", "city", "consultantId", "createdAt", "document", "documentDigits", "farmName", "id", "name", "phone", "updatedAt") SELECT "areaHa", "city", "consultantId", "createdAt", "document", "documentDigits", "farmName", "id", "name", "phone", "updatedAt" FROM "Producer";
DROP TABLE "Producer";
ALTER TABLE "new_Producer" RENAME TO "Producer";
CREATE UNIQUE INDEX "Producer_documentDigits_key" ON "Producer"("documentDigits");
PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;

-- CreateIndex
CREATE INDEX "AuditLog_at_idx" ON "AuditLog"("at");

-- CreateIndex
CREATE INDEX "AuditLog_targetType_targetId_idx" ON "AuditLog"("targetType", "targetId");
