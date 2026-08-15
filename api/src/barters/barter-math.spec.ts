import {
  classRequired,
  classSpend,
  inputCost,
  minQuantityFor,
  sacksToCover,
  type PricedInput,
} from './barter-math';

/**
 * O coração do escambo: insumos formam um custo e o custo vira sacas do grão.
 * Números de referência tirados da permuta PRM-2026-001 do dataset.
 */
describe('BarterMath', () => {
  const inputs: PricedInput[] = [
    { productId: 5, quantity: 300, unitPrice: 115.0, classId: 1 }, // NPK
    { productId: 6, quantity: 150, unitPrice: 18.9, classId: 2 }, // Glifosato
  ];

  it('custo dos insumos é a soma de quantidade × preço', () => {
    expect(inputCost(inputs)).toBe(37335.0);
    expect(inputCost([])).toBe(0);
  });

  it('sacas do grão cobrem exatamente o custo (4 casas)', () => {
    expect(sacksToCover(37335.0, 148.5)).toBe(251.4141);
    expect(sacksToCover(11946.0, 148.5)).toBe(80.4444);
  });

  it('grão sem preço não gera sacas (evita divisão por zero)', () => {
    expect(sacksToCover(1000, 0)).toBe(0);
    expect(sacksToCover(1000, -5)).toBe(0);
  });

  it('gasto por classe considera apenas os insumos dela', () => {
    expect(classSpend(inputs, 1)).toBe(34500.0);
    expect(classSpend(inputs, 2)).toBe(2835.0);
    expect(classSpend(inputs, 99)).toBe(0);
  });

  it('mínimo percentual do total', () => {
    const rule = { ruleType: 'percentOfTotal', ruleValue: 30 };
    expect(classRequired(rule, { totalCost: 37335, areaHa: 120 })).toBe(11200.5);
  });

  it('mínimo por hectare multiplica pela área do produtor', () => {
    const rule = { ruleType: 'valuePerHa', ruleValue: 50 };
    expect(classRequired(rule, { totalCost: 37335, areaHa: 120 })).toBe(6000);
    expect(
      classRequired({ ruleType: 'none', ruleValue: 10 }, { totalCost: 37335, areaHa: 120 }),
    ).toBe(0);
  });

  it('quantidade mínima de insumo = taxa por hectare × área', () => {
    expect(minQuantityFor(0.4, 120)).toBe(48);
    expect(minQuantityFor(2.5, 120)).toBe(300);
    expect(minQuantityFor(0.15, 120)).toBe(18);
    expect(minQuantityFor(0, 120)).toBe(0);
  });

  /**
   * O app repete esta conta enquanto o consultor monta a permuta (o servidor
   * não pode ser consultado a cada dígito). Os valores abaixo são os mesmos
   * fixados em app/test/barter_math_test.dart: se um lado mudar de
   * arredondamento, um dos dois testes cai.
   *
   * Meio centavo importa aqui — é a diferença entre a tela mostrar a
   * quantidade mínima e o envio ser recusado por estar abaixo dela.
   */
  it('arredondamento casa com o do app (mesmos casos de meio centavo)', () => {
    expect(minQuantityFor(0.015, 1)).toBe(0.02);
    expect(minQuantityFor(0.045, 1)).toBe(0.05);
    expect(minQuantityFor(2.675, 1)).toBe(2.68);
    expect(minQuantityFor(1.005, 1)).toBe(1.0);
    expect(sacksToCover(1, 3)).toBe(0.3333);
  });
});
