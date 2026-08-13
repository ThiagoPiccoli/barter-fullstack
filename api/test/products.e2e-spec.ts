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
    const asConsultant = await request(app.getHttpServer())
      .put('/api/v1/products/1/price')
      .set('Authorization', await asUser(JOAO))
      .send({ price: 150 });
    expect(asConsultant.status).toBe(403);

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

  it('tipo de produto desconhecido é recusado em vez de devolver o catálogo inteiro', async () => {
    const response = await request(app.getHttpServer())
      .get('/api/v1/products?type=qualquer')
      .set('Authorization', await asUser(ADMIN));
    expect(response.status).toBe(422);
    expect(response.body.message).toContain('tipo');
  });

  /**
   * Sem criação e exclusão, o catálogo ficava congelado no que o seed criou:
   * cadastrar um insumo novo ou aposentar um descontinuado exigia SQL na mão.
   */
  describe('catálogo é administrável', () => {
    const novoInsumo = {
      name: 'Adubo Foliar Zinco',
      unit: 'litro',
      type: 'input',
      currentPrice: 62.5,
      requiredPerHa: 0,
      categoryId: 1,
    };

    it('admin cria produto e ele já nasce com o primeiro ponto do histórico', async () => {
      const created = await request(app.getHttpServer())
        .post('/api/v1/products')
        .set('Authorization', await asUser(ADMIN))
        .send(novoInsumo);
      expect(created.status).toBe(201);
      expect(created.body.data.priceHistory).toHaveLength(1);
      expect(created.body.data.priceHistory[0].price).toBe(62.5);
      expect(created.body.data.priceHistory[0].changedBy).toBe('Carlos Mendes');
    });

    it('criar e excluir produto é só do admin', async () => {
      const consultant = await asUser(JOAO);
      await request(app.getHttpServer())
        .post('/api/v1/products')
        .set('Authorization', consultant)
        .send(novoInsumo)
        .expect(403);
      await request(app.getHttpServer())
        .delete('/api/v1/products/8')
        .set('Authorization', consultant)
        .expect(403);
    });

    /**
     * A exclusão não pode reescrever o passado: a permuta guarda nome, unidade
     * e preço no próprio item, e é isso que faz o histórico sobreviver ao
     * produto sair do catálogo.
     */
    it('excluir produto preserva as permutas já registradas', async () => {
      const admin = await asUser(ADMIN);

      // Produto 8 (Fungicida Azoxistrobina) aparece em permutas do seed.
      const before = await request(app.getHttpServer())
        .get('/api/v1/barters')
        .set('Authorization', admin);
      const usedIn = before.body.data.filter((b: { items: { productId: number }[] }) =>
        b.items.some((i) => i.productId === 8),
      );
      expect(usedIn.length).toBeGreaterThan(0);

      await request(app.getHttpServer())
        .delete('/api/v1/products/8')
        .set('Authorization', admin)
        .expect(204);

      // Sumiu do catálogo...
      await request(app.getHttpServer())
        .get('/api/v1/products/8')
        .set('Authorization', admin)
        .expect(404);

      // ...mas as permutas continuam inteiras, com o nome congelado no item.
      const after = await request(app.getHttpServer())
        .get('/api/v1/barters')
        .set('Authorization', admin);
      expect(after.body.data).toHaveLength(before.body.data.length);
      const item = after.body.data
        .flatMap((b: { items: { productName: string; productId: number | null }[] }) => b.items)
        .find((i: { productName: string }) => i.productName.startsWith('Fungicida'));
      expect(item.productName).toBe('Fungicida Azoxistrobina');
      expect(item.productId).toBeNull();
    });

    it('excluir produto inexistente responde 404', async () => {
      await request(app.getHttpServer())
        .delete('/api/v1/products/9999')
        .set('Authorization', await asUser(ADMIN))
        .expect(404);
    });
  });
});
