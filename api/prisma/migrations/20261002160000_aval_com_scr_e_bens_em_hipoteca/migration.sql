-- O AVALISTA ganha SCR próprio, e a HIPOTECA deixa de ser texto livre na
-- cédula: cada bem dado em hipoteca vira um cadastro (`CprMortgage`) com o
-- documento anexado.
--
-- A ORDEM importa: a tabela nova nasce, o texto que já existia vira um bem
-- (com o texto inteiro na descrição — os outros campos ficam em branco e a
-- cédula passa a cobrá-los, que é a verdade), e só então a coluna sai.

-- AlterTable
ALTER TABLE "CprGuarantor" ADD COLUMN "scrFileId" INTEGER;

-- CreateTable
CREATE TABLE "CprMortgage" (
    "id" SERIAL NOT NULL,
    "cprId" INTEGER NOT NULL,
    "position" INTEGER NOT NULL DEFAULT 0,
    "description" TEXT NOT NULL DEFAULT '',
    "registryNumber" TEXT NOT NULL DEFAULT '',
    "registryDistrict" TEXT NOT NULL DEFAULT '',
    "city" TEXT NOT NULL DEFAULT '',
    "ownerName" TEXT NOT NULL DEFAULT '',
    "ownerDocument" TEXT NOT NULL DEFAULT '',
    "appraisedValue" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "documentFileId" INTEGER,

    CONSTRAINT "CprMortgage_pkey" PRIMARY KEY ("id")
);

-- O texto livre de antes vira o primeiro bem de cada cédula que o tinha.
INSERT INTO "CprMortgage" ("cprId", "position", "description")
SELECT "id", 0, btrim("mortgages")
FROM "BarterCpr"
WHERE btrim("mortgages") <> '';

-- AlterTable
ALTER TABLE "BarterCpr" DROP COLUMN "mortgages";

-- CreateIndex
CREATE UNIQUE INDEX "CprGuarantor_scrFileId_key" ON "CprGuarantor"("scrFileId");

-- CreateIndex
CREATE UNIQUE INDEX "CprMortgage_documentFileId_key" ON "CprMortgage"("documentFileId");

-- CreateIndex
CREATE INDEX "CprMortgage_cprId_position_idx" ON "CprMortgage"("cprId", "position");

-- AddForeignKey
ALTER TABLE "CprGuarantor" ADD CONSTRAINT "CprGuarantor_scrFileId_fkey" FOREIGN KEY ("scrFileId") REFERENCES "BarterFile"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CprMortgage" ADD CONSTRAINT "CprMortgage_cprId_fkey" FOREIGN KEY ("cprId") REFERENCES "BarterCpr"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CprMortgage" ADD CONSTRAINT "CprMortgage_documentFileId_fkey" FOREIGN KEY ("documentFileId") REFERENCES "BarterFile"("id") ON DELETE SET NULL ON UPDATE CASCADE;
