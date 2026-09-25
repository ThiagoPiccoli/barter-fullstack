-- O PENHOR — a área de lavoura que garante a venda, dimensionada em vez de
-- apenas exigida.
--
-- A regra "ao menos uma lavoura" já existia em `cprGaps()`, e ela respondia
-- "existe garantia?" sem responder "garantia de quanto?". Uma permuta de 3.000
-- sacas passava com uma matrícula de 4 ha anotada. Agora a conta é:
--
--     área exigida = (sacas ÷ produtividade estimada) × (1 + margem de segurança)
--
-- e cada uma das três parcelas ganha aqui o seu lugar.

-- A PRODUTIVIDADE, na versão — ao lado de `grainPrice`, porque é a outra metade
-- da mesma conversão: o preço leva o custo a sacas, a produtividade leva as
-- sacas a hectares.
--
-- `0` nas versões já publicadas: elas foram lançadas sem que ninguém tivesse
-- este número, e inventá-lo seria afirmar uma estimativa que a empresa não fez.
-- Enquanto ele for 0, `POST /barters` recusa a versão e manda acertá-la (ver
-- PUT /barter-versions/:code/estimated-yield) — que é a recusa certa: sem a
-- taxa não há área exigida, e uma permuta sem área exigida é uma permuta sem
-- garantia dimensionada.
ALTER TABLE "BarterVersion" ADD COLUMN "estimatedYield" DOUBLE PRECISION NOT NULL DEFAULT 0;

-- A MARGEM DE SEGURANÇA, na credora — política da empresa, não da safra.
--
-- `0` é o padrão e é uma resposta legítima ("não exijo folga"), então ela não
-- entra em `creditorGaps()`. NÃO é a reserva legal do Código Florestal: aquela é
-- atributo do imóvel e imposta por lei; esta é apetite de risco e muda quando a
-- diretoria muda de ideia.
ALTER TABLE "Creditor" ADD COLUMN "pledgeMarginPercent" DOUBLE PRECISION NOT NULL DEFAULT 0;

-- AS DUAS TAXAS CONGELADAS na permuta, pelo mesmo motivo de `taxRate` e
-- `producerAreaHa`: as duas mudam, e lidas na conferência fariam uma permuta já
-- encaminhada passar a exigir mais área sem que nada nela tivesse mudado.
--
-- A ÁREA EXIGIDA não vira coluna: ela é derivada. As sacas mudam depois do
-- registro (deferir produto de fora do Barter recalcula a linha do grão), e um
-- número gravado continuaria dizendo o valor da semana passada.
--
-- `pledgeYield` 0 é a MARCA DO LEGADO, e é o que isenta as permutas já fechadas:
-- cobrar área delas travaria a emissão de títulos aprovados por uma regra que
-- não existia no dia em que foram aprovados.
ALTER TABLE "Barter" ADD COLUMN     "pledgeYield" DOUBLE PRECISION NOT NULL DEFAULT 0,
                     ADD COLUMN     "pledgeMarginPercent" DOUBLE PRECISION NOT NULL DEFAULT 0;
