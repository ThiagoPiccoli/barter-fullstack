-- OS DOIS DOCUMENTOS QUE VOLTAM DE FORA.
--
-- O sistema gera a cédula e a devolve ao mundo; o que volta é papel assinado e,
-- depois, a via carimbada pelo registro. Enquanto eles não tinham onde ficar, a
-- permuta dizia "assinada" e "registrada" sem ter como provar nenhuma das duas —
-- o documento morava no e-mail de alguém.
--
-- Nuláveis, e sem migração de dados: as cédulas que já existem foram assinadas
-- antes de haver onde guardar o papel, e inventar um anexo para elas seria
-- inventar um documento.
ALTER TABLE "BarterCpr" ADD COLUMN     "signedFileId" INTEGER,
                        ADD COLUMN     "registryFileId" INTEGER;

-- 1-1 com o arquivo, como o SCR: um anexo tem um dono só.
CREATE UNIQUE INDEX "BarterCpr_signedFileId_key" ON "BarterCpr"("signedFileId");
CREATE UNIQUE INDEX "BarterCpr_registryFileId_key" ON "BarterCpr"("registryFileId");

-- SET NULL: apagar o arquivo não pode apagar a cédula.
ALTER TABLE "BarterCpr" ADD CONSTRAINT "BarterCpr_signedFileId_fkey" FOREIGN KEY ("signedFileId") REFERENCES "BarterFile"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "BarterCpr" ADD CONSTRAINT "BarterCpr_registryFileId_fkey" FOREIGN KEY ("registryFileId") REFERENCES "BarterFile"("id") ON DELETE SET NULL ON UPDATE CASCADE;
