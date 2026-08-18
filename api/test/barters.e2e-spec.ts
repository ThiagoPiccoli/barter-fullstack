import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import {
  ADMIN,
  ANA,
  GERENTE,
  GERENTE_SUL,
  JOAO,
  UNIT,
  createTestApp,
  loginAs,
  resetDb,
} from './utils';

/**
 * Payload válido para o Antônio Carvalho (120 ha, carteira do João).
 * Mínimos por hectare: 48 sacos NPK (0.4/ha), 300 L glifosato (2.5/ha),
 * 18 L lambda (0.15/ha). Custo: 48×115 + 300×18.9 + 18×42 = R$ 11.946,00.
 *
 * A retirada é na Filial 02, que é a unidade do próprio João — e é da Beatriz
 * (GERENTE) o parecer sobre ela.
 */
const validPayload = {
  producerId: 1,
  unitId: UNIT.filial02,
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
    expect(pending.body.data).toHaveLength(1);
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
    // Ela NASCE na mesa do gerente da unidade de retirada, não em análise.
    expect(barter.status).toBe('sentToManager');
    expect(barter.unitName).toBe('Filial 02 – Gran. Santa T.');
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

  /**
   * A ETAPA DO GERENTE, por inteiro.
   *
   * O que estes casos prendem não é a rota — é a ordem do fluxo. O erro que eles
   * existem para pegar é o que teria acontecido se a permuta continuasse
   * nascendo em `pending`: o parecer viraria um campo opcional que a análise
   * podia ignorar, e a etapa do gerente seria só decoração.
   */
  describe('parecer técnico do gerente', () => {
    const opinion = 'Volume compatível com a área e com o histórico do produtor.';

    it('a permuta nasce endereçada ao gerente do consultor, esperando o parecer', async () => {
      const created = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send(validPayload);

      expect(created.status).toBe(201);
      // João é do time da Beatriz — e é para ela que a permuta vai, esteja a
      // retirada onde estiver.
      expect(created.body.data.managerName).toBe('Beatriz Nogueira');
      expect(created.body.data.managerNote).toBeNull();

      const code = created.body.data.code as string;
      const cedoDemais = await request(app.getHttpServer())
        .post(`/api/v1/barters/${code}/review`)
        .set('Authorization', await asUser(ADMIN))
        .send({ status: 'approved' });
      expect(cedoDemais.status).toBe(422);
      // A mensagem diz COM QUEM ela está parada, não "já foi revisada".
      expect(cedoDemais.body.message).toContain('parecer do gerente');
      expect(cedoDemais.body.message).toContain('Beatriz Nogueira');
    });

    it('o gerente dá o parecer e a permuta segue para a análise', async () => {
      // PRM-2026-005 é do João, do time da Beatriz, e espera o parecer dela.
      const response = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-005/opinion')
        .set('Authorization', await asUser(GERENTE))
        .send({ note: opinion });

      expect(response.status).toBe(200);
      const barter = response.body.data;
      expect(barter.status).toBe('pending');
      expect(barter.managerName).toBe('Beatriz Nogueira');
      expect(barter.managerNote).toBe(opinion);
      expect(barter.managerReviewedAt).toBeTruthy();

      // E agora sim o admin alcança.
      const review = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-005/review')
        .set('Authorization', await asUser(ADMIN))
        .send({ status: 'approved' });
      expect(review.status).toBe(200);
      // O parecer não é apagado pela decisão seguinte: os dois convivem.
      expect(review.body.data.managerNote).toBe(opinion);
    });

    /**
     * O caso que a tabela de capacidades sozinha não pega: Gustavo TEM
     * `barters.opinion` e mesmo assim não opina sobre o time da Beatriz.
     */
    it('gerente de outro time não dá parecer na permuta deste', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-005/opinion')
        .set('Authorization', await asUser(GERENTE_SUL))
        .send({ note: opinion });
      expect(response.status).toBe(403);
      expect(response.body.message).toContain('outro gerente');
    });

    it('parecer não se dá duas vezes', async () => {
      const gerente = await asUser(GERENTE);
      await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-005/opinion')
        .set('Authorization', gerente)
        .send({ note: opinion })
        .expect(200);

      const denovo = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-005/opinion')
        .set('Authorization', gerente)
        .send({ note: 'Mudei de ideia.' });
      expect(denovo.status).toBe(422);
    });

    /** Parecer em branco não é parecer — é um botão de "seguir". */
    it('parecer vazio ou curto demais é recusado', async () => {
      const gerente = await asUser(GERENTE);
      for (const note of ['', '   ', 'ok']) {
        const response = await request(app.getHttpServer())
          .post('/api/v1/barters/PRM-2026-005/opinion')
          .set('Authorization', gerente)
          .send({ note });
        expect(response.status).toBe(422);
      }
    });

    it('nem admin nem consultor dão parecer — a etapa é do gerente', async () => {
      for (const email of [ADMIN, JOAO]) {
        const response = await request(app.getHttpServer())
          .post('/api/v1/barters/PRM-2026-005/opinion')
          .set('Authorization', await asUser(email))
          .send({ note: opinion });
        expect(response.status).toBe(403);
      }
    });

    /**
     * A fila do gerente sai do próprio escopo dele, sem filtro nenhum: ele já
     * enxerga só o time. `?status=sentToManager` é o recorte do que pede ação.
     */
    it('a fila do gerente é o que espera parecer dentro do escopo dele', async () => {
      const gerente = await asUser(GERENTE);
      const fila = await request(app.getHttpServer())
        .get('/api/v1/barters?status=sentToManager')
        .set('Authorization', gerente);
      expect(fila.status).toBe(200);
      // PRM-2026-007 também espera parecer, mas é do time do Gustavo — e nem
      // aparece para ela.
      expect(fila.body.data.map((b: { code: string }) => b.code)).toEqual(['PRM-2026-005']);
    });

    /**
     * A troca de gerente vale para as PRÓXIMAS permutas. As que já estão na
     * mesa de alguém continuam lá — a permuta guarda a quem foi enviada, e não
     * muda de mãos sem ninguém ter agido sobre ela.
     */
    it('trocar o gerente do consultor não move o que já foi enviado', async () => {
      const admin = await asUser(ADMIN);
      await request(app.getHttpServer())
        .put('/api/v1/consultants/2') // João: Beatriz (7) → Gustavo (10)
        .set('Authorization', admin)
        .send({
          fullName: 'João Silva',
          email: JOAO,
          unitId: UNIT.filial02,
          managerId: 10,
        })
        .expect(200);

      // A que já estava esperando continua com a Beatriz.
      await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-005/opinion')
        .set('Authorization', await asUser(GERENTE_SUL))
        .send({ note: 'Assumi o consultor, mas esta não é minha.' })
        .expect(403);
      await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-005/opinion')
        .set('Authorization', await asUser(GERENTE))
        .send({ note: opinion })
        .expect(200);

      // A PRÓXIMA já nasce para o gerente novo.
      const nova = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send(validPayload);
      expect(nova.status).toBe(201);
      expect(nova.body.data.managerName).toBe('Gustavo Ramires');
    });

    /**
     * O cadastro exige gerente, então só se chega aqui quando o gerente é
     * excluído depois. A permuta nasceria endereçada a ninguém.
     */
    it('consultor sem gerente não registra permuta', async () => {
      const admin = await asUser(ADMIN);
      // Esvazia o time da Beatriz e a fila dela, para poder excluí-la.
      for (const [id, nome, email] of [
        [2, 'João Silva', JOAO],
        [3, 'Ana Paula Ferreira', ANA],
      ] as const) {
        await request(app.getHttpServer())
          .put(`/api/v1/consultants/${id}`)
          .set('Authorization', admin)
          .send({ fullName: nome, email, unitId: UNIT.filial02, managerId: 10 })
          .expect(200);
      }
      await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-005/opinion')
        .set('Authorization', await asUser(GERENTE))
        .send({ note: opinion })
        .expect(200);
      await request(app.getHttpServer())
        .delete('/api/v1/managers/10') // Gustavo, que agora tem o time inteiro
        .set('Authorization', admin)
        .expect(422);
    });
  });

  describe('unidade de retirada', () => {
    it('permuta sem unidade é recusada — não há retirada sem lugar', async () => {
      const { unitId, ...semUnidade } = validPayload;
      void unitId;
      const response = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send(semUnidade);
      expect(response.status).toBe(422);
    });

    it('unidade inexistente é recusada', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send({ ...validPayload, unitId: 999 });
      expect(response.status).toBe(422);
      expect(response.body.message).toContain('unidade');
    });

    /**
     * A retirada é combinada com o produtor e QUALQUER praça serve. O parecer
     * continua sendo do gerente do consultor — a unidade não roteia nada.
     */
    it('qualquer unidade serve, e ela não muda de quem é o parecer', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send({ ...validPayload, unitId: UNIT.filial34 });
      expect(response.status).toBe(201);
      expect(response.body.data.unitName).toBe('Filial 34 – Gran. Jari');
      expect(response.body.data.managerName).toBe('Beatriz Nogueira');
    });
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

    it('unidade que não é número é recusada pelo mesmo motivo', async () => {
      const response = await list('?unitId=abc');
      expect(response.status).toBe(422);
      expect(response.body.message).toContain('unitId');
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
      const response = await list('?status=sentToManager&limit=1');
      expect(response.body.data).toHaveLength(1);
      expect(response.body.meta.total).toBe(2);
      expect(response.body.data[0].status).toBe('sentToManager');
    });
  });
});
