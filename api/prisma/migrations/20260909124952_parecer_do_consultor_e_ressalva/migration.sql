-- AlterTable
ALTER TABLE "Barter" ADD COLUMN     "consultantNote" TEXT,
ADD COLUMN     "consultantSentAt" TIMESTAMP(3),
ADD COLUMN     "producerAreaHa" DOUBLE PRECISION NOT NULL DEFAULT 0,
ALTER COLUMN "status" SET DEFAULT 'draft';

-- A ÁREA das permutas que já existem: a do cadastro do produtor, hoje.
--
-- É uma aproximação, e a única disponível — a área não era gravada na permuta.
-- Ela erra para o produtor que arrendou terra depois do registro, e acerta em
-- todos os outros; o zero, que é a alternativa, faria o sc/ha sumir de toda a
-- base histórica. Daqui para a frente o número é congelado no registro.
UPDATE "Barter" b
SET "producerAreaHa" = p."areaHa"
FROM "Producer" p
WHERE b."producerId" = p."id";

-- O ENCAMINHAMENTO das permutas que já existem é o registro delas.
--
-- Não é conveniência: no fluxo anterior, registrar ERA encaminhar — a permuta
-- nascia em `sentToManager`, na mesa do gerente. A data é a mesma, e afirmá-la
-- é dizer o que de fato aconteceu. O `consultantNote` fica NULL de propósito:
-- parecer nenhum foi escrito, e preenchê-lo seria assinar em nome de alguém.
UPDATE "Barter" SET "consultantSentAt" = "createdAt" WHERE "consultantSentAt" IS NULL;
