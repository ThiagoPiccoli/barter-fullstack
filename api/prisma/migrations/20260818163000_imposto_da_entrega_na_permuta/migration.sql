-- O IMPOSTO DA ENTREGA (Funrural/Senar) na permuta: a forma de recolhimento
-- escolhida no fechamento e a alíquota que ela produziu.
-- Ver `src/barters/tax-regime.ts` para o porquê de cada um.

-- `comercializacao` é o padrão porque é o que vale para quem não fez a opção
-- formal pela folha — nas permutas antigas ele diz o que teria sido aplicado,
-- e é `taxRate` (abaixo) que separa "aplicado" de "não houve".
ALTER TABLE "Barter" ADD COLUMN "taxRegime" TEXT NOT NULL DEFAULT 'comercializacao';

-- As permutas ANTIGAS ficam com alíquota 0, e de propósito: elas foram fechadas
-- antes de o sistema perguntar a forma de recolhimento, então não existe
-- alíquota que tenha sido aplicada a elas. Preencher com a de hoje faria o
-- comprovante afirmar um imposto que não foi combinado — e as telas leem o 0
-- justamente para omitir a linha nesses casos.
ALTER TABLE "Barter" ADD COLUMN "taxRate" DOUBLE PRECISION NOT NULL DEFAULT 0;
