import { unitFromName } from './unit-from-name';

/**
 * Os casos vêm da lista de preços REAL do fornecedor (656 itens): é ela que
 * define o que este leitor precisa aguentar. Hoje ele resolve 644 deles.
 */
describe('Unidade a partir da descrição', () => {
  it.each([
    ['HERBIC.2,4-D AGROIMPORT emb.20 l', '20 L'],
    ['HERBIC.AMINOL 806 emb.05 l', '5 L'],
    ['INSET.EXALT emb.5l', '5 L'],
    ['FUNGICIDA NATIVO SC300 emb. 20 l', '20 L'],
    ['HERBIC.SUMISOYA emb.5 LT', '5 L'],
    ['INSET.ACTELLIC 500 CE 01 l', '1 L'],
    ['FERTILIZ. TRANSLOK 10KG', '10 kg'],
    ['HERBIC.ZARTAN 200GR', '200 g'],
    ['ADJUVANTE X emb.1,5 l', '1,5 L'],
  ])('%s → %s', (descricao, esperado) => {
    expect(unitFromName(descricao)).toBe(esperado);
  });

  /**
   * A primeira medida do nome costuma ser CONCENTRAÇÃO do princípio ativo, não
   * embalagem. Ler a primeira cadastraria um herbicida "de 500 g" que na
   * verdade vem em bombona de 1 kg — e o erro só apareceria no comprovante.
   */
  it('a concentração não é confundida com a embalagem', () => {
    expect(unitFromName('HERBIC.FLUMIOXAZINA HONIZYN WP-500 G/KG-1KG')).toBe('1 kg');
    expect(unitFromName('HERBIC.GLIF.PRECISO XK 540 SL-20 L')).toBe('20 L');
    expect(unitFromName('HERBIC.SOBERAN SC630 5LT')).toBe('5 L');
    // Só concentração, sem embalagem: melhor nada do que "100 g".
    expect(unitFromName('HERBIC.ACERT EC 100g/L')).toBeNull();
  });

  it('embalagem escrita por extenso também conta', () => {
    expect(unitFromName('ADUBO 10-20-10 CIBRA "BIG-BAG"')).toBe('big-bag');
    expect(unitFromName('ADUBO 10-18-18 S15 MOSAIC BB')).toBe('big-bag');
    expect(unitFromName('ADUBO 7-34-12 MOSAIC S15 B-B')).toBe('big-bag');
    expect(unitFromName('ADUBO 10-20-10 CIBRA "mist."')).toBe('granel');
  });

  /** Adubo vendido a peso não diz embalagem nenhuma — e chutar seria pior. */
  it('sem embalagem no nome, devolve null em vez de inventar', () => {
    expect(unitFromName('UREIA PLUS (45-00-00)')).toBeNull();
    expect(unitFromName('CLORETO DE POTASSIO')).toBeNull();
    expect(unitFromName('DAP 18-46-00')).toBeNull();
  });
});
