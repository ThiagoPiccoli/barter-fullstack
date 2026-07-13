import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { ADMIN, JOAO, createTestApp, loginAs, resetDb } from './utils';

describe('Products & Categories (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const asUser = async (email: string) => `Bearer ${await loginAs(app, email)}`;

  it('catálogo traz histórico de valores em ordem cronológica', async () => {
    const response = await request(app.getHttpServer())
      .get('/api/v1/products?type=grain')
      .set('Authorization', await asUser(JOAO));

    expect(response.status).toBe(200);
    const soja = response.body.data.find((p: { name: string }) => p.name === 'Soja');
    expect(soja.currentPrice).toBe(148.5);
    expect(soja.priceHistory).toHaveLength(7);
    expect(soja.priceHistory[0].price).toBe(142.0); // mais antigo primeiro
    expect(soja.priceHistory[6].price).toBe(148.5);
  });

  it('reajuste de valor é do admin e alimenta a linha do tempo', async () => {
    const asSeller = await request(app.getHttpServer())
      .put('/api/v1/products/1/price')
      .set('Authorization', await asUser(JOAO))
      .send({ price: 150 });
    expect(asSeller.status).toBe(403);

    const asAdmin = await request(app.getHttpServer())
      .put('/api/v1/products/1/price')
      .set('Authorization', await asUser(ADMIN))
      .send({ price: 152.75 });
    expect(asAdmin.status).toBe(200);
    const soja = asAdmin.body.data;
    expect(soja.currentPrice).toBe(152.75);
    expect(soja.priceHistory).toHaveLength(8);
    expect(soja.priceHistory[7].changedBy).toBe('Carlos Mendes');
  });

  it('reajuste não altera permutas antigas (snapshot nos itens)', async () => {
    const admin = await asUser(ADMIN);
    await request(app.getHttpServer())
      .put('/api/v1/products/1/price')
      .set('Authorization', admin)
      .send({ price: 999 });

    const barter = await request(app.getHttpServer())
      .get('/api/v1/barters/PRM-2026-001')
      .set('Authorization', admin);
    const grain = barter.body.data.items.find((i: { kind: string }) => i.kind === 'grain');
    expect(grain.unitValue).toBe(148.5);
  });

  it('grão não pertence a categoria (só insumos)', async () => {
    const response = await request(app.getHttpServer())
      .put('/api/v1/products/1')
      .set('Authorization', await asUser(ADMIN))
      .send({ categoryId: 1 });
    expect(response.status).toBe(422);
  });

  it('percentual de categoria acima de 100 é rejeitado', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/categories')
      .set('Authorization', await asUser(ADMIN))
      .send({ name: 'Inválida', ruleType: 'percentOfTotal', ruleValue: 120 });
    expect(response.status).toBe(422);
  });

  it('excluir a pasta desvincula os insumos sem apagá-los', async () => {
    const admin = await asUser(ADMIN);

    // Sementes (id 3) tem a Semente Soja (produto 9).
    await request(app.getHttpServer())
      .delete('/api/v1/categories/3')
      .set('Authorization', admin)
      .expect(204);

    const products = await request(app.getHttpServer())
      .get('/api/v1/products?type=input')
      .set('Authorization', admin);
    const semente = products.body.data.find((p: { name: string }) =>
      p.name.startsWith('Semente Soja'),
    );
    expect(semente.categoryId).toBeNull();
  });
});
