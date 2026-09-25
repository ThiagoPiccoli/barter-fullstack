import {
  classRequired,
  classSpend,
  inputCost,
  minQuantityFor,
  pledgeAreaFor,
  roundQuantity,
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
    expect(roundQuantity(0.015)).toBe(0.02);
    expect(roundQuantity(0.045)).toBe(0.05);
    expect(minQuantityFor(0.015, 1)).toBe(0.02);

    // Casos em que o binário já resolve para baixo sozinho — aqui os dois
    // sempre concordaram, e continuam concordando.
    expect(roundQuantity(2.675)).toBe(2.68);
    expect(roundQuantity(1.005)).toBe(1.0);
    expect(roundQuantity(0.1 + 0.2)).toBe(0.3);

    expect(sacksToCover(1, 3)).toBe(0.3333);
  });
});

/**
 * O PENHOR: as sacas viram a ÁREA DE LAVOURA que precisa produzi-las.
 *
 * É a conversão que fecha o ciclo — o custo vira sacas (`sacksToCover`), e as
 * sacas viram terra. Os números abaixo são os da conversa que originou a regra:
 * 1.200 sacas a 60 sc/ha dão 20 ha, e 20% de margem os levam a 24.
 */
describe('Penhor — a área que a permuta exige em garantia', () => {
  it('sacas ÷ produtividade, mais a margem de segurança', () => {
    expect(pledgeAreaFor(1200, 60, 20)).toBe(24);
    expect(pledgeAreaFor(1200, 60, 0)).toBe(20);
    expect(pledgeAreaFor(900, 60, 20)).toBe(18);
    // Margem de 100% é o dobro da área estimada — o teto que o DTO da credora
    // aceita, e por isso o caso extremo que a conta precisa acertar.
    expect(pledgeAreaFor(1200, 60, 100)).toBe(40);
  });

  /**
   * ARREDONDA PARA CIMA, e este é o teste que guarda a direção do erro.
   *
   * 1.000 ÷ 57 = 17,5438…, e o piso de uma GARANTIA não se arredonda para baixo:
   * 17,54 entregaria quatro milésimos de hectare de graça. A precisão é de duas
   * casas porque é a precisão em que a área da matrícula é digitada.
   */
  it('a área exigida arredonda para cima, a duas casas', () => {
    expect(pledgeAreaFor(1000, 57, 0)).toBe(17.55);
    expect(pledgeAreaFor(1000, 3, 0)).toBe(333.34);
  });

  /**
   * E NÃO INVENTA UM CENTÉSIMO quando a conta já fecha redonda.
   *
   * `1200 / 60 * 1.2` dá 24.000000000000004 em ponto flutuante, e um teto
   * ingênuo o levaria a 24,01 — a garantia crescendo por causa do binário. É o
   * recuo de 1e-9 em `pledgeAreaFor` que segura isso, e é este teste que o
   * mantém lá.
   */
  it('conta redonda não vira um centésimo a mais', () => {
    expect(pledgeAreaFor(1200, 60, 20)).toBe(24);
    expect(pledgeAreaFor(300, 50, 10)).toBe(6.6);
  });

  /**
   * SEM SACAS OU SEM PRODUTIVIDADE, zero — e zero aqui é "não dá para calcular",
   * não "não exige garantia". Quem lê a ausência e decide o que ela significa é
   * `cprGapsOf`; aqui o que não pode acontecer é uma divisão por zero virar
   * `Infinity` e a área exigida sair como um número.
   */
  it('sem sacas ou sem produtividade não há área calculável', () => {
    expect(pledgeAreaFor(1200, 0, 20)).toBe(0);
    expect(pledgeAreaFor(0, 60, 20)).toBe(0);
    expect(pledgeAreaFor(-10, 60, 20)).toBe(0);
    // Margem negativa não ENCOLHE a garantia: ela é tratada como zero. Um
    // percentual negativo só chega aqui por defeito de quem chama, e o efeito
    // dele seria exigir MENOS área do que a produção estimada justifica.
    expect(pledgeAreaFor(1200, 60, -50)).toBe(20);
  });
});
