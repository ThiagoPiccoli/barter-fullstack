-- A EMISSÃO DA CPR como etapa, as NOTAS do faturamento como anexo e o SCR do
-- produtor na cédula.
--
-- Três mudanças de dono viajam juntas nesta migration, porque elas são uma só
-- decisão: a cédula deixou de ser trabalho do faturista.
--
-- 1. o VENCIMENTO da CPR sai do formulário e vira cadastro da SAFRA — ele muda
--    conforme a cultura, e é o mesmo para todas as cédulas de uma safra;
-- 2. o NÚMERO DA NOTA e o da DUPLICATA saem da cédula e viram `BarterInvoice`,
--    com o arquivo junto e em lista: uma permuta sai em vários carregamentos;
-- 3. a EMISSÃO ganha três estados na esteira (`cprIssued`, `cprSigned`,
--    `cprRegistered`), com o EMISSOR como dono.
--
-- Nada é apagado sem destino: os números de nota e duplicata já gravados nas
-- cédulas viram a primeira `BarterInvoice` da permuta, SEM arquivo — o registro
-- histórico sobrevive, e a pendência do anexo aparece na tela de quem pode
-- resolvê-la. Ver o bloco marcado ⟨MIGRAÇÃO DE DADOS⟩ abaixo.

-- AlterTable: o vencimento da CPR passa a ser da SAFRA (a cultura + o ano).
ALTER TABLE "Season" ADD COLUMN     "cprDueDate" TIMESTAMP(3);

-- AlterTable: as marcas dos três atos do emissor, ao lado das do faturamento.
ALTER TABLE "Barter" ADD COLUMN     "cprEmissionNote" TEXT,
ADD COLUMN     "cprEmittedAt" TIMESTAMP(3),
ADD COLUMN     "cprEmittedBy" TEXT,
ADD COLUMN     "cprEmittedById" INTEGER,
ADD COLUMN     "cprRegisteredAt" TIMESTAMP(3),
ADD COLUMN     "cprRegistryNumber" TEXT,
ADD COLUMN     "cprRegistryPlace" TEXT,
ADD COLUMN     "cprSignatureNote" TEXT,
ADD COLUMN     "cprSignedAt" TIMESTAMP(3);

-- CreateTable: o arquivo anexado, com o conteúdo no banco.
--
-- Tabela à parte da nota de propósito: `BYTEA` numa tabela lida em lista viria
-- junto em toda consulta, e a listagem de permutas carregaria megabytes de PDF
-- para desenhar uma linha de tabela.
CREATE TABLE "BarterFile" (
    "id" SERIAL NOT NULL,
    "fileName" TEXT NOT NULL,
    "contentType" TEXT NOT NULL,
    "size" INTEGER NOT NULL,
    "content" BYTEA NOT NULL,
    "uploadedBy" TEXT NOT NULL,
    "uploadedById" INTEGER,
    "uploadedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BarterFile_pkey" PRIMARY KEY ("id")
);

-- CreateTable: a nota fiscal do faturamento.
--
-- `fileId` é nulável AQUI e obrigatório no schema — a diferença dura o tempo
-- desta migration: as notas herdadas da cédula antiga não têm arquivo, e
-- recusá-las apagaria o número que alguém digitou. Ver ⟨MIGRAÇÃO DE DADOS⟩ e a
-- trava no fim do arquivo.
CREATE TABLE "BarterInvoice" (
    "id" SERIAL NOT NULL,
    "barterId" INTEGER NOT NULL,
    "number" TEXT NOT NULL,
    "series" TEXT NOT NULL DEFAULT '',
    "duplicateNumber" TEXT NOT NULL DEFAULT '',
    "issuedAt" TIMESTAMP(3),
    "value" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "note" TEXT,
    "fileId" INTEGER,
    "attachedBy" TEXT NOT NULL,
    "attachedById" INTEGER,
    "attachedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BarterInvoice_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "BarterInvoice_fileId_key" ON "BarterInvoice"("fileId");

-- CreateIndex
CREATE INDEX "BarterInvoice_barterId_idx" ON "BarterInvoice"("barterId");

-- AddForeignKey
ALTER TABLE "BarterInvoice" ADD CONSTRAINT "BarterInvoice_barterId_fkey" FOREIGN KEY ("barterId") REFERENCES "Barter"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BarterInvoice" ADD CONSTRAINT "BarterInvoice_fileId_fkey" FOREIGN KEY ("fileId") REFERENCES "BarterFile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AlterTable: o SCR do produtor na cédula.
ALTER TABLE "BarterCpr" ADD COLUMN     "scrConsultedAt" TIMESTAMP(3),
ADD COLUMN     "scrFileId" INTEGER;

-- CreateIndex
CREATE UNIQUE INDEX "BarterCpr_scrFileId_key" ON "BarterCpr"("scrFileId");

-- AddForeignKey
ALTER TABLE "BarterCpr" ADD CONSTRAINT "BarterCpr_scrFileId_fkey" FOREIGN KEY ("scrFileId") REFERENCES "BarterFile"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- ⟨MIGRAÇÃO DE DADOS⟩ ────────────────────────────────────────────────────────
-- A nota que estava DENTRO da cédula vira a primeira nota da permuta.
--
-- Só onde havia número: cédula com o campo em branco não produz nota nenhuma —
-- inventar uma linha vazia seria afirmar um faturamento que ninguém registrou.
-- `attachedBy` herda `filledBy`, que é quem de fato digitou aquele número.
INSERT INTO "BarterInvoice" ("barterId", "number", "duplicateNumber", "attachedBy", "attachedById", "attachedAt")
SELECT "barterId", "invoiceNumber", "duplicateNumber", "filledBy", "filledById", "updatedAt"
FROM "BarterCpr"
WHERE btrim("invoiceNumber") <> '';

-- O VENCIMENTO que estava em cada cédula sobe para a SAFRA dela.
--
-- A data escolhida é a MAIS USADA entre as cédulas daquela safra (e, no empate,
-- a mais recente): é a que a operação de fato praticou. As cédulas continuam com
-- a data que tinham — `BarterCpr.dueDate` não é apagado —, e a partir de agora é
-- a safra quem a escreve.
UPDATE "Season" AS s
SET "cprDueDate" = escolhida."dueDate"
FROM (
    SELECT DISTINCT ON (v."seasonId") v."seasonId", c."dueDate"
    FROM "BarterCpr" c
    JOIN "Barter" b ON b."id" = c."barterId"
    JOIN "BarterVersion" v ON v."id" = b."versionId"
    WHERE c."dueDate" IS NOT NULL
    GROUP BY v."seasonId", c."dueDate"
    ORDER BY v."seasonId", count(*) DESC, c."dueDate" DESC
) AS escolhida
WHERE s."id" = escolhida."seasonId";

-- AS PERMUTAS JÁ FATURADAS continuam onde estavam.
--
-- `invoiced` deixou de ser fim de linha, e isso é o certo para elas também: a
-- cédula delas ou não existe, ou existe e não foi emitida por este fluxo. Elas
-- aparecem na fila do emissor, que é exatamente o trabalho que estava invisível.
-- Nenhum UPDATE aqui, portanto — o estado delas já é o correto.

-- AlterTable: os campos que saíram da cédula.
--
-- POR ÚLTIMO, depois de os dados terem destino: o número da nota e o da
-- duplicata agora moram em `BarterInvoice`.
ALTER TABLE "BarterCpr" DROP COLUMN "invoiceNumber",
DROP COLUMN "duplicateNumber";
