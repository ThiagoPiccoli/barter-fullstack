/// NÚMERO COMO O BRASIL ESCREVE — a leitura de tudo o que alguém digita.
///
/// Ela existia sete vezes, uma por formulário, e em três feitios diferentes:
/// `replaceAll(',', '.')` puro (que lê "1.250,00" como 1.25), o mesmo com o
/// ponto de milhar removido, e uma versão que ainda limpava "R$" e espaços. O
/// mesmo texto entrava como três números diferentes conforme a tela — e a que
/// lia errado era justamente a do valor da saca, que multiplica a permuta
/// inteira.
///
/// É a MESMA regra do servidor (`parseNumber`, em `api/src/seasons/version-
/// import.ts`), que lê a planilha do fornecedor: quem digita e quem carrega o
/// arquivo não podem ter leituras diferentes do mesmo "152,50".
library;

/// O texto digitado, lido como número — ou `null` quando ele não é um.
///
/// `null` é resposta, e não erro: campo vazio é campo vazio, e quem decide o que
/// fazer com isso é o formulário (alguns exigem, outros tratam como "não
/// informado"). Devolver `0` aqui apagaria essa diferença — e um preço zerado
/// que ninguém digitou é pior do que um campo em branco.
///
/// A VÍRGULA é quem manda: tendo vírgula, o ponto é separador de milhar
/// ("1.250,00" → 1250.0); não tendo, o ponto é decimal ("1250.5" → 1250.5).
/// Sem essa distinção, "1.250" vira 1,25 — que é como o valor da saca de um
/// Barter inteiro sai errado por um caractere.
///
/// O que não for dígito, vírgula, ponto ou sinal sai fora antes ("R$ 1.250,00",
/// "120 ha", "45%"): o rótulo do campo costuma escapar para dentro do texto
/// quando alguém cola um valor de outro lugar.
double? parseNumber(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^\d,.-]'), '').trim();
  if (cleaned.isEmpty) return null;
  final normalized =
      cleaned.contains(',') ? cleaned.replaceAll('.', '').replaceAll(',', '.') : cleaned;
  return double.tryParse(normalized);
}

/// O mesmo, com um padrão para quem não tem o que fazer com o vazio.
///
/// Existe para os lugares em que "nada digitado" e "zero" são a mesma coisa —
/// a quantidade de um insumo que o consultor apagou do campo, por exemplo. Onde
/// os dois significam coisas diferentes, use [parseNumber] e trate o `null`.
double parseNumberOr(String raw, {double fallback = 0}) => parseNumber(raw) ?? fallback;
