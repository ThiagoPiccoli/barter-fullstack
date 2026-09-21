import {
  MISSING_CITY_REFUSAL,
  cityKeyOf,
  cityNameOf,
  insuranceCostFor,
  insuranceItemNameOf,
  missingRateRefusal,
  sameCity,
  ufOf,
} from './insurance-rate';

/**
 * A conta do seguro e a chave do município — as duas coisas que o cadastro por
 * praça precisa acertar para a permuta achar a taxa certa.
 */
describe('InsuranceRate', () => {
  describe('a chave do município', () => {
    it('ignora acento, caixa e espaço repetido', () => {
      expect(cityKeyOf('Maringá/PR')).toBe('maringa/pr');
      expect(cityKeyOf('MARINGA/PR')).toBe('maringa/pr');
      expect(cityKeyOf('  Campo  Mourão/PR ')).toBe('campo mourao/pr');
    });

    /**
     * O caso que `normalizeName` sozinho não resolve, e o motivo de esta função
     * existir: a barra da UF vem cercada de espaço tantas vezes quanto não vem,
     * e sem isto "Campo Mourão / PR" seria uma segunda praça com um segundo
     * preço.
     */
    it('junta a UF quando a barra vem cercada de espaço', () => {
      expect(cityKeyOf('Campo Mourão / PR')).toBe('campo mourao/pr');
      expect(cityKeyOf('Campo Mourão /PR')).toBe('campo mourao/pr');
      expect(cityKeyOf('Campo Mourão/ PR')).toBe('campo mourao/pr');
    });
  });

  describe('o mesmo município escrito de dois jeitos', () => {
    it('separa o nome da UF', () => {
      expect(cityNameOf('Tupanciretã/RS')).toBe('tupancireta');
      expect(cityNameOf('TUPANCIRETÃ')).toBe('tupancireta');
      expect(ufOf('Tupanciretã/RS')).toBe('rs');
      expect(ufOf('TUPANCIRETÃ')).toBe('');
    });

    /**
     * O CASO REAL, e é o normal — não a exceção: a planilha da seguradora é
     * toda de um estado só e traz "TUPANCIRETÃ"; o cadastro do produtor traz
     * "Tupanciretã/RS", porque ali o município aparece sozinho e precisa se
     * identificar. Sem isto, a permuta do produtor seria recusada por falta de
     * uma praça que está na base.
     */
    it('casa quando um dos lados não declara a UF', () => {
      expect(sameCity('TUPANCIRETÃ', 'Tupanciretã/RS')).toBe(true);
      expect(sameCity('Tupanciretã/RS', 'tupancireta')).toBe(true);
      expect(sameCity('Capão do Cipo', 'CAPÃO DO CIPO/RS')).toBe(true);
    });

    /**
     * E NÃO CASA quando as duas declaram estados diferentes: "Bom Jesus/RS" e
     * "Bom Jesus/SC" são duas praças de verdade, com dois riscos e dois preços.
     * Cobrar uma pela outra seria vender ao produtor o seguro de outro estado.
     */
    it('não casa duas UFs diferentes, nem nomes diferentes', () => {
      expect(sameCity('Bom Jesus/RS', 'Bom Jesus/SC')).toBe(false);
      expect(sameCity('Tupanciretã', 'Tupanciretã do Sul')).toBe(false);
    });
  });

  describe('o custo', () => {
    it('é a área cultivável vezes a taxa da praça', () => {
      expect(insuranceCostFor(120, 85)).toBe(10200);
      expect(insuranceCostFor(1200, 140.5)).toBe(168600);
    });

    it('arredonda a centavos, que é a precisão do comprovante', () => {
      expect(insuranceCostFor(133.33, 92.5)).toBe(12333.03);
    });

    /**
     * Zero não é "seguro de graça": é "não dá para calcular". Quem lê a ausência
     * e decide o que fazer com ela é o registro da permuta, que recusa com o
     * nome do município em vez de gravar uma linha de R$ 0,00.
     */
    it('é zero sem área ou sem taxa, em vez de inventar um valor', () => {
      expect(insuranceCostFor(0, 85)).toBe(0);
      expect(insuranceCostFor(120, 0)).toBe(0);
      expect(insuranceCostFor(-120, 85)).toBe(0);
      expect(insuranceCostFor(120, -85)).toBe(0);
    });
  });

  it('a linha do seguro carrega a praça que a precificou', () => {
    expect(insuranceItemNameOf('Maringá/PR')).toBe('Seguro agrícola — Maringá/PR');
  });

  describe('as recusas', () => {
    it('a da praça sem taxa nomeia o município e manda ao cadastro', () => {
      const message = missingRateRefusal('Sorriso/MT');
      expect(message).toContain('"Sorriso/MT"');
      expect(message).toContain('base de seguros por município');
    });

    /** Sem município no cadastro não há o que nomear — e a frase não inventa. */
    it('a da praça vazia fala do produtor, sem aspas vazias', () => {
      const message = missingRateRefusal('   ');
      expect(message).toContain('o município do produtor');
      expect(message).not.toContain('""');
    });

    it('a do cadastro incompleto manda para outro lugar', () => {
      expect(MISSING_CITY_REFUSAL).toContain('sem o município');
      expect(MISSING_CITY_REFUSAL).not.toContain('base de seguros');
    });
  });
});
