/**
 * O documento do produtor (CPF ou CNPJ) é digitado à mão e chega formatado de
 * jeitos diferentes: "CPF 123.456.789-00", "123.456.789-00", "12345678900".
 * Para o cadastro em duplicidade ser detectável, existe uma forma canônica —
 * só os dígitos — e é sobre ela que a unicidade é garantida no banco.
 */
export function documentDigitsOf(document: string): string {
  return document.replace(/\D/g, '');
}

/** Um CPF tem 11 dígitos; um CNPJ, 14. Qualquer outra contagem é erro de digitação. */
export const DOCUMENT_PATTERN = /^(?:\D*\d){11}\D*$|^(?:\D*\d){14}\D*$/;

export const DOCUMENT_MESSAGE =
  'Informe um CPF (11 dígitos) ou CNPJ (14 dígitos) — a pontuação é opcional';
