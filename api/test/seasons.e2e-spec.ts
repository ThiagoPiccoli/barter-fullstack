import type { INestApplication } from '@nestjs/common';
import ExcelJS from 'exceljs';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { MAX_VERSION_PRICES } from '../src/seasons/version-import';
import {
  ADMIN,
  BACK_OFFICE,
  COMITE,
  GERENTE,
  JOAO,
  UNIT,
  createTestApp,
  forwardWithCpr,
  loginAs,
  resetDb,
} from './utils';

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

  /**
   * Permuta válida do Antônio (120 ha, carteira do João), paga em soja — a
   * cultura é escolha do consultor, entre as que o lançamento aceita. A retirada
   * é na Filial 02, a unidade do próprio João.
   */
  const permuta = {
    producerId: 1,
    unitId: UNIT.filial02,
    // A CULTURA em que ela é paga — soja, a primeira do lançamento vigente.
    grainId: 1,
    inputs: [
      { productId: 5, quantity: 48 },
      { productId: 6, quantity: 300 },
      { productId: 7, quantity: 18 },
    ],
  };

  /**
   * Uma permuta nova percorrendo a esteira INTEIRA, do rascunho à decisão do
   * comitê. Devolve a resposta da decisão.
   *
   * Ela aparece nos casos de meta porque a decisão do comitê é o único ato que
   * mexe no realizado — e, portanto, o único capaz de bater uma meta. Chegar até
   * lá exige os quatro passos: sem o parecer do gerente, o comitê não alcança a
   * permuta.
   */
  const aprovarUmaPermuta = async (status: 'approved' | 'denied' = 'approved') => {
    const consultor = await asUser(JOAO);
    const criada = await http()
      .post('/api/v1/barters')
      .set('Authorization', consultor)
      .send(permuta);
    const code = criada.body.data.code as string;

    await forwardWithCpr(app, consultor, code);
    await http()
      .post(`/api/v1/barters/${code}/opinion`)
      .set('Authorization', await asUser(GERENTE))
      .send({ note: 'Área conferida e histórico bom.' });

    return http()
      .post(`/api/v1/barters/${code}/review`)
      .set('Authorization', await asUser(COMITE))
      .send({ status, ...(status === 'denied' ? { note: 'Endividamento acima do limite.' } : {}) });
  };

  /**
   * Tabela mínima para publicar uma versão nova pelo corpo da requisição — com
   * UMA cultura (soja), que é o caso simples. Os testes sobre culturas que
   * coexistem acrescentam a segunda na chamada.
   */
  const soja = { grainId: 1, price: 150, estimatedYield: 60 };
  const milho = { grainId: 2, price: 64.5, estimatedYield: 170 };
  const tabela = (price: number) => ({
    grains: [soja],
    prices: [
      { productId: 5, price },
      { productId: 6, price: 18.9 },
      { productId: 7, price: 42 },
    ],
  });

  it('a versão vigente é a que o consultor enxerga, com a tabela em sacas', async () => {
    const response = await http()
      .get('/api/v1/barter-versions/current')
      .set('Authorization', await asUser(JOAO));

    expect(response.status).toBe(200);
    expect(response.body.data).toMatchObject({
      code: 'B2026.02',
      seasonCode: 'B2026',
      status: 'active',
      isOpen: true,
    });
    expect(response.body.data.prices).toHaveLength(5);

    // AS CULTURAS que este Barter aceita, na ordem em que foram lançadas. A
    // primeira é a que a tela mostra escolhida, e é por ela que a tabela abaixo
    // está convertida (`pricedInGrainId`).
    expect(response.body.data.grains.map((g: { grainName: string }) => g.grainName)).toEqual([
      'Soja',
      'Milho',
    ]);
    expect(response.body.data.pricedInGrainId).toBe(1);

    // A LENTE DE VALOR: o consultor recebe a mesma tabela medida em SACAS, que é
    // a unidade em que ele sempre montou a permuta. O numerador não vai — nem a
    // cotação da saca, que devolveria os R$ por multiplicação.
    const npk = response.body.data.prices.find((p: { productId: number }) => p.productId === 5);
    expect(npk.price).toBeUndefined();
    // 115 ÷ 148,50 = 0,7744 sacas por saco de NPK.
    expect(npk.sacksPerUnit).toBeCloseTo(115 / 148.5, 6);
    expect(response.body.data.grains[0].price).toBeUndefined();
    expect(response.body.data.targetSales).toBeUndefined();

    // A PRODUTIVIDADE e o VENCIMENTO vão para ele, e não são valor: a primeira
    // explica a área de penhor que a permuta dele vai exigir, o segundo é a data
    // que ele combina com o produtor.
    expect(response.body.data.grains[0]).toMatchObject({ grainId: 1, estimatedYield: 60 });
    expect(response.body.data.grains[0].cprDueDate).not.toBeNull();
  });

  /**
   * A MESMA TABELA, OUTRA CULTURA: é o que a tela do consultor faz quando ele
   * troca o seletor de cultura. O insumo custa os mesmos R$ 115 nas duas — o que
   * muda é a cotação que os converte, e por isso o mesmo NPK vale 0,77 saca de
   * soja e 1,78 de milho.
   */
  it('a tabela é convertida pela cultura pedida', async () => {
    const response = await http()
      .get('/api/v1/barter-versions/current?grainId=2')
      .set('Authorization', await asUser(JOAO));

    expect(response.status).toBe(200);
    expect(response.body.data.pricedInGrainId).toBe(2);
    const npk = response.body.data.prices.find((p: { productId: number }) => p.productId === 5);
    expect(npk.sacksPerUnit).toBeCloseTo(115 / 64.5, 6);
  });

  /**
   * CULTURA QUE NÃO ESTÁ NO LANÇAMENTO cai na primeira, e a resposta DIZ isso em
   * `pricedInGrainId`. O contrário — uma tabela convertida por uma cotação que
   * não existe — mostraria sacas de um grão que este Barter não aceita.
   */
  it('cultura desconhecida cai na primeira, e a resposta diz qual usou', async () => {
    const response = await http()
      .get('/api/v1/barter-versions/current?grainId=3')
      .set('Authorization', await asUser(JOAO));

    expect(response.status).toBe(200);
    expect(response.body.data.pricedInGrainId).toBe(1);
  });

  /**
   * A LENTE atravessa o ANINHAMENTO. A safra carrega as versões dentro dela, e
   * quem serializa a versão é a mesma função da rota de versão — que, sem
   * viewer, cai no padrão fechado e devolve a tabela em sacas.
   *
   * Foi exatamente o que aconteceu: `GET /seasons` era a única rota de
   * `barterManage` que não repassava quem estava perguntando, e o admin recebia
   * a própria safra sem `grainPrice` e sem as metas — os campos de que a tela de
   * lançamento vive. O padrão fechado é o certo (papel novo não herda R$ por
   * omissão); o que faltava era a rota dizer por quais olhos ela monta o JSON.
   */
  it('a safra traz as versões aninhadas com os valores em R$ para a retaguarda', async () => {
    const response = await http()
      .get('/api/v1/seasons')
      .set('Authorization', await asUser(ADMIN));

    expect(response.status).toBe(200);
    const safra = response.body.data.find((s: { code: string }) => s.code === 'B2026');
    const vigente = safra.versions.find((v: { code: string }) => v.code === 'B2026.02');
    // A cotação da saca e as metas — os campos que a lente fechada suprime, e
    // sem os quais a tela de lançamento não tem o que desenhar. A listagem não
    // carrega a tabela `prices` (é a rota da versão que a traz), então quem
    // responde por ela aqui é a versão em si.
    expect(vigente.grains[0]).toMatchObject({ grainName: 'Soja', price: 148.5 });
    expect(vigente.targetSales).not.toBeUndefined();
    expect(vigente.targetBarters).not.toBeUndefined();
  });

  it('a retaguarda enxerga a mesma versão com os valores em R$', async () => {
    const response = await http()
      .get('/api/v1/barter-versions/current')
      .set('Authorization', await asUser(ADMIN));

    expect(response.status).toBe(200);
    expect(response.body.data.grains[0]).toMatchObject({ grainName: 'Soja', price: 148.5 });
    const npk = response.body.data.prices.find((p: { productId: number }) => p.productId === 5);
    expect(npk).toMatchObject({ price: 115 });
    expect(npk.sacksPerUnit).toBeUndefined();
  });

  /**
   * ENCAMINHA o rascunho ao gerente. A permuta nasce na mão do consultor, e a
   * retaguarda — que é quem enxerga R$ — só a alcança depois de encaminhada.
   * Nada aqui recalcula preço: o valor congelado é o do registro.
   */
  const encaminhar = async (code: string, auth: string) => {
    // A CÉDULA vai junto: ela é pré-requisito do encaminhamento desde que a
    // coleta passou a acontecer na visita, e não semanas depois. Aqui ela é
    // preâmbulo — o que esta suíte testa é a safra e o congelamento do preço.
    const encaminhada = await forwardWithCpr(app, auth, code, 'Cliente conhecido, área conferida.');
    expect(encaminhada.status).toBe(200);
    return encaminhada;
  };

  it('a permuta nasce amarrada à versão vigente e congela o preço', async () => {
    const response = await http()
      .post('/api/v1/barters')
      .set('Authorization', await asUser(JOAO))
      .send(permuta);

    expect(response.status).toBe(201);
    expect(response.body.data.versionCode).toBe('B2026.02');
    // O grão vem da safra: o consultor não escolheu nada. Para ele a permuta é
    // "tantos insumos -> tantas sacas", e é isso que a resposta traz.
    const grainDoConsultor = response.body.data.items.find(
      (i: { kind: string }) => i.kind === 'grain',
    );
    expect(grainDoConsultor).toMatchObject({ productName: 'Soja' });
    expect(grainDoConsultor.unitValue).toBeUndefined();

    // O valor CONGELADO é o que a retaguarda lê de volta — é ela que vê R$.
    await encaminhar(response.body.data.code as string, await asUser(JOAO));
    const daRetaguarda = await http()
      .get(`/api/v1/barters/${response.body.data.code}`)
      .set('Authorization', await asUser(ADMIN));
    const npk = daRetaguarda.body.data.items.find((i: { productId: number }) => i.productId === 5);
    expect(npk).toMatchObject({ unitValue: 115 });
    const grain = daRetaguarda.body.data.items.find((i: { kind: string }) => i.kind === 'grain');
    expect(grain).toMatchObject({ productName: 'Soja', unitValue: 148.5 });
  });

  describe('publicar a próxima versão', () => {
    it('fecha a anterior, numera em sequência e passa a precificar as permutas novas', async () => {
      const admin = await asUser(ADMIN);
      const publicada = await http()
        .post('/api/v1/seasons/B2026/versions')
        .set('Authorization', admin)
        .send(tabela(200));

      expect(publicada.status).toBe(201);
      expect(publicada.body.data).toMatchObject({ code: 'B2026.03', number: 3, status: 'active' });

      const anterior = await http()
        .get('/api/v1/barter-versions/B2026.02')
        .set('Authorization', admin);
      expect(anterior.body.data.status).toBe('closed');
      expect(anterior.body.data.closedBy).toBe('Carlos Mendes');

      // 48×200 + 300×18,9 + 18×42 = 16.026 ÷ 150 = 106,84 sacas
      const permutaNova = await http()
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send(permuta);
      expect(permutaNova.body.data.versionCode).toBe('B2026.03');
      // A QUANTIDADE é a resposta que o consultor recebe — ela não é moeda.
      const grain = permutaNova.body.data.items.find((i: { kind: string }) => i.kind === 'grain');
      expect(grain.quantity).toBe(106.84);
      // O valor da saca aplicado sai na leitura da retaguarda.
      await encaminhar(permutaNova.body.data.code as string, await asUser(JOAO));
      const daRetaguarda = await http()
        .get(`/api/v1/barters/${permutaNova.body.data.code}`)
        .set('Authorization', admin);
      const grainEmReais = daRetaguarda.body.data.items.find(
        (i: { kind: string }) => i.kind === 'grain',
      );
      expect(grainEmReais.unitValue).toBe(150);
    });

    /**
     * O MESMO teto do caminho da planilha, entregue por JSON.
     *
     * É o que a constante compartilhada promete e não cumpria: 20.000 itens
     * davam 595 KB e batiam no limite de 256 KB do corpo, devolvendo 413 antes
     * de qualquer validação. Compartilhar a constante não bastava — ela
     * precisava caber nos dois caminhos.
     */
    it(`publica ${MAX_VERSION_PRICES} preços por JSON — o mesmo teto da planilha`, async () => {
      const admin = await asUser(ADMIN);
      const prisma = app.get(PrismaService);
      await prisma.product.createMany({
        data: Array.from({ length: MAX_VERSION_PRICES }, (_, i) => ({
          name: `Insumo JSON ${i}`,
          unit: 'kg',
          type: 'input',
          currentPrice: 10,
        })),
      });
      const insumos = await prisma.product.findMany({
        where: { type: 'input', name: { startsWith: 'Insumo JSON ' } },
        select: { id: true },
        take: MAX_VERSION_PRICES,
      });

      const response = await http()
        .post('/api/v1/seasons/B2026/versions')
        .set('Authorization', admin)
        .send({
          grains: [soja],
          prices: insumos.map((produto, i) => ({ productId: produto.id, price: 10 + i })),
        });

      expect(response.status).toBe(201);
      expect(response.body.data.prices).toHaveLength(MAX_VERSION_PRICES);
    }, 120_000);

    /**
     * Produto repetido no corpo é recusado com o id na mensagem. Quem barrava
     * antes era o índice único `[versionId, productId]`, e o admin recebia "Já
     * existe um registro com estes dados." — verdadeiro e inútil.
     */
    it('recusa o mesmo produto duas vezes na tabela, dizendo qual', async () => {
      const response = await http()
        .post('/api/v1/seasons/B2026/versions')
        .set('Authorization', await asUser(ADMIN))
        .send({
          grains: [soja],
          prices: [
            { productId: 5, price: 100 },
            { productId: 6, price: 18.9 },
            { productId: 5, price: 200 },
          ],
        });

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('repete');
      expect(response.body.message).toContain('5');
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
        .post('/api/v1/seasons/B2026/versions')
        .set('Authorization', await asUser(ADMIN))
        .send(tabela(999));

      const depois = await http()
        .get(`/api/v1/barters/${antes.body.data.code}`)
        .set('Authorization', await asUser(JOAO));
      expect(depois.body.data.versionCode).toBe('B2026.02');
      expect(depois.body.data.items).toEqual(antes.body.data.items);
      expect(depois.body.data.items.find((i: { kind: string }) => i.kind === 'grain')).toEqual(
        sacasAntes,
      );
    });

    it('insumo fora da tabela da versão não é permutável', async () => {
      // A tabela nova não traz a semente (produto 9), que a anterior trazia.
      await http()
        .post('/api/v1/seasons/B2026/versions')
        .set('Authorization', await asUser(ADMIN))
        .send(tabela(115));

      const response = await http()
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send({ ...permuta, inputs: [...permuta.inputs, { productId: 9, quantity: 1 }] });

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Fora do Barter B2026.03');
    });
  });

  describe('encerramento', () => {
    it('Barter encerrado recusa permuta nova, com mensagem que o consultor entende', async () => {
      await http()
        .post('/api/v1/barter-versions/B2026.02/close')
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
      await http().post('/api/v1/barter-versions/B2026.02/close').set('Authorization', admin);

      const response = await http()
        .put('/api/v1/barter-versions/B2026.02/prices/5')
        .set('Authorization', admin)
        .send({ price: 120 });
      expect(response.status).toBe(422);
    });

    it('encerrar a safra encerra junto a versão vigente', async () => {
      const admin = await asUser(ADMIN);
      const response = await http().post('/api/v1/seasons/B2026/close').set('Authorization', admin);

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
        .put('/api/v1/barter-versions/B2026.02/prices/5')
        .set('Authorization', admin)
        .send({ price: 120 });

      expect(response.status).toBe(200);
      const npk = response.body.data.prices.find((p: { productId: number }) => p.productId === 5);
      expect(npk).toMatchObject({ price: 120 });

      const nova = await http()
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send(permuta);
      await encaminhar(nova.body.data.code as string, await asUser(JOAO));
      const registrada = await http()
        .get(`/api/v1/barters/${nova.body.data.code}`)
        .set('Authorization', admin);
      const item = registrada.body.data.items.find((i: { productId: number }) => i.productId === 5);
      expect(item).toMatchObject({ unitValue: 120 });
    });

    /**
     * A COTAÇÃO DE UMA CULTURA entra pela mesma porta do insumo: o `productId`
     * do grão. Com mais de uma cultura no lançamento, é ele que diz qual delas
     * está sendo corrigida — e a outra não é tocada.
     */
    it('o valor da saca é corrigido pelo mesmo caminho, cultura por cultura', async () => {
      const response = await http()
        .put('/api/v1/barter-versions/B2026.02/prices/1')
        .set('Authorization', await asUser(ADMIN))
        .send({ price: 160 });

      expect(response.status).toBe(200);
      const [soja2, milho2] = response.body.data.grains;
      expect(soja2).toMatchObject({ grainId: 1, price: 160 });
      expect(milho2).toMatchObject({ grainId: 2, price: 64.5 });
    });
  });

  describe('safra', () => {
    it('só uma safra aberta por vez', async () => {
      const response = await http()
        .post('/api/v1/seasons')
        .set('Authorization', await asUser(ADMIN))
        .send({ year: 2027 });

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Barter 2026/27');
    });

    /**
     * A SAFRA NÃO TEM MAIS GRÃO: ela é o CICLO. O código nasce da letra do ciclo
     * (o `B` de Barter, o padrão) e do ano, e as culturas chegam depois, no
     * lançamento — que é o que permite acrescentar o milho a um Barter que já
     * está no ar sem abrir uma segunda safra.
     */
    it('encerrada a anterior, a safra nova nasce com o código do ciclo e do ano', async () => {
      const admin = await asUser(ADMIN);
      await http().post('/api/v1/seasons/B2026/close').set('Authorization', admin);

      const response = await http()
        .post('/api/v1/seasons')
        .set('Authorization', admin)
        .send({ year: 2027 });

      expect(response.status).toBe(201);
      expect(response.body.data).toMatchObject({
        code: 'B2027',
        name: 'Barter 2027',
        status: 'open',
      });
      // O grão saiu do contrato da safra junto com o campo: quem responde "em
      // que se paga?" é a versão.
      expect(response.body.data.grainName).toBeUndefined();
    });

    /**
     * O VENCIMENTO DA CPR nasce COM A CULTURA, no lançamento — e não mais com a
     * safra.
     *
     * Ele é da CULTURA porque muda com ela: soja vence na colheita da soja,
     * milho safrinha no dele. Enquanto morou na safra, a safra ERA a cultura; com
     * as duas convivendo na mesma gestão, uma data só para ambas seria uma
     * delas errada.
     *
     * OPCIONAL de propósito: o Barter é lançado antes de a colheita ter data
     * fechada, e travar a publicação por isso pararia a venda por um campo que a
     * cédula sabe cobrar sozinha, de quem o resolve.
     */
    it('a cultura pode nascer com o vencimento da CPR, e sem ele também', async () => {
      const admin = await asUser(ADMIN);
      const response = await http()
        .post('/api/v1/seasons/B2026/versions')
        .set('Authorization', admin)
        .send({
          ...tabela(115),
          grains: [{ ...soja, cprDueDate: '2027-06-30T12:00:00.000Z' }, milho],
        });

      expect(response.status).toBe(201);
      expect(response.body.data.grains[0].cprDueDate).toBe('2027-06-30T12:00:00.000Z');
      // E a que veio sem data abre igual, com o campo nulo — a pendência aparece
      // na cédula, endereçada ao admin.
      expect(response.body.data.grains[1].cprDueDate).toBeNull();
    });

    /** Data que não é data não vira vencimento de título executável. */
    it('vencimento inválido no lançamento é recusado', async () => {
      const response = await http()
        .post('/api/v1/seasons/B2026/versions')
        .set('Authorization', await asUser(ADMIN))
        .send({ ...tabela(115), grains: [{ ...soja, cprDueDate: '30/06/2027' }] });

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Vencimento da CPR inválido');
    });

    it('a primeira versão da safra nova é a .01', async () => {
      const admin = await asUser(ADMIN);
      await http().post('/api/v1/seasons/B2026/close').set('Authorization', admin);
      await http().post('/api/v1/seasons').set('Authorization', admin).send({ year: 2027 });

      const response = await http()
        .post('/api/v1/seasons/B2027/versions')
        .set('Authorization', admin)
        .send(tabela(115));
      expect(response.body.data.code).toBe('B2027.01');
    });
  });

  describe('metas', () => {
    it('o detalhe traz o realizado contra as metas definidas', async () => {
      const response = await http()
        .get('/api/v1/barter-versions/B2026.02')
        .set('Authorization', await asUser(ADMIN));

      expect(response.status).toBe(200);
      // As metas do seed viram barra, e as de SACAS são UMA POR CULTURA: soja e
      // milho não somam, e cada uma tem a sua. O realizado sai das aprovadas.
      expect(
        response.body.data.goals.map((g: { kind: string; grainName?: string }) => [
          g.kind,
          g.grainName,
        ]),
      ).toEqual([
        ['sales', undefined],
        ['sacks', 'Soja'],
        ['sacks', 'Milho'],
        ['barters', undefined],
      ]);
      expect(response.body.data.realized.barters).toBe(3);
      expect(response.body.data.goals.every((g: { met: boolean }) => !g.met)).toBe(true);

      // E o REALIZADO em sacas também é por cultura: as permutas aprovadas do
      // seed são todas de soja, e a barra do milho começa no zero em vez de
      // sumir da tela.
      expect(response.body.data.realized.sacks).toEqual([
        { grainId: 1, grainName: 'Soja', sacks: expect.any(Number) },
      ]);
    });

    it('no modo manual (o padrão) a meta não fecha o Barter — quem encerra é o admin', async () => {
      const admin = await asUser(ADMIN);
      // Meta de uma permuta só, com três já aprovadas na versão.
      await http()
        .post('/api/v1/seasons/B2026/versions')
        .set('Authorization', admin)
        .send({ ...tabela(115), targetBarters: 1 });

      await aprovarUmaPermuta();

      const versão = await http()
        .get('/api/v1/barter-versions/B2026.03')
        .set('Authorization', admin);
      expect(versão.body.data.goals[0].met).toBe(true);
      expect(versão.body.data.status).toBe('active');
      expect(versão.body.data.closeOnGoal).toBe(false);

      // E o Barter segue aceitando permuta: a meta avisou, e mais nada.
      const permutaNova = await http()
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send(permuta);
      expect(permutaNova.status).toBe(201);
    });

    /**
     * O ENCERRAMENTO AUTOMÁTICO, ponta a ponta — a outra metade da opção.
     *
     * O que estes casos protegem: quem fecha o Barter é a APROVAÇÃO que cruzou a
     * meta. Não há relógio, o fechamento tem hora e ator, e o `closedBy` explica
     * o motivo para quem abrir a versão meses depois.
     */
    describe('encerrar ao bater meta', () => {
      it('a aprovação que bate a meta encerra o Barter na hora', async () => {
        const admin = await asUser(ADMIN);
        await http()
          .post('/api/v1/seasons/B2026/versions')
          .set('Authorization', admin)
          .send({ ...tabela(115), targetBarters: 1, closeOnGoal: true });

        const aprovada = await aprovarUmaPermuta();
        expect(aprovada.status).toBe(200);

        const versão = await http()
          .get('/api/v1/barter-versions/B2026.03')
          .set('Authorization', admin);
        expect(versão.body.data.status).toBe('closed');
        expect(versão.body.data.isOpen).toBe(false);
        expect(versão.body.data.closedAt).toBeTruthy();
        // O MOTIVO fica gravado: ninguém clicou em nada, e a versão precisa
        // dizer por que fechou.
        expect(versão.body.data.closedBy).toBe('Automático: meta de permutas atingida (1)');

        // E o consultor para de registrar permuta na hora.
        //
        // A mensagem é a de "não há Barter aberto", e não a de "este Barter está
        // fechado": encerrada a única versão ativa da safra, não existe versão
        // vigente para nomear. É a mesma frase de quando nada foi lançado ainda,
        // e é a verdade da tela — o consultor está esperando o próximo
        // lançamento.
        const tardeDemais = await http()
          .post('/api/v1/barters')
          .set('Authorization', await asUser(JOAO))
          .send(permuta);
        expect(tardeDemais.status).toBe(422);
        expect(tardeDemais.body.message).toContain('Não há Barter aberto');
      });

      it('a permuta que a aprovação fechou continua aprovada: o Barter fecha DEPOIS dela', async () => {
        const admin = await asUser(ADMIN);
        await http()
          .post('/api/v1/seasons/B2026/versions')
          .set('Authorization', admin)
          .send({ ...tabela(115), targetBarters: 1, closeOnGoal: true });

        const aprovada = await aprovarUmaPermuta();
        expect(aprovada.body.data.status).toBe('approved');
        // Ela é a permuta que bateu a meta, e o realizado a conta.
        const versão = await http()
          .get('/api/v1/barter-versions/B2026.03')
          .set('Authorization', admin);
        expect(versão.body.data.realized.barters).toBe(1);
      });

      it('permuta NEGADA não fecha nada — ela não soma na meta', async () => {
        const admin = await asUser(ADMIN);
        await http()
          .post('/api/v1/seasons/B2026/versions')
          .set('Authorization', admin)
          .send({ ...tabela(115), targetBarters: 1, closeOnGoal: true });

        await aprovarUmaPermuta('denied');

        const versão = await http()
          .get('/api/v1/barter-versions/B2026.03')
          .set('Authorization', admin);
        expect(versão.body.data.status).toBe('active');
        expect(versão.body.data.realized.barters).toBe(0);
      });

      it('encerrar ao bater meta SEM meta é recusado — seria uma opção que nunca acontece', async () => {
        const response = await http()
          .post('/api/v1/seasons/B2026/versions')
          .set('Authorization', await asUser(ADMIN))
          .send({ ...tabela(115), closeOnGoal: true });

        expect(response.status).toBe(422);
        expect(response.body.message).toContain('ao menos uma meta');
      });

      it('o admin liga o automático na versão vigente, sem republicar a tabela', async () => {
        const admin = await asUser(ADMIN);
        await http()
          .post('/api/v1/seasons/B2026/versions')
          .set('Authorization', admin)
          .send({ ...tabela(115), targetBarters: 2 });

        const ligado = await http()
          .put('/api/v1/barter-versions/B2026.03/close-on-goal')
          .set('Authorization', admin)
          .send({ enabled: true });
        expect(ligado.status).toBe(200);
        expect(ligado.body.data.closeOnGoal).toBe(true);
        // Meta de duas permutas, nenhuma aprovada ainda: ligar não fecha.
        expect(ligado.body.data.status).toBe('active');

        const desligado = await http()
          .put('/api/v1/barter-versions/B2026.03/close-on-goal')
          .set('Authorization', admin)
          .send({ enabled: false });
        expect(desligado.body.data.closeOnGoal).toBe(false);
      });

      /**
       * Ligar a opção com a meta JÁ batida encerra na hora. É a leitura literal
       * de "encerre ao bater meta" — a alternativa seria um Barter aberto, com a
       * meta batida e a opção ligada, esperando uma aprovação que talvez nunca
       * venha.
       */
      it('ligar o automático com a meta já batida encerra na hora', async () => {
        const admin = await asUser(ADMIN);
        await http()
          .post('/api/v1/seasons/B2026/versions')
          .set('Authorization', admin)
          .send({ ...tabela(115), targetBarters: 1 });

        await aprovarUmaPermuta();

        const ligado = await http()
          .put('/api/v1/barter-versions/B2026.03/close-on-goal')
          .set('Authorization', admin)
          .send({ enabled: true });
        expect(ligado.status).toBe(200);
        expect(ligado.body.data.status).toBe('closed');
        expect(ligado.body.data.closedBy).toBe('Automático: meta de permutas atingida (1)');
      });

      it('versão sem meta não aceita o automático, e versão encerrada não muda de modo', async () => {
        const admin = await asUser(ADMIN);
        await http()
          .post('/api/v1/seasons/B2026/versions')
          .set('Authorization', admin)
          .send(tabela(115));

        const semMeta = await http()
          .put('/api/v1/barter-versions/B2026.03/close-on-goal')
          .set('Authorization', admin)
          .send({ enabled: true });
        expect(semMeta.status).toBe(422);
        expect(semMeta.body.message).toContain('não tem meta');

        await http().post('/api/v1/barter-versions/B2026.03/close').set('Authorization', admin);
        const encerrada = await http()
          .put('/api/v1/barter-versions/B2026.03/close-on-goal')
          .set('Authorization', admin)
          .send({ enabled: false });
        expect(encerrada.status).toBe(422);
        expect(encerrada.body.message).toContain('Só a versão vigente');
      });

      it('consultor e retaguarda não mudam o modo de encerramento', async () => {
        for (const email of [JOAO, ...BACK_OFFICE]) {
          const response = await http()
            .put('/api/v1/barter-versions/B2026.02/close-on-goal')
            .set('Authorization', await asUser(email))
            .send({ enabled: true });
          expect(response.status).toBe(403);
        }
      });
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
        .post('/api/v1/seasons/B2026/versions/import')
        .set('Authorization', await asUser(ADMIN))
        .field('grains', JSON.stringify([{ ...soja, price: '152,50' }]))
        .attach('file', arquivo, 'tabela-setembro.xlsx');

      expect(response.status).toBe(201);
      expect(response.body.data).toMatchObject({
        code: 'B2026.03',
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
        .post('/api/v1/seasons/B2026/versions/import')
        .set('Authorization', await asUser(ADMIN))
        .field('grains', JSON.stringify([soja]))
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
        .post('/api/v1/seasons/B2026/versions/import')
        .set('Authorization', admin)
        .field('grains', JSON.stringify([soja]))
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
        .post('/api/v1/seasons/B2026/versions/import')
        .set('Authorization', admin)
        .field('grains', JSON.stringify([soja]))
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
        .post('/api/v1/seasons/B2026/versions/import')
        .set('Authorization', await asUser(ADMIN))
        .field('grains', JSON.stringify([soja]))
        .attach('file', arquivo, 'tabela.xlsx');

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Linha 2');

      // A versão vigente continua sendo a de antes.
      const current = await http()
        .get('/api/v1/barter-versions/current')
        .set('Authorization', await asUser(JOAO));
      expect(current.body.data.code).toBe('B2026.02');
    });

    it('arquivo que não é .xlsx é recusado', async () => {
      const response = await http()
        .post('/api/v1/seasons/B2026/versions/import')
        .set('Authorization', await asUser(ADMIN))
        .field('grains', JSON.stringify([soja]))
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
          .post('/api/v1/seasons/B2026/versions/import')
          .set('Authorization', await asUser(ADMIN))
          .field('grains', JSON.stringify([soja]))
          .field('endsAt', '2020-01-01T00:00:00.000Z')
          .attach('file', await fantasma(), 'tabela.xlsx');

        expect(response.status).toBe(422);
        expect(response.body.message).toContain('futuro');

        expect(await catalogo()).not.toContain('Insumo Fantasma');
      });

      it('safra já encerrada', async () => {
        const admin = await asUser(ADMIN);
        await http().post('/api/v1/seasons/B2026/close').set('Authorization', admin);

        const response = await http()
          .post('/api/v1/seasons/B2026/versions/import')
          .set('Authorization', admin)
          .field('grains', JSON.stringify([soja]))
          .attach('file', await fantasma(), 'tabela.xlsx');

        expect(response.status).toBe(422);
        expect(response.body.message).toContain('encerrada');

        expect(await catalogo()).not.toContain('Insumo Fantasma');
      });
    });

    /**
     * A ATOMICIDADE da importação, no ponto em que ela realmente faltava.
     *
     * O casamento com o catálogo CRIA produto e pasta, e isso acontecia fora de
     * qualquer transação — a publicação vinha depois, separada. Falhando a
     * publicação, os cadastros recém-criados ficavam para trás e nenhuma versão
     * saía: o admin lia "Erro inesperado no servidor" e o catálogo dele tinha
     * mudado assim mesmo.
     *
     * O gatilho aqui é o `sku` do GRÃO. A busca por código só enxerga insumos,
     * então uma linha com `GRA-0001` não casa com nada, entra como produto novo
     * e esbarra no índice único de `sku` na hora de gravar — depois de a pasta
     * nova já ter sido criada. É essa pasta que este teste procura.
     */
    it('falha no meio da gravação desfaz também as PASTAS que a planilha criou', async () => {
      const admin = await asUser(ADMIN);
      const pastas = async () => {
        const response = await http().get('/api/v1/classes').set('Authorization', admin);
        return response.body.data.map((c: { name: string }) => c.name);
      };
      expect(await pastas()).not.toContain('Pasta Inédita');

      const response = await http()
        .post('/api/v1/seasons/B2026/versions/import')
        .set('Authorization', admin)
        .field('grains', JSON.stringify([soja]))
        .attach(
          'file',
          await planilha([['GRA-0001', 'Insumo de Código Tomado', 'litro', 'Pasta Inédita', 99]]),
          'tabela.xlsx',
        );

      expect(response.status).toBe(422);
      expect(await pastas()).not.toContain('Pasta Inédita');
    });

    /**
     * O TETO DECLARADO, entregue de verdade — nos dois caminhos.
     *
     * Publicar a tabela cheia estourava o prazo da transação (P2028 aos 5 s) e
     * voltava como 500, porque a linha do tempo de preços era gravada com um
     * UPDATE por produto, em série. O que este teste guarda não é a velocidade:
     * é que o número que o sistema anuncia como limite seja um número que ele
     * consegue gravar.
     */
    it(`publica ${MAX_VERSION_PRICES} preços por planilha — o teto declarado`, async () => {
      const linhas = Array.from({ length: MAX_VERSION_PRICES }, (_, i) => [
        `CARGA-${i}`,
        `Insumo de carga ${i}`,
        'kg',
        'Fertilizantes',
        10 + i,
      ]);

      const response = await http()
        .post('/api/v1/seasons/B2026/versions/import')
        .set('Authorization', await asUser(ADMIN))
        .field('grains', JSON.stringify([soja]))
        .attach('file', await planilha(linhas), 'tabela-cheia.xlsx');

      expect(response.status).toBe(201);
      expect(response.body.data.prices).toHaveLength(MAX_VERSION_PRICES);
    }, 120_000);

    it('carryOver mantém na tabela nova os insumos que o arquivo não trouxe', async () => {
      const arquivo = await planilha([
        ['NPK-0414', 'Fertilizante NPK 04-14-08', 'saco 50kg', 'Fertilizantes', 125],
      ]);

      const response = await http()
        .post('/api/v1/seasons/B2026/versions/import')
        .set('Authorization', await asUser(ADMIN))
        .field('grains', JSON.stringify([soja]))
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
              .post('/api/v1/seasons/B2026/versions')
              .set('Authorization', auth)
              .send(tabela(115))
          ).status,
        ).toBe(403);
        expect(
          (await http().post('/api/v1/barter-versions/B2026.02/close').set('Authorization', auth))
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
        expect(response.body.data.code).toBe('B2026.02');
      }
    });
  });
});
