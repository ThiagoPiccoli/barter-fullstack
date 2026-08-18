-- A carteira deixa de ser uma COLUNA no produtor e passa a ser uma RELAÇÃO:
-- o mesmo produtor pode ser atendido por vários consultores (regiões
-- compartilhadas). Ver o comentário do model ProducerConsultant no schema.
--
-- A ORDEM aqui não é a que o `prisma migrate diff` gera, e a diferença é o
-- ponto desta migration: o diff dropa a coluna primeiro e a tabela nova nasce
-- vazia — sete produtores ficariam sem consultor nenhum, invisíveis para quem
-- os atende. Aqui a tabela nasce, os vínculos existentes são COPIADOS para
-- dentro dela, e só então a coluna sai.

-- CreateTable
CREATE TABLE "ProducerConsultant" (
    "producerId" INTEGER NOT NULL,
    "consultantId" INTEGER NOT NULL,
    "assignedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProducerConsultant_pkey" PRIMARY KEY ("producerId","consultantId")
);

-- CreateIndex
CREATE INDEX "ProducerConsultant_consultantId_idx" ON "ProducerConsultant"("consultantId");

-- AddForeignKey
ALTER TABLE "ProducerConsultant" ADD CONSTRAINT "ProducerConsultant_producerId_fkey" FOREIGN KEY ("producerId") REFERENCES "Producer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ProducerConsultant" ADD CONSTRAINT "ProducerConsultant_consultantId_fkey" FOREIGN KEY ("consultantId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- A carteira que já existia vira o primeiro vínculo de cada produtor.
-- `assignedAt` recebe a data de cadastro do produtor: o vínculo é tão antigo
-- quanto ele, e usar CURRENT_TIMESTAMP diria que a operação inteira começou no
-- dia do deploy. Produtor com `consultantId` nulo (consultor excluído antes
-- desta migration) continua sem vínculo, esperando realocação.
INSERT INTO "ProducerConsultant" ("producerId", "consultantId", "assignedAt")
SELECT "id", "consultantId", "createdAt"
FROM "Producer"
WHERE "consultantId" IS NOT NULL;

-- DropForeignKey
ALTER TABLE "Producer" DROP CONSTRAINT "Producer_consultantId_fkey";

-- AlterTable
ALTER TABLE "Producer" DROP COLUMN "consultantId";
