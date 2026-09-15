import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import {
  ADMIN,
  COMITE,
  FATURISTA,
  GERENTE,
  JOAO,
  UNIT,
  createTestApp,
  loginAs,
  resetDb,
} from './utils';

/**
 * A CÉDULA DE PRODUTO RURAL — a coleta dos dados que o documento exige e a
 * permuta não guarda.
 *
 * O que estas provas travam, em ordem de importância:
 *
 * 1. quem preenche é o FATURISTA, e só ele: é o posto que emite documento para
 *    fora, pelo mesmo motivo pelo qual a nota fiscal é dele;
 * 2. o que a permuta já sabe NÃO é campo de formulário — vem resolvido pelo
 *    servidor, e o que o cliente mandar por cima é descartado;
 * 3. o rascunho é salvável pela metade, e salvar um pedaço não apaga o resto;
 * 4. a repetição de digitar o mesmo produtor a cada safra é resolvida pela
 *    sugestão, e não dando ao faturista a caneta do cadastro de produtor.
 */
describe('CPR — o preenchimento da cédula (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const asUser = async (email: string) => `Bearer ${await loginAs(app, email)}`;

  const readCpr = async (code: string, auth: string) =>
    request(app.getHttpServer()).get(`/api/v1/barters/${code}/cpr`).set('Authorization', auth);

  const saveCpr = async (code: string, auth: string, body: Record<string, unknown>) =>
    request(app.getHttpServer())
      .put(`/api/v1/barters/${code}/cpr`)
      .set('Authorization', auth)
      .send(body);

  /** A qualificação civil completa do emitente — o bloco I do documento. */
  const qualificacao = {
    number: 'CPR-2026-014',
    dueDate: '2026-06-30T00:00:00.000Z',
    emitterNationality: 'brasileiro',
    emitterMaritalStatus: 'solteiro',
    emitterProfession: 'produtor rural',
    emitterRg: '10.234.567-8',
    emitterAddress: 'Rua das Acácias',
    emitterAddressNumber: '340',
    emitterCity: 'Maringá/PR',
    deliveryPlace: 'Filial 02 — Granel Santa Tecla',
  };

  const lavoura = {
    locality: 'Água Boa',
    city: 'Maringá/PR',
    areaHa: 45.5,
    registryNumber: '12.345',
    registryBook: '2-RG',
    registryDistrict: 'Maringá/PR',
    owners: [{ name: 'Antônio Pereira', document: '111.222.333-44' }],
  };

  /**
   * A PRIMEIRA ABERTURA da tela: nada preenchido, e mesmo assim ela sabe dizer o
   * que o documento vai exigir e o que a permuta já respondeu.
   *
   * `known` é a metade que ninguém digita — e é ela que impede a cédula de
   * cobrar um número diferente do que foi acordado.
   */
  it('permuta sem cédula: a mesa vem vazia, mas com o que a permuta já sabe', async () => {
    const resposta = await readCpr('PRM-2026-004', await asUser(FATURISTA));
    expect(resposta.status).toBe(200);

    const { cpr, known, gaps, complete } = resposta.body.data;
    expect(cpr).toBeNull();
    expect(complete).toBe(false);

    // O que sai do registro: emitente, grão, sacas, preço e valor da permuta.
    expect(known.emitterName).toBe('Cláudia Nunes');
    expect(known.emitterDocument).toBe('CPF 345.678.901-22');
    expect(known.grainName).toBe('Soja');
    expect(known.sacks).toBe(358.7879);
    expect(known.sackPrice).toBe(148.5);
    // 358,7879 sacas × 60 kg — o peso padrão, enquanto a cédula não disser outro.
    expect(known.quantityKg).toBe(21_527.27);
    expect(known.versionCode).toBe('S2026.02');

    // E o que ela ainda vai pedir a alguém.
    expect(gaps).toContain('número da CPR');
    expect(gaps).toContain('RG do emitente');
    expect(gaps).toContain('local da entrega');
    expect(gaps).toContain('ao menos uma lavoura (a garantia do penhor)');
  });

  /**
   * A UNIDADE DE RETIRADA da permuta vem junto, como SUGESTÃO do local da
   * entrega — não como o valor. Retirar insumo na Filial 02 não obriga ninguém
   * a entregar o grão lá, e quem confirma é quem assina embaixo.
   */
  it('a unidade da permuta vem como sugestão do local de entrega', async () => {
    const resposta = await readCpr('PRM-2026-004', await asUser(FATURISTA));
    expect(resposta.body.data.known.pickupUnit).toBeTruthy();
    // Sugestão, e não preenchimento: o campo continua vazio até alguém salvar.
    expect(resposta.body.data.cpr).toBeNull();
  });

  /**
   * O QUE A PROPOSTA PEDE E A CÉDULA NÃO IMPRIME: CNH, filiação, e-mail, RG do
   * cônjuge, avalistas e hipotecas são gravados e NÃO entram em `gaps`. Cobrá-los
   * travaria a geração de um documento que não os usa.
   */
  it('os campos da proposta são gravados sem travar a geração', async () => {
    const salvo = await saveCpr('PRM-2026-004', await asUser(FATURISTA), {
      emitterCnh: '01234567890',
      emitterFatherName: 'José Nunes',
      emitterMotherName: 'Rita Nunes',
      emitterEmail: 'claudia@fazenda.com.br',
      spouseRg: '20.111.222-3',
      mortgages: 'Hipoteca de 1º grau sobre a matrícula 9.876',
      guarantors: [
        {
          name: 'Pedro Avalista',
          document: '111.222.333-44',
          rg: '30.444.555-6',
          cnh: '99887766554',
          nationality: 'brasileiro',
          profession: 'produtor rural',
          maritalStatus: 'casado',
          fatherName: 'Paulo Avalista',
          motherName: 'Ana Avalista',
          email: 'pedro@fazenda.com.br',
          address: 'Rua das Palmeiras',
          addressNumber: '77',
          city: 'Sarandi/PR',
          spouseName: 'Joana Avalista',
          spouseDocument: '222.333.444-55',
          spouseRg: '40.555.666-7',
          spouseNationality: 'brasileira',
          spouseProfession: 'do lar',
        },
      ],
    });

    expect(salvo.status).toBe(200);
    expect(salvo.body.data.cpr.emitterCnh).toBe('01234567890');
    expect(salvo.body.data.cpr.emitterFatherName).toBe('José Nunes');
    expect(salvo.body.data.cpr.mortgages).toContain('9.876');
    expect(salvo.body.data.cpr.guarantors).toHaveLength(1);
    expect(salvo.body.data.cpr.guarantors[0].spouseName).toBe('Joana Avalista');

    // Nada disso virou pendência.
    const pendencias = salvo.body.data.gaps.join(' ');
    expect(pendencias).not.toContain('CNH');
    expect(pendencias).not.toContain('avalista');
    expect(pendencias).not.toContain('hipoteca');
  });

  /** Os avalistas seguem a regra das lavouras: a lista inteira substitui. */
  it('mandar avalistas substitui a lista; omiti-los preserva', async () => {
    const faturista = await asUser(FATURISTA);
    await saveCpr('PRM-2026-004', faturista, {
      guarantors: [{ name: 'Primeiro' }, { name: 'Segundo' }],
    });

    const semTocar = await saveCpr('PRM-2026-004', faturista, { cultivar: 'BMX Ativa RR' });
    expect(semTocar.body.data.cpr.guarantors).toHaveLength(2);

    const um = await saveCpr('PRM-2026-004', faturista, { guarantors: [{ name: 'Único' }] });
    expect(um.body.data.cpr.guarantors).toHaveLength(1);
    expect(um.body.data.cpr.guarantors[0].name).toBe('Único');
  });

  it('o município do cadastro do produtor entra como sugestão, não como campo gravado', async () => {
    const resposta = await readCpr('PRM-2026-004', await asUser(FATURISTA));
    expect(resposta.body.data.suggestion).toEqual({ emitterCity: 'Marialva/PR' });
  });

  /**
   * O rascunho é salvável PELA METADE, e é assim que o trabalho acontece: a
   * qualificação o faturista tem na mão agora, o número da nota só existe
   * depois de ela ser emitida.
   */
  it('salva pela metade, e o que falta continua listado', async () => {
    const faturista = await asUser(FATURISTA);
    const salvo = await saveCpr('PRM-2026-004', faturista, qualificacao);

    expect(salvo.status).toBe(200);
    expect(salvo.body.data.cpr.emitterRg).toBe('10.234.567-8');
    expect(salvo.body.data.cpr.filledBy).toBe('Patrícia Lemos');
    expect(salvo.body.data.complete).toBe(false);
    expect(salvo.body.data.gaps).toContain('número da nota fiscal');
    expect(salvo.body.data.gaps).not.toContain('RG do emitente');
  });

  /**
   * O SEGUNDO salvamento não pode apagar o primeiro. É a diferença entre um
   * formulário que guarda o trabalho e um que o perde a cada aba fechada.
   */
  it('o campo ausente do payload fica como estava', async () => {
    const faturista = await asUser(FATURISTA);
    await saveCpr('PRM-2026-004', faturista, qualificacao);
    const depois = await saveCpr('PRM-2026-004', faturista, {
      invoiceNumber: '00012345',
      duplicateNumber: '12345-A',
    });

    expect(depois.body.data.cpr.invoiceNumber).toBe('00012345');
    // O RG veio da gravação anterior, e continua lá.
    expect(depois.body.data.cpr.emitterRg).toBe('10.234.567-8');
    expect(depois.body.data.cpr.number).toBe('CPR-2026-014');
  });

  /**
   * A CÉDULA COMPLETA — o estado em que ela pode virar documento. Repare que a
   * `complete` depende também da CREDORA estar cadastrada: sem razão social e
   * CNPJ não há como emitir. O dataset já a traz, e o teste abaixo prova o
   * contrário — que apagá-la reabre a pendência.
   */
  it('cédula inteira, com credora cadastrada, fica completa', async () => {
    const salvo = await saveCpr('PRM-2026-004', await asUser(FATURISTA), {
      ...qualificacao,
      cultivar: 'BMX Ativa RR',
      maxMoisture: 14,
      maxImpurities: 1,
      oilContent: 18,
      invoiceNumber: '00012345',
      duplicateNumber: '12345-A',
      areas: [lavoura],
    });

    expect(salvo.body.data.gaps).toEqual([]);
    expect(salvo.body.data.creditorGaps).toEqual([]);
    expect(salvo.body.data.complete).toBe(true);
    // O foro cai na comarca da sede quando ninguém elege outro — o dataset
    // deixa o campo em branco justamente para exercitar isso.
    expect(salvo.body.data.creditor.effectiveForum).toBe('Maringá/PR');
  });

  /**
   * A CREDORA não cadastrada não trava a coleta: o faturista preenche a parte
   * dele hoje, e a pendência aparece na lista DELA, não na da cédula. Somar as
   * duas mandaria ele procurar um campo de CNPJ dentro do formulário da cédula,
   * onde ele não existe.
   */
  it('credora incompleta é pendência à parte, e não trava o preenchimento', async () => {
    // Apaga a razão social pela própria rota — é o que uma instalação nova tem.
    await request(app.getHttpServer())
      .put('/api/v1/creditor')
      .set('Authorization', await asUser(ADMIN))
      .send({ cnpj: '12.345.678/0001-90', city: 'Maringá/PR' });

    const resposta = await readCpr('PRM-2026-004', await asUser(FATURISTA));
    expect(resposta.status).toBe(200);
    expect(resposta.body.data.creditorGaps).toContain('razão social');
    expect(resposta.body.data.gaps).not.toContain('razão social');
    expect(resposta.body.data.complete).toBe(false);
  });

  /**
   * As LAVOURAS são substituídas em bloco, e é o que uma lista editada numa tela
   * precisa: mesclar por posição faria "apaguei a primeira" virar "editei a
   * primeira, e a segunda sumiu".
   */
  it('mandar as lavouras substitui as que estavam lá; omiti-las preserva', async () => {
    const faturista = await asUser(FATURISTA);
    const duas = await saveCpr('PRM-2026-004', faturista, {
      areas: [lavoura, { ...lavoura, locality: 'Linha São João', withinLargerArea: true }],
    });
    expect(duas.body.data.cpr.areas).toHaveLength(2);
    expect(duas.body.data.cpr.areas[1].withinLargerArea).toBe(true);

    // Um salvamento que não fala de lavoura não mexe nelas.
    const semTocar = await saveCpr('PRM-2026-004', faturista, { cultivar: 'BMX Ativa RR' });
    expect(semTocar.body.data.cpr.areas).toHaveLength(2);

    // Uma lista com uma só substitui as duas.
    const uma = await saveCpr('PRM-2026-004', faturista, { areas: [lavoura] });
    expect(uma.body.data.cpr.areas).toHaveLength(1);
    expect(uma.body.data.cpr.areas[0].locality).toBe('Água Boa');
    expect(uma.body.data.cpr.areas[0].owners).toEqual([
      { name: 'Antônio Pereira', document: '111.222.333-44' },
    ]);
  });

  /**
   * A REPETIÇÃO REAL do trabalho: o mesmo produtor emite cédula a cada safra, e
   * o RG, o endereço e as matrículas dele são os mesmos da vez passada.
   *
   * A sugestão vem da última CÉDULA do produtor — e não do cadastro dele —
   * porque quem escreve cadastro é o admin. Resolver a digitação dando ao
   * faturista a caneta do cadastro trocaria um incômodo por uma mudança de quem
   * pode alterar cliente.
   */
  it('a cédula anterior do mesmo produtor volta como sugestão na próxima', async () => {
    const faturista = await asUser(FATURISTA);
    // PRM-2026-001 é do Antônio e já foi faturada — a cédula dela é editável.
    await saveCpr('PRM-2026-001', faturista, { ...qualificacao, areas: [lavoura] });

    // Uma permuta NOVA para o mesmo Antônio, levada até a aprovação.
    const criada = await request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', await asUser(JOAO))
      .send({
        producerId: 1,
        unitId: UNIT.filial02,
        inputs: [
          { productId: 5, quantity: 48 },
          { productId: 6, quantity: 300 },
          { productId: 7, quantity: 18 },
        ],
      });
    const code = criada.body.data.code as string;
    // Ela nasce RASCUNHO: quem a tira da mesa do consultor é o encaminhamento,
    // com o parecer dele junto.
    await request(app.getHttpServer())
      .post(`/api/v1/barters/${code}/forward`)
      .set('Authorization', await asUser(JOAO))
      .send({ note: 'Cliente antigo, mesma área da safra passada.' })
      .expect(200);
    await request(app.getHttpServer())
      .post(`/api/v1/barters/${code}/opinion`)
      .set('Authorization', await asUser(GERENTE))
      .send({ note: 'Volume compatível com a área declarada.' });
    await request(app.getHttpServer())
      .post(`/api/v1/barters/${code}/review`)
      .set('Authorization', await asUser(COMITE))
      .send({ status: 'approved' });

    const nova = await readCpr(code, faturista);
    expect(nova.body.data.cpr).toBeNull();
    expect(nova.body.data.suggestion.emitterRg).toBe('10.234.567-8');
    expect(nova.body.data.suggestion.areas[0].registryNumber).toBe('12.345');
    // O NÚMERO da cédula não é sugerido: cada uma tem o seu, e repeti-lo faria
    // duas cédulas nascerem com a mesma numeração.
    expect(nova.body.data.suggestion.number).toBeUndefined();
  });

  /**
   * Depois que o faturista escreveu, o que está na tela é dele. Oferecer por
   * cima o texto de uma cédula antiga é a maneira mais fácil de sobrescrever uma
   * correção que alguém acabou de fazer.
   */
  it('com rascunho começado, não há mais sugestão', async () => {
    const faturista = await asUser(FATURISTA);
    await saveCpr('PRM-2026-004', faturista, { emitterRg: '99.999.999-9' });
    const resposta = await readCpr('PRM-2026-004', faturista);
    expect(resposta.body.data.suggestion).toEqual({});
  });

  /**
   * O QUE A PERMUTA JÁ SABE não é campo. Mandar sacas ou valor por cima é
   * descartado pelo `whitelist` do ValidationPipe — e é para descartar mesmo: um
   * número na cédula que discorde do registro é um título cobrando o que não foi
   * acordado.
   */
  it('valor e sacas mandados pelo cliente são descartados', async () => {
    const salvo = await saveCpr('PRM-2026-004', await asUser(FATURISTA), {
      number: 'CPR-2026-014',
      sacks: 1,
      totalValue: 1,
      emitterName: 'Outro Nome',
    });

    expect(salvo.status).toBe(200);
    expect(salvo.body.data.known.sacks).toBe(358.7879);
    expect(salvo.body.data.known.emitterName).toBe('Cláudia Nunes');
    expect(salvo.body.data.cpr).not.toHaveProperty('sacks');
  });

  it('percentual fora da escala é recusado antes de virar documento', async () => {
    const recusado = await saveCpr('PRM-2026-004', await asUser(FATURISTA), { maxMoisture: 140 });
    expect(recusado.status).toBe(422);
    expect(recusado.body.message).toContain('percentual');
  });

  /**
   * PREENCHER A CÉDULA É DO FATURISTA — e continua sendo, para todo mundo.
   *
   * O `PUT` é o ato: quem apura a matrícula do imóvel responde pelo que o
   * título afirma. Nenhum outro papel escreve nele, o admin inclusive.
   */
  it('só o faturista preenche a cédula', async () => {
    for (const email of [ADMIN, COMITE, GERENTE, JOAO]) {
      const escrita = await saveCpr('PRM-2026-004', await asUser(email), { number: 'X' });
      expect([email, escrita.status]).toEqual([email, 403]);
    }
  });

  /**
   * LER A CÉDULA é outra pergunta, e o admin passa por ela.
   *
   * A segunda via de um documento emitido é registro da operação que ele
   * administra — ele já enxerga a permuta inteira por `bartersReadAll` e já
   * responde pelo timbre por `creditorManage`. O que ele NÃO ganhou está no
   * teste acima: ler não virou escrever.
   *
   * O comitê, o gerente e o consultor continuam na porta: quem não emite
   * documento em nome da empresa não tira segunda via dele.
   */
  it('o admin lê a cédula e gera o documento; os demais papéis não', async () => {
    const admin = await readCpr('PRM-2026-004', await asUser(ADMIN));
    expect(admin.status).toBe(200);
    expect(admin.body.data).toHaveProperty('creditor');

    for (const email of [COMITE, GERENTE, JOAO]) {
      const leitura = await readCpr('PRM-2026-004', await asUser(email));
      expect([email, leitura.status]).toEqual([email, 403]);
    }
  });

  /**
   * O ALCANCE é o mesmo do faturamento: o faturista recebe o que as etapas
   * anteriores produziram. Permuta parada no gerente, no comitê ou negada não é
   * dele — e a recusa não conta o estado dela, pelo mesmo motivo do
   * `POST /invoice`.
   */
  it('a cédula só existe para a permuta que chegou ao faturamento', async () => {
    const faturista = await asUser(FATURISTA);
    for (const code of ['PRM-2026-005', 'PRM-2026-002', 'PRM-2026-003']) {
      const resposta = await readCpr(code, faturista);
      expect([code, resposta.status]).toEqual([code, 403]);
      expect(resposta.body.message).toBe('Você não tem acesso a esta permuta');
    }
  });

  /**
   * A permuta faturada é fim de linha para o ATO, e não para o PAPEL: a cédula é
   * um documento que vem depois, e corrigir uma matrícula errada nela não
   * desfatura coisa nenhuma.
   */
  it('a cédula continua editável depois de a permuta ser faturada', async () => {
    const salvo = await saveCpr('PRM-2026-001', await asUser(FATURISTA), qualificacao);
    expect(salvo.status).toBe(200);
    expect(salvo.body.data.cpr.emitterRg).toBe('10.234.567-8');
  });

  it('código que não existe é 404, e não uma cédula em branco', async () => {
    const resposta = await readCpr('PRM-9999-999', await asUser(FATURISTA));
    expect(resposta.status).toBe(404);
  });

  /**
   * A TRILHA registra o preenchimento pelo mesmo critério dos outros atos que
   * decidem dinheiro — e com folga: a cédula é título executável, e a linha do
   * tempo da permuta não a alcança (ela guarda mudança de ESTADO, e preencher
   * cédula não move a permuta de posto).
   *
   * O que a trilha NÃO leva é o conteúdo: despejar ali a qualificação civil de
   * um produtor espalharia dado pessoal por um registro que ninguém apaga.
   */
  it('preencher a cédula deixa rastro na trilha, sem copiar o conteúdo dela', async () => {
    await saveCpr('PRM-2026-004', await asUser(FATURISTA), qualificacao);

    const trilha = await request(app.getHttpServer())
      .get('/api/v1/audit-logs?action=barter.cpr-saved')
      .set('Authorization', await asUser(ADMIN));

    expect(trilha.status).toBe(200);
    const linha = trilha.body.data[0];
    expect(linha.actorName).toBe('Patrícia Lemos');
    expect(linha.targetLabel).toBe('PRM-2026-004');
    expect(linha.detail).toContain('CPR-2026-014');
    expect(linha.detail).toContain('faltam');
    expect(linha.detail).not.toContain('10.234.567-8');
  });
});
