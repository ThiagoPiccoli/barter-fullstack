/// O IMPOSTO DA ENTREGA (Funrural e Senar) — ESPELHO de
/// `api/src/barters/tax-regime.ts`, pelo mesmo motivo de `barter_math.dart`: o
/// consultor fecha a permuta na fazenda, sem sinal, e precisa ver o imposto
/// antes de mandar. O número que VALE é o `taxRate` que o servidor grava na
/// permuta; o daqui é previsão.
///
/// ## O que está sendo calculado
///
/// Toda entrega de grão é COMERCIALIZAÇÃO DE PRODUÇÃO RURAL, e sobre ela
/// incidem a contribuição previdenciária rural (o "Funrural") e a contribuição
/// ao Senar. A permuta não é exceção: o produtor paga os insumos entregando
/// grão, e essa entrega é uma venda como outra qualquer.
///
/// O que se ESCOLHE no fechamento da permuta é a BASE da parte previdenciária —
/// comercialização ou folha de pagamento. O que NÃO se escolhe é o Senar: ele
/// incide sobre a receita da comercialização SEMPRE, inclusive para quem optou
/// pela folha. É por isso que [TaxRegime.folha] não zera a conta desta permuta.
///
/// PF ou PJ não é pergunta: sai do documento do cadastro (11 dígitos = CPF,
/// 14 = CNPJ).
///
/// Alíquotas vigentes desde 1º/04/2026 (LC 224/2025).
library;

/// As duas bases possíveis da contribuição previdenciária rural.
enum TaxRegime {
  /// Sobre a receita bruta da comercialização. É o padrão — quem não faz a
  /// opção formal pela folha está aqui.
  comercializacao,

  /// Sobre a folha de pagamento (20% de INSS patronal + RAT, ~23%). O Senar
  /// continua saindo da receita.
  folha,
}

/// O regime como o servidor o nomeia (`comercializacao` / `folha`).
extension TaxRegimeApi on TaxRegime {
  String get apiValue => name;

  /// Rótulo curto, para o fechamento da permuta e o detalhe dela.
  String get label => switch (this) {
    TaxRegime.comercializacao => 'Sobre a comercialização',
    TaxRegime.folha => 'Sobre a folha de pagamento',
  };

  /// Nome curto, para onde não cabe o [label] inteiro — os segmentos do
  /// seletor, que dividem a largura da tela em duas.
  String get shortLabel => switch (this) {
    TaxRegime.comercializacao => 'Comercialização',
    TaxRegime.folha => 'Folha',
  };

  /// O que a escolha significa, em uma linha — o consultor está fechando uma
  /// permuta, não estudando legislação.
  String get description => switch (this) {
    TaxRegime.comercializacao =>
      'O Funrural sai da receita de cada venda, incluindo o grão desta permuta.',
    TaxRegime.folha => 'O Funrural sai da folha de pagamento; sobre o grão fica só o Senar.',
  };
}

/// Forma vinda do servidor (ou de uma simulação guardada por uma versão
/// anterior do app), tolerante ao desconhecido — mesma razão do status da
/// permuta: um valor que esta versão não conhece não pode derrubar a lista
/// inteira. Cai no padrão legal, que é a comercialização.
TaxRegime taxRegimeFrom(dynamic value) {
  for (final regime in TaxRegime.values) {
    if (regime.name == value) return regime;
  }
  return TaxRegime.comercializacao;
}

/// A composição da alíquota sobre a comercialização, por tipo de pessoa.
///
/// Em parcelas, e não como um total só, porque é a separação que o regime
/// [TaxRegime.folha] usa: lá a previdência e o RAT saem da receita (vão para a
/// folha) e o Senar fica.
class _Rates {
  final double previdencia;
  final double rat;
  final double senar;
  const _Rates(this.previdencia, this.rat, this.senar);
}

/// Produtor pessoa física (CPF): 1,32 + 0,11 + 0,20 = 1,63%.
const _pf = _Rates(1.32, 0.11, 0.2);

/// Produtor pessoa jurídica (CNPJ): 1,98 (Funrural + RAT) + 0,25 = 2,23%.
const _pj = _Rates(1.98, 0, 0.25);

/// Só os dígitos do documento — o que separa CPF de CNPJ é a contagem, e o
/// cadastro aceita a pontuação que a pessoa quiser digitar.
String _digitsOf(String document) => document.replaceAll(RegExp(r'\D'), '');

/// O documento é de pessoa jurídica (CNPJ, 14 dígitos)?
bool isCompanyDocument(String document) => _digitsOf(document).length == 14;

/// A alíquota (%) que incide sobre o valor entregue em grão.
///
/// No regime da folha sobra só o Senar: a parte previdenciária existe, mas a
/// base dela é a folha de pagamento do produtor — que este sistema não conhece
/// e não tem por que conhecer. Devolver a alíquota cheia ali seria cobrar duas
/// vezes do mesmo produtor no papel.
double taxRateOf(TaxRegime regime, String document) {
  final rate = isCompanyDocument(document) ? _pj : _pf;
  final total = regime == TaxRegime.folha ? rate.senar : rate.previdencia + rate.rat + rate.senar;
  // Duas casas: as alíquotas são publicadas assim, e somar 1.32 + 0.11 + 0.2 em
  // ponto flutuante devolve 1.6300000000000001 — que viraria um comprovante com
  // dezesseis casas de imposto.
  return (total * 100).round() / 100;
}

/// O valor devido, dado o valor comercializado e a alíquota (%).
///
/// Arredonda em CENTAVOS, e só no fim — é dinheiro, e a conta de quem confere é
/// "valor × alíquota", uma vez só. Serve também para sacas: a alíquota é
/// percentual, então aplicá-la sobre o total em sacas dá o imposto na unidade
/// em que o consultor enxerga a permuta (ele não vê R$).
double taxAmountOf(double commercializedValue, double rate) {
  if (commercializedValue <= 0 || rate <= 0) return 0;
  return (commercializedValue * rate).round() / 100;
}
