-- A SEGURADORA entra na esteira: a permuta aprovada COM SEGURO passa pela mesa
-- dela antes do faturista, e ela informa a apólice — o documento e o número.
-- Os dois estados novos (`awaitingPolicy`, `awaitingPolicyWithConditions`) são
-- só valores de `Barter.status` (texto), e não precisam de coluna. O papel novo
-- (`insurer`) também não: `User.role` é texto.
--
-- O que muda no banco são três coisas, nesta ordem:
--
-- 1. a permuta ganha a ETAPA DA APÓLICE: o número, o arquivo e a assinatura de
--    quem os informou;
-- 2. o NÚMERO DA APÓLICE sai da cédula, onde o consultor o digitava, e vem para
--    a permuta — copiado ANTES de a coluna sair, para nenhuma cédula já
--    preenchida perder a alínea "j" da cláusula XVIII;
-- 3. o SEGURO deixa de ser exigência do comitê (`requiresInsurance`). A história
--    não se perde: cada rodada de exigências tem o evento `require` na linha do
--    tempo, com "Exigências: …, Seguro." por extenso.
--
-- As permutas que já estavam aprovadas não voltam à seguradora: elas seguem no
-- faturista, onde estavam. A etapa vale para o que for decidido daqui em diante.

-- AlterTable
ALTER TABLE "Barter" ADD COLUMN "insurancePolicyNumber" TEXT,
ADD COLUMN "insurancePolicyFileId" INTEGER,
ADD COLUMN "insuredBy" TEXT,
ADD COLUMN "insuredById" INTEGER,
ADD COLUMN "insuredAt" TIMESTAMP(3),
ADD COLUMN "insuranceNote" TEXT;

-- O número que o consultor tinha digitado na cédula vem para a permuta.
UPDATE "Barter" AS b
   SET "insurancePolicyNumber" = btrim(c."insurancePolicy")
  FROM "BarterCpr" AS c
 WHERE c."barterId" = b."id"
   AND btrim(coalesce(c."insurancePolicy", '')) <> '';

-- AlterTable
ALTER TABLE "BarterCpr" DROP COLUMN "insurancePolicy";

-- AlterTable
ALTER TABLE "Barter" DROP COLUMN "requiresInsurance";

-- CreateIndex
CREATE UNIQUE INDEX "Barter_insurancePolicyFileId_key" ON "Barter"("insurancePolicyFileId");

-- AddForeignKey
ALTER TABLE "Barter" ADD CONSTRAINT "Barter_insurancePolicyFileId_fkey" FOREIGN KEY ("insurancePolicyFileId") REFERENCES "BarterFile"("id") ON DELETE SET NULL ON UPDATE CASCADE;
