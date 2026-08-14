import type { INestApplication } from '@nestjs/common';
import ExcelJS from 'exceljs';
import request from 'supertest';
import { ADMIN, JOAO, createTestApp, loginAs, resetDb } from './utils';

describe('Products & Classes (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const asUser = async (email: string) => `Bearer ${await loginAs(app, email)}`;

  /**
   * A LISTAGEM não carrega a linha do tempo. Ela cresce um ponto por produto a
   * cada versão do Barter publicada, sem teto, e esta rota é pedida a cada
   * login e a cada refresh do app — a série inteira de todo o catálogo em toda
   * abertura é justamente o que não pode acontecer.
   *
   * O que vai no lugar é o que a tela de lista lê da série: o primeiro valor
   * (para a variação) e quantos pontos existem.
   */
  it('catálogo traz o RESUMO do histórico, não a série inteira', async () => {
    const response = await request(app.getHttpServer())
      .get('/api/v1/products?type=grain')
      .set('Authorization', await asUser(JOAO));

    expect(response.status).toBe(200);
    const soja = response.body.data.find((p: { name: string }) => p.name === 'Soja');
    expect(soja.currentPrice).toBe(148.5);
    expect(soja.firstPrice).toBe(142.0);
    expect(soja.priceHistoryCount).toBe(7);
    // O campo não vem pela metade: ou é a série inteira, ou não é o campo.
    expect(soja.priceHistory).toBeUndefined();
  });

  it('o detalhe do produto traz a linha do tempo completa, em ordem cronológica', async () => {
    const response = await request(app.getHttpServer())
      .get('/api/v1/products/1')
      .set('Authorization', await asUser(JOAO));

    expect(response.status).toBe(200);
    expect(response.body.data.name).toBe('Soja');
    expect(response.body.data.priceHistory).toHaveLength(7);
    expect(response.body.data.priceHistory[0].price).toBe(142.0); // mais antigo primeiro
    expect(response.body.data.priceHistory[6].price).toBe(148.5);
  });

  /**
   * O catálogo não tem mais rota de preço: valor é do Barter, e reajustar por
   * fora dele criaria um número que o app mostra e a permuta não usa. O
   * `currentPrice` continua existindo como ÚLTIMO VALOR PUBLICADO, escrito por
   * quem publica a versão — ver seasons.e2e-spec.ts.
   */
  it('não existe reajuste de preço pelo catálogo', async () => {
    const response = await request(app.getHttpServer())
      .put('/api/v1/products/1/price')
      .set('Authorization', await asUser(ADMIN))
      .send({ price: 152.75 });
    expect(response.status).toBe(404);
  });

  it('corrigir o valor na versão alimenta a linha do tempo do produto', async () => {
    const admin = await asUser(ADMIN);
    const corrigido = await request(app.getHttpServer())
      .put('/api/v1/barter-versions/S2026.02/prices/1')
      .set('Authorization', admin)
      .send({ price: 152.75 });
    expect(corrigido.status).toBe(200);

    const soja = await request(app.getHttpServer())
      .get('/api/v1/products/1')
      .set('Authorization', admin);
    expect(soja.body.data.currentPrice).toBe(152.75);
    expect(soja.body.data.priceHistory).toHaveLength(8);
    expect(soja.body.data.priceHistory[7].changedBy).toBe('Barter S2026.02');
  });

  it('reajuste não altera permutas antigas (snapshot nos itens)', async () => {
    const admin = await asUser(ADMIN);
    await request(app.getHttpServer())
      .put('/api/v1/barter-versions/S2026.02/prices/1')
      .set('Authorization', admin)
      .send({ price: 999 });

    const barter = await request(app.getHttpServer())
      .get('/api/v1/barters/PRM-2026-001')
      .set('Authorization', admin);
    const grain = barter.body.data.items.find((i: { kind: string }) => i.kind === 'grain');
    expect(grain.unitValue).toBe(148.5);
  });

  /**
   * Todo item precisa de CÓDIGO: é por ele que se procura na busca e é ele que
   * casa a planilha do fornecedor com o cadastro. Quem não informa recebe um
   * gerado, para nenhum item ficar sem.
   */
  describe('código do item', () => {
    const novo = {
      name: 'Adjuvante de Verificação',
      unit: 'litro',
      type: 'input',
      currentPrice: 30,
    };

    it('item sem código informado nasce com um gerado', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/products')
        .set('Authorization', await asUser(ADMIN))
        .send(novo);

      expect(response.status).toBe(201);
      expect(response.body.data.sku).toMatch(/^INS-\d{4}$/);
    });

    it('o código do fornecedor, quando informado, é o que vale', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/products')
        .set('Authorization', await asUser(ADMIN))
        .send({ ...novo, sku: 'ADJ-991' });

      expect(response.body.data.sku).toBe('ADJ-991');
    });

    /** Código repetido tornaria a busca ambígua e o casamento da planilha, um sorteio. */
    it('código repetido é recusado com o nome de quem já o usa', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/products')
        .set('Authorization', await asUser(ADMIN))
        .send({ ...novo, sku: 'NPK-0414' });

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Fertilizante NPK 04-14-08');
    });

    it('o código é corrigível depois, e continua único', async () => {
      const admin = await asUser(ADMIN);
      const corrigido = await request(app.getHttpServer())
        .put('/api/v1/products/5')
        .set('Authorization', admin)
        .send({ sku: 'NPK-NOVO' });
      expect(corrigido.body.data.sku).toBe('NPK-NOVO');

      const repetido = await request(app.getHttpServer())
        .put('/api/v1/products/6')
        .set('Authorization', admin)
        .send({ sku: 'NPK-NOVO' });
      expect(repetido.status).toBe(422);
    });

    it('a planilha reconhece o item pelo código, sem criar um segundo cadastro', async () => {
      const admin = await asUser(ADMIN);
      const antes = await request(app.getHttpServer())
        .get('/api/v1/products?type=input')
        .set('Authorization', admin);

      // Mesmo código do seed, nome escrito de outro jeito.
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet('Tabela');
      sheet.addRow(['codigo', 'nome', 'unidade', 'classe', 'preco', 'custo']);
      sheet.addRow([
        'NPK-0414',
        'FERTILIZANTE NPK 04 14 08',
        'saco 50kg',
        'Fertilizantes',
        130,
        100,
      ]);
      const arquivo = Buffer.from((await workbook.xlsx.writeBuffer()) as unknown as Buffer);

      await request(app.getHttpServer())
        .post('/api/v1/seasons/S2026/versions/import')
        .set('Authorization', admin)
        .field('grainPrice', '150')
        .attach('file', arquivo, 'tabela.xlsx')
        .expect(201);

      const depois = await request(app.getHttpServer())
        .get('/api/v1/products?type=input')
        .set('Authorization', admin);
      expect(depois.body.data).toHaveLength(antes.body.data.length);
    });
  });

  it('grão não pertence a classe (só insumos)', async () => {
    const response = await request(app.getHttpServer())
      .put('/api/v1/products/1')
      .set('Authorization', await asUser(ADMIN))
      .send({ classId: 1 });
    expect(response.status).toBe(422);
  });

  /**
   * A lista de classes é FIXA — ela nasce na migration. Estas duas rotas
   * existiam quando "pasta" era um cadastro livre, e a ausência delas é o que
   * impede o vocabulário de voltar a se multiplicar a cada carga de planilha.
   */
  it('classe não se cria nem se exclui', async () => {
    const admin = await asUser(ADMIN);
    await request(app.getHttpServer())
      .post('/api/v1/classes')
      .set('Authorization', admin)
      .send({ name: 'Classe Inventada' })
      .expect(404);
    await request(app.getHttpServer())
      .delete('/api/v1/classes/1')
      .set('Authorization', admin)
      .expect(404);
  });

  it('a lista vem completa e na ordem do negócio', async () => {
    const response = await request(app.getHttpServer())
      .get('/api/v1/classes')
      .set('Authorization', await asUser(JOAO));

    expect(response.status).toBe(200);
    expect(response.body.data.map((c: { slug: string }) => c.slug)).toEqual([
      'fungicidas',
      'inseticidas',
      'herbicidas',
      'sementes',
      'fertilizantes',
      'biologicos',
      'nutricao',
      'seguro-agricola',
      'oleos-adjuvantes',
    ]);
  });

  it('a regra de mínimo da classe é editável — e o percentual não passa de 100', async () => {
    const admin = await asUser(ADMIN);

    const ok = await request(app.getHttpServer())
      .put('/api/v1/classes/1/rule')
      .set('Authorization', admin)
      .send({ ruleType: 'percentOfTotal', ruleValue: 15 });
    expect(ok.status).toBe(200);
    expect(ok.body.data).toMatchObject({
      slug: 'fungicidas',
      ruleType: 'percentOfTotal',
      ruleValue: 15,
    });

    const demais = await request(app.getHttpServer())
      .put('/api/v1/classes/1/rule')
      .set('Authorization', admin)
      .send({ ruleType: 'percentOfTotal', ruleValue: 120 });
    expect(demais.status).toBe(422);
  });

  /** Sem exigência, o valor da regra não significa nada — some junto. */
  it('desligar a regra zera o valor', async () => {
    const response = await request(app.getHttpServer())
      .put('/api/v1/classes/5/rule')
      .set('Authorization', await asUser(ADMIN))
      .send({ ruleType: 'none', ruleValue: 30 });
    expect(response.body.data).toMatchObject({ ruleType: 'none', ruleValue: 0 });
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
      classId: 1,
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
