/*
  Impede o mesmo produtor de ser cadastrado duas vezes.

  A unicidade não pode cair sobre `document`: ele guarda o texto como o admin
  digitou ("CPF 123.456.789-00"), e a mesma pessoa reaparece com outra
  formatação ("12345678900") sem o banco perceber. Por isso a nova coluna
  `documentDigits` — o mesmo documento reduzido a dígitos — que é onde o índice
  único mora.

  A carga inicial extrai os dígitos das linhas existentes com um CTE recursivo
  (o SQLite não tem expressão regular). Se o banco já tiver DOIS produtores com
  o mesmo documento, a criação do índice falha de propósito: são dados a
  resolver à mão antes de seguir, não algo para a migração escolher sozinha.
*/

-- AlterTable: nasce vazia para as linhas existentes serem preenchidas abaixo.
ALTER TABLE "Producer" ADD COLUMN "documentDigits" TEXT NOT NULL DEFAULT '';

-- Backfill: percorre cada documento caractere a caractere e guarda só os dígitos.
WITH RECURSIVE digits(id, rest, acc) AS (
    SELECT "id", "document", '' FROM "Producer"
  UNION ALL
    SELECT
      id,
      substr(rest, 2),
      CASE WHEN substr(rest, 1, 1) GLOB '[0-9]' THEN acc || substr(rest, 1, 1) ELSE acc END
    FROM digits
    WHERE length(rest) > 0
)
UPDATE "Producer"
SET "documentDigits" = (
  SELECT acc FROM digits WHERE digits.id = "Producer"."id" AND length(digits.rest) = 0
);

-- Linha sem nenhum dígito no documento não pode virar chave vazia repetida:
-- cai para um valor próprio, derivado do id, até alguém corrigir o cadastro.
UPDATE "Producer" SET "documentDigits" = 'sem-documento-' || "id" WHERE "documentDigits" = '';

-- CreateIndex
CREATE UNIQUE INDEX "Producer_documentDigits_key" ON "Producer"("documentDigits");
