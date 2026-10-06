import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import {
  ADMIN,
  COMITE,
  EMISSOR,
  FATURISTA,
  GERENTE,
  JOAO,
  SEGURADORA,
  UNIT,
  createTestApp,
  forwardWithCpr,
  loginAs,
  resetDb,
} from './utils';

/**
 * A SEGURADORA na esteira — o posto entre a decisão do comitê e o faturista,
 * que só existe para a permuta COM SEGURO.
 *
 * As provas travam quatro coisas:
 *
 * 1. **o seguro decide o caminho**: aprovada com seguro, a permuta cai na
 *    seguradora; sem seguro, direto no faturista — e o comitê só escolhe o
 *    desfecho;
 * 2. **a apólice é documento E número**, no mesmo ato, e só a seguradora (e o
 *    admin) o pratica;
 * 3. **cada aprovação volta ao seu par**: a ressalva continua ressalva quando a
 *    permuta chega ao faturista;
 * 4. **a cédula cita o número que a seguradora informou** — e só ele.
 */
describe('Seguradora (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const asUser = async (email: string) => `Bearer ${await loginAs(app, email)}`;

  /** O Barter vigente da soja — é nele que a permuta nova cai. */
  const VERSAO = 'SOJA2627.02';

  /** A mesma permuta de `insurance.e2e-spec.ts`: Antônio, 120 ha de soja, Maringá/PR. */
  const payload = {
    producerId: 1,
    unitId: UNIT.filial02,
    seasonId: 3, // Soja 26/27
    plantedAreaHa: 120,
    inputs: [
      { productId: 5, quantity: 48 },
      { productId: 6, quantity: 300 },
      { productId: 7, quantity: 18 },
    ],
  };

  const APOLICE = 'AP-2026-778.412';

  const ligarSeguro = async (policy = 'required') =>
    request(app.getHttpServer())
      .put(`/api/v1/barter-versions/${VERSAO}/insurance`)
      .set('Authorization', await asUser(ADMIN))
      .send({ policy });

  /**
   * Uma permuta NA MESA DO COMITÊ: registrada, com a cédula do consultor,
   * encaminhada e com o parecer do gerente. É o preâmbulo de todo caso daqui —
   * a seguradora só entra depois da decisão.
   */
  const noComite = async (extra: object = {}): Promise<string> => {
    const joao = await asUser(JOAO);
    const criada = await request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', joao)
      .send({ ...payload, ...extra });
    expect(criada.status).toBe(201);
    const code = criada.body.data.code as string;

    expect((await forwardWithCpr(app, joao, code)).status).toBe(200);
    const parecer = await request(app.getHttpServer())
      .post(`/api/v1/barters/${code}/opinion`)
      .set('Authorization', await asUser(GERENTE))
      .send({ note: 'Estoque conferido na unidade, volume compatível com a área.' });
    expect(parecer.status).toBe(200);
    return code;
  };

  const decidir = async (code: string, body: object = { status: 'approved' }) =>
    request(app.getHttpServer())
      .post(`/api/v1/barters/${code}/review`)
      .set('Authorization', await asUser(COMITE))
      .send(body);

  const informar = async (
    email: string,
    code: string,
    fields: { policyNumber?: string; note?: string } = { policyNumber: APOLICE },
    withFile = true,
  ) => {
    let req = request(app.getHttpServer())
      .post(`/api/v1/barters/${code}/insure`)
      .set('Authorization', await asUser(email));
    for (const [key, value] of Object.entries(fields)) {
      if (value !== undefined) req = req.field(key, value);
    }
    if (withFile) {
      req = req.attach('file', Buffer.from('%PDF-1.4\nAPOLICE\n%%EOF\n'), {
        filename: 'apolice.pdf',
        contentType: 'application/pdf',
      });
    }
    return req;
  };

  const ler = async (email: string, code: string) =>
    request(app.getHttpServer())
      .get(`/api/v1/barters/${code}`)
      .set('Authorization', await asUser(email));

  /* ── O caminho ───────────────────────────────────────────────────────── */

  it('aprovada COM seguro, a permuta cai na mesa da seguradora', async () => {
    await ligarSeguro('required');
    const code = await noComite();

    const decisão = await decidir(code);
    expect(decisão.status).toBe(200);
    expect(decisão.body.data).toMatchObject({
      status: 'awaitingPolicy',
      statusLabel: 'Aprovada, aguardando a apólice',
      waitingFor: 'insurer',
      nextAction: 'insure',
      insured: true,
      insurancePolicyNumber: null,
      insurancePolicyFile: null,
    });

    // A decisão continua tendo sido uma APROVAÇÃO na linha do tempo.
    const steps = decisão.body.data.steps as {
      action: string;
      state: string;
      outcomeLabel: string | null;
      roleLabel: string | null;
    }[];
    expect(steps.find((step) => step.action === 'review')).toMatchObject({
      state: 'done',
      outcomeLabel: 'Aprovada',
    });
    expect(steps.find((step) => step.action === 'insure')).toMatchObject({
      state: 'current',
      roleLabel: 'Seguradora',
    });
  });

  it('aprovada SEM seguro, ela vai direto ao faturista — e a etapa nem aparece', async () => {
    const code = await noComite();

    const decisão = await decidir(code);
    expect(decisão.status).toBe(200);
    expect(decisão.body.data).toMatchObject({
      status: 'approved',
      waitingFor: 'biller',
      insured: false,
    });
    expect(
      (decisão.body.data.steps as { action: string }[]).map((step) => step.action),
    ).not.toContain('insure');

    // E a seguradora não a enxerga: nunca foi trabalho dela.
    expect((await ler(SEGURADORA, code)).status).toBe(403);
    // O admin, que enxerga tudo, ouve que ela não passa pela seguradora.
    const tentativa = await informar(ADMIN, code);
    expect(tentativa.status).toBe(422);
    expect(tentativa.body.message).toBe(
      'Esta permuta não tem seguro — ela não passa pela seguradora',
    );
  });

  /** O produtor que recusou o seguro opcional segue o caminho sem seguro. */
  it('o opcional recusado vai ao faturista, e o aceito à seguradora', async () => {
    await ligarSeguro('optional');

    const recusado = await noComite({ insurance: false });
    expect((await decidir(recusado)).body.data.status).toBe('approved');

    const aceito = await noComite({ insurance: true });
    expect((await decidir(aceito)).body.data.status).toBe('awaitingPolicy');
  });

  /* ── O ato ───────────────────────────────────────────────────────────── */

  it('a seguradora anexa a apólice e informa o número, e a permuta segue ao faturista', async () => {
    await ligarSeguro('required');
    const code = await noComite();
    await decidir(code);

    const resposta = await informar(SEGURADORA, code, {
      policyNumber: `  ${APOLICE}  `,
      note: 'Cobertura de granizo e seca.',
    });
    expect(resposta.status).toBe(200);
    expect(resposta.body.data).toMatchObject({
      status: 'approved',
      waitingFor: 'biller',
      insurancePolicyNumber: APOLICE,
      insuredBy: 'Sílvia Moreira',
      insuranceNote: 'Cobertura de granizo e seca.',
      insurancePolicyFile: { fileName: 'apolice.pdf', contentType: 'application/pdf' },
    });
    expect(resposta.body.data.insuredAt).not.toBeNull();

    // O NÚMERO vai por extenso na linha do tempo.
    const evento = (resposta.body.data.events as { action: string; note: string }[]).find(
      (linha) => linha.action === 'insure',
    );
    expect(evento?.note).toBe(`Apólice ${APOLICE} — Cobertura de granizo e seca.`);

    // Chegar de novo é chegar tarde.
    const deNovo = await informar(SEGURADORA, code);
    expect(deNovo.status).toBe(422);
    expect(deNovo.body.message).toBe('A apólice desta permuta já foi informada');

    // O FATURISTA agora a enxerga, e baixa a apólice sem pedi-la a ninguém.
    const arquivo = await request(app.getHttpServer())
      .get(`/api/v1/barters/${code}/policy-file`)
      .set('Authorization', await asUser(FATURISTA));
    expect(arquivo.status).toBe(200);
    expect(arquivo.headers['content-type']).toContain('application/pdf');
    expect(arquivo.headers['content-disposition']).toContain('apolice.pdf');
  });

  /** A ressalva que o comitê escreveu continua sendo ressalva no faturista. */
  it('a aprovada com ressalva volta como aprovada com ressalva', async () => {
    await ligarSeguro('required');
    const code = await noComite();

    const decisão = await decidir(code, {
      status: 'approvedWithConditions',
      note: 'Retirada só depois da confirmação do plantio.',
    });
    expect(decisão.body.data).toMatchObject({
      status: 'awaitingPolicyWithConditions',
      statusLabel: 'Aprovada com ressalva, aguardando a apólice',
      waitingFor: 'insurer',
    });

    const resposta = await informar(SEGURADORA, code);
    expect(resposta.status).toBe(200);
    expect(resposta.body.data.status).toBe('approvedWithConditions');
  });

  it('sem o arquivo ou sem o número, a apólice não entra', async () => {
    await ligarSeguro('required');
    const code = await noComite();
    await decidir(code);

    const semArquivo = await informar(SEGURADORA, code, { policyNumber: APOLICE }, false);
    expect(semArquivo.status).toBe(422);
    expect(semArquivo.body.message).toBe('Anexe a apólice do seguro (campo "file")');

    const semNumero = await informar(SEGURADORA, code, {});
    expect(semNumero.status).toBe(422);
    expect(semNumero.body.message).toBe('Informe o número da apólice do seguro (até 60 caracteres)');

    const emBranco = await informar(SEGURADORA, code, { policyNumber: '   ' });
    expect(emBranco.status).toBe(422);
    expect(emBranco.body.message).toBe('Informe o número da apólice do seguro (até 60 caracteres)');

    // Nada ficou gravado: ela continua esperando a apólice.
    expect((await ler(SEGURADORA, code)).body.data).toMatchObject({
      status: 'awaitingPolicy',
      insurancePolicyFile: null,
    });
  });

  /* ── Quem pode ───────────────────────────────────────────────────────── */

  it('só a seguradora (e o admin) informa a apólice', async () => {
    await ligarSeguro('required');
    const code = await noComite();
    await decidir(code);

    for (const email of [JOAO, GERENTE, COMITE, FATURISTA, EMISSOR]) {
      expect([email, (await informar(email, code)).status]).toEqual([email, 403]);
    }

    const doAdmin = await informar(ADMIN, code);
    expect(doAdmin.status).toBe(200);
    expect(doAdmin.body.data.status).toBe('approved');
  });

  /**
   * O ESCOPO da seguradora: o trecho dela da linha, e só das permutas com
   * seguro. E o faturista não enxerga a que ainda espera a apólice — ela não
   * chegou ao faturamento.
   */
  it('a seguradora enxerga só o que tem seguro e chegou nela', async () => {
    await ligarSeguro('required');
    const naMesa = await noComite();
    await decidir(naMesa);
    const aindaNoComite = await noComite();

    const lista = await request(app.getHttpServer())
      .get('/api/v1/barters')
      .set('Authorization', await asUser(SEGURADORA));
    expect(lista.status).toBe(200);
    expect((lista.body.data as { code: string }[]).map((b) => b.code)).toEqual([naMesa]);

    expect((await ler(SEGURADORA, aindaNoComite)).status).toBe(403);
    // As aprovadas SEM seguro do dataset também não aparecem para ela.
    expect((await ler(SEGURADORA, 'PRM-2026-004')).status).toBe(403);

    // O faturista ainda não a vê, e quem tenta faturar ouve onde ela está.
    expect((await ler(FATURISTA, naMesa)).status).toBe(403);
    const cedo = await request(app.getHttpServer())
      .post(`/api/v1/barters/${naMesa}/invoice`)
      .set('Authorization', await asUser(ADMIN))
      .send({});
    expect(cedo.status).toBe(422);
    expect(cedo.body.message).toBe('Esta permuta aguarda a apólice da seguradora');
  });

  /* ── A cédula ────────────────────────────────────────────────────────── */

  /**
   * A APÓLICE SAIU DO FORMULÁRIO DO CONSULTOR: a cédula cita o número que a
   * seguradora informou, e o que o consultor mandar é descartado.
   */
  it('a cédula cita a apólice que a seguradora informou — e só ela', async () => {
    await ligarSeguro('required');
    const code = await noComite();
    await decidir(code);

    const joao = await asUser(JOAO);
    const tentativa = await request(app.getHttpServer())
      .put(`/api/v1/barters/${code}/cpr`)
      .set('Authorization', joao)
      .send({ insurancePolicy: 'AP-DIGITADA-PELO-CONSULTOR' });
    expect(tentativa.status).toBe(200);
    expect(tentativa.body.data.known.insurancePolicy).toBe('');
    expect(tentativa.body.data.cpr).not.toHaveProperty('insurancePolicy');

    await informar(SEGURADORA, code);

    const mesa = await request(app.getHttpServer())
      .get(`/api/v1/barters/${code}/cpr`)
      .set('Authorization', joao);
    expect(mesa.body.data.known.insurancePolicy).toBe(APOLICE);
  });

  /**
   * Aprovada esperando a apólice já é negócio FECHADO, e conta na meta: contada
   * só a partir do faturista, ela sumiria da barra enquanto a seguradora
   * trabalha. Depois da apólice, continua contando — uma vez só.
   */
  it('a permuta esperando a apólice já conta como decidida a favor', async () => {
    const realizadas = async () =>
      (
        await request(app.getHttpServer())
          .get(`/api/v1/barter-versions/${VERSAO}`)
          .set('Authorization', await asUser(ADMIN))
      ).body.data.realized.barters as number;

    await ligarSeguro('required');
    const code = await noComite();
    const antes = await realizadas();

    await decidir(code);
    expect(await realizadas()).toBe(antes + 1);

    await informar(SEGURADORA, code);
    expect(await realizadas()).toBe(antes + 1);
  });
});
