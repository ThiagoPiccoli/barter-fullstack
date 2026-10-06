-- AS EXIGÊNCIAS DO COMITÊ viram etapa: o comitê pede avalista, hipoteca e/ou
-- seguro, a permuta volta ao consultor (`awaitingRequirements`) e, cumpridas,
-- retorna direto ao comitê. O estado novo é só um valor de `Barter.status`
-- (texto), e não precisa de coluna.
--
-- O que precisa de tabela é o AVISO: o gerente não age no desvio, mas precisa
-- saber que a permuta do time dele voltou ao consultor e, depois, ao comitê.

-- CreateTable
CREATE TABLE "Notice" (
    "id" SERIAL NOT NULL,
    "userId" INTEGER NOT NULL,
    "barterId" INTEGER,
    "barterCode" TEXT NOT NULL DEFAULT '',
    "message" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "readAt" TIMESTAMP(3),

    CONSTRAINT "Notice_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Notice_userId_readAt_idx" ON "Notice"("userId", "readAt");

-- AddForeignKey
ALTER TABLE "Notice" ADD CONSTRAINT "Notice_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Notice" ADD CONSTRAINT "Notice_barterId_fkey" FOREIGN KEY ("barterId") REFERENCES "Barter"("id") ON DELETE CASCADE ON UPDATE CASCADE;
