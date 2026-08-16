import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { ADMIN, JOAO, createTestApp, loginAs, resetDb } from './utils';

/**
 * Payload válido para o Antônio Carvalho (120 ha, carteira do João).
 * Mínimos por hectare: 48 sacos NPK (0.4/ha), 300 L glifosato (2.5/ha),
 * 18 L lambda (0.15/ha). Custo: 48×115 + 300×18.9 + 18×42 = R$ 11.946,00.
 */
const validPayload = {
  producerId: 1,
  grainId: 1, // Soja a R$ 148,50
  inputs: [
    { productId: 5, quantity: 48 },
    { productId: 6, quantity: 300 },
    { productId: 7, quantity: 18 },
  ],
};

describe('Barters (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const asUser = async (email: string) => `Bearer ${await loginAs(app, email)}`;

  it('listagem é escopada: consultor vê as suas, admin vê todas', async () => {
    const asJoao = await request(app.getHttpServer())
      .get('/api/v1/barters')
      .set('Authorization', await asUser(JOAO));
    expect(asJoao.status).toBe(200);
    expect(asJoao.body.data.map((b: { code: string }) => b.code).sort()).toEqual([
      'PRM-2026-001',
      'PRM-2026-005',
    ]);

    const admin = await asUser(ADMIN);
    const asAdmin = await request(app.getHttpServer())
      .get('/api/v1/barters')
      .set('Authorization', admin);
    expect(asAdmin.body.data).toHaveLength(8);

    const pending = await request(app.getHttpServer())
      .get('/api/v1/barters?status=pending')
      .set('Authorization', admin);
    expect(pending.body.data).toHaveLength(3);
  });

  it('consultor não abre permuta de outro consultor', async () => {
    // PRM-2026-002 é da Ana.
    const response = await request(app.getHttpServer())
      .get('/api/v1/barters/PRM-2026-002')
      .set('Authorization', await asUser(JOAO));
    expect(response.status).toBe(403);
  });

  it('servidor calcula as sacas para cobrir o custo dos insumos', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', await asUser(JOAO))
      .send(validPayload);

    expect(response.status).toBe(201);
    const barter = response.body.data;
    expect(barter.code).toBe('PRM-2026-009');
    expect(barter.status).toBe('pending');
    expect(barter.producerName).toBe('Antônio Carvalho');

    const grains = barter.items.filter((i: { kind: string }) => i.kind === 'grain');
    expect(grains).toHaveLength(1);
    // 11946 / 148.5 = 80.4444 sacas de soja
    expect(grains[0].quantity).toBe(80.4444);
    expect(grains[0].unitValue).toBe(148.5);
  });

  /**
   * A quantidade é GRAVADA em 2 casas, e quem arredonda é o servidor.
   *
   * O app já mandava arredondado (`roundQuantity`, em barter_math.dart), mas
   * quem grava é este lado — e ele aceitava a precisão que viesse. Uma chamada
   * direta à API registrava `48,1234` de insumo: o banco guardava isso, a tela
   * e o comprovante mostravam `48,12`, e o valor impresso não fechava com o
   * gravado.
   */
  it('arredonda a quantidade em 2 casas — a precisão em que ela é gravada', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', await asUser(JOAO))
      .send({
        ...validPayload,
        inputs: [
          { productId: 5, quantity: 48.1234 },
          { productId: 6, quantity: 300.005 },
          { productId: 7, quantity: 18 },
        ],
      });

    expect(response.status).toBe(201);
    const porProduto = (id: number) =>
      response.body.data.items.find((i: { productId: number }) => i.productId === id).quantity;
    expect(porProduto(5)).toBe(48.12);
    expect(porProduto(6)).toBe(300.01);
  });

  it('preço enviado pelo cliente é ignorado: quem precifica é o banco', async () => {
    const adulterado = {
      ...validPayload,
      inputs: validPayload.inputs.map((i) => ({ ...i, unitValue: 0.01 })),
    };
    const response = await request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', await asUser(JOAO))
      .send(adulterado);

    expect(response.status).toBe(201);
    const npk = response.body.data.items.find((i: { productId: number }) => i.productId === 5);
    expect(npk.unitValue).toBe(115.0);
  });

  it('insumo obrigatório por hectare não pode faltar nem ficar abaixo do mínimo', async () => {
    const joao = await asUser(JOAO);

    // Sem o NPK (obrigatório: 48 para 120 ha)
    const faltando = await request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', joao)
      .send({ ...validPayload, inputs: validPayload.inputs.slice(1) });
    expect(faltando.status).toBe(422);

    // NPK abaixo do mínimo
    const abaixo = await request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', joao)
      .send({
        ...validPayload,
        inputs: [{ productId: 5, quantity: 10 }, ...validPayload.inputs.slice(1)],
      });
    expect(abaixo.status).toBe(422);
  });

  it('regra de mínimo da CLASSE trava o envio', async () => {
    // Adicionando 30 sacos de semente (R$ 9.600, classe sem regra), o custo
    // total vai a R$ 21.546 e Fertilizantes cai para 25,6% — abaixo dos 30%.
    const response = await request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', await asUser(JOAO))
      .send({
        ...validPayload,
        inputs: [...validPayload.inputs, { productId: 9, quantity: 30 }],
      });

    expect(response.status).toBe(422);
    expect(response.body.message).toContain('FERTILIZANTES');
  });

  it('produtor precisa pertencer à carteira de quem registra', async () => {
    // Helena Prado (id 2) é da carteira da Ana.
    const response = await request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', await asUser(JOAO))
      .send({ ...validPayload, producerId: 2 });
    expect(response.status).toBe(403);
  });

  it('admin não registra permuta (ato do consultor da carteira)', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', await asUser(ADMIN))
      .send(validPayload);
    expect(response.status).toBe(403);
  });

  it('admin aprova pendente com observação e snapshot do revisor', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-002/review')
      .set('Authorization', await asUser(ADMIN))
      .send({ status: 'approved', note: 'Tudo certo com o estoque.' });

    expect(response.status).toBe(200);
    const barter = response.body.data;
    expect(barter.status).toBe('approved');
    expect(barter.reviewedBy).toBe('Carlos Mendes');
    expect(barter.adminNote).toBe('Tudo certo com o estoque.');
    expect(barter.reviewedAt).toBeTruthy();
  });

  it('permuta já revisada não pode ser revisada de novo', async () => {
    // PRM-2026-001 já está aprovada no dataset.
    const response = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-001/review')
      .set('Authorization', await asUser(ADMIN))
      .send({ status: 'denied' });
    expect(response.status).toBe(422);
  });

  it('consultor não revisa permuta', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-005/review')
      .set('Authorization', await asUser(JOAO))
      .send({ status: 'approved' });
    expect(response.status).toBe(403);
  });

  describe('filtros e paginação da listagem', () => {
    const list = async (query: string) =>
      request(app.getHttpServer())
        .get(`/api/v1/barters${query}`)
        .set('Authorization', await asUser(ADMIN));

    /**
     * Um status desconhecido sumia do `where` e a resposta trazia TODAS as
     * permutas — indistinguível, para quem olhava, de "nenhuma permuta tem
     * esse status" ou de uma lista corretamente filtrada.
     */
    it('status desconhecido é recusado em vez de devolver tudo', async () => {
      const response = await list('?status=lixo');
      expect(response.status).toBe(422);
      expect(response.body.message).toContain('status');
    });

    it('página traz meta.total e não repete registros entre páginas', async () => {
      const first = await list('?limit=3');
      expect(first.body.data).toHaveLength(3);
      expect(first.body.meta).toEqual({ total: 8, limit: 3, offset: 0 });

      const second = await list('?limit=3&offset=3');
      const third = await list('?limit=3&offset=6');
      const codes = [...first.body.data, ...second.body.data, ...third.body.data].map(
        (b: { code: string }) => b.code,
      );

      // As três páginas somadas reconstroem a coleção inteira, sem repetição.
      expect(codes).toHaveLength(8);
      expect(new Set(codes).size).toBe(8);
    });

    it('o filtro de status também conta certo no meta', async () => {
      const response = await list('?status=pending&limit=1');
      expect(response.body.data).toHaveLength(1);
      expect(response.body.meta.total).toBe(3);
      expect(response.body.data[0].status).toBe('pending');
    });
  });
});
