-- A LINHA DE PRODUÇÃO da permuta ganha os dois últimos postos:
--
--     sentToManager → pending → approved → invoiced
--      (gerente)     (comitê)  (faturista)
--                        ↘ denied
--
-- Quem decide passou a ser o COMITÊ (o admin administra o sistema e não decide
-- negócio), e o FATURISTA fatura o que foi aprovado. Ver
-- `src/barters/barter-workflow.ts`, que é onde o caminho está escrito.

-- A decisão não é mais do admin, e o campo deixa de dizer que é. RENAME, e não
-- coluna nova + cópia: o texto é o mesmo dado, e duplicá-lo deixaria duas
-- versões do mesmo parecer podendo divergir.
ALTER TABLE "Barter" RENAME COLUMN "adminNote" TO "reviewNote";

-- O FATURAMENTO. Tudo nulável: as permutas existentes não foram faturadas, e
-- nulo aqui é exatamente isso — não há valor a inventar para elas.
ALTER TABLE "Barter" ADD COLUMN "invoicedBy" TEXT,
ADD COLUMN "invoicedById" INTEGER,
ADD COLUMN "invoicedAt" TIMESTAMP(3),
ADD COLUMN "invoiceNote" TEXT;

-- As filas do comitê e do faturista não têm destinatário: quem as define é o
-- ESTADO ("as que esperam decisão", "as aprovadas a faturar"), e é esta a
-- consulta que as duas telas fazem o tempo todo.
CREATE INDEX "Barter_status_createdAt_idx" ON "Barter"("status", "createdAt");

-- O HISTÓRICO da permuta — cada passagem de um estado para o outro, gravada na
-- mesma transação da mudança. Ver o comentário do model no schema.
CREATE TABLE "BarterEvent" (
    "id" SERIAL NOT NULL,
    "barterId" INTEGER NOT NULL,
    "action" TEXT NOT NULL,
    "fromStatus" TEXT,
    "toStatus" TEXT NOT NULL,
    "actorId" INTEGER,
    "actorName" TEXT NOT NULL,
    "actorRole" TEXT NOT NULL,
    "note" TEXT,
    "at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BarterEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "BarterEvent_barterId_at_idx" ON "BarterEvent"("barterId", "at");

-- AddForeignKey
ALTER TABLE "BarterEvent" ADD CONSTRAINT "BarterEvent_barterId_fkey" FOREIGN KEY ("barterId") REFERENCES "Barter"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- O histórico das permutas que JÁ EXISTEM, reconstruído do que a própria linha
-- guarda: o registro (createdAt), o parecer (managerReviewedAt) e a decisão
-- (reviewedAt). Nada é inventado — cada evento abaixo só existe se a permuta
-- tiver a data correspondente preenchida, e o texto é o que já estava lá.
--
-- Sem isto, toda permuta anterior a esta migration abriria com a linha do tempo
-- vazia, e a tela do faturista — que existe para mostrar o que as etapas
-- anteriores produziram — não teria o que mostrar justamente nas mais antigas.
--
-- `actorRole` sai da conta de quem agiu, lida AGORA: é a melhor aproximação
-- disponível, e fica vazio quando a conta não existe mais. Nas decisões antigas
-- ele dirá `admin`, porque foi o admin quem as tomou — o papel mudou daqui em
-- diante, e reescrever o passado para "committee" seria falsificá-lo.
-- O estado em que a permuta NASCEU: `sentToManager` para as que têm gerente
-- destinatário, e `pending` para as anteriores à etapa do gerente — que nunca
-- estiveram em `sentToManager` e entraram direto na fila de decisão (ver a
-- migration 20260817025307).
INSERT INTO "BarterEvent" ("barterId", "action", "fromStatus", "toStatus", "actorId", "actorName", "actorRole", "note", "at")
SELECT b."id", 'register', NULL,
       CASE WHEN b."managerId" IS NULL THEN 'pending' ELSE 'sentToManager' END,
       b."consultantId", b."consultantName", COALESCE(u."role", ''), NULL, b."createdAt"
FROM "Barter" b LEFT JOIN "User" u ON u."id" = b."consultantId";

INSERT INTO "BarterEvent" ("barterId", "action", "fromStatus", "toStatus", "actorId", "actorName", "actorRole", "note", "at")
SELECT b."id", 'opinion', 'sentToManager', 'pending', b."managerId", COALESCE(b."managerName", ''), COALESCE(u."role", ''), b."managerNote", b."managerReviewedAt"
FROM "Barter" b LEFT JOIN "User" u ON u."id" = b."managerId"
WHERE b."managerReviewedAt" IS NOT NULL;

INSERT INTO "BarterEvent" ("barterId", "action", "fromStatus", "toStatus", "actorId", "actorName", "actorRole", "note", "at")
SELECT b."id", 'review', 'pending', b."status", b."reviewedById", COALESCE(b."reviewedBy", ''), COALESCE(u."role", ''), b."reviewNote", b."reviewedAt"
FROM "Barter" b LEFT JOIN "User" u ON u."id" = b."reviewedById"
WHERE b."reviewedAt" IS NOT NULL AND b."status" IN ('approved', 'denied');
