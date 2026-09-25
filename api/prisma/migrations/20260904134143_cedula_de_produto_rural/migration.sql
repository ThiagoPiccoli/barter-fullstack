-- CreateTable
CREATE TABLE "BarterCpr" (
    "id" SERIAL NOT NULL,
    "barterId" INTEGER NOT NULL,
    "number" TEXT NOT NULL DEFAULT '',
    "issuedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "dueDate" TIMESTAMP(3),
    "emitterNationality" TEXT NOT NULL DEFAULT '',
    "emitterMaritalStatus" TEXT NOT NULL DEFAULT '',
    "emitterProfession" TEXT NOT NULL DEFAULT '',
    "emitterRg" TEXT NOT NULL DEFAULT '',
    "emitterAddress" TEXT NOT NULL DEFAULT '',
    "emitterAddressNumber" TEXT NOT NULL DEFAULT '',
    "emitterCity" TEXT NOT NULL DEFAULT '',
    "emitterCoopId" TEXT,
    "spouseName" TEXT,
    "spouseNationality" TEXT,
    "spouseProfession" TEXT,
    "spouseDocument" TEXT,
    "sackWeightKg" DOUBLE PRECISION NOT NULL DEFAULT 60,
    "cultivar" TEXT NOT NULL DEFAULT '',
    "maxMoisture" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "maxImpurities" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "oilContent" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "invoiceNumber" TEXT NOT NULL DEFAULT '',
    "duplicateNumber" TEXT NOT NULL DEFAULT '',
    "insurancePolicy" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "filledBy" TEXT NOT NULL,
    "filledById" INTEGER,

    CONSTRAINT "BarterCpr_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CprArea" (
    "id" SERIAL NOT NULL,
    "cprId" INTEGER NOT NULL,
    "position" INTEGER NOT NULL DEFAULT 0,
    "locality" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "areaHa" DOUBLE PRECISION NOT NULL,
    "withinLargerArea" BOOLEAN NOT NULL DEFAULT false,
    "registryNumber" TEXT NOT NULL,
    "registryBook" TEXT NOT NULL,
    "registryDistrict" TEXT NOT NULL,

    CONSTRAINT "CprArea_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CprAreaOwner" (
    "id" SERIAL NOT NULL,
    "areaId" INTEGER NOT NULL,
    "position" INTEGER NOT NULL DEFAULT 0,
    "name" TEXT NOT NULL,
    "document" TEXT NOT NULL,

    CONSTRAINT "CprAreaOwner_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "BarterCpr_barterId_key" ON "BarterCpr"("barterId");

-- CreateIndex
CREATE INDEX "CprArea_cprId_position_idx" ON "CprArea"("cprId", "position");

-- CreateIndex
CREATE INDEX "CprAreaOwner_areaId_position_idx" ON "CprAreaOwner"("areaId", "position");

-- AddForeignKey
ALTER TABLE "BarterCpr" ADD CONSTRAINT "BarterCpr_barterId_fkey" FOREIGN KEY ("barterId") REFERENCES "Barter"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CprArea" ADD CONSTRAINT "CprArea_cprId_fkey" FOREIGN KEY ("cprId") REFERENCES "BarterCpr"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CprAreaOwner" ADD CONSTRAINT "CprAreaOwner_areaId_fkey" FOREIGN KEY ("areaId") REFERENCES "CprArea"("id") ON DELETE CASCADE ON UPDATE CASCADE;
