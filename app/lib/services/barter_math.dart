/// Matemática da permuta — ESPELHO de `api/src/barters/barter-math.ts`.
///
/// As duas cópias existem de propósito: o app precisa recalcular a cada toque,
/// enquanto o consultor monta a permuta, e não dá para pedir ao servidor a
/// cada dígito. O servidor recalcula tudo no envio e é ele quem decide — o que
/// está aqui é previsão, não autoridade.
///
/// O risco de duas cópias é elas divergirem em silêncio: a tela diria "faltam
/// 3 sacas" e o envio seria recusado, ou pior, mostraria um número e gravaria
/// outro. Por isso as funções têm os MESMOS nomes dos dois lados, arredondam
/// do mesmo jeito, e `test/barter_math_test.dart` repete exatamente os números
/// de `barter-math.spec.ts`. Mudou um lado, os dois testes precisam concordar.
library;

/// Tolerância de centavos ao comparar valores em R$ (mesma do servidor).
const double moneyEpsilon = 0.01;

/// Um insumo escolhido, com o preço vigente do catálogo.
class PricedInput {
  final String productId;
  final double quantity;
  final double unitPrice;
  final String? classId;

  const PricedInput({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.classId,
  });
}

/// Como uma classe calcula seu mínimo. Espelha o `ruleType` da API.
enum ClassRule { none, percentOfTotal, valuePerHa }

/// Arredondamento igual ao do servidor.
///
/// O servidor usa `Math.round(v * f) / f`, e é isso que está reproduzido aqui.
/// `toStringAsFixed` seria o caminho natural em Dart — e era o que a tela
/// usava —, mas ele arredonda pelo valor decimal enquanto o JavaScript
/// arredonda pelo binário: varrendo 0,001 a 200,000 de milésimo em milésimo,
/// os dois discordam em 8.453 valores (4,2%), sempre em meio centavo. Meio
/// centavo é o bastante para a tela mostrar a quantidade mínima de um insumo e
/// o servidor recusar o envio por estar abaixo dela.
///
/// `.round()` do Dart e `Math.round` do JS, esses sim, coincidiram nos mesmos
/// 200 mil valores. Ver test/barter_math_test.dart.
double _roundTo(double value, int factor) => (value * factor).round() / factor;

/// Custo total dos insumos retirados (R$) — o valor que a permuta paga.
double inputCost(Iterable<PricedInput> inputs) =>
    inputs.fold(0.0, (sum, item) => sum + item.quantity * item.unitPrice);

/// Custo (R$) dos insumos que pertencem a uma classe.
double classSpend(Iterable<PricedInput> inputs, String classId) =>
    inputCost(inputs.where((item) => item.classId == classId));

/// Mínimo (R$) exigido pela regra de uma classe, dado o custo total da
/// permuta e a área (ha) do produtor. Devolve 0 quando não há exigência.
double classRequired(
  ClassRule rule,
  double ruleValue, {
  required double totalCost,
  required double areaHa,
}) {
  switch (rule) {
    case ClassRule.percentOfTotal:
      return totalCost * ruleValue / 100;
    case ClassRule.valuePerHa:
      return ruleValue * areaHa;
    case ClassRule.none:
      return 0;
  }
}

/// Sacas do grão de pagamento necessárias para cobrir um custo (4 casas).
double sacksToCover(double cost, double grainPrice) {
  if (grainPrice <= 0) return 0;
  return _roundTo(cost / grainPrice, 10000);
}

/// Quantidade mínima obrigatória de um insumo: taxa por hectare × área (2 casas).
double minQuantityFor(double requiredPerHa, double areaHa) {
  if (requiredPerHa <= 0) return 0;
  return _roundTo(requiredPerHa * areaHa, 100);
}

/// Quantidade digitada, na precisão em que ela será gravada (2 casas).
double roundQuantity(double quantity) => _roundTo(quantity, 100);
