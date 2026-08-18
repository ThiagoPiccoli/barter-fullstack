import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import {
  ADMIN,
  BACK_OFFICE,
  COMITE,
  FATURISTA,
  GERENTE,
  GERENTE_SUL,
  JOAO,
  SEED_PASSWORD,
  UNIT,
  createTestApp,
  loginAs,
  resetDb,
} from './utils';

/**
 * Papéis de RETAGUARDA (gerente, comitê, faturista) — o que cada um pode hoje.
 *
 * O contrato entre eles ainda vai ser desenhado; o que estes testes fixam é o
 * ponto de partida, que é justamente onde um RBAC costuma vazar: papel novo
 * ENXERGA a operação (leitura) e não ESCREVE nada até alguém decidir que
 * escreve. Sem isto, cada papel acrescentado herdaria em silêncio o que as
 * regras antigas liberavam por não conhecê-lo.
 */
describe('RBAC — papéis de retaguarda (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const asUser = async (email: string) => `Bearer ${await loginAs(app, email)}`;

  it('cada papel novo entra e se identifica pelo próprio papel', async () => {
    const cases: [string, string][] = [
      [GERENTE, 'manager'],
      [COMITE, 'committee'],
      [FATURISTA, 'biller'],
    ];

    for (const [email, role] of cases) {
      const response = await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email, password: SEED_PASSWORD });
      expect(response.status).toBe(200);
      expect(response.body.data.user.role).toBe(role);
      expect(response.body.data.user.mustChangePassword).toBe(false);
    }
  });

  it('comitê e faturista acompanham a operação inteira, não uma carteira', async () => {
    for (const email of [COMITE, FATURISTA]) {
      const auth = await asUser(email);

      const barters = await request(app.getHttpServer())
        .get('/api/v1/barters')
        .set('Authorization', auth);
      expect(barters.status).toBe(200);
      // As 8 do dataset — o consultor João, por comparação, vê 2.
      expect(barters.body.data).toHaveLength(8);

      const producers = await request(app.getHttpServer())
        .get('/api/v1/producers')
        .set('Authorization', auth);
      expect(producers.status).toBe(200);
      expect(producers.body.data).toHaveLength(7);

      // Permuta de um consultor qualquer abre sem 403 (não é "carteira alheia").
      const one = await request(app.getHttpServer())
        .get('/api/v1/barters/PRM-2026-002')
        .set('Authorization', auth);
      expect(one.status).toBe(200);
    }
  });

  /**
   * O GERENTE tem um escopo próprio, mais estreito que o da retaguarda: ele
   * enxerga o TIME dele.
   *
   * Ele não é auditor — responde por um time, e a permuta de outro time não é
   * assunto dele. Enquanto teve `barters.readAll`, a fila que pedia ação dele
   * ficava misturada com a operação inteira, e a tela não tinha como dar ênfase
   * ao que era dele.
   */
  it('o gerente enxerga o time dele, e só ele', async () => {
    const beatriz = await asUser(GERENTE);

    // Beatriz responde por João e Ana: 001, 002, 004 e 005.
    const lista = await request(app.getHttpServer())
      .get('/api/v1/barters')
      .set('Authorization', beatriz);
    expect(lista.status).toBe(200);
    expect(lista.body.data.map((b: { code: string }) => b.code).sort()).toEqual([
      'PRM-2026-001',
      'PRM-2026-002',
      'PRM-2026-004',
      'PRM-2026-005',
    ]);

    // E o detalhe segue o MESMO recorte: o que não aparece na lista também não
    // abre pelo código.
    await request(app.getHttpServer())
      .get('/api/v1/barters/PRM-2026-002')
      .set('Authorization', beatriz)
      .expect(200);
    const alheia = await request(app.getHttpServer())
      .get('/api/v1/barters/PRM-2026-007') // do Lucas, time do Gustavo
      .set('Authorization', beatriz);
    expect(alheia.status).toBe(403);

    // O outro gerente enxerga exatamente o complemento.
    const gustavo = await request(app.getHttpServer())
      .get('/api/v1/barters')
      .set('Authorization', await asUser(GERENTE_SUL));
    expect(gustavo.body.data.map((b: { code: string }) => b.code).sort()).toEqual([
      'PRM-2026-003',
      'PRM-2026-006',
      'PRM-2026-007',
      'PRM-2026-008',
    ]);
  });

  it('retaguarda não escreve cadastro nem revisão: isso é do admin', async () => {
    for (const email of BACK_OFFICE) {
      const auth = await asUser(email);
      const post = (url: string, body: object) =>
        request(app.getHttpServer()).post(url).set('Authorization', auth).send(body);
      const put = (url: string, body: object) =>
        request(app.getHttpServer()).put(url).set('Authorization', auth).send(body);

      await expect(
        post('/api/v1/producers', {
          name: 'Produtor Novo',
          consultantId: 2,
          document: 'CPF 999.999.999-99',
          farmName: 'Fazenda X',
          city: 'Maringá/PR',
          areaHa: 10,
        }).then((r) => r.status),
      ).resolves.toBe(403);

      await expect(
        post('/api/v1/consultants', {
          fullName: 'Consultor Novo',
          email: 'consultor.novo@agrobarter.com.br',
          unitId: UNIT.filial02,
        }).then((r) => r.status),
      ).resolves.toBe(403);

      await expect(
        post('/api/v1/products', {
          name: 'Produto Novo',
          unit: 'sc',
          type: 'input',
          currentPrice: 10,
        }).then((r) => r.status),
      ).resolves.toBe(403);

      // Classe não se cria (a lista é fixa); o que existe é ajustar a regra.
      await expect(
        put('/api/v1/classes/1/rule', { ruleType: 'percentOfTotal', ruleValue: 10 }).then(
          (r) => r.status,
        ),
      ).resolves.toBe(403);

      // PRM-2026-002 está em análise no dataset.
      await expect(
        post('/api/v1/barters/PRM-2026-002/review', { status: 'approved' }).then((r) => r.status),
      ).resolves.toBe(403);

      // Abrir e fechar praça é operação do admin. A retaguarda LÊ a lista (ela
      // aparece nas permutas), mas não mexe nela.
      await expect(
        post('/api/v1/units', { name: 'Filial Nova', city: 'Maringá/PR' }).then((r) => r.status),
      ).resolves.toBe(403);
      await expect(
        put('/api/v1/units/1', { name: 'Matriz', city: 'Maringá/PR' }).then((r) => r.status),
      ).resolves.toBe(403);
    }
  });

  /**
   * O gerente é o único da retaguarda que escreve — e escreve UMA coisa. Este
   * caso é o par do de cima: ele fixa o que o gerente ganhou sem deixar a lista
   * de "não escreve nada" perder o sentido para comitê e faturista.
   */
  it('o parecer é do gerente; comitê e faturista não alcançam a etapa', async () => {
    for (const email of [COMITE, FATURISTA]) {
      const response = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-005/opinion')
        .set('Authorization', await asUser(email))
        .send({ note: 'Parecer que este papel não deveria conseguir dar.' });
      expect(response.status).toBe(403);
    }

    const gerente = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-005/opinion')
      .set('Authorization', await asUser(GERENTE))
      .send({ note: 'Estoque conferido na unidade, volume compatível com a área.' });
    expect(gerente.status).toBe(200);
    expect(gerente.body.data.status).toBe('pending');
  });

  it('permuta é ato do consultor da carteira — nem retaguarda nem admin registram', async () => {
    const payload = {
      producerId: 1,
      unitId: UNIT.filial02,
      grainId: 1,
      inputs: [
        { productId: 5, quantity: 48 },
        { productId: 6, quantity: 300 },
        { productId: 7, quantity: 18 },
      ],
    };

    for (const email of [...BACK_OFFICE, ADMIN]) {
      const response = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', await asUser(email))
        .send(payload);
      expect(response.status).toBe(403);
    }

    // E o consultor dono da carteira continua registrando normalmente.
    const asJoao = await request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', await asUser(JOAO))
      .send(payload);
    expect(asJoao.status).toBe(201);
  });

  it('a lista de consultores não passa a incluir os papéis de retaguarda', async () => {
    const response = await request(app.getHttpServer())
      .get('/api/v1/consultants')
      .set('Authorization', await asUser(ADMIN));
    expect(response.status).toBe(200);
    expect(response.body.data.map((u: { role: string }) => u.role)).toEqual(
      Array(5).fill('consultant'),
    );
  });
});
