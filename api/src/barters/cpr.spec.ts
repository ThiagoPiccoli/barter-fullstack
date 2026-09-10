import { EMPTY_CPR, cprGaps, knownFrom, requiresSpouse, suggestFrom } from './cpr';
import type { CprAreaDraft, CprDraft } from './cpr';

/**
 * O que a CÉDULA exige, testado contra o modelo de documento que a operação usa.
 *
 * A pergunta que estes testes travam é sempre a mesma: um campo em branco vira
 * uma pendência DITA, ou vira um espaço vazio impresso num título de crédito?
 */
describe('CPR — o que falta para a cédula sair', () => {
  const area = (): CprAreaDraft => ({
    locality: 'Água Boa',
    city: 'Maringá/PR',
    areaHa: 45.5,
    withinLargerArea: false,
    registryNumber: '12.345',
    registryBook: '2-RG',
    registryDistrict: 'Maringá/PR',
    owners: [{ name: 'Antônio Pereira', document: '111.222.333-44' }],
  });

  const filled = (): CprDraft => ({
    ...EMPTY_CPR,
    number: 'CPR-2026-014',
    dueDate: new Date('2026-06-30'),
    emitterNationality: 'brasileiro',
    emitterMaritalStatus: 'solteiro',
    emitterProfession: 'produtor rural',
    emitterRg: '10.234.567-8',
    emitterAddress: 'Rua das Acácias',
    emitterAddressNumber: '340',
    emitterCity: 'Maringá/PR',
    cultivar: 'BMX Ativa RR',
    maxMoisture: 14,
    maxImpurities: 1,
    oilContent: 18,
    invoiceNumber: '00012345',
    duplicateNumber: '12345-A',
    deliveryPlace: 'Filial 02 — Granel Santa Tecla',
  });

  it('cédula preenchida com uma lavoura não tem pendência', () => {
    expect(cprGaps(filled(), [area()])).toEqual([]);
  });

  it('a permuta sem cédula nenhuma lista TUDO o que falta', () => {
    const gaps = cprGaps(EMPTY_CPR, []);
    expect(gaps).toContain('número da CPR');
    expect(gaps).toContain('data de vencimento');
    expect(gaps).toContain('RG do emitente');
    expect(gaps).toContain('local da entrega');
    expect(gaps).toContain('ao menos uma lavoura (a garantia do penhor)');

    // O que a PROPOSTA pede e a cédula NÃO imprime não é cobrado aqui: cobrar
    // CNH, filiação ou avalista travaria a geração de um documento que não os
    // usa. A pergunta desta função é "dá para emitir?", não "o cadastro está
    // cheio?".
    expect(gaps.join(' ')).not.toContain('CNH');
    expect(gaps.join(' ')).not.toContain('filiação');
    expect(gaps.join(' ')).not.toContain('avalista');
    expect(gaps.join(' ')).not.toContain('hipoteca');
    // O peso da saca é o único campo obrigatório que já nasce respondido: 60 kg
    // é o padrão do mercado, e é o default da coluna.
    expect(gaps).not.toContain('peso da saca (kg)');
  });

  /**
   * O PENHOR é a razão de ser da cédula: sem a matrícula do imóvel, o documento
   * promete um grão e não garante nada. Por isso a ausência de lavoura é
   * pendência, e não uma lista vazia aceitável.
   */
  it('sem lavoura não há garantia — e isso é dito', () => {
    expect(cprGaps(filled(), [])).toEqual(['ao menos uma lavoura (a garantia do penhor)']);
  });

  it('a pendência da lavoura diz DE QUAL lavoura se trata', () => {
    const incomplete: CprAreaDraft = { ...area(), registryNumber: '', owners: [] };
    const gaps = cprGaps(filled(), [area(), incomplete]);
    expect(gaps).toEqual(['matrícula da 2ª lavoura', 'proprietário da 2ª lavoura']);
  });

  it('proprietário sem CPF é pendência — o penhor identifica o dono do imóvel', () => {
    const semDocumento: CprAreaDraft = {
      ...area(),
      owners: [{ name: 'Antônio Pereira', document: '  ' }],
    };
    expect(cprGaps(filled(), [semDocumento])).toEqual([
      'CPF/CNPJ do 1º proprietário da 1ª lavoura',
    ]);
  });

  /**
   * O ESTADO CIVIL decide se há um bloco inteiro a preencher. É a única
   * exigência condicional da cédula, e ela é condicional de verdade: a maioria
   * das cédulas não tem cônjuge, e cobrar o campo de quem é solteiro
   * transformaria "falta" em ruído que se aprende a ignorar.
   */
  it('emitente solteiro não deve nada ao bloco do cônjuge', () => {
    expect(cprGaps(filled(), [area()])).toEqual([]);
  });

  it('emitente casado precisa da anuência do cônjuge', () => {
    const gaps = cprGaps({ ...filled(), emitterMaritalStatus: 'Casado' }, [area()]);
    expect(gaps).toEqual([
      'nome do cônjuge (o emitente é casado)',
      'CPF do cônjuge',
      'nacionalidade do cônjuge',
      'profissão do cônjuge',
    ]);
  });

  it('o estado civil é texto livre, e a leitura dele aguenta isso', () => {
    expect(requiresSpouse('Casada')).toBe(true);
    expect(requiresSpouse('CASADO(A)')).toBe(true);
    expect(requiresSpouse('união estável')).toBe(true);
    expect(requiresSpouse('Uniao Estavel')).toBe(true);
    expect(requiresSpouse('solteiro')).toBe(false);
    expect(requiresSpouse('divorciado')).toBe(false);
    expect(requiresSpouse('viúva')).toBe(false);
  });

  /**
   * Zero por cento de umidade recusaria a colheita inteira: o número tem de ser
   * digitado por alguém, e por isso o vazio dos percentuais é 0 e 0 é pendência.
   */
  it('percentual em branco é pendência, não tolerância zero', () => {
    const gaps = cprGaps({ ...filled(), maxMoisture: 0 }, [area()]);
    expect(gaps).toEqual(['umidade máxima (%)']);
  });
});

