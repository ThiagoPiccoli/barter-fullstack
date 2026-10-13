-- A carteira volta a ser uma COLUNA no produtor: a regra passou a ser um
-- consultor por produtor. É o caminho inverso de 20260818141058, e com o mesmo
-- cuidado de ordem: a coluna nasce, cada produtor recebe o seu consultor, e só
-- então a tabela de vínculos sai. O `prisma migrate diff` faria o contrário e
-- deixaria todo produtor sem consultor.
--
-- QUEM FICA com o produtor que hoje está em mais de uma carteira:
--
--   1. o consultor que registrou a permuta MAIS RECENTE para ele — é quem está
--      atendendo o cliente agora;
--   2. nenhum dos vinculados permutou com ele: o vínculo MAIS ANTIGO — o dono
--      original, já que o compartilhamento é o que veio depois;
--   3. empate (mesmo `assignedAt`, comum nos vínculos copiados pela migration
--      de agosto): o menor id. Arbitrário, mas determinístico — rodar de novo
--      dá o mesmo resultado.
--
-- Só contam permutas registradas por um consultor AINDA VINCULADO: quem já saiu
-- da carteira não volta para ela por causa de uma permuta antiga.
--
-- Quem perde o produtor NÃO perde as permutas dele: elas são de quem as
-- registrou (`Barter.consultantId`), e a visibilidade e os atos sobre elas não
-- passam pela carteira. Ele deixa de ver o cadastro e de registrar permuta nova
-- para esse cliente — que é a regra.

-- AlterTable
ALTER TABLE "Producer" ADD COLUMN "consultantId" INTEGER;

UPDATE "Producer" p
SET "consultantId" = escolhido."consultantId"
FROM (
  SELECT DISTINCT ON (pc."producerId") pc."producerId", pc."consultantId"
  FROM "ProducerConsultant" pc
  LEFT JOIN LATERAL (
    SELECT max(b."createdAt") AS "lastBarterAt"
    FROM "Barter" b
    WHERE b."producerId" = pc."producerId" AND b."consultantId" = pc."consultantId"
  ) ultima ON true
  ORDER BY pc."producerId", ultima."lastBarterAt" DESC NULLS LAST, pc."assignedAt" ASC, pc."consultantId" ASC
) escolhido
WHERE escolhido."producerId" = p."id";

-- CreateIndex
CREATE INDEX "Producer_consultantId_idx" ON "Producer"("consultantId");

-- AddForeignKey
ALTER TABLE "Producer" ADD CONSTRAINT "Producer_consultantId_fkey" FOREIGN KEY ("consultantId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- DropTable
DROP TABLE "ProducerConsultant";
