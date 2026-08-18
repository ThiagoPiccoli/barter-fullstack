-- O novo padrão de `status` vale para as permutas que NASCEREM daqui em diante.
-- As que já existem continuam onde estão (pending/approved/denied), que é o
-- correto: elas já passaram da etapa do gerente — que não existia — e voltá-las
-- para `sentToManager` inventaria uma fila de parecer sobre acordos fechados.
-- Elas ficam sem unidade de retirada (unitName ''), e o app mostra "—".

-- AlterTable
ALTER TABLE "Barter" ADD COLUMN     "managerId" INTEGER,
ADD COLUMN     "managerName" TEXT,
ADD COLUMN     "managerNote" TEXT,
ADD COLUMN     "managerReviewedAt" TIMESTAMP(3),
ADD COLUMN     "unitId" INTEGER,
ADD COLUMN     "unitName" TEXT NOT NULL DEFAULT '',
ALTER COLUMN "status" SET DEFAULT 'sentToManager';

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "managerId" INTEGER,
ADD COLUMN     "unitId" INTEGER;

-- CreateTable
CREATE TABLE "Unit" (
    "id" SERIAL NOT NULL,
    "name" TEXT NOT NULL,
    "nameKey" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Unit_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Unit_nameKey_key" ON "Unit"("nameKey");

-- CreateIndex
CREATE INDEX "Barter_unitId_idx" ON "Barter"("unitId");

-- CreateIndex
CREATE INDEX "Barter_managerId_status_idx" ON "Barter"("managerId", "status");

-- CreateIndex
CREATE INDEX "User_managerId_idx" ON "User"("managerId");

-- AddForeignKey
ALTER TABLE "User" ADD CONSTRAINT "User_unitId_fkey" FOREIGN KEY ("unitId") REFERENCES "Unit"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "User" ADD CONSTRAINT "User_managerId_fkey" FOREIGN KEY ("managerId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Barter" ADD CONSTRAINT "Barter_unitId_fkey" FOREIGN KEY ("unitId") REFERENCES "Unit"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Barter" ADD CONSTRAINT "Barter_managerId_fkey" FOREIGN KEY ("managerId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