describe('CPR — o que a permuta já responde', () => {
  const barter = {
    code: 'PRM-2026-014',
    producerName: 'João da Silva',
    versionCode: 'S2026.02',
    unitName: 'Filial 02',
  };
  const grain = { productName: 'Soja', quantity: 440, unitValue: 128.5 };

  it('sacas viram quilos pelo peso da saca da cédula', () => {
    const known = knownFrom(barter, grain, '123.456.789-00', 60);
    expect(known.sacks).toBe(440);
    expect(known.quantityKg).toBe(26_400);
    expect(known.totalValue).toBe(56_540);
    expect(known.sackPrice).toBe(128.5);
  });

  it('peso de saca diferente muda os quilos, e nada mais', () => {
    const known = knownFrom(barter, grain, '123.456.789-00', 50);
    expect(known.quantityKg).toBe(22_000);
    expect(known.totalValue).toBe(56_540);
  });

  /**
   * Permuta sem item de grão não existe na prática (o servidor cria o item na
   * criação), mas o registro histórico pode ter perdido o produto. Zerado é a
   * resposta certa: a alternativa é a cédula sair com `NaN` impresso.
   */
  it('sem item de grão, os números saem zerados em vez de quebrados', () => {
    const known = knownFrom(barter, undefined, '', 60);
    expect(known.sacks).toBe(0);
    expect(known.quantityKg).toBe(0);
    expect(known.totalValue).toBe(0);
    expect(known.grainName).toBe('');
  });
});

describe('CPR — a sugestão de preenchimento', () => {
  it('sem cédula anterior, só o município que o cadastro do produtor já sabe', () => {
    expect(suggestFrom({ city: 'Sarandi/PR' }, null)).toEqual({ emitterCity: 'Sarandi/PR' });
  });

  it('produtor excluído do cadastro não impede a tela de abrir', () => {
    expect(suggestFrom(null, null)).toEqual({});
  });

  /**
   * A repetição que esta função existe para resolver: matrícula, livro e comarca
   * são a parte mais cara de digitar da cédula, e não mudam de uma safra para a
   * outra. O que muda é a área plantada — que continua editável.
   */
  it('a cédula anterior do mesmo produtor traz a qualificação e as lavouras', () => {
    const previous = {
      ...EMPTY_CPR,
      emitterRg: '10.234.567-8',
      emitterMaritalStatus: 'casado',
      spouseName: 'Maria da Silva',
      cultivar: 'BMX Ativa RR',
      guarantors: [],
      areas: [
        {
          locality: 'Água Boa',
          city: 'Maringá/PR',
          areaHa: 45.5,
          withinLargerArea: false,
          registryNumber: '12.345',
          registryBook: '2-RG',
          registryDistrict: 'Maringá/PR',
          owners: [{ name: 'Antônio Pereira', document: '111.222.333-44' }],
        },
      ],
    };

    const suggestion = suggestFrom({ city: 'Sarandi/PR' }, previous);

    expect(suggestion.emitterRg).toBe('10.234.567-8');
    expect(suggestion.spouseName).toBe('Maria da Silva');
    expect(suggestion.areas?.[0].registryNumber).toBe('12.345');
    // O NÚMERO da cédula anterior não vem junto: cada cédula tem o seu, e
    // sugerir o passado faria duas cédulas nascerem com a mesma numeração.
    expect(suggestion).not.toHaveProperty('number');
    expect(suggestion).not.toHaveProperty('invoiceNumber');
  });
});
