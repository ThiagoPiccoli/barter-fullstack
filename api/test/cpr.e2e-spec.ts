import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import {
  ADMIN,
  ANA,
  COMITE,
  EMISSOR,
  FATURISTA,
  GERENTE,
  JOAO,
  UNIT,
  attachInvoice,
  createTestApp,
  loginAs,
  resetDb,
} from './utils';

/**
 * A CÉDULA DE PRODUTO RURAL — a coleta dos dados que o documento exige e a
 * permuta não guarda, e a EMISSÃO do título.
 *
 * O que estas provas travam, em ordem de importância:
 *
 * 1. **quem preenche é o CONSULTOR**, e só ele. Era do faturista, com o
 *    argumento de que o posto que emite documento para fora é o mesmo que emite
 *    a nota — e o argumento não se sustentou: a matrícula da lavoura, o nome do
 *    cônjuge, o dono da área arrendada e o SCR são o que se traz da visita à
 *    fazenda. O faturista os obtinha por telefone e digitava;
 * 2. **quem emite é o EMISSOR**, e a emissão é uma CONFERÊNCIA: a cédula com
 *    lacuna não sai, e a recusa diz o que falta e com quem;
 * 3. **o que a permuta já sabe NÃO é campo** — e isso cresceu: o VENCIMENTO
 *    agora é da safra (ele muda conforme a cultura) e os NÚMEROS DAS NOTAS são
 *    do faturamento. Os dois eram campos digitados por quem não tinha a
 *    informação;
 * 4. o rascunho é salvável pela metade, e salvar um pedaço não apaga o resto —
 *    mas depois de EMITIDA a cédula não se reescreve;
 * 5. o SCR do produtor é anexo OBRIGATÓRIO: uma CPR é crédito, e conceder sem
 *    olhar o endividamento de quem emite é conceder no escuro.
 */
