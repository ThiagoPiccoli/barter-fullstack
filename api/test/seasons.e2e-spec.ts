import type { INestApplication } from '@nestjs/common';
import ExcelJS from 'exceljs';
import request from 'supertest';
import { ADMIN, BACK_OFFICE, JOAO, createTestApp, loginAs, resetDb } from './utils';

/**
 * O LANÇAMENTO do Barter, ponta a ponta.
 *
 * O que estes testes protegem, em uma frase: **existe uma resposta só para "por
 * quanto se permuta agora"**. Publicar a próxima versão fecha a anterior, a
 * permuta nasce amarrada à versão vigente e o que foi fechado numa gestão
 * continua valendo pelos números dela.
 */
describe('Barter — safra e versões (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const asUser = async (email: string) => `Bearer ${await loginAs(app, email)}`;
  const http = () => request(app.getHttpServer());

  /** Permuta válida do Antônio (120 ha, carteira do João) — sem grão: é da safra. */
  const permuta = {
    producerId: 1,
    inputs: [
      { productId: 5, quantity: 48 },
      { productId: 6, quantity: 300 },
      { productId: 7, quantity: 18 },
    ],
  };

  /** Tabela mínima para publicar uma versão nova pelo corpo da requisição. */
  const tabela = (price: number) => ({
    grainPrice: 150,
    prices: [
      { productId: 5, price },
      { productId: 6, price: 18.9 },
      { productId: 7, price: 42 },
    ],
  });

  it('a versão vigente é a que o consultor enxerga, com a tabela de valores', async () => {
    const response = await http()
      .get('/api/v1/barter-versions/current')
      .set('Authorization', await asUser(JOAO));

    expect(response.status).toBe(200);
    expect(response.body.data).toMatchObject({
      code: 'S2026.02',
      seasonCode: 'S2026',
      grainName: 'Soja',
      grainPrice: 148.5,
      status: 'active',
      isOpen: true,
    });
    expect(response.body.data.prices).toHaveLength(5);
  });

  it('a permuta nasce amarrada à versão vigente e congela o preço', async () => {
    const response = await http()
      .post('/api/v1/barters')
      .set('Authorization', await asUser(JOAO))
      .send(permuta);

    expect(response.status).toBe(201);
    expect(response.body.data.versionCode).toBe('S2026.02');
    const npk = response.body.data.items.find((i: { productId: number }) => i.productId === 5);
    expect(npk).toMatchObject({ unitValue: 115 });
    // O grão vem da safra: o consultor não escolheu nada.
    const grain = response.body.data.items.find((i: { kind: string }) => i.kind === 'grain');
    expect(grain).toMatchObject({ productName: 'Soja', unitValue: 148.5 });
  });

  describe('publicar a próxima versão', () => {
    it('fecha a anterior, numera em sequência e passa a precificar as permutas novas', async () => {
      const admin = await asUser(ADMIN);
      const publicada = await http()
        .post('/api/v1/seasons/S2026/versions')
        .set('Authorization', admin)
        .send(tabela(200));

      expect(publicada.status).toBe(201);
      expect(publicada.body.data).toMatchObject({ code: 'S2026.03', number: 3, status: 'active' });

      const anterior = await http()
        .get('/api/v1/barter-versions/S2026.02')
        .set('Authorization', admin);
      expect(anterior.body.data.status).toBe('closed');
      expect(anterior.body.data.closedBy).toBe('Carlos Mendes');

      // 48×200 + 300×18,9 + 18×42 = 16.026 ÷ 150 = 106,84 sacas
      const permutaNova = await http()
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send(permuta);
      expect(permutaNova.body.data.versionCode).toBe('S2026.03');
      const grain = permutaNova.body.data.items.find((i: { kind: string }) => i.kind === 'grain');
      expect(grain.unitValue).toBe(150);
      expect(grain.quantity).toBe(106.84);
    });

    /**
     * O ponto do desenho inteiro: permuta é registro histórico. Trocar a gestão
     * NÃO pode reescrever o que já foi acordado — nem o preço, nem as sacas.
     */
    it('não mexe nas permutas já registradas na versão anterior', async () => {
      const antes = await http()
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send(permuta);
      const sacasAntes = antes.body.data.items.find((i: { kind: string }) => i.kind === 'grain');

      await http()
        .post('/api/v1/seasons/S2026/versions')
        .set('Authorization', await asUser(ADMIN))
        .send(tabela(999));

      const depois = await http()
        .get(`/api/v1/barters/${antes.body.data.code}`)
        .set('Authorization', await asUser(JOAO));
      expect(depois.body.data.versionCode).toBe('S2026.02');
      expect(depois.body.data.items).toEqual(antes.body.data.items);
      expect(depois.body.data.items.find((i: { kind: string }) => i.kind === 'grain')).toEqual(
        sacasAntes,
      );
    });

    it('insumo fora da tabela da versão não é permutável', async () => {
      // A tabela nova não traz a semente (produto 9), que a anterior trazia.
      await http()
        .post('/api/v1/seasons/S2026/versions')
        .set('Authorization', await asUser(ADMIN))
        .send(tabela(115));

      const response = await http()
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send({ ...permuta, inputs: [...permuta.inputs, { productId: 9, quantity: 1 }] });

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Fora do Barter S2026.03');
    });
  });

  describe('encerramento', () => {
    it('Barter encerrado recusa permuta nova, com mensagem que o consultor entende', async () => {
      await http()
        .post('/api/v1/barter-versions/S2026.02/close')
        .set('Authorization', await asUser(ADMIN));

      const response = await http()
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send(permuta);

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Aguarde o próximo lançamento');
    });

    it('versão encerrada não aceita mais correção de preço', async () => {
      const admin = await asUser(ADMIN);
      await http().post('/api/v1/barter-versions/S2026.02/close').set('Authorization', admin);

      const response = await http()
        .put('/api/v1/barter-versions/S2026.02/prices/5')
        .set('Authorization', admin)
        .send({ price: 120 });
      expect(response.status).toBe(422);
    });

    it('encerrar a safra encerra junto a versão vigente', async () => {
      const admin = await asUser(ADMIN);
      const response = await http().post('/api/v1/seasons/S2026/close').set('Authorization', admin);

      expect(response.status).toBe(200);
      expect(response.body.data.status).toBe('closed');

      const current = await http()
        .get('/api/v1/barter-versions/current')
        .set('Authorization', admin);
      expect(current.body.data).toBeNull();
    });
  });

  describe('correção pontual de valor', () => {
    it('corrige um insumo da versão vigente e passa a valer na próxima permuta', async () => {
      const admin = await asUser(ADMIN);
      const response = await http()
        .put('/api/v1/barter-versions/S2026.02/prices/5')
        .set('Authorization', admin)
        .send({ price: 120 });

      expect(response.status).toBe(200);
      const npk = response.body.data.prices.find((p: { productId: number }) => p.productId === 5);
      expect(npk).toMatchObject({ price: 120 });

      const nova = await http()
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send(permuta);
      const item = nova.body.data.items.find((i: { productId: number }) => i.productId === 5);
      expect(item).toMatchObject({ unitValue: 120 });
    });

    it('o valor da saca é corrigido pelo mesmo caminho (o grão é o produto da safra)', async () => {
      const response = await http()
        .put('/api/v1/barter-versions/S2026.02/prices/1')
        .set('Authorization', await asUser(ADMIN))
        .send({ price: 160 });

      expect(response.status).toBe(200);
      expect(response.body.data.grainPrice).toBe(160);
    });
  });

  describe('safra', () => {
    it('só uma safra aberta por vez', async () => {
      const response = await http()
        .post('/api/v1/seasons')
        .set('Authorization', await asUser(ADMIN))
        .send({ grainId: 2, year: 2027 });

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Soja 2026');
    });

    it('encerrada a anterior, a safra nova nasce com o código do grão e do ano', async () => {
      const admin = await asUser(ADMIN);
      await http().post('/api/v1/seasons/S2026/close').set('Authorization', admin);

      const response = await http()
        .post('/api/v1/seasons')
        .set('Authorization', admin)
        .send({ grainId: 2, year: 2027 });

      expect(response.status).toBe(201);
      expect(response.body.data).toMatchObject({
        code: 'M2027',
        name: 'Milho 2027',
        grainName: 'Milho',
        status: 'open',
      });
    });

    it('a primeira versão da safra nova é a .01', async () => {
      const admin = await asUser(ADMIN);
      await http().post('/api/v1/seasons/S2026/close').set('Authorization', admin);
      await http()
        .post('/api/v1/seasons')
        .set('Authorization', admin)
        .send({ grainId: 2, year: 2027 });

      const response = await http()
        .post('/api/v1/seasons/M2027/versions')
        .set('Authorization', admin)
        .send(tabela(115));
      expect(response.body.data.code).toBe('M2027.01');
    });
  });

  describe('metas', () => {
    it('o detalhe traz o realizado contra as metas definidas', async () => {
      const response = await http()
        .get('/api/v1/barter-versions/S2026.02')
        .set('Authorization', await asUser(ADMIN));

      expect(response.status).toBe(200);
      // Só as quatro metas do seed viram barra; o realizado sai das aprovadas.
      expect(response.body.data.goals.map((g: { kind: string }) => g.kind)).toEqual([
        'sales',
        'sacks',
        'barters',
      ]);
      expect(response.body.data.realized.barters).toBe(3);
      expect(response.body.data.goals.every((g: { met: boolean }) => !g.met)).toBe(true);
    });

    it('a meta não fecha o Barter sozinha — quem encerra é o admin', async () => {
      const admin = await asUser(ADMIN);
      // Meta de uma permuta só, com três já aprovadas na versão.
      await http()
        .post('/api/v1/seasons/S2026/versions')
        .set('Authorization', admin)
        .send({ ...tabela(115), targetBarters: 1 });

      const permutaNova = await http()
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send(permuta);
      expect(permutaNova.status).toBe(201);
    });
  });

  describe('publicação por planilha', () => {
    const planilha = async (linhas: (string | number | null)[][]) => {
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet('Tabela');
      sheet.addRow(['codigo', 'nome', 'unidade', 'classe', 'preco']);
      linhas.forEach((linha) => sheet.addRow(linha));
      return Buffer.from((await workbook.xlsx.writeBuffer()) as unknown as Buffer);
    };

    it('carrega a tabela em massa e cria o insumo que ainda não existia', async () => {
      const arquivo = await planilha([
        ['NPK-0414', 'Fertilizante NPK 04-14-08', 'saco 50kg', 'Fertilizantes', 125],
        ['ADJ-01', 'Adjuvante Novo', 'litro', 'OLEOS e ADJUVANTES', 30],
      ]);

      const response = await http()
        .post('/api/v1/seasons/S2026/versions/import')
        .set('Authorization', await asUser(ADMIN))
        .field('grainPrice', '152,50')
        .attach('file', arquivo, 'tabela-setembro.xlsx');

      expect(response.status).toBe(201);
      expect(response.body.data).toMatchObject({
        code: 'S2026.03',
        grainPrice: 152.5,
        sourceFile: 'tabela-setembro.xlsx',
      });
      expect(response.body.data.prices).toHaveLength(2);

      // O insumo novo entrou no catálogo; o que já existia foi RECONHECIDO
      // pelo nome, sem virar um segundo cadastro.
      const produtos = await http()
        .get('/api/v1/products')
        .set('Authorization', await asUser(ADMIN));
      const nomes = produtos.body.data.map((p: { name: string }) => p.name);
      expect(nomes).toContain('Adjuvante Novo');
      expect(nomes.filter((n: string) => n === 'Fertilizante NPK 04-14-08')).toHaveLength(1);
    });

    /**
     * A lista real não tem coluna de unidade — a embalagem vem no fim da
     * descrição. O que o nome não diz, a classe diz; e o que nem a classe
     * resolve entra MARCADO, para o admin escrever depois em vez de a unidade
     * errada aparecer no comprovante do produtor.
     */
    it('lê a embalagem da descrição, cai para o padrão da classe e marca o resto', async () => {
      const arquivo = await planilha([
        ['A-1', 'HERBIC.AMINOL 806 emb.20 l', '', 'HERBICIDAS', 19.9],
        ['A-2', 'ADUBO 10-20-10 CIBRA BIG-BAG', '', 'FERTILIZANTES', 3140],
        ['A-3', 'UREIA PLUS (45-00-00)', '', 'FERTILIZANTES', 3470],
        ['A-4', 'INOCULANTE SEM PISTA', '', 'INOCULANTES', 90],
      ]);

      await http()
        .post('/api/v1/seasons/S2026/versions/import')
        .set('Authorization', await asUser(ADMIN))
        .field('grainPrice', '150')
        .attach('file', arquivo, 'tabela.xlsx')
        .expect(201);

      const produtos = await http()
        .get('/api/v1/products?type=input')
        .set('Authorization', await asUser(ADMIN));
      const bySku = (sku: string) => produtos.body.data.find((p: { sku: string }) => p.sku === sku);

      expect(bySku('A-1')).toMatchObject({ unit: '20 L', unitPending: false });
      expect(bySku('A-2')).toMatchObject({ unit: 'big-bag', unitPending: false });
      // O nome não diz nada; a classe diz: fertilizante a peso é tonelada.
      expect(bySku('A-3')).toMatchObject({ unit: 'tonelada', unitPending: false });
      // Nem nome nem classe: entra marcado, e é isso que o admin filtra depois.
      expect(bySku('A-4')).toMatchObject({ unit: 'unidade', unitPending: true });
    });

    it('escrever a unidade encerra a pendência — e a carga seguinte não a desfaz', async () => {
      const admin = await asUser(ADMIN);
      const arquivo = await planilha([['B-1', 'INOCULANTE SEM PISTA', '', 'INOCULANTES', 90]]);
      await http()
        .post('/api/v1/seasons/S2026/versions/import')
        .set('Authorization', admin)
        .field('grainPrice', '150')
        .attach('file', arquivo, 'tabela.xlsx')
        .expect(201);

      const produtos = await http().get('/api/v1/products?type=input').set('Authorization', admin);
      const item = produtos.body.data.find((p: { sku: string }) => p.sku === 'B-1');
      expect(item.unitPending).toBe(true);

      const revisado = await http()
        .put(`/api/v1/products/${item.id}`)
        .set('Authorization', admin)
        .send({ unit: 'dose 100 mL' });
      expect(revisado.body.data).toMatchObject({ unit: 'dose 100 mL', unitPending: false });

      // A carga seguinte traz o mesmo item ilegível: a revisão do admin fica.
      await http()
        .post('/api/v1/seasons/S2026/versions/import')
        .set('Authorization', admin)
        .field('grainPrice', '150')
        .attach(
          'file',
          await planilha([['B-1', 'INOCULANTE SEM PISTA', '', 'INOCULANTES', 95]]),
          'tabela.xlsx',
        )
        .expect(201);

      const depois = await http().get('/api/v1/products?type=input').set('Authorization', admin);
      expect(depois.body.data.find((p: { sku: string }) => p.sku === 'B-1')).toMatchObject({
        unit: 'dose 100 mL',
        unitPending: false,
      });
    });

    it('planilha com erro não publica nada, e a mensagem diz a linha', async () => {
      const arquivo = await planilha([['X', 'Sem preço', 'litro', '', null]]);

      const response = await http()
        .post('/api/v1/seasons/S2026/versions/import')
        .set('Authorization', await asUser(ADMIN))
        .field('grainPrice', '150')
        .attach('file', arquivo, 'tabela.xlsx');

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Linha 2');

      // A versão vigente continua sendo a de antes.
      const current = await http()
        .get('/api/v1/barter-versions/current')
        .set('Authorization', await asUser(JOAO));
      expect(current.body.data.code).toBe('S2026.02');
    });

    it('arquivo que não é .xlsx é recusado', async () => {
      const response = await http()
        .post('/api/v1/seasons/S2026/versions/import')
        .set('Authorization', await asUser(ADMIN))
        .field('grainPrice', '150')
        .attach('file', Buffer.from('nome;preco'), 'tabela.csv');

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('.xlsx');
    });

    /**
     * A recusa precisa ser INTEIRA. Resolver a planilha contra o catálogo CRIA
     * o produto que ainda não existia — é o que torna a carga em massa útil —,
     * e isso acontece fora da transação que publica a versão. Enquanto as
     * precondições eram conferidas só lá dentro, uma planilha boa recusada por
     * safra encerrada ou por data no passado devolvia 422 e deixava o cadastro
     * sujo: um insumo sem preço que ninguém pediu e ninguém veria para limpar.
     */
    describe('publicação recusada não deixa rastro no catálogo', () => {
      const fantasma = () => planilha([['ZZZ-01', 'Insumo Fantasma', 'litro', 'Biológicos', 99]]);

      const catalogo = async () => {
        const produtos = await http()
          .get('/api/v1/products')
          .set('Authorization', await asUser(ADMIN));
        return produtos.body.data.map((p: { name: string }) => p.name);
      };

      it('data de encerramento no passado', async () => {
        const response = await http()
          .post('/api/v1/seasons/S2026/versions/import')
          .set('Authorization', await asUser(ADMIN))
          .field('grainPrice', '150')
          .field('endsAt', '2020-01-01T00:00:00.000Z')
          .attach('file', await fantasma(), 'tabela.xlsx');

        expect(response.status).toBe(422);
        expect(response.body.message).toContain('futuro');

        expect(await catalogo()).not.toContain('Insumo Fantasma');
      });

      it('safra já encerrada', async () => {
        const admin = await asUser(ADMIN);
        await http().post('/api/v1/seasons/S2026/close').set('Authorization', admin);

        const response = await http()
          .post('/api/v1/seasons/S2026/versions/import')
          .set('Authorization', admin)
          .field('grainPrice', '150')
          .attach('file', await fantasma(), 'tabela.xlsx');

        expect(response.status).toBe(422);
        expect(response.body.message).toContain('encerrada');

        expect(await catalogo()).not.toContain('Insumo Fantasma');
      });
    });

    it('carryOver mantém na tabela nova os insumos que o arquivo não trouxe', async () => {
      const arquivo = await planilha([
        ['NPK-0414', 'Fertilizante NPK 04-14-08', 'saco 50kg', 'Fertilizantes', 125],
      ]);

      const response = await http()
        .post('/api/v1/seasons/S2026/versions/import')
        .set('Authorization', await asUser(ADMIN))
        .field('grainPrice', '150')
        .field('carryOver', 'true')
        .attach('file', arquivo, 'so-o-que-mudou.xlsx');

      expect(response.status).toBe(201);
      expect(response.body.data.prices).toHaveLength(5);
      const npk = response.body.data.prices.find((p: { productId: number }) => p.productId === 5);
      expect(npk.price).toBe(125);
    });
  });

  describe('quem pode', () => {
    it('consultor e retaguarda não lançam Barter', async () => {
      for (const email of [JOAO, ...BACK_OFFICE]) {
        const auth = await asUser(email);
        expect((await http().get('/api/v1/seasons').set('Authorization', auth)).status).toBe(403);
        expect(
          (
            await http()
              .post('/api/v1/seasons/S2026/versions')
              .set('Authorization', auth)
              .send(tabela(115))
          ).status,
        ).toBe(403);
        expect(
          (await http().post('/api/v1/barter-versions/S2026.02/close').set('Authorization', auth))
            .status,
        ).toBe(403);
      }
    });

    it('mas todos enxergam a versão vigente', async () => {
      for (const email of [JOAO, ...BACK_OFFICE, ADMIN]) {
        const response = await http()
          .get('/api/v1/barter-versions/current')
          .set('Authorization', await asUser(email));
        expect(response.status).toBe(200);
        expect(response.body.data.code).toBe('S2026.02');
      }
    });
  });
});
