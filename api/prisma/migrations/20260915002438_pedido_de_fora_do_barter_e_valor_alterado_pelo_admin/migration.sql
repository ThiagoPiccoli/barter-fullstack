-- AlterTable
ALTER TABLE "BarterItem" ADD COLUMN     "listValue" DOUBLE PRECISION,
ADD COLUMN     "offBarter" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "requestId" INTEGER;

-- CreateTable
CREATE TABLE "BarterProductRequest" (
    "id" SERIAL NOT NULL,
    "barterId" INTEGER NOT NULL,
    "productName" TEXT NOT NULL,
    "unit" TEXT NOT NULL,
    "quantity" DOUBLE PRECISION NOT NULL,
    "sku" TEXT,
    "note" TEXT,
    "status" TEXT NOT NULL DEFAULT 'open',
    "requestedBy" TEXT NOT NULL,
    "requestedById" INTEGER,
    "requestedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "decidedBy" TEXT,
    "decidedById" INTEGER,
    "decidedAt" TIMESTAMP(3),
    "reply" TEXT,
    "unitValue" DOUBLE PRECISION,

    CONSTRAINT "BarterProductRequest_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "BarterProductRequest_status_requestedAt_idx" ON "BarterProductRequest"("status", "requestedAt");

-- CreateIndex
CREATE INDEX "BarterProductRequest_barterId_idx" ON "BarterProductRequest"("barterId");

-- CreateIndex
CREATE INDEX "BarterItem_requestId_idx" ON "BarterItem"("requestId");

-- AddForeignKey
ALTER TABLE "BarterItem" ADD CONSTRAINT "BarterItem_requestId_fkey" FOREIGN KEY ("requestId") REFERENCES "BarterProductRequest"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BarterProductRequest" ADD CONSTRAINT "BarterProductRequest_barterId_fkey" FOREIGN KEY ("barterId") REFERENCES "Barter"("id") ON DELETE CASCADE ON UPDATE CASCADE;
