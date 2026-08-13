import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { ADMIN, ANA, JOAO, createTestApp, loginAs, resetDb } from './utils';

describe('Sellers — gestão pelo admin (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const asUser = async (email: string) => `Bearer ${await loginAs(app, email)}`;

  it('lista de vendedores é restrita ao admin', async () => {
    const asSeller = await request(app.getHttpServer())
      .get('/api/v1/sellers')
      .set('Authorization', await asUser(JOAO));
    expect(asSeller.status).toBe(403);

    const asAdmin = await request(app.getHttpServer())
      .get('/api/v1/sellers')
      .set('Authorization', await asUser(ADMIN));
    expect(asAdmin.status).toBe(200);
    expect(asAdmin.body.data).toHaveLength(5);
    expect(asAdmin.body.data.map((s: { role: string }) => s.role)).not.toContain('admin');
  });

  it('vendedor criado pelo admin loga com a senha padrão', async () => {
    const created = await request(app.getHttpServer())
      .post('/api/v1/sellers')
      .set('Authorization', await asUser(ADMIN))
      .send({
        fullName: 'Novo Vendedor',
        email: 'novo.vendedor@barter.com.br',
        branch: 'Filial 99',
      });
    expect(created.status).toBe(201);
    expect(created.body.data.role).toBe('seller');

    const login = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email: 'novo.vendedor@barter.com.br', password: '123456' });
    expect(login.status).toBe(200);
  });

  it('e-mail duplicado é rejeitado na criação e na edição', async () => {
    const admin = await asUser(ADMIN);

    const duplicateCreate = await request(app.getHttpServer())
      .post('/api/v1/sellers')
      .set('Authorization', admin)
      .send({ fullName: 'Clone', email: JOAO, branch: 'Filial X' });
    expect(duplicateCreate.status).toBe(422);

    // João é o usuário id 2 no seed; tenta assumir o e-mail da Ana.
    const duplicateUpdate = await request(app.getHttpServer())
      .put('/api/v1/sellers/2')
      .set('Authorization', admin)
      .send({ fullName: 'João Silva', email: ANA, branch: 'Filial 02' });
    expect(duplicateUpdate.status).toBe(422);
  });

  it('excluir vendedor deixa a carteira sem dono e preserva permutas', async () => {
    const admin = await asUser(ADMIN);

    await request(app.getHttpServer())
      .delete('/api/v1/sellers/2') // João
      .set('Authorization', admin)
      .expect(204);

    // Antônio Carvalho (id 1) era da carteira do João → fica sem vendedor.
    const producer = await request(app.getHttpServer())
      .get('/api/v1/producers/1')
      .set('Authorization', admin);
    expect(producer.body.data.sellerId).toBeNull();

    // A permuta histórica preserva o nome do vendedor (snapshot).
    const barter = await request(app.getHttpServer())
      .get('/api/v1/barters/PRM-2026-001')
      .set('Authorization', admin);
    expect(barter.body.data.sellerName).toBe('João Silva');
    expect(barter.body.data.sellerId).toBeNull();
  });

  it('rota de vendedores não gerencia o admin', async () => {
    const response = await request(app.getHttpServer())
      .delete('/api/v1/sellers/1') // admin
      .set('Authorization', await asUser(ADMIN));
    expect(response.status).toBe(404);
  });
});