describe('CPR — o preenchimento e a emissão da cédula (e2e)', () => {
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

  /** Anexa o SCR do produtor — o anexo obrigatório da cédula. */
  const saveScr = async (code: string, auth: string) =>
    request(app.getHttpServer())
      .put(`/api/v1/barters/${code}/cpr/scr`)
      .set('Authorization', auth)
      .attach('file', Buffer.from('%PDF-1.4\nSCR\n%%EOF\n'), {
        filename: 'scr.pdf',
        contentType: 'application/pdf',
      });

  /**
   * LANÇA AS ASSINATURAS com a cédula assinada anexada.
   *
   * O anexo é OBRIGATÓRIO, e por isso a rota virou `multipart`: "assinada" sem o
   * papel assinado era um estado afirmando o que o sistema não tinha como
   * mostrar — a segunda via saía em branco, diferente da que está com o
   * produtor, e o documento com as assinaturas morava no e-mail de alguém.
   */
  const assinarCpr = (code: string, auth: string, fields: Record<string, string> = {}) => {
    const chamada = request(app.getHttpServer())
      .post(`/api/v1/barters/${code}/cpr/signatures`)
      .set('Authorization', auth);
    for (const [campo, valor] of Object.entries(fields)) chamada.field(campo, valor);
    return chamada.attach('file', Buffer.from('%PDF-1.4\nASSINADA\n%%EOF\n'), {
      filename: 'cpr-assinada.pdf',
      contentType: 'application/pdf',
    });
  };

  /**
   * A qualificação civil completa do emitente — o bloco I do documento.
   *
   * Sem `dueDate`: ele deixou de ser campo. O vencimento é da SAFRA, e o
   * servidor o copia de lá — mandá-lo aqui é descartado pelo `whitelist`, que é
   * exatamente o que o teste "o vencimento vem da safra" prova.
   */
  const qualificacao = {
    number: 'CPR-2026-014',
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

  /** O padrão do grão — o bloco que fecha a cédula junto com a lavoura. */
  const padraoDoGrao = {
    cultivar: 'BMX Ativa RR',
    maxMoisture: 14,
    maxImpurities: 1,
    oilContent: 18,
  };

  /**
   * A PRIMEIRA ABERTURA da tela: nada preenchido, e mesmo assim ela sabe dizer o
   * que o documento vai exigir e o que a permuta já respondeu.
   *
   * `known` é a metade que ninguém digita — e é ela que impede a cédula de
   * cobrar um número diferente do que foi acordado.
   */
  it('permuta sem cédula: a mesa vem vazia, mas com o que a permuta já sabe', async () => {
    const resposta = await readCpr('PRM-2026-004', await asUser(ANA));
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
    // A LAVOURA é cobrada COM O TAMANHO dela: 358,7879 sacas ÷ 60 sc/ha dão
    // 5,98 ha, e os 20% de margem da credora os levam a 7,18. Sem o número, a
    // pendência mandaria o consultor voltar à fazenda sem saber quanta matrícula
    // precisa trazer — que é a pergunta inteira desta etapa.
    expect(gaps).toContain(
      'ao menos uma lavoura (a garantia do penhor — esta permuta exige 7,18 ha)',
    );
  });

  /**
   * O PENHOR DIMENSIONADO — a mesa da cédula traz o placar, e não só a lacuna.
   *
   * As duas coisas respondem perguntas diferentes: a lacuna diz o que fazer e
   * some quando a área fecha; o placar continua dizendo por quanto ela fechou. É
   * ele que a tela desenha no cabeçalho das lavouras enquanto alguém acrescenta
   * matrícula.
   */
  it('a mesa traz o placar do penhor: exigido, penhorado e o que falta', async () => {
    const ana = await asUser(ANA);
    const mesa = async () => (await readCpr('PRM-2026-004', ana)).body.data;

    const vazia = await mesa();
    expect(vazia.pledge).toEqual({
      applies: true,
      requiredAreaHa: 7.18,
      pledgedAreaHa: 0,
      shortfallHa: 7.18,
    });
    // E as taxas que produziram o número acompanham a permuta, para quem for
    // contestá-lo: a produtividade da versão e a margem da credora, congeladas.
    expect(vazia.known.sacks).toBe(358.7879);

    // Uma lavoura pequena não fecha, e a frase traz os três números.
    await saveCpr('PRM-2026-004', ana, { areas: [{ ...lavoura, areaHa: 5 }] });
    const curta = await mesa();
    expect(curta.pledge.shortfallHa).toBe(2.18);
    expect(curta.consultantGaps.join(' ')).toContain(
      'área de penhor insuficiente: faltam 2,18 ha (a permuta exige 7,18 ha e as lavouras somam 5,00 ha)',
    );

    // A SEGUNDA MATRÍCULA fecha a área — é o caso que a feature existe para
    // permitir: o produtor planta em pedaços, e o penhor soma todos eles.
    await saveCpr('PRM-2026-004', ana, {
      areas: [
        { ...lavoura, areaHa: 5 },
        { ...lavoura, areaHa: 3, registryNumber: '67.890' },
      ],
    });
    const fechada = await mesa();
    expect(fechada.pledge).toEqual({
      applies: true,
      requiredAreaHa: 7.18,
      pledgedAreaHa: 8,
      shortfallHa: 0,
    });
    expect(fechada.consultantGaps.join(' ')).not.toContain('penhor');
  });

  /**
   * O VENCIMENTO é da SAFRA, e essa é a correção mais silenciosa desta versão.
   *
   * Ele muda conforme a CULTURA — soja vence na colheita dela, milho no dele — e
   * vale para todas as cédulas da safra. Enquanto foi um campo do formulário,
   * quem o digitava não tinha nada que dissesse qual era a data certa daquela
   * cultura: duas cédulas da mesma safra saíam com vencimentos diferentes, e a
   * única maneira de descobrir era comparar os papéis.
   */
  it('o vencimento vem da safra, e o cliente não consegue escrevê-lo', async () => {
    const consultor = await asUser(ANA);

    const mesa = await readCpr('PRM-2026-004', consultor);
    expect(mesa.body.data.known.seasonName).toBe('Soja 2026');
    expect(mesa.body.data.known.dueDate).toBe('2026-06-30T12:00:00.000Z');

    // Mandar um vencimento por cima é DESCARTADO pelo `whitelist` — e o que
    // fica gravado é o da safra.
    const salvo = await saveCpr('PRM-2026-004', consultor, {
      ...qualificacao,
      dueDate: '2030-01-01T00:00:00.000Z',
    });
    expect(salvo.status).toBe(200);
    expect(salvo.body.data.cpr.dueDate).toBe('2026-06-30T12:00:00.000Z');
    expect(salvo.body.data.gaps.join(' ')).not.toContain('vencimento');
  });

  /**
   * SAFRA SEM VENCIMENTO acertado é pendência — e a frase diz ONDE ela se
   * resolve, porque quem lê a lista é o consultor, e ele não tem campo de
   * vencimento em tela nenhuma.
   */
  it('safra sem vencimento cobra o admin, e não o consultor', async () => {
    await request(app.getHttpServer())
      .put('/api/v1/seasons/S2026/cpr-due-date')
      .set('Authorization', await asUser(ADMIN))
      .send({ cprDueDate: '2026-07-15T12:00:00.000Z' })
      .expect(200);

    const mesa = await readCpr('PRM-2026-004', await asUser(ANA));
    expect(mesa.body.data.known.dueDate).toBe('2026-07-15T12:00:00.000Z');

    // E uma data ilegível é recusada antes de virar o vencimento de todas as
    // cédulas da safra.
    const semData = await request(app.getHttpServer())
      .put('/api/v1/seasons/S2026/cpr-due-date')
      .set('Authorization', await asUser(ADMIN))
      .send({ cprDueDate: 'nem data é' });
    expect(semData.status).toBe(422);
  });

  /**
   * AS NOTAS FISCAIS do faturamento são a origem da dívida (cláusula VII), e
   * chegam como LEITURA. Eram dois campos de texto dentro da cédula, digitados
   * por quem não emitia a nota, e cabia uma só.
   */
  it('as notas do faturamento chegam como leitura, e são várias', async () => {
    const faturista = await asUser(FATURISTA);
    await attachInvoice(app, faturista, 'PRM-2026-004', { number: '55.318' });
    await attachInvoice(app, faturista, 'PRM-2026-004', {
      number: '55.319',
      duplicateNumber: '55.319-A',
    });

    const mesa = await readCpr('PRM-2026-004', await asUser(ANA));
    expect(mesa.body.data.known.invoices).toEqual([
      { number: '55.318', series: '1', duplicateNumber: '55.318-A' },
      { number: '55.319', series: '1', duplicateNumber: '55.319-A' },
    ]);
    expect(mesa.body.data.gaps.join(' ')).not.toContain('nota fiscal');
  });

  it('sem nota anexada, a cédula cobra o FATURISTA — e diz isso', async () => {
    const mesa = await readCpr('PRM-2026-004', await asUser(ANA));
    expect(mesa.body.data.gaps).toContain(
      'ao menos uma nota fiscal do faturamento (com o faturista)',
    );
  });

  /* ── O SCR: o anexo obrigatório ───────────────────────────────────────── */

  /**
   * O SCR é a única exigência da cédula que não vem do modelo do documento.
   *
   * Ela vem da decisão de não assinar título sem olhar o endividamento de quem o
   * emite: uma CPR é crédito, e o SCR é o relatório do Banco Central que diz
   * quanto o produtor já deve e a quem.
   */
  it('o SCR é anexo obrigatório, e ele é do consultor', async () => {
    const consultor = await asUser(ANA);

    const semScr = await readCpr('PRM-2026-004', consultor);
    expect(semScr.body.data.gaps).toContain(
      'o SCR do produtor (anexo obrigatório, com o consultor)',
    );

    const anexado = await saveScr('PRM-2026-004', consultor);
    expect(anexado.status).toBe(200);
    expect(anexado.body.data.cpr.scrFile.fileName).toBe('scr.pdf');
    expect(anexado.body.data.cpr.scrFile.contentType).toBe('application/pdf');
    // O CONTEÚDO não viaja no JSON da mesa: ele tem rota própria.
    expect(anexado.body.data.cpr.scrFile).not.toHaveProperty('content');
    expect(anexado.body.data.gaps.join(' ')).not.toContain('SCR');
  });

  /**
   * O ARQUIVO se baixa por rota própria, e quem alcança a permuta o alcança: é
   * assim que o EMISSOR confere o SCR na hora de emitir, sem pedir o PDF a
   * ninguém.
   */
  it('o SCR anexado é baixável por quem alcança a permuta', async () => {
    await saveScr('PRM-2026-001', await asUser(JOAO));

    const baixado = await request(app.getHttpServer())
      .get('/api/v1/barters/PRM-2026-001/cpr/scr')
      .set('Authorization', await asUser(EMISSOR));

    expect(baixado.status).toBe(200);
    expect(baixado.headers['content-type']).toContain('application/pdf');
    expect(baixado.headers['content-disposition']).toContain('attachment');
    expect(baixado.headers['content-disposition']).toContain('scr.pdf');
    expect(baixado.body.toString()).toContain('SCR');
  });

  it('anexo de tipo que não é documento é recusado', async () => {
    const recusado = await request(app.getHttpServer())
      .put('/api/v1/barters/PRM-2026-004/cpr/scr')
      .set('Authorization', await asUser(ANA))
      .attach('file', Buffer.from('MZ  '), {
        filename: 'scr.exe',
        contentType: 'application/x-msdownload',
      });

    expect(recusado.status).toBe(422);
    expect(recusado.body.message).toContain('PDF, XML ou imagem');
  });

  /* ── Quem escreve, quem lê ────────────────────────────────────────────── */

  /**
   * A MUDANÇA DE DONO, travada em um caso só.
   *
   * O CONSULTOR escreve — é ele quem tem a informação. O FATURISTA não escreve e
   * NEM LÊ: o que ele produz é a nota, não o título. É o teste que impede a
   * cédula de voltar para a mesa dele sem alguém escrever a linha em policy.ts.
   */
  it('só o consultor preenche a cédula — nem o faturista, nem o emissor', async () => {
    const dele = await saveCpr('PRM-2026-004', await asUser(ANA), { number: 'CPR-2026-014' });
    expect(dele.status).toBe(200);
    expect(dele.body.data.cpr.filledBy).toBe('Ana Paula Ferreira');

    for (const email of [ADMIN, COMITE, GERENTE, FATURISTA, EMISSOR]) {
      const escrita = await saveCpr('PRM-2026-004', await asUser(email), { number: 'X' });
      expect([email, escrita.status]).toEqual([email, 403]);
    }
  });

  /**
   * LER é outra pergunta, e três papéis passam por ela: o consultor (para
   * preencher), o emissor (para conferir) e o admin (para a segunda via do que a
   * operação dele emitiu).
   */
  it('consultor, emissor e admin leem a cédula; os demais não', async () => {
    // Cada um na permuta que o ESCOPO dele alcança: a PRM-2026-004 está
    // aprovada (a carteira da Ana) e a PRM-2026-001 já foi faturada, que é onde
    // o emissor começa a enxergar.
    for (const [email, code] of [
      [ANA, 'PRM-2026-004'],
      [EMISSOR, 'PRM-2026-001'],
      [ADMIN, 'PRM-2026-004'],
    ] as const) {
      const leitura = await readCpr(code, await asUser(email));
      expect([email, leitura.status]).toEqual([email, 200]);
    }

    // O FATURISTA está nesta lista desde que a cédula saiu das mãos dele: o que
    // ele produz é a nota, não o título.
    for (const email of [COMITE, GERENTE, FATURISTA]) {
      const leitura = await readCpr('PRM-2026-001', await asUser(email));
      expect([email, leitura.status]).toEqual([email, 403]);
    }
  });

  /**
   * O CONSULTOR só alcança a própria carteira, e a cédula não afrouxa isso: ela
   * abre pela mesma porta do detalhe da permuta.
   */
  it('a cédula de permuta de outro consultor não abre', async () => {
    const outro = await readCpr('PRM-2026-004', await asUser(JOAO));
    expect(outro.status).toBe(403);
  });

  /**
   * O CONSULTOR PREENCHE DESDE O RASCUNHO. É a razão prática da mudança: a
   * permuta demora semanas para chegar ao faturamento, e a visita à fazenda é
   * hoje. Coletar depois é coletar por telefone.
   */
  it('a cédula do rascunho já aceita preenchimento', async () => {
    const rascunho = await saveCpr('PRM-2026-009', await asUser(JOAO), qualificacao);
    expect(rascunho.status).toBe(200);
    expect(rascunho.body.data.cpr.emitterRg).toBe('10.234.567-8');
  });

  /* ── O rascunho: salvável pela metade ────────────────────────────────── */

  /**
   * O rascunho é salvável PELA METADE, e é assim que o trabalho acontece: a
   * qualificação o consultor tem da visita, a matrícula costuma vir por e-mail do
   * produtor no dia seguinte.
   */
  it('salva pela metade, e o que falta continua listado', async () => {
    const consultor = await asUser(ANA);
    const salvo = await saveCpr('PRM-2026-004', consultor, qualificacao);

    expect(salvo.status).toBe(200);
    expect(salvo.body.data.cpr.emitterRg).toBe('10.234.567-8');
    expect(salvo.body.data.cpr.filledBy).toBe('Ana Paula Ferreira');
    expect(salvo.body.data.complete).toBe(false);
    expect(salvo.body.data.gaps).toContain('cultivar do grão');
    expect(salvo.body.data.gaps).not.toContain('RG do emitente');
  });

  /**
   * O SEGUNDO salvamento não pode apagar o primeiro. É a diferença entre um
   * formulário que guarda o trabalho e um que o perde a cada aba fechada.
   */
  it('o campo ausente do payload fica como estava', async () => {
    const consultor = await asUser(ANA);
    await saveCpr('PRM-2026-004', consultor, qualificacao);
    const depois = await saveCpr('PRM-2026-004', consultor, padraoDoGrao);

    expect(depois.body.data.cpr.cultivar).toBe('BMX Ativa RR');
    // O RG veio da gravação anterior, e continua lá.
    expect(depois.body.data.cpr.emitterRg).toBe('10.234.567-8');
    expect(depois.body.data.cpr.number).toBe('CPR-2026-014');
  });

  /**
   * O QUE A PROPOSTA PEDE E A CÉDULA NÃO IMPRIME: CNH, filiação, e-mail, RG do
   * cônjuge, avalistas e hipotecas são gravados e NÃO entram em `gaps`.
   * Cobrá-los travaria a geração de um documento que não os usa.
   */
  it('os campos da proposta são gravados sem travar a geração', async () => {
    const salvo = await saveCpr('PRM-2026-004', await asUser(ANA), {
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
    const consultor = await asUser(ANA);
    await saveCpr('PRM-2026-004', consultor, {
      guarantors: [{ name: 'Primeiro' }, { name: 'Segundo' }],
    });

    const semTocar = await saveCpr('PRM-2026-004', consultor, { cultivar: 'BMX Ativa RR' });
    expect(semTocar.body.data.cpr.guarantors).toHaveLength(2);

    const um = await saveCpr('PRM-2026-004', consultor, { guarantors: [{ name: 'Único' }] });
    expect(um.body.data.cpr.guarantors).toHaveLength(1);
    expect(um.body.data.cpr.guarantors[0].name).toBe('Único');
  });

  /**
   * As LAVOURAS são substituídas em bloco, e é o que uma lista editada numa tela
   * precisa: mesclar por posição faria "apaguei a primeira" virar "editei a
   * primeira, e a segunda sumiu".
   */
  it('mandar as lavouras substitui as que estavam lá; omiti-las preserva', async () => {
    const consultor = await asUser(ANA);
    const duas = await saveCpr('PRM-2026-004', consultor, {
      areas: [lavoura, { ...lavoura, locality: 'Linha São João', withinLargerArea: true }],
    });
    expect(duas.body.data.cpr.areas).toHaveLength(2);
    expect(duas.body.data.cpr.areas[1].withinLargerArea).toBe(true);

    // Um salvamento que não fala de lavoura não mexe nelas.
    const semTocar = await saveCpr('PRM-2026-004', consultor, { cultivar: 'BMX Ativa RR' });
    expect(semTocar.body.data.cpr.areas).toHaveLength(2);

    // Uma lista com uma só substitui as duas.
    const uma = await saveCpr('PRM-2026-004', consultor, { areas: [lavoura] });
    expect(uma.body.data.cpr.areas).toHaveLength(1);
    expect(uma.body.data.cpr.areas[0].locality).toBe('Água Boa');
    expect(uma.body.data.cpr.areas[0].owners).toEqual([
      { name: 'Antônio Pereira', document: '111.222.333-44' },
    ]);
  });

  it('o município do cadastro do produtor entra como sugestão, não como campo gravado', async () => {
    const resposta = await readCpr('PRM-2026-004', await asUser(ANA));
    expect(resposta.body.data.suggestion).toEqual({ emitterCity: 'Marialva/PR' });
  });

  /**
   * A REPETIÇÃO REAL do trabalho: o mesmo produtor emite cédula a cada safra, e
   * o RG, o endereço e as matrículas dele são os mesmos da vez passada.
   *
   * A sugestão vem da última CÉDULA do produtor — e não do cadastro dele —
   * porque quem escreve cadastro é o admin. Resolver a digitação dando ao
   * consultor a caneta do cadastro trocaria um incômodo por uma mudança de quem
   * pode alterar cliente.
   */
  it('a cédula anterior do mesmo produtor volta como sugestão na próxima', async () => {
    const consultor = await asUser(JOAO);
    // PRM-2026-001 é do Antônio e ainda não teve a cédula emitida — editável.
    await saveCpr('PRM-2026-001', consultor, { ...qualificacao, areas: [lavoura] });

    // Uma permuta NOVA para o mesmo Antônio.
    const criada = await request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', consultor)
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

    const nova = await readCpr(code, consultor);
    expect(nova.body.data.cpr).toBeNull();
    expect(nova.body.data.suggestion.emitterRg).toBe('10.234.567-8');
    expect(nova.body.data.suggestion.areas[0].registryNumber).toBe('12.345');
    // O NÚMERO da cédula não é sugerido: cada uma tem o seu, e repeti-lo faria
    // duas cédulas nascerem com a mesma numeração.
    expect(nova.body.data.suggestion.number).toBeUndefined();
    // O SCR também não: ele é uma fotografia com data, e a da safra passada não
    // diz nada sobre o endividamento de hoje.
    expect(nova.body.data.suggestion.scrFileId).toBeUndefined();
  });

  /**
   * Depois que o consultor escreveu, o que está na tela é dele. Oferecer por
   * cima o texto de uma cédula antiga é a maneira mais fácil de sobrescrever uma
   * correção que alguém acabou de fazer.
   */
  it('com rascunho começado, não há mais sugestão', async () => {
    const consultor = await asUser(ANA);
    await saveCpr('PRM-2026-004', consultor, { emitterRg: '99.999.999-9' });
    const resposta = await readCpr('PRM-2026-004', consultor);
    expect(resposta.body.data.suggestion).toEqual({});
  });

  /**
   * O QUE A PERMUTA JÁ SABE não é campo. Mandar sacas ou valor por cima é
   * descartado pelo `whitelist` do ValidationPipe — e é para descartar mesmo: um
   * número na cédula que discorde do registro é um título cobrando o que não foi
   * acordado.
   */
  it('valor e sacas mandados pelo cliente são descartados', async () => {
    const salvo = await saveCpr('PRM-2026-004', await asUser(ANA), {
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
    const recusado = await saveCpr('PRM-2026-004', await asUser(ANA), { maxMoisture: 140 });
    expect(recusado.status).toBe(422);
    expect(recusado.body.message).toContain('percentual');
  });

  it('código que não existe é 404, e não uma cédula em branco', async () => {
    const resposta = await readCpr('PRM-9999-999', await asUser(ANA));
    expect(resposta.status).toBe(404);
  });

  /* ── A emissão: os três atos do emissor ──────────────────────────────── */

  /**
   * DEIXA A PERMUTA PRONTA PARA EMITIR: a cédula completa e a nota anexada.
   *
   * A PRM-2026-001 é a única já faturada do dataset, e a cédula dela já vem
   * pronta do seed — mas os testes que a usam mexem nela, então esta função
   * reconstrói o estado a partir do que cada ato exige.
   */
  const prontaParaEmitir = async (code = 'PRM-2026-001') => {
    const consultor = await asUser(JOAO);
    await saveCpr(code, consultor, { ...qualificacao, ...padraoDoGrao, areas: [lavoura] });
    await saveScr(code, consultor);
  };

  /**
   * A EMISSÃO é a CONFERÊNCIA do fluxo, e é o único momento em que alguém diz
   * "este papel não está pronto".
   *
   * A recusa não é um estado — o emissor não devolve a permuta a ninguém — e sim
   * um 422 com a lista por extenso, cada item dizendo com quem ele se resolve.
   */
  it('a cédula com lacuna não é emitida, e a recusa diz o que falta', async () => {
    const recusada = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/issue')
      .set('Authorization', await asUser(EMISSOR))
      .send({});

    // O dataset traz a cédula completa, então a lacuna precisa ser criada: uma
    // cédula sem número não sai.
    expect(recusada.status).toBe(200);

    await resetDb(app);
    await saveCpr('PRM-2026-001', await asUser(JOAO), { number: '' });
    const semNumero = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/issue')
      .set('Authorization', await asUser(EMISSOR))
      .send({});
    expect(semNumero.status).toBe(422);
    expect(semNumero.body.message).toContain('não pode ser emitida');
    expect(semNumero.body.message).toContain('número da CPR');
  });

  /**
   * O TRECHO INTEIRO DO EMISSOR: emitir, colher as assinaturas, registrar.
   *
   * São três atos e três estados porque eles acontecem em dias diferentes — a
   * cédula é gerada hoje, assinada quando o produtor vem à cidade, registrada
   * quando o cartório responde. Enquanto isso não tinha etapa, uma permuta
   * faturada dizia "pronta" com o título por emitir.
   */
  it('emitir, assinar e registrar movem a permuta, na ordem', async () => {
    await prontaParaEmitir();
    const emissor = await asUser(EMISSOR);
    const post = (rota: string, body: Record<string, unknown>) =>
      request(app.getHttpServer())
        .post(`/api/v1/barters/PRM-2026-001/cpr/${rota}`)
        .set('Authorization', emissor)
        .send(body);

    const emitida = await post('issue', { note: 'Duas vias impressas.' });
    expect(emitida.status).toBe(200);
    expect(emitida.body.data.status).toBe('cprIssued');
    expect(emitida.body.data.statusLabel).toBe('CPR emitida, a assinar');
    expect(emitida.body.data.cprEmittedBy).toBe('Renata Bicudo');
    expect(emitida.body.data.cprEmittedAt).toBeTruthy();
    expect(emitida.body.data.waitingFor).toBe('emitter');
    expect(emitida.body.data.nextAction).toBe('cprSign');

    const assinada = await assinarCpr('PRM-2026-001', emissor, {
      note: 'Emitente e cônjuge, presencial.',
    });
    expect(assinada.status).toBe(200);
    expect(assinada.body.data.status).toBe('cprSigned');
    expect(assinada.body.data.cprSignedAt).toBeTruthy();
    expect(assinada.body.data.cprSignatureNote).toContain('presencial');

    // E O PAPEL FICOU: a data do ato sem o documento é a metade que não prova
    // nada. O anexo entra pela CÉDULA (é dela), e a data pela PERMUTA (é o
    // andamento) — as duas metades do mesmo fato, cada uma onde mora.
    const comAssinatura = await readCpr('PRM-2026-001', emissor);
    expect(comAssinatura.body.data.cpr.signedFile.fileName).toBe('cpr-assinada.pdf');
    expect(comAssinatura.body.data.cpr.signedFile.contentType).toBe('application/pdf');

    const registrada = await post('registration', {
      registryNumber: 'R-4 / 18.442',
      registryPlace: 'CRI Maringá/PR',
    });
    expect(registrada.status).toBe(200);
    expect(registrada.body.data.status).toBe('cprRegistered');
    expect(registrada.body.data.statusLabel).toBe('CPR registrada');
    expect(registrada.body.data.cprRegistryNumber).toBe('R-4 / 18.442');
    expect(registrada.body.data.cprRegistryPlace).toBe('CRI Maringá/PR');
    // AGORA sim é fim de linha: não há mais próximo ato.
    expect(registrada.body.data.waitingFor).toBeNull();
    expect(registrada.body.data.nextAction).toBeNull();

    // E a linha do tempo guarda o número do registro, que é o que se leva ao
    // cartório para pedir a certidão.
    const eventos = registrada.body.data.events as { action: string; note: string | null }[];
    expect(eventos.at(-1)?.action).toBe('cprRegister');
    expect(eventos.at(-1)?.note).toContain('R-4 / 18.442');
  });

  /**
   * O PAPEL ASSINADO É OBRIGATÓRIO PARA ASSINAR.
   *
   * É a correção do ato, e não um rigor a mais: a cédula sai do sistema em
   * branco e volta assinada, e enquanto não havia onde guardar a que voltou, a
   * permuta dizia "assinada" sem ter como mostrar. Quem pedisse a segunda via
   * receberia o documento em branco — diferente, portanto, do que está na mão do
   * produtor, que é o que vale.
   *
   * O REGISTRO é o contrário, e de propósito: lá o papel é PROVA de um fato que
   * o número já afirma, e o cartório devolve a via carimbada quando devolve.
   * Exigi-la travaria o fim da linha num protocolo.
   */
  it('assinar exige a cédula assinada anexada; registrar não exige a via', async () => {
    await prontaParaEmitir();
    const emissor = await asUser(EMISSOR);
    await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/issue')
      .set('Authorization', emissor)
      .send({})
      .expect(200);

    const semPapel = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/signatures')
      .set('Authorization', emissor)
      .send({ note: 'Assinou, mas o papel está na gaveta.' });
    expect(semPapel.status).toBe(422);
    expect(semPapel.body.message).toContain('Anexe a cédula assinada');

    // E a permuta NÃO andou: o ato não aconteceu.
    const parada = await request(app.getHttpServer())
      .get('/api/v1/barters/PRM-2026-001')
      .set('Authorization', emissor);
    expect(parada.body.data.status).toBe('cprIssued');

    expect((await assinarCpr('PRM-2026-001', emissor)).status).toBe(200);

    // O REGISTRO passa sem anexo nenhum — e a cédula fica sem a via, o que é um
    // estado legítimo (o papel ainda está no cartório).
    const registrada = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/registration')
      .set('Authorization', emissor)
      .send({ registryNumber: 'R-4 / 18.442' });
    expect(registrada.status).toBe(200);

    const mesa = await readCpr('PRM-2026-001', emissor);
    expect(mesa.body.data.cpr.signedFile).not.toBeNull();
    expect(mesa.body.data.cpr.registryFile).toBeNull();
  });

  /**
   * OS DOCUMENTOS QUE VOLTARAM SÃO BAIXÁVEIS por quem alcança a permuta.
   *
   * É o ponto da mudança inteira — "deixar tudo no app" só vale se o papel sair
   * de lá depois. O ADMIN baixa sem pedir nada ao emissor, que é o caso real: o
   * jurídico quer a via assinada e o emissor está em outra praça.
   */
  it('a cédula assinada e a via do registro são baixáveis', async () => {
    await prontaParaEmitir();
    const emissor = await asUser(EMISSOR);
    await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/issue')
      .set('Authorization', emissor)
      .send({})
      .expect(200);
    await assinarCpr('PRM-2026-001', emissor);

    // A VIA CARIMBADA sobe JUNTO com o registro, que é o caminho comum quando o
    // cartório já devolveu.
    const registrada = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/registration')
      .set('Authorization', emissor)
      .field('registryNumber', 'R-4 / 18.442')
      .attach('file', Buffer.from('%PDF-1.4\nREGISTRO\n%%EOF\n'), {
        filename: 'via-registrada.pdf',
        contentType: 'application/pdf',
      });
    expect(registrada.status).toBe(200);
    expect(registrada.body.data.status).toBe('cprRegistered');

    const admin = await asUser(ADMIN);
    const assinada = await request(app.getHttpServer())
      .get('/api/v1/barters/PRM-2026-001/cpr/signed')
      .set('Authorization', admin);
    expect(assinada.status).toBe(200);
    expect(assinada.headers['content-type']).toContain('application/pdf');
    expect(assinada.headers['content-disposition']).toContain('cpr-assinada.pdf');

    const via = await request(app.getHttpServer())
      .get('/api/v1/barters/PRM-2026-001/cpr/registry-file')
      .set('Authorization', admin);
    expect(via.status).toBe(200);
    expect(via.headers['content-disposition']).toContain('via-registrada.pdf');
  });

  /**
   * A VIA QUE CHEGA DEPOIS — e a razão de a rota existir.
   *
   * O cartório dá o número na hora e devolve o papel carimbado semanas depois. O
   * ato do registro já aconteceu e não se refaz, então sem esta porta a via
   * ficaria de fora do sistema para sempre — que é exatamente o problema que
   * guardar os documentos veio resolver.
   */
  it('a via do registro pode ser anexada depois do ato, e não antes', async () => {
    await prontaParaEmitir();
    const emissor = await asUser(EMISSOR);

    const anexar = () =>
      request(app.getHttpServer())
        .put('/api/v1/barters/PRM-2026-001/cpr/registry-file')
        .set('Authorization', emissor)
        .attach('file', Buffer.from('%PDF-1.4\nREGISTRO\n%%EOF\n'), {
          filename: 'via-registrada.pdf',
          contentType: 'application/pdf',
        });

    // ANTES do registro não há o que comprovar.
    const cedo = await anexar();
    expect(cedo.status).toBe(422);
    expect(cedo.body.message).toContain('depois de a cédula ser registrada');

    await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/issue')
      .set('Authorization', emissor)
      .send({})
      .expect(200);
    await assinarCpr('PRM-2026-001', emissor);
    await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/registration')
      .set('Authorization', emissor)
      .send({ registryNumber: 'R-4 / 18.442' })
      .expect(200);

    const depois = await anexar();
    expect(depois.status).toBe(200);
    expect(depois.body.data.cpr.registryFile.fileName).toBe('via-registrada.pdf');

    // E a cédula continua REGISTRADA: juntar o papel não é um ato novo, e não
    // move a permuta — ela já estava no fim da linha.
    const permuta = await request(app.getHttpServer())
      .get('/api/v1/barters/PRM-2026-001')
      .set('Authorization', emissor);
    expect(permuta.body.data.status).toBe('cprRegistered');
  });

  /**
   * O ANEXO NOVO SUBSTITUI O ANTERIOR, e o antigo some do banco.
   *
   * Cada coluna guarda UM documento: duas vias penduradas na mesma cédula fariam
   * alguém conferir a errada — e a errada, aqui, é um título executável. É a
   * mesma regra do SCR.
   */
  it('a via reanexada substitui a anterior, sem deixar arquivo órfão', async () => {
    await prontaParaEmitir();
    const emissor = await asUser(EMISSOR);
    await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/issue')
      .set('Authorization', emissor)
      .send({})
      .expect(200);
    await assinarCpr('PRM-2026-001', emissor);
    await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/registration')
      .set('Authorization', emissor)
      .send({ registryNumber: 'R-4 / 18.442' })
      .expect(200);

    const prisma = app.get(PrismaService);
    const antes = await prisma.barterFile.count();
    for (const nome of ['primeira.pdf', 'corrigida.pdf']) {
      await request(app.getHttpServer())
        .put('/api/v1/barters/PRM-2026-001/cpr/registry-file')
        .set('Authorization', emissor)
        .attach('file', Buffer.from('%PDF-1.4\nREGISTRO\n%%EOF\n'), {
          filename: nome,
          contentType: 'application/pdf',
        })
        .expect(200);
    }

    const mesa = await readCpr('PRM-2026-001', emissor);
    expect(mesa.body.data.cpr.registryFile.fileName).toBe('corrigida.pdf');
    // Duas subidas, UM arquivo a mais: a primeira via saiu quando a segunda
    // entrou.
    expect(await prisma.barterFile.count()).toBe(antes + 1);
  });

  /**
   * A ORDEM é a do mundo: não se registra um título que ninguém assinou, e não
   * se assina um que não foi emitido. A recusa diz em que pé a CÉDULA está.
   */
  it('a cédula não se registra antes de assinada', async () => {
    await prontaParaEmitir();
    const emissor = await asUser(EMISSOR);

    const cedo = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/registration')
      .set('Authorization', emissor)
      .send({ registryNumber: 'R-4' });
    expect(cedo.status).toBe(422);
    expect(cedo.body.message).toContain('aguarda a emissão da cédula');
  });

  /** Sem número, "registrada" seria uma afirmação sem como ser conferida. */
  it('o registro exige o número', async () => {
    await prontaParaEmitir();
    const emissor = await asUser(EMISSOR);
    await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/issue')
      .set('Authorization', emissor)
      .send({})
      .expect(200);
    expect((await assinarCpr('PRM-2026-001', emissor)).status).toBe(200);

    const semNumero = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/registration')
      .set('Authorization', emissor)
      .send({});
    expect(semNumero.status).toBe(422);
    expect(semNumero.body.message).toContain('número do registro');
  });

  /**
   * DEPOIS DE EMITIDA, A CÉDULA NÃO SE REESCREVE.
   *
   * Até a emissão ela é rascunho e se corrige à vontade; do ato do emissor em
   * diante ela é um documento que existe no mundo, que alguém conferiu e assinou
   * embaixo. Reescrevê-la por baixo faria a segunda via sair diferente da
   * primeira — e é a primeira que está com o produtor.
   */
  it('a cédula emitida não aceita mais escrita', async () => {
    await prontaParaEmitir();
    await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/issue')
      .set('Authorization', await asUser(EMISSOR))
      .send({})
      .expect(200);

    const tarde = await saveCpr('PRM-2026-001', await asUser(JOAO), { emitterRg: '00.000.000-0' });
    expect(tarde.status).toBe(422);
    expect(tarde.body.message).toContain('não se reescreve depois de emitido');

    // O SCR também não se troca: ele é parte do que foi conferido.
    const outroScr = await saveScr('PRM-2026-001', await asUser(JOAO));
    expect(outroScr.status).toBe(422);
  });

  /**
   * O ALCANCE do emissor é o mais estreito da retaguarda: um degrau adiante do
   * faturista. A permuta que ainda não foi faturada não é dele — e a recusa não
   * conta o estado dela, pelo mesmo motivo do `POST /invoice`.
   */
  it('o emissor não alcança o que ainda não foi faturado', async () => {
    const emissor = await asUser(EMISSOR);
    for (const code of ['PRM-2026-004', 'PRM-2026-005', 'PRM-2026-002', 'PRM-2026-003']) {
      const resposta = await readCpr(code, emissor);
      expect([code, resposta.status]).toEqual([code, 403]);
      expect(resposta.body.message).toBe('Você não tem acesso a esta permuta');
    }
  });

  /**
   * A TRILHA registra o preenchimento e a emissão pelo mesmo critério dos atos
   * que decidem dinheiro — e com folga: a cédula é título executável.
   *
   * O que a trilha NÃO leva é o conteúdo: despejar ali a qualificação civil de
   * um produtor espalharia dado pessoal por um registro que ninguém apaga.
   */
  it('preencher a cédula deixa rastro na trilha, sem copiar o conteúdo dela', async () => {
    await saveCpr('PRM-2026-004', await asUser(ANA), qualificacao);

    const trilha = await request(app.getHttpServer())
      .get('/api/v1/audit-logs?action=barter.cpr-saved')
      .set('Authorization', await asUser(ADMIN));

    expect(trilha.status).toBe(200);
    const linha = trilha.body.data[0];
    expect(linha.actorName).toBe('Ana Paula Ferreira');
    expect(linha.targetLabel).toBe('PRM-2026-004');
    expect(linha.detail).toContain('CPR-2026-014');
    expect(linha.detail).toContain('faltam');
    expect(linha.detail).not.toContain('10.234.567-8');
  });

  /**
   * A EMISSÃO é o ato que AFIRMA que o título está correto. Quando um título for
   * questionado, "quem conferiu e em que dia?" é a primeira pergunta — e ela
   * precisa de resposta fora do registro da permuta.
   */
  it('a emissão e o registro deixam rastro, com quem conferiu', async () => {
    await prontaParaEmitir();
    const emissor = await asUser(EMISSOR);
    await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/issue')
      .set('Authorization', emissor)
      .send({})
      .expect(200);

    const trilha = await request(app.getHttpServer())
      .get('/api/v1/audit-logs?action=barter.cpr-issued')
      .set('Authorization', await asUser(ADMIN));

    expect(trilha.status).toBe(200);
    expect(trilha.body.data[0].actorName).toBe('Renata Bicudo');
    expect(trilha.body.data[0].targetLabel).toBe('PRM-2026-001');
    expect(trilha.body.data[0].detail).toContain('CPR-2026-014');
  });

  /* ── As bordas que a operação vai encontrar ──────────────────────────── */

  /**
   * O VENCIMENTO MUDA, E A CÉDULA EMITIDA NÃO.
   *
   * A colheita se antecipa e o admin corrige a data da safra. Isso vale para as
   * cédulas que ainda não saíram — e NÃO pode alcançar o título que já está com
   * o produtor: ele diz o que diz, e o papel não se reescreve à distância.
   */
  it('mudar o vencimento da safra não reescreve a cédula já emitida', async () => {
    await prontaParaEmitir();
    await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/issue')
      .set('Authorization', await asUser(EMISSOR))
      .send({})
      .expect(200);

    await request(app.getHttpServer())
      .put('/api/v1/seasons/S2026/cpr-due-date')
      .set('Authorization', await asUser(ADMIN))
      .send({ cprDueDate: '2026-08-31T12:00:00.000Z' })
      .expect(200);

    const emitida = await readCpr('PRM-2026-001', await asUser(EMISSOR));
    // A CÉDULA congelou: ela continua com a data que foi conferida e assinada.
    expect(emitida.body.data.cpr.dueDate).toBe('2026-06-30T12:00:00.000Z');
    // E a SAFRA já responde a data nova para as que ainda não saíram.
    expect(emitida.body.data.known.dueDate).toBe('2026-08-31T12:00:00.000Z');
  });

  /**
   * A CREDORA INCOMPLETA trava a emissão, e a recusa separa as duas listas: um
   * título sem a qualificação de quem cobra não é título, mas a pendência é de
   * OUTRA pessoa — mandar o emissor procurar um campo de CNPJ dentro do
   * formulário da cédula seria mandá-lo procurar onde não existe.
   */
  it('credora incompleta trava a emissão, e a recusa diz que é dela', async () => {
    await prontaParaEmitir();
    await request(app.getHttpServer())
      .put('/api/v1/creditor')
      .set('Authorization', await asUser(ADMIN))
      .send({ cnpj: '12.345.678/0001-90', city: 'Maringá/PR' })
      .expect(200);

    const recusada = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/issue')
      .set('Authorization', await asUser(EMISSOR))
      .send({});

    expect(recusada.status).toBe(422);
    expect(recusada.body.message).toContain('falta na credora');
    expect(recusada.body.message).toContain('razão social');
    expect(recusada.body.message).not.toContain('falta na cédula');
  });

  /**
   * A PERMUTA ANTERIOR AO LANÇAMENTO POR VERSÕES não tem safra, e por isso não
   * tem vencimento. A mesa dela ABRE mesmo assim, com a pendência escrita: uma
   * tela que quebrasse esconderia o registro em vez de dizer o que falta nele.
   */
  it('permuta sem safra não quebra a cédula — ela cobra o vencimento', async () => {
    const prisma = app.get(PrismaService);
    await prisma.barter.update({
      where: { code: 'PRM-2026-001' },
      data: { versionId: null, versionCode: '' },
    });

    // A MESA ABRE, e a safra não responde nada: uma tela que quebrasse
    // esconderia o registro em vez de dizer o que falta nele.
    const mesa = await readCpr('PRM-2026-001', await asUser(EMISSOR));
    expect(mesa.status).toBe(200);
    expect(mesa.body.data.known.dueDate).toBeNull();
    expect(mesa.body.data.known.seasonName).toBe('');

    // A CÉDULA JÁ GRAVADA mantém o vencimento que tinha — ele é o congelamento,
    // não uma leitura da safra. É por isso que a pendência ainda não apareceu:
    // o documento tem a data, e ela continua valendo.
    expect(mesa.body.data.cpr.dueDate).toBe('2026-06-30T12:00:00.000Z');
    expect(mesa.body.data.gaps.join(' ')).not.toContain('vencimento');

    // Na GRAVAÇÃO seguinte é que a ausência aparece: o servidor copia o
    // vencimento da safra a cada salvamento, e sem safra não há o que copiar. A
    // pendência então diz onde ela se resolve.
    const salva = await saveCpr('PRM-2026-001', await asUser(JOAO), { number: 'CPR-2026-014' });
    expect(salva.status).toBe(200);
    expect(salva.body.data.cpr.dueDate).toBeNull();
    expect(salva.body.data.gaps.join(' ')).toContain('vencimento da CPR');
  });

  /**
   * O PEDIDO DE ALTERAÇÃO é o caminho de volta da esteira, e ele para no
   * faturamento — e continua parando depois dele. O que saiu para fora não se
   * corrige por aqui, e um título emitido menos ainda.
   */
  it('não se pede alteração de permuta cuja cédula já foi emitida', async () => {
    await prontaParaEmitir();
    await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/issue')
      .set('Authorization', await asUser(EMISSOR))
      .send({})
      .expect(200);

    const pedido = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/change-request')
      .set('Authorization', await asUser(JOAO))
      .send({ note: 'O produtor quer trocar um insumo.' });
    expect(pedido.status).toBe(422);
  });

  /**
   * OS TRÊS ATOS na trilha global. A emissão já tem prova acima; estes dois
   * fecham o trecho — o registro é o que se leva ao cartório para pedir a
   * certidão, e ele precisa de resposta fora do registro da permuta.
   */
  it('a assinatura e o registro também deixam rastro', async () => {
    await prontaParaEmitir();
    const emissor = await asUser(EMISSOR);
    const post = (rota: string, body: Record<string, unknown>) =>
      request(app.getHttpServer())
        .post(`/api/v1/barters/PRM-2026-001/cpr/${rota}`)
        .set('Authorization', emissor)
        .send(body);

    await post('issue', {}).expect(200);
    expect((await assinarCpr('PRM-2026-001', emissor)).status).toBe(200);
    await post('registration', { registryNumber: 'R-4 / 18.442' }).expect(200);

    const admin = await asUser(ADMIN);
    const assinatura = await request(app.getHttpServer())
      .get('/api/v1/audit-logs?action=barter.cpr-signed')
      .set('Authorization', admin);
    expect(assinatura.body.data[0].actorName).toBe('Renata Bicudo');

    const registro = await request(app.getHttpServer())
      .get('/api/v1/audit-logs?action=barter.cpr-registered')
      .set('Authorization', admin);
    expect(registro.body.data[0].detail).toContain('R-4 / 18.442');
  });

  /**
   * O VENCIMENTO DA SAFRA na trilha: ele vale para TODAS as cédulas dela, e
   * mudá-lo antecipa ou adia a entrega de cada produtor que ainda não teve o
   * título emitido — num campo que ninguém mais confere depois.
   */
  it('mexer no vencimento da safra deixa rastro', async () => {
    await request(app.getHttpServer())
      .put('/api/v1/seasons/S2026/cpr-due-date')
      .set('Authorization', await asUser(ADMIN))
      .send({ cprDueDate: '2026-08-31T12:00:00.000Z' })
      .expect(200);

    const trilha = await request(app.getHttpServer())
      .get('/api/v1/audit-logs?action=season.cpr-due-date-set')
      .set('Authorization', await asUser(ADMIN));
    expect(trilha.body.data[0].targetLabel).toBe('S2026');
    expect(trilha.body.data[0].detail).toContain('31/08/2026');
  });

  /**
   * O EMISSOR ANEXA O SCR — a única escrita dele na cédula, junto com o número.
   *
   * Ela existe porque ele é quem fica TRAVADO pelo anexo: a cédula não sai sem
   * SCR, e "peça ao consultor e espere" é a resposta errada com o produtor na
   * sala. Anexar não é escrever a cédula — o que ele não pode é mexer no que
   * confere, e o SCR não é afirmação dele sobre o produtor: é o relatório do
   * Banco Central, do jeito que veio.
   */
  it('o emissor anexa o SCR que falta, e aí consegue emitir', async () => {
    const emissor = await asUser(EMISSOR);
    // A cédula do seed vem completa; tirar o SCR recria a situação real — o
    // consultor preencheu tudo e esqueceu o anexo.
    const prisma = app.get(PrismaService);
    await prisma.barterCpr.update({
      where: {
        barterId: (await prisma.barter.findUniqueOrThrow({ where: { code: 'PRM-2026-001' } })).id,
      },
      data: { scrFileId: null },
    });

    const travada = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/issue')
      .set('Authorization', emissor)
      .send({});
    expect(travada.status).toBe(422);
    expect(travada.body.message).toContain('SCR');

    const anexado = await saveScr('PRM-2026-001', emissor);
    expect(anexado.status).toBe(200);
    expect(anexado.body.data.cpr.scrFile.fileName).toBe('scr.pdf');

    const emitida = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/issue')
      .set('Authorization', emissor)
      .send({});
    expect(emitida.status).toBe(200);
  });

  /** E o que ele continua NÃO podendo: escrever o que confere. */
  it('anexar o SCR não abre o resto da cédula para o emissor', async () => {
    const escrita = await saveCpr('PRM-2026-001', await asUser(EMISSOR), { emitterRg: 'X' });
    expect(escrita.status).toBe(403);
  });

  /**
   * O NÚMERO DA CÉDULA é informado NO ATO de emitir — é a única coisa dela que o
   * emissor escreve, e escreve porque é a única que ele tem: a numeração vem de
   * fora do sistema (cartório, B3, controle da credora). Cobrá-la do consultor
   * no encaminhamento travaria a esteira num número que só existe semanas
   * depois.
   */
  it('o emissor informa o número da cédula ao emitir', async () => {
    const prisma = app.get(PrismaService);
    const barter = await prisma.barter.findUniqueOrThrow({ where: { code: 'PRM-2026-001' } });
    await prisma.barterCpr.update({ where: { barterId: barter.id }, data: { number: '' } });

    const emissor = await asUser(EMISSOR);
    const semNumero = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/issue')
      .set('Authorization', emissor)
      .send({});
    expect(semNumero.status).toBe(422);
    expect(semNumero.body.message).toContain('número da CPR');

    const comNumero = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/cpr/issue')
      .set('Authorization', emissor)
      .send({ number: 'CPR-2026-099' });
    expect(comNumero.status).toBe(200);

    const mesa = await readCpr('PRM-2026-001', emissor);
    expect(mesa.body.data.cpr.number).toBe('CPR-2026-099');
  });
});
