-- AlterTable
ALTER TABLE "BarterVersion" ADD COLUMN     "closeOnGoal" BOOLEAN NOT NULL DEFAULT false;

-- O PADRÃO É MANUAL de propósito, e não por conservadorismo de migration: é o
-- comportamento que todas as versões já publicadas tiveram. Ligar o automático
-- aqui reescreveria a história — versões cuja meta foi batida e que seguiram
-- abertas por decisão de alguém apareceriam como "deveriam ter fechado".
