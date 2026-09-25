-- O PEDIDO DE ALTERAÇÃO — o caminho de volta da esteira, que ela não tinha.
--
-- Sete colunas e nenhuma tabela nova: o que a operação pergunta é se ESTA
-- permuta tem um pedido em aberto agora, e a história de todos eles já é
-- gravada em "BarterEvent". Ver `src/barters/change-request.ts`.
--
-- Todas nulas nas permutas existentes, e é a verdade sobre elas: ninguém pediu
-- alteração de nada até hoje, porque não havia como pedir.
-- AlterTable
ALTER TABLE "Barter" ADD COLUMN     "changeRequestAt" TIMESTAMP(3),
ADD COLUMN     "changeRequestBy" TEXT,
ADD COLUMN     "changeRequestById" INTEGER,
ADD COLUMN     "changeRequestFrom" TEXT,
ADD COLUMN     "changeRequestNote" TEXT,
ADD COLUMN     "changeRequestReply" TEXT,
ADD COLUMN     "changeRequestStatus" TEXT;

-- O CÓDIGO do produto congelado no item, ao lado do nome e do preço.
--
-- NULO nos itens já gravados, e de propósito: o código que o produto tem HOJE
-- não é necessariamente o que ele tinha quando a permuta foi fechada, e
-- preencher a coluna com ele transformaria um palpite em snapshot — que é
-- exatamente o que esta coluna existe para impedir. As telas caem no código
-- atual do catálogo quando o item não tem o seu, e aí o número está sendo LIDO
-- do cadastro, não afirmado pelo registro.
-- AlterTable
ALTER TABLE "BarterItem" ADD COLUMN     "productSku" TEXT;

-- O REGIME DE RECOLHIMENTO no cadastro do produtor.
--
-- O padrão é `comercializacao` porque é o regime de quem não fez a opção formal
-- pela folha — a maioria —, e é o que os cadastros existentes de fato têm: até
-- aqui a pergunta era feita permuta a permuta e o padrão dela era este mesmo.
-- AlterTable
ALTER TABLE "Producer" ADD COLUMN     "taxRegime" TEXT NOT NULL DEFAULT 'comercializacao';

-- A fila do admin: os pedidos em aberto, na ordem em que chegaram.
-- CreateIndex
CREATE INDEX "Barter_changeRequestStatus_changeRequestAt_idx" ON "Barter"("changeRequestStatus", "changeRequestAt");
