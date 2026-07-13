import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { ADMIN, ANA, JOAO, createTestApp, loginAs, resetDb } from './utils';

describe('Producers — carteira (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const get = (path: string, token: string) =>
    request(app.getHttpServer()).get(path).set('Authorization', `Bearer ${token}`);

  it('vendedor enxerga apenas a própria carteira', async () => {
    const token = await loginAs(app, JOAO);
    const response = await get('/api/v1/producers', token);

    expect(response.status).toBe(200);
    const names = response.body.data.map((p: { name: string }) => p.name);
    expect(names.sort()).toEqual(['Antônio Carvalho', 'Sebastião Ramos']);
  });

  it('admin enxerga todas as carteiras e pode filtrar por vendedor', async () => {
    const token = await loginAs(app, ADMIN);

    const all = await get('/api/v1/producers', token);
    expect(all.body.data).toHaveLength(7);

    // Ana é o usuário id 3 no seed.
    const filtered = await get('/api/v1/producers?sellerId=3', token);
    const names = filtered.body.data.map((p: { name: string }) => p.name);
    expect(names.sort()).toEqual(['Cláudia Nunes', 'Helena Prado']);
  });

  it('vendedor não acessa produtor de outra carteira', async () => {
    const token = await loginAs(app, JOAO);
    // Helena Prado (id 2) pertence à carteira da Ana.
    const response = await get('/api/v1/producers/2', token);
    expect(response.status).toBe(403);
  });

  it('cadastro de produtor é ato do admin', async () => {
    const payload = {
      name: 'Produtor Novo',
      sellerId: 2, // João
      document: 'CPF 999.999.999-99',
      farmName: 'Fazenda Teste',
      city: 'Maringá/PR',
      areaHa: 55,
    };

    const asSeller = await request(app.getHttpServer())
      .post('/api/v1/producers')
      .set('Authorization', `Bearer ${await loginAs(app, JOAO)}`)
      .send(payload);
    expect(asSeller.status).toBe(403);

    const asAdmin = await request(app.getHttpServer())
      .post('/api/v1/producers')
      .set('Authorization', `Bearer ${await loginAs(app, ADMIN)}`)
      .send(payload);
    expect(asAdmin.status).toBe(201);
    expect(asAdmin.body.data.sellerId).toBe(2);
  });

  it('produtor precisa nascer na carteira de um vendedor válido', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/producers')
      .set('Authorization', `Bearer ${await loginAs(app, ADMIN)}`)
      .send({
        name: 'Sem Carteira',
        sellerId: 1, // admin não tem carteira
        document: 'CPF 000',
        farmName: 'Fazenda X',
        city: 'Cidade/PR',
        areaHa: 10,
      });
    expect(response.status).toBe(422);
  });

  it('vendedores diferentes têm carteiras diferentes', async () => {
    const token = await loginAs(app, ANA);
    const response = await get('/api/v1/producers', token);
    const names = response.body.data.map((p: { name: string }) => p.name);
    expect(names).not.toContain('Antônio Carvalho');
    expect(names).toContain('Helena Prado');
  });
});
