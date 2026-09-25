-- O SEGURO DO PRODUTOR e o DOSSIÊ DO COMITÊ — duas peças que faltavam na mesa
-- de quem decide, e uma linha de custo que faltava na permuta.
--
-- O seguro é opcional e é decisão de LANÇAMENTO: o admin diz, ao publicar o
-- Barter, se aquela safra leva seguro; a base por município diz quanto custa o
-- hectare em cada praça; e a permuta pega a área do produtor e a taxa da praça
-- dele. O custo entra como qualquer insumo retirado — soma, vira sacas e
-- dimensiona o penhor —, porque é isso que ele é: dinheiro que a empresa
-- adianta e o produtor devolve na colheita.

-- A BASE POR MUNICÍPIO. Chave pelo município NORMALIZADO, pelo mesmo motivo de
-- `Unit.nameKey`: sobre o texto cru, "Campo Mourão/PR" e "campo mourao/pr"
-- seriam duas praças com dois preços, e a permuta acharia uma delas por acaso
-- de digitação.
--
-- Ela não entra no catálogo de produtos de propósito: o catálogo é a lista do
-- FORNECEDOR de insumos, e o seguro é contratado de uma seguradora, cotado por
-- região, sem unidade de venda. Posto lá, ele apareceria no seletor de insumos
-- do consultor — que é justamente onde ele não deve estar, porque não é ele
-- quem escolhe.
CREATE TABLE "InsuranceRate" (
    "id" SERIAL NOT NULL,
    "city" TEXT NOT NULL,
    "cityKey" TEXT NOT NULL,
    "valuePerHa" DOUBLE PRECISION NOT NULL,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InsuranceRate_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "InsuranceRate_cityKey_key" ON "InsuranceRate"("cityKey");

-- A CHAVE DO SEGURO, no lançamento, ao lado da cotação da saca e da
-- produtividade estimada — as três decisões comerciais do mesmo ato.
--
-- `false` nas versões já publicadas, e isso é a verdade sobre elas: foram
-- lançadas sem seguro, e ligá-lo retroativamente acrescentaria custo a permutas
-- já acordadas, aprovadas e faturadas.
ALTER TABLE "BarterVersion" ADD COLUMN "insuranceRequired" BOOLEAN NOT NULL DEFAULT false;

-- O SEGURO CONGELADO NA PERMUTA: o município que a precificou e a taxa do dia.
--
-- Snapshot pelo mesmo motivo de `taxRate`, `producerAreaHa` e das duas taxas do
-- penhor: a base por município é cadastro vivo e o produtor muda de praça
-- quando arrenda do outro lado do rio. Lidas na conferência, uma permuta já
-- encaminhada passaria a custar mais sacas do que as que o consultor combinou.
--
-- O CUSTO não vira coluna: ele é derivado, e mora na linha do seguro
-- (`BarterItem.insurance`), que é onde o custo da permuta mora inteiro.
-- `insuranceRatePerHa` 0 é "esta permuta não tem seguro" — o que dizem tanto as
-- anteriores à regra quanto as de um Barter lançado sem ele.
ALTER TABLE "Barter" ADD COLUMN     "insuranceCity" TEXT NOT NULL DEFAULT '',
                     ADD COLUMN     "insuranceRatePerHa" DOUBLE PRECISION NOT NULL DEFAULT 0;

-- AS EXIGÊNCIAS DO COMITÊ, que viviam dentro do texto da decisão.
--
-- "Exigir aval do cônjuge", "com avalista", "condicionada a aval" — a mesma
-- exigência escrita de três jeitos, em prosa, a cada reunião. Bastava para quem
-- lia a permuta e não bastava para mais nada: não havia como listar o que
-- estava pendente de aval, e a exigência esquecida no meio do parágrafo não era
-- esquecida por ninguém em particular.
--
-- O TEXTO continua obrigatório na ressalva: as caixas dizem O QUÊ, e só ele diz
-- QUAL — qual matrícula, qual valor segurado, quem se espera como avalista.
ALTER TABLE "Barter" ADD COLUMN     "requiresGuarantor" BOOLEAN NOT NULL DEFAULT false,
                     ADD COLUMN     "requiresCollateral" BOOLEAN NOT NULL DEFAULT false,
                     ADD COLUMN     "requiresInsurance" BOOLEAN NOT NULL DEFAULT false;

-- A MARCA DA LINHA DO SEGURO. Ela é `kind = 'input'` de propósito — `kind`
-- responde "forma custo ou paga a permuta?", e o seguro forma custo —, e esta
-- coluna é o que a explica no comprovante, como `offBarter` explica o item que
-- não está em tabela nenhuma.
ALTER TABLE "BarterItem" ADD COLUMN "insurance" BOOLEAN NOT NULL DEFAULT false;

-- O DOSSIÊ DO COMITÊ: a consulta ao Serasa, o endividamento do produtor dentro
-- da cooperativa, e o que mais a reunião tiver pedido.
--
-- Esses documentos existiam e não estavam aqui: circulavam por e-mail entre os
-- integrantes e morriam na caixa de quem convocou a reunião. Meses depois, "com
-- base em quê vocês aprovaram isto?" não tinha onde ser respondido — o registro
-- guardava a decisão e não guardava a prova.
--
-- `fileId` com Cascade (e não SetNull como o SCR): sem o documento esta peça não
-- é nada, enquanto a cédula sobrevive à perda do anexo com uma pendência a
-- mostrar. A leitura é RESTRITA ao comitê e ao admin — ver `bartersCreditRead`
-- em policy.ts.
CREATE TABLE "BarterCreditFile" (
    "id" SERIAL NOT NULL,
    "barterId" INTEGER NOT NULL,
    "kind" TEXT NOT NULL,
    "note" TEXT,
    "fileId" INTEGER NOT NULL,
    "attachedBy" TEXT NOT NULL,
    "attachedById" INTEGER,
    "attachedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BarterCreditFile_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "BarterCreditFile_fileId_key" ON "BarterCreditFile"("fileId");

CREATE INDEX "BarterCreditFile_barterId_idx" ON "BarterCreditFile"("barterId");

ALTER TABLE "BarterCreditFile" ADD CONSTRAINT "BarterCreditFile_barterId_fkey" FOREIGN KEY ("barterId") REFERENCES "Barter"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "BarterCreditFile" ADD CONSTRAINT "BarterCreditFile_fileId_fkey" FOREIGN KEY ("fileId") REFERENCES "BarterFile"("id") ON DELETE CASCADE ON UPDATE CASCADE;
