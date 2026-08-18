import { TAX_REGIME, isTaxRegime, taxAmountOf, taxPayerKindOf, taxRateOf } from './tax-regime';

/**
 * As alíquotas de Funrural/Senar vigentes desde 1º/04/2026 (LC 224/2025) e a
 * conta que elas produzem sobre a entrega de grão.
 *
 * Os NÚMEROS estão escritos à mão de propósito: eles são a lei, não o resultado
 * de uma fórmula que dê para reconstruir do código. Se uma alíquota mudar, é
 * aqui que a mudança precisa ser afirmada — e `app/test/tax_regime_test.dart`
 * repete os mesmos valores, pelo mesmo motivo que os dois `barter_math` se
 * espelham.
 */
describe('TaxRegime', () => {
  const cpf = '12345678900'; // 11 dígitos
  const cnpj = '12345678000190'; // 14 dígitos

  it('CPF é pessoa física; CNPJ é jurídica', () => {
    expect(taxPayerKindOf(cpf)).toBe('pf');
    expect(taxPayerKindOf(cnpj)).toBe('pj');
  });

  it('pessoa física na comercialização: 1,32 + 0,11 + 0,20 = 1,63%', () => {
    expect(taxRateOf(TAX_REGIME.comercializacao, cpf)).toBe(1.63);
  });

  it('pessoa jurídica na comercialização: 1,98 + 0,25 = 2,23%', () => {
    expect(taxRateOf(TAX_REGIME.comercializacao, cnpj)).toBe(2.23);
  });

  /**
   * O ponto da funcionalidade: optar pela folha NÃO zera o imposto da permuta.
   * A previdência muda de base (vai para a folha, que este sistema não conhece),
   * mas o Senar continua incidindo sobre a receita da comercialização.
   */
  it('quem recolhe pela folha ainda paga o Senar sobre a entrega', () => {
    expect(taxRateOf(TAX_REGIME.folha, cpf)).toBe(0.2);
    expect(taxRateOf(TAX_REGIME.folha, cnpj)).toBe(0.25);
  });

  it('valor devido é valor × alíquota, arredondado em centavos', () => {
    // 251,4141 sacas × R$ 148,50 = R$ 37.335,00 de entrega (PRM-2026-001).
    expect(taxAmountOf(37335.0, 1.63)).toBe(608.56);
    expect(taxAmountOf(37335.0, 0.2)).toBe(74.67);
  });

  it('entrega ou alíquota inexistentes não geram imposto', () => {
    expect(taxAmountOf(0, 1.63)).toBe(0);
    expect(taxAmountOf(37335.0, 0)).toBe(0);
    expect(taxAmountOf(-100, 1.63)).toBe(0);
  });

  it('só os dois regimes conhecidos passam pela validação do DTO', () => {
    expect(isTaxRegime('comercializacao')).toBe(true);
    expect(isTaxRegime('folha')).toBe(true);
    expect(isTaxRegime('presumido')).toBe(false);
    expect(isTaxRegime(undefined)).toBe(false);
  });
});
