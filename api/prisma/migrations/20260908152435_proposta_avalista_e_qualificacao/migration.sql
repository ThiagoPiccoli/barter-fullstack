-- AlterTable
ALTER TABLE "BarterCpr" ADD COLUMN     "deliveryPlace" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "emitterCnh" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "emitterEmail" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "emitterFatherName" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "emitterMotherName" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "mortgages" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "spouseRg" TEXT;

-- CreateTable
CREATE TABLE "CprGuarantor" (
    "id" SERIAL NOT NULL,
    "cprId" INTEGER NOT NULL,
    "position" INTEGER NOT NULL DEFAULT 0,
    "name" TEXT NOT NULL DEFAULT '',
    "document" TEXT NOT NULL DEFAULT '',
    "rg" TEXT NOT NULL DEFAULT '',
    "cnh" TEXT NOT NULL DEFAULT '',
    "nationality" TEXT NOT NULL DEFAULT '',
    "profession" TEXT NOT NULL DEFAULT '',
    "maritalStatus" TEXT NOT NULL DEFAULT '',
    "fatherName" TEXT NOT NULL DEFAULT '',
    "motherName" TEXT NOT NULL DEFAULT '',
    "email" TEXT NOT NULL DEFAULT '',
    "address" TEXT NOT NULL DEFAULT '',
    "addressNumber" TEXT NOT NULL DEFAULT '',
    "city" TEXT NOT NULL DEFAULT '',
    "spouseName" TEXT NOT NULL DEFAULT '',
    "spouseDocument" TEXT NOT NULL DEFAULT '',
    "spouseRg" TEXT NOT NULL DEFAULT '',
    "spouseNationality" TEXT NOT NULL DEFAULT '',
    "spouseProfession" TEXT NOT NULL DEFAULT '',

    CONSTRAINT "CprGuarantor_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "CprGuarantor_cprId_position_idx" ON "CprGuarantor"("cprId", "position");

-- AddForeignKey
ALTER TABLE "CprGuarantor" ADD CONSTRAINT "CprGuarantor_cprId_fkey" FOREIGN KEY ("cprId") REFERENCES "BarterCpr"("id") ON DELETE CASCADE ON UPDATE CASCADE;
