import {
  EMPTY_CPR,
  consultantCprGaps,
  cprGaps,
  cprGapsOf,
  knownFrom,
  requiresSpouse,
  suggestFrom,
} from './cpr';
import { attachmentTypeOf } from './barters.service';
import type { CprAreaDraft, CprContext, CprDraft } from './cpr';

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
    // O SCR é anexo OBRIGATÓRIO, e por isso a cédula "preenchida" o tem: sem
    // ele, todo teste daqui passaria a ter uma pendência a mais e nenhum deles
    // seria mais sobre o que se propõe a testar.
    scrFileId: 77,
    deliveryPlace: 'Filial 02 — Granel Santa Tecla',
  });

  /**
   * O CONTEXTO do faturamento e da safra — o que a cédula exige e não é dela.
   *
   * Ele entra por parâmetro porque as duas peças têm outros donos: a nota é do
   * faturista e o vencimento é de quem cadastra a safra. `contexto()` é o caso
   * resolvido; os testes que cobram uma das duas o alteram na chamada.
   */
  const contexto = (): CprContext => ({
    invoices: [{ number: '55.318', fileId: 42 }],
    seasonName: 'Soja 2026',
  });

  it('cédula preenchida com uma lavoura não tem pendência', () => {
    expect(cprGaps(filled(), [area()], contexto())).toEqual([]);
  });

  it('a permuta sem cédula nenhuma lista TUDO o que falta', () => {
    const gaps = cprGaps(EMPTY_CPR, [], contexto());
    expect(gaps).toContain('número da CPR');
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
    expect(cprGaps(filled(), [], contexto())).toEqual([
      'ao menos uma lavoura (a garantia do penhor)',
    ]);
  });

  it('a pendência da lavoura diz DE QUAL lavoura se trata', () => {
    const incomplete: CprAreaDraft = { ...area(), registryNumber: '', owners: [] };
    const gaps = cprGaps(filled(), [area(), incomplete], contexto());
    expect(gaps).toEqual(['matrícula da 2ª lavoura', 'proprietário da 2ª lavoura']);
  });

  it('proprietário sem CPF é pendência — o penhor identifica o dono do imóvel', () => {
    const semDocumento: CprAreaDraft = {
      ...area(),
      owners: [{ name: 'Antônio Pereira', document: '  ' }],
    };
    expect(cprGaps(filled(), [semDocumento], contexto())).toEqual([
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
    expect(cprGaps(filled(), [area()], contexto())).toEqual([]);
  });

  it('emitente casado precisa da anuência do cônjuge', () => {
    const gaps = cprGaps({ ...filled(), emitterMaritalStatus: 'Casado' }, [area()], contexto());
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
    const gaps = cprGaps({ ...filled(), maxMoisture: 0 }, [area()], contexto());
    expect(gaps).toEqual(['umidade máxima (%)']);
  });

  /**
   * O SCR é a única exigência desta lista que não vem do modelo do documento.
   *
   * Ela vem da decisão de não assinar título sem olhar o endividamento de quem o
   * emite: a CPR é crédito, e o SCR é o que diz quanto o produtor já deve e a
   * quem. Emitir sem ele é conceder no escuro.
   */
  it('sem o SCR do produtor a cédula não sai — e a frase diz com quem ele está', () => {
    const gaps = cprGaps({ ...filled(), scrFileId: null }, [area()], contexto());
    expect(gaps).toEqual(['o SCR do produtor (anexo obrigatório, com o consultor)']);
  });

  /**
   * AS TRÊS PENDÊNCIAS DE OUTROS DONOS — o que este arquivo passou a saber
   * endereçar.
   *
   * A cédula deixou de caber numa tabela só: a nota é do faturista e o
   * vencimento é de quem cadastra a safra. Quem lê a lista é, em geral, o
   * consultor — e "falta o vencimento" o mandaria procurar um campo que não
   * existe na tela dele. Por isso cada frase diz ONDE a coisa se resolve.
   */
  it('o vencimento é da SAFRA, e a pendência dele diz isso', () => {
    const gaps = cprGaps({ ...filled(), dueDate: null }, [area()], contexto());
    expect(gaps).toEqual([
      'vencimento da CPR (defina-o na safra Soja 2026, no cadastro do Barter)',
    ]);
  });

  it('sem nota fiscal não há origem da dívida — e ela é do faturista', () => {
    const gaps = cprGaps(filled(), [area()], { ...contexto(), invoices: [] });
    expect(gaps).toEqual(['ao menos uma nota fiscal do faturamento (com o faturista)']);
  });

  /**
   * A NOTA SEM ARQUIVO existe: são as herdadas do campo de texto que ficava
   * dentro da cédula (ver a migration). Elas contam como registro e não contam
   * como prova — e a diferença entre as duas frases é o que diz ao faturista que
   * o que falta é o PDF, não a nota.
   */
  it('nota sem arquivo é pendência de anexo, não de nota', () => {
    const gaps = cprGaps(filled(), [area()], {
      ...contexto(),
      invoices: [{ number: '55.318', fileId: null }],
    });
    expect(gaps).toEqual(['o arquivo de ao menos uma nota fiscal (com o faturista)']);
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
  // A SAFRA carrega o vencimento (ele muda conforme a cultura) e o FATURAMENTO
  // carrega as notas. Nenhum dos dois é da cédula, e nenhum dos dois é digitado.
  const safra = { name: 'Soja 2026', cprDueDate: new Date('2026-06-30T12:00:00Z') };
  const notas = [{ number: '55.318', series: '1', duplicateNumber: '55.318-A' }];

  it('sacas viram quilos pelo peso da saca da cédula', () => {
    const known = knownFrom(barter, grain, '123.456.789-00', 60, safra, notas);
    expect(known.sacks).toBe(440);
    expect(known.quantityKg).toBe(26_400);
    expect(known.totalValue).toBe(56_540);
    expect(known.sackPrice).toBe(128.5);
  });

  /**
   * O VENCIMENTO e as NOTAS entram aqui — entre o que ninguém digita — e não no
   * rascunho, e essa mudança de lado é o conserto: os dois eram campos de
   * formulário preenchidos por quem não tinha a informação.
   */
  it('o vencimento vem da safra, e as notas vêm do faturamento', () => {
    const known = knownFrom(barter, grain, '123.456.789-00', 60, safra, notas);
    expect(known.dueDate).toEqual(new Date('2026-06-30T12:00:00Z'));
    expect(known.seasonName).toBe('Soja 2026');
    expect(known.invoices).toEqual([
      { number: '55.318', series: '1', duplicateNumber: '55.318-A' },
    ]);
  });

  /**
   * Safra sem vencimento acertado não quebra a leitura: ela devolve `null`, e é
   * `cprGaps` quem transforma isso em pendência endereçada. Inventar uma data
   * aqui seria imprimir num título executável um prazo que ninguém combinou.
   */
  it('safra sem vencimento devolve null em vez de inventar uma data', () => {
    const known = knownFrom(
      barter,
      grain,
      '123.456.789-00',
      60,
      { name: 'Soja 2026', cprDueDate: null },
      [],
    );
    expect(known.dueDate).toBeNull();
    expect(known.invoices).toEqual([]);
  });

  it('peso de saca diferente muda os quilos, e nada mais', () => {
    const known = knownFrom(barter, grain, '123.456.789-00', 50, safra, notas);
    expect(known.quantityKg).toBe(22_000);
    expect(known.totalValue).toBe(56_540);
  });

  /**
   * Permuta sem item de grão não existe na prática (o servidor cria o item na
   * criação), mas o registro histórico pode ter perdido o produto. Zerado é a
   * resposta certa: a alternativa é a cédula sair com `NaN` impresso.
   */
  it('sem item de grão, os números saem zerados em vez de quebrados', () => {
    const known = knownFrom(barter, undefined, '', 60, safra, notas);
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
    // O SCR também não: ele é uma fotografia com data, e a da safra passada não
    // diz nada sobre o endividamento de hoje — que é a única coisa que ele
    // existe para dizer.
    expect(suggestion).not.toHaveProperty('scrFileId');
  });
});
/**
 * DE QUEM É CADA PENDÊNCIA — a divisão que permite a MESMA regra responder a
 * duas perguntas.
 *
 * "Dá para emitir?" conta tudo. "O consultor já fez a parte dele?" conta só a
 * dele — e é essa a que o ENCAMINHAMENTO faz. Sem a separação, encaminhar uma
 * permuta exigiria uma nota fiscal que só existe depois do faturamento: a
 * esteira travaria num impossível.
 */
describe('CPR — de quem é cada pendência', () => {
  const vazia = { ...EMPTY_CPR };

  it('a cédula em branco cobra o consultor, e não só ele', () => {
    const donos = new Set(
      cprGapsOf(vazia, [], { invoices: [], seasonName: 'Soja 2026' }).map((g) => g.owner),
    );
    expect(donos).toEqual(new Set(['consultant', 'biller', 'admin', 'emitter']));
  });

  /**
   * O NÚMERO DA CÉDULA é do EMISSOR, e essa é a correção que destrava o
   * encaminhamento: a numeração da CPR vem de fora do sistema (cartório, B3,
   * controle da credora) e o consultor não a tem quando visita a fazenda.
   * Cobrá-la dele pararia toda permuta num número que só existe semanas depois.
   */
  it('o número da cédula é do emissor, e o vencimento é do admin', () => {
    const gaps = cprGapsOf(vazia, [], { invoices: [], seasonName: 'Soja 2026' });
    const donoDe = (trecho: string) => gaps.find((g) => g.label.includes(trecho))?.owner;

    expect(donoDe('número da CPR')).toBe('emitter');
    expect(donoDe('vencimento da CPR')).toBe('admin');
    expect(donoDe('nota fiscal')).toBe('biller');
    expect(donoDe('RG do emitente')).toBe('consultant');
    expect(donoDe('SCR do produtor')).toBe('consultant');
    expect(donoDe('lavoura')).toBe('consultant');
  });

  /**
   * O QUE O ENCAMINHAMENTO COBRA: só o do consultor. A cédula com a parte dele
   * pronta ainda está INCOMPLETA para emitir — e encaminha do mesmo jeito.
   */
  it('a lista do consultor não inclui o de ninguém mais', () => {
    const dele = consultantCprGaps(vazia, []);
    expect(dele.join(' ')).toContain('RG do emitente');
    expect(dele.join(' ')).toContain('SCR do produtor');
    expect(dele.join(' ')).not.toContain('nota fiscal');
    expect(dele.join(' ')).not.toContain('vencimento');
    expect(dele.join(' ')).not.toContain('número da CPR');
  });

  it('com a parte do consultor pronta, a lista dele fica vazia', () => {
    const preenchida: CprDraft = {
      ...EMPTY_CPR,
      emitterNationality: 'brasileiro',
      emitterMaritalStatus: 'solteiro',
      emitterProfession: 'produtor rural',
      emitterRg: '10.234.567-8',
      emitterAddress: 'Rua das Acácias',
      emitterAddressNumber: '340',
      emitterCity: 'Maringá/PR',
      deliveryPlace: 'Filial 02',
      cultivar: 'BMX Ativa RR',
      maxMoisture: 14,
      maxImpurities: 1,
      oilContent: 18,
      scrFileId: 77,
    };
    const lavoura: CprAreaDraft = {
      locality: 'Água Boa',
      city: 'Maringá/PR',
      areaHa: 45.5,
      withinLargerArea: false,
      registryNumber: '12.345',
      registryBook: '2-RG',
      registryDistrict: 'Maringá/PR',
      owners: [{ name: 'Antônio Pereira', document: '111.222.333-44' }],
    };

    expect(consultantCprGaps(preenchida, [lavoura])).toEqual([]);
    // E a cédula continua SEM PODER SER EMITIDA — o que falta é dos outros.
    expect(
      cprGaps(preenchida, [lavoura], { invoices: [], seasonName: 'Soja 2026' }).length,
    ).toBeGreaterThan(0);
  });
});

/**
 * O TIPO DO ANEXO, resolvido pelo que dá para saber.
 *
 * O `Content-Type` de um multipart é dito por quem envia, e quem envia às vezes
 * não sabe: o Chrome manda `application/octet-stream` para todo arquivo cujo
 * tipo o sistema não resolveu — inclusive um PDF comum, escolhido pelo seletor.
 * Recusá-lo pelo cabeçalho era recusar o documento certo por uma informação que
 * nunca foi confiável.
 */
describe('o tipo do anexo', () => {
  it('o tipo declarado vale quando ele diz alguma coisa', () => {
    expect(attachmentTypeOf('nota.pdf', 'application/pdf')).toBe('application/pdf');
    expect(attachmentTypeOf('nfe.xml', 'text/xml')).toBe('text/xml');
    expect(attachmentTypeOf('foto.JPG', 'image/jpeg')).toBe('image/jpeg');
  });

  /** O caso do print: o navegador não resolveu o tipo, e o arquivo é um PDF. */
  it('tipo genérico cai na extensão — é o PDF que o Chrome não reconheceu', () => {
    expect(attachmentTypeOf('acessos-agrobarter.pdf', 'application/octet-stream')).toBe(
      'application/pdf',
    );
    expect(attachmentTypeOf('nfe.XML', 'application/octet-stream')).toBe('application/xml');
    expect(attachmentTypeOf('scr.jpeg', '')).toBe('image/jpeg');
  });

  /** O que continua não passando: o que erra nos DOIS. */
  it('sem tipo e sem extensão conhecida, não passa', () => {
    expect(attachmentTypeOf('nota.exe', 'application/x-msdownload')).toBeNull();
    expect(attachmentTypeOf('nota.exe', 'application/octet-stream')).toBeNull();
    expect(attachmentTypeOf('semextensao', 'application/octet-stream')).toBeNull();
    // Tipo declarado ERRADO e conhecido continua recusado: ele diz alguma coisa,
    // e o que ele diz não serve. A extensão só é consultada quando o cabeçalho
    // não diz nada.
    expect(attachmentTypeOf('nota.pdf', 'text/html')).toBeNull();
  });
});
