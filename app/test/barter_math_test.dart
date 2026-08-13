import 'package:flutter_test/flutter_test.dart';
import 'package:barter_app/services/barter_math.dart';

/// ESPELHO de `api/src/barters/barter-math.spec.ts`.
///
/// Os mesmos casos, com os mesmos números, rodando contra a implementação
/// Dart. É esse par de arquivos que impede as duas cópias da matemática de
/// divergirem: qualquer mudança em uma delas tem de passar nos dois testes,
/// senão a tela passa a prometer um número e o servidor a gravar outro.
///
/// Ao mexer em qualquer um dos dois, mexa no outro junto.
void main() {
  // Referência: permuta PRM-2026-001 do dataset de demonstração.
  const inputs = [
    PricedInput(productId: '5', quantity: 300, unitPrice: 115.0, categoryId: '1'), // NPK
    PricedInput(productId: '6', quantity: 150, unitPrice: 18.9, categoryId: '2'), // Glifosato
  ];

  test('custo dos insumos é a soma de quantidade × preço', () {
    expect(inputCost(inputs), 37335.0);
    expect(inputCost([]), 0);
  });

  test('sacas do grão cobrem exatamente o custo (4 casas)', () {
    expect(sacksToCover(37335.0, 148.5), 251.4141);
    expect(sacksToCover(11946.0, 148.5), 80.4444);
  });

  test('grão sem preço não gera sacas (evita divisão por zero)', () {
    expect(sacksToCover(1000, 0), 0);
    expect(sacksToCover(1000, -5), 0);
  });

  test('gasto por categoria considera apenas os insumos da pasta', () {
    expect(categorySpend(inputs, '1'), 34500.0);
    expect(categorySpend(inputs, '2'), 2835.0);
    expect(categorySpend(inputs, '99'), 0);
  });

  test('mínimo percentual do total', () {
    expect(
      categoryRequired(CategoryRule.percentOfTotal, 30, totalCost: 37335, areaHa: 120),
      11200.5,
    );
  });

  test('mínimo por hectare multiplica pela área do produtor', () {
    expect(categoryRequired(CategoryRule.valuePerHa, 50, totalCost: 37335, areaHa: 120), 6000);
    expect(categoryRequired(CategoryRule.none, 10, totalCost: 37335, areaHa: 120), 0);
  });

  test('quantidade mínima de insumo = taxa por hectare × área', () {
    expect(minQuantityFor(0.4, 120), 48);
    expect(minQuantityFor(2.5, 120), 300);
    expect(minQuantityFor(0.15, 120), 18);
    expect(minQuantityFor(0, 120), 0);
  });

  /// O arredondamento tem de ser o MESMO do servidor, não só parecido.
  ///
  /// A tela usava `toStringAsFixed(2)`, o caminho natural em Dart. Ele
  /// arredonda pelo valor decimal; `Math.round(v * 100) / 100`, do servidor,
  /// arredonda pelo binário. Varrendo 0,001 a 200,000 de milésimo em milésimo,
  /// os dois discordam em 8.453 valores (4,2%) — sempre em meio centavo, que é
  /// exatamente o suficiente para a tela mostrar a quantidade mínima e o
  /// servidor recusar o envio por estar abaixo dela.
  ///
  /// Os casos abaixo são desses: `toStringAsFixed(2)` daria 0,01 e 0,04.
  test('arredondamento acompanha o do servidor, inclusive nos casos limítrofes', () {
    expect(roundQuantity(0.015), 0.02);
    expect(roundQuantity(0.045), 0.05);
    expect(minQuantityFor(0.015, 1), 0.02);

    // Casos em que o binário já resolve para baixo sozinho — aqui os dois
    // sempre concordaram, e continuam concordando.
    expect(roundQuantity(2.675), 2.68);
    expect(roundQuantity(1.005), 1.0);
    expect(roundQuantity(0.1 + 0.2), 0.3);
  });
}
