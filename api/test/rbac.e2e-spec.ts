import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import {
  ADMIN,
  BACK_OFFICE,
  COMITE,
  FATURISTA,
  GERENTE,
  JOAO,
  SEED_PASSWORD,
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

  it('retaguarda enxerga a operação inteira, não uma carteira', async () => {
    for (const email of BACK_OFFICE) {
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

  it('retaguarda ainda não escreve nada: cadastros, catálogo e revisão são do admin', async () => {
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
          branch: 'Filial 99',
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

      // PRM-2026-003 está pendente no dataset.
      await expect(
        post('/api/v1/barters/PRM-2026-003/review', { status: 'approved' }).then((r) => r.status),
      ).resolves.toBe(403);
    }
  });

  it('permuta é ato do consultor da carteira — nem retaguarda nem admin registram', async () => {
    const payload = {
      producerId: 1,
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
