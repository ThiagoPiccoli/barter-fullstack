import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import {
  ADMIN,
  ANA,
  COMITE,
  FATURISTA,
  GERENTE,
  GERENTE_SUL,
  JOAO,
  ROBERTO,
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
    // A conta em SACAS é toda a resposta que o consultor recebe: o valor da saca
    // é R$, e R$ não atravessa a lente dele (ver `ValueLens`). Quem confere o
    // valor congelado é a retaguarda, abaixo.
    expect(grains[0].unitValue).toBeUndefined();

    const daRetaguarda = await request(app.getHttpServer())
      .get(`/api/v1/barters/${barter.code}`)
      .set('Authorization', await asUser(ADMIN));
    const grainEmReais = daRetaguarda.body.data.items.find(
      (i: { kind: string }) => i.kind === 'grain',
    );
    expect(grainEmReais.unitValue).toBe(148.5);
  });

  /**
   * FUNRURAL/SENAR: a entrega de grão é comercialização de produção rural, e as
   * DUAS FORMAS de recolhimento são escolhidas no fechamento da permuta.
   *
   * O que a permuta grava é a ALÍQUOTA que a escolha produziu — snapshot, como
   * `producerName` e o preço do item. A alíquota muda por lei, e um comprovante
   * reimpresso depois não pode mostrar outro imposto.
   */
  describe('imposto da entrega (Funrural/Senar)', () => {
    const registrar = async (taxRegime?: string) =>
      request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send(taxRegime ? { ...validPayload, taxRegime } : validPayload);

    it('fechar sobre a comercialização aplica a alíquota cheia', async () => {
      const response = await registrar('comercializacao');

      expect(response.status).toBe(201);
      // Antônio Carvalho é CPF: 1,32 + 0,11 + 0,20 = 1,63%.
      expect(response.body.data.taxRegime).toBe('comercializacao');
      expect(response.body.data.taxRate).toBe(1.63);
    });

    /**
     * O ponto da funcionalidade: escolher a folha NÃO isenta a entrega. A parte
     * previdenciária muda de base (vai para a folha de pagamento, que este
     * sistema não conhece), e o Senar continua incidindo sobre a comercialização.
     */
    it('fechar sobre a folha deixa só o Senar sobre a entrega', async () => {
      const response = await registrar('folha');

      expect(response.status).toBe(201);
      expect(response.body.data.taxRegime).toBe('folha');
      expect(response.body.data.taxRate).toBe(0.2);
    });

    it('permuta sem a escolha cai na comercialização', async () => {
      const response = await registrar();
      expect(response.body.data.taxRegime).toBe('comercializacao');
      expect(response.body.data.taxRate).toBe(1.63);
    });

    it('forma de recolhimento que não existe é recusada', async () => {
      const response = await registrar('presumido');
      expect(response.status).toBe(422);
      expect(response.body.message).toContain('recolhimento');
    });

    /** PF ou PJ não é escolha: sai do documento do produtor da permuta. */
    it('a mesma escolha cobra percentuais diferentes de CPF e CNPJ', async () => {
      // Joaquim Tavares (id 3) é CNPJ e também é atendido pelo João. São 320 ha,
      // então os mínimos por hectare sobem junto: 128 NPK, 800 glifosato, 48
      // lambda.
      const doCnpj = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send({
          ...validPayload,
          producerId: 3,
          taxRegime: 'comercializacao',
          inputs: [
            { productId: 5, quantity: 128 },
            { productId: 6, quantity: 800 },
            { productId: 7, quantity: 48 },
          ],
        });

      expect(doCnpj.status).toBe(201);
      // CNPJ: 1,98 + 0,25 = 2,23%.
      expect(doCnpj.body.data.taxRate).toBe(2.23);
    });

    /** A alíquota fica congelada: reler a permuta devolve o que foi registrado. */
    it('a alíquota registrada não muda quando a permuta é relida', async () => {
      const criada = await registrar('folha');
      const relida = await request(app.getHttpServer())
        .get(`/api/v1/barters/${criada.body.data.code}`)
        .set('Authorization', await asUser(JOAO));

      expect(relida.body.data.taxRegime).toBe('folha');
      expect(relida.body.data.taxRate).toBe(0.2);
    });
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
    // O preço GRAVADO é o do banco, e é a retaguarda que o lê de volta — para o
    // consultor a permuta continua sem R$ nenhum.
    const registrada = await request(app.getHttpServer())
      .get(`/api/v1/barters/${response.body.data.code}`)
      .set('Authorization', await asUser(ADMIN));
    const npk = registrada.body.data.items.find((i: { productId: number }) => i.productId === 5);
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
    // Helena Prado (id 2) é atendida só pela Ana.
    const response = await request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', await asUser(JOAO))
      .send({ ...validPayload, producerId: 2 });
    expect(response.status).toBe(403);
  });

  /**
   * A carteira compartilhada não afrouxa a regra acima — ela muda a pergunta,
   * de "é o dono?" para "está na carteira?". Joaquim Tavares (id 3, 320 ha) é
   * atendido pelo Roberto E pelo João, e os dois registram permuta para ele.
   * Cada permuta continua sendo de UM consultor: o que a registrou.
   */
  it('produtor compartilhado permuta pelos dois consultores', async () => {
    // Mínimos para 320 ha: 128 sacos NPK, 800 L glifosato, 48 L lambda.
    const payload = {
      ...validPayload,
      producerId: 3,
      unitId: UNIT.filial34,
      inputs: [
        { productId: 5, quantity: 128 },
        { productId: 6, quantity: 800 },
        { productId: 7, quantity: 48 },
      ],
    };

    for (const [email, nome] of [
      [ROBERTO, 'Roberto Souza'],
      [JOAO, 'João Silva'],
    ]) {
      const response = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', await asUser(email))
        .send(payload);
      expect(response.status).toBe(201);
      expect(response.body.data.producerName).toBe('Joaquim Tavares');
      expect(response.body.data.consultantName).toBe(nome);
    }
  });

  it('admin não registra permuta (ato do consultor da carteira)', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', await asUser(ADMIN))
      .send(validPayload);
    expect(response.status).toBe(403);
  });

  it('o comitê aprova pendente com observação e snapshot de quem decidiu', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-002/review')
      .set('Authorization', await asUser(COMITE))
      .send({ status: 'approved', note: 'Tudo certo com o estoque.' });

    expect(response.status).toBe(200);
    const barter = response.body.data;
    expect(barter.status).toBe('approved');
    expect(barter.reviewedBy).toBe('Comitê de Permutas');
    expect(barter.reviewNote).toBe('Tudo certo com o estoque.');
    expect(barter.reviewedAt).toBeTruthy();
    // Aprovada é a fila do faturista: quem está com ela agora é ele.
    expect(barter.waitingFor).toBe('biller');
  });

  it('permuta já decidida não é decidida de novo', async () => {
    // PRM-2026-004 já está aprovada no dataset.
    const response = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-004/review')
      .set('Authorization', await asUser(COMITE))
      .send({ status: 'denied' });
    expect(response.status).toBe(422);
    expect(response.body.message).toContain('já foi decidida');
  });

  it('consultor não decide permuta', async () => {
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
        .set('Authorization', await asUser(COMITE))
        .send({ status: 'approved' });
      expect(cedoDemais.status).toBe(422);
      // A mensagem diz COM QUEM ela está parada, não "já foi revisada".
      expect(cedoDemais.body.message).toContain('parecer do gerente');
      expect(cedoDemais.body.message).toContain('Beatriz Nogueira');
    });

    it('o gerente dá o parecer e a permuta segue para o comitê', async () => {
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

      // E agora sim o comitê alcança.
      const review = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-005/review')
        .set('Authorization', await asUser(COMITE))
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

  /**
   * OS DOIS ÚLTIMOS POSTOS DA LINHA — a decisão do comitê e o faturamento.
   *
   * O que estes casos prendem é a separação: quem decide não fatura, quem fatura
   * não decide, e quem administra o sistema não faz nem uma coisa nem outra. Sem
   * eles, devolver a decisão ao admin — de propósito ou por descuido numa linha
   * da tabela de capacidades — passaria em silêncio.
   */
  describe('a decisão do comitê e o faturamento', () => {
    /**
     * O ADMIN NÃO DECIDE MAIS. Este é o caso que a mudança inteira existe para
     * produzir: ele continua enxergando tudo e administrando tudo, e a única
     * coisa que perdeu foi decidir o negócio.
     */
    it('o admin não decide permuta — ele administra o sistema', async () => {
      const admin = await asUser(ADMIN);
      const decisão = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/review')
        .set('Authorization', admin)
        .send({ status: 'approved' });
      expect(decisão.status).toBe(403);
      expect(decisão.body.message).toContain('Comitê');

      // E o que ele perdeu foi só isso: continua vendo a operação inteira.
      const lista = await request(app.getHttpServer())
        .get('/api/v1/barters')
        .set('Authorization', admin);
      expect(lista.body.data).toHaveLength(8);
    });

    it('a permuta aprovada é faturada pelo faturista, e aí acabou a linha', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/review')
        .set('Authorization', await asUser(COMITE))
        .send({ status: 'approved' })
        .expect(200);

      const faturista = await asUser(FATURISTA);
      const faturada = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/invoice')
        .set('Authorization', faturista)
        .send({ note: 'Nota emitida em 12/05.' });

      expect(faturada.status).toBe(200);
      expect(faturada.body.data.status).toBe('invoiced');
      expect(faturada.body.data.invoicedBy).toBe('Patrícia Lemos');
      expect(faturada.body.data.invoicedAt).toBeTruthy();
      expect(faturada.body.data.invoiceNote).toBe('Nota emitida em 12/05.');
      // Fim de linha: ninguém mais está com ela, e não há próximo ato.
      expect(faturada.body.data.waitingFor).toBeNull();
      expect(faturada.body.data.nextAction).toBeNull();

      const denovo = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/invoice')
        .set('Authorization', faturista)
        .send({});
      expect(denovo.status).toBe(422);
      expect(denovo.body.message).toContain('já foi faturada');
    });

    /**
     * "Ele apenas faturará o que foi aprovado" — e as três maneiras de a permuta
     * não estar aprovada agora param ANTES, no escopo.
     *
     * O faturista alcança o que chegou ao faturamento e nada antes disso, então
     * pedir a nota de uma permuta que está no gerente, no comitê ou negada não é
     * "chegou fora de hora": é uma permuta que não é dele. A NEGADA continua
     * sendo a que mais importa — é a única forma de dinheiro sair por engano
     * daqui —, e ela agora nem abre.
     *
     * O que a recusa NÃO pode fazer é contar o que ele não pode ler. Enquanto a
     * permuta era buscada sem escopo, a resposta vinha com o estado e o nome do
     * gerente dentro: a mensagem da etapa virava a porta dos fundos do recorte,
     * e um código chutado devolvia o andamento de uma negociação em aberto.
     */
    it('o faturista não alcança o que ainda não chegou nele — e a recusa não conta nada', async () => {
      const faturista = await asUser(FATURISTA);

      // 005 está no gerente, 002 no comitê e 003 foi negada.
      for (const code of ['PRM-2026-005', 'PRM-2026-002', 'PRM-2026-003']) {
        const resposta = await request(app.getHttpServer())
          .post(`/api/v1/barters/${code}/invoice`)
          .set('Authorization', faturista)
          .send({});
        expect([code, resposta.status]).toEqual([code, 403]);
        // A resposta é a MESMA para os três: nem o estado nem o nome de quem
        // está com ela vazam pela mensagem.
        expect(resposta.body.message).toBe('Você não tem acesso a esta permuta');
      }
    });

    /**
     * A MENSAGEM DA ETAPA continua existindo — para quem ENXERGA a permuta.
     *
     * Quem chega cedo precisa saber com quem ela está parada; quem chega tarde,
     * que a etapa dele já foi cumprida. O comitê é o caso: ele lê a linha
     * inteira, então a recusa pode lhe dizer onde a permuta está sem contar nada
     * que ele já não pudesse abrir.
     */
    it('para quem enxerga a permuta, a recusa diz onde ela está', async () => {
      const comitê = await asUser(COMITE);
      const decidir = (code: string) =>
        request(app.getHttpServer())
          .post(`/api/v1/barters/${code}/review`)
          .set('Authorization', comitê)
          .send({ status: 'approved' });

      // Cedo: ainda no gerente.
      const cedo = await decidir('PRM-2026-005');
      expect(cedo.status).toBe(422);
      expect(cedo.body.message).toContain('parecer do gerente');

      // Tarde: já faturada.
      const tarde = await decidir('PRM-2026-001');
      expect(tarde.status).toBe(422);
      expect(tarde.body.message).toContain('já foi decidida');

      // Negada: fim de linha, e nenhuma das duas explicações serve.
      const negada = await decidir('PRM-2026-003');
      expect(negada.status).toBe(422);
      expect(negada.body.message).toContain('negada');
    });

    it('o comitê não fatura e o faturista não decide', async () => {
      const semFaturar = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-004/invoice')
        .set('Authorization', await asUser(COMITE))
        .send({});
      expect(semFaturar.status).toBe(403);
      expect(semFaturar.body.message).toContain('Faturista');

      const semDecidir = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/review')
        .set('Authorization', await asUser(FATURISTA))
        .send({ status: 'approved' });
      expect(semDecidir.status).toBe(403);
      expect(semDecidir.body.message).toContain('Comitê');
    });

    /**
     * DUAS DECISÕES AO MESMO TEMPO. O comitê é um colegiado — mais de uma pessoa
     * com a mesma capacidade —, então dois membros podem abrir a mesma permuta e
     * clicar quase junto.
     *
     * O que não pode acontecer é a segunda decisão sobrescrever a primeira em
     * silêncio: as duas passariam pela leitura do estado antes de qualquer uma
     * gravar. Quem impede é o `status` no `where` do update (ver applyStep) —
     * exatamente uma das duas encontra a linha, e a outra recebe a resposta de
     * quem chegou tarde.
     */
    it('duas decisões simultâneas: uma vale, a outra é recusada', async () => {
      const comitê = await asUser(COMITE);
      const decidir = (status: string) =>
        request(app.getHttpServer())
          .post('/api/v1/barters/PRM-2026-002/review')
          .set('Authorization', comitê)
          .send({ status });

      const [uma, outra] = await Promise.all([decidir('approved'), decidir('denied')]);
      const status = [uma.status, outra.status].sort();
      expect(status).toEqual([200, 422]);

      // E a permuta ficou com UMA decisão, a de quem chegou primeiro.
      const depois = await request(app.getHttpServer())
        .get('/api/v1/barters/PRM-2026-002')
        .set('Authorization', comitê);
      const events = depois.body.data.events as { action: string }[];
      expect(events.filter((e) => e.action === 'review')).toHaveLength(1);
    });

    /** A fila de cada posto é um filtro de estado — nenhuma delas tem dono. */
    it('cada posto tem a própria fila, e ela é o estado da permuta', async () => {
      const filas: [string, string, number][] = [
        [FATURISTA, 'approved', 3],
        [COMITE, 'pending', 1],
        [FATURISTA, 'invoiced', 1],
      ];

      for (const [email, status, quantas] of filas) {
        const response = await request(app.getHttpServer())
          .get(`/api/v1/barters?status=${status}`)
          .set('Authorization', await asUser(email));
        expect(response.status).toBe(200);
        expect(response.body.data).toHaveLength(quantas);
      }
    });
  });

  /**
   * A LINHA DO TEMPO da permuta — a auditoria do fluxo, dentro do documento.
   *
   * Ela é o que o faturista recebe das etapas anteriores: o pedido, o parecer e
   * a decisão, na ordem em que aconteceram, sem depender de nenhum campo ter
   * sobrevivido a uma edição posterior.
   */
  describe('histórico da permuta', () => {
    it('o detalhe conta a permuta inteira, um passo por etapa', async () => {
      // PRM-2026-001 nasceu, teve parecer, foi decidida e foi faturada.
      const response = await request(app.getHttpServer())
        .get('/api/v1/barters/PRM-2026-001')
        .set('Authorization', await asUser(FATURISTA));

      expect(response.status).toBe(200);
      const events = response.body.data.events as {
        action: string;
        fromStatus: string | null;
        toStatus: string;
        actorName: string;
        actorRole: string;
        actorRoleLabel: string;
        note: string | null;
      }[];

      expect(events.map((e) => [e.action, e.fromStatus, e.toStatus])).toEqual([
        ['register', null, 'sentToManager'],
        ['opinion', 'sentToManager', 'pending'],
        ['review', 'pending', 'approved'],
        ['invoice', 'approved', 'invoiced'],
      ]);
      expect(events.map((e) => e.actorRole)).toEqual([
        'consultant',
        'manager',
        'committee',
        'biller',
      ]);
      expect(events.map((e) => e.actorName)).toEqual([
        'João Silva',
        'Beatriz Nogueira',
        'Comitê de Permutas',
        'Patrícia Lemos',
      ]);
      // O texto de cada etapa fica no evento, e não só no campo da permuta —
      // que é sobrescrito.
      expect(events[1].note).toContain('Volume compatível');
      expect(events[3].note).toContain('nota única');
      expect(events[0].actorRoleLabel).toBe('Consultor');
    });

    it('cada ato acrescenta um passo, e nenhum apaga o anterior', async () => {
      const antes = await request(app.getHttpServer())
        .get('/api/v1/barters/PRM-2026-002')
        .set('Authorization', await asUser(COMITE));
      expect(antes.body.data.events).toHaveLength(2);

      const decisão = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/review')
        .set('Authorization', await asUser(COMITE))
        .send({ status: 'denied', note: 'Fora da política de risco desta safra.' });
      expect(decisão.status).toBe(200);

      // A RESPOSTA DO ATO já traz o passo que ele acabou de criar. Sem isso, a
      // tela que agiu ficaria com uma permuta sem histórico na mão, e a linha do
      // tempo sumiria no instante seguinte ao clique.
      expect(decisão.body.data.events).toHaveLength(3);

      const depois = await request(app.getHttpServer())
        .get('/api/v1/barters/PRM-2026-002')
        .set('Authorization', await asUser(COMITE));
      const events = depois.body.data.events;
      expect(events).toHaveLength(3);
      expect(events[2]).toMatchObject({
        action: 'review',
        fromStatus: 'pending',
        toStatus: 'denied',
        actorName: 'Comitê de Permutas',
        note: 'Fora da política de risco desta safra.',
      });
      // O parecer do gerente continua lá, intacto.
      expect(events[1].action).toBe('opinion');
    });

    /**
     * A LISTAGEM não traz histórico. Não é economia de bytes: é a diferença
     * entre uma tela que mostra estado e uma que mostra trajetória — e cinquenta
     * linhas de tabela não têm o que fazer com quatro eventos cada uma.
     */
    it('a listagem não carrega a linha do tempo de cada permuta', async () => {
      const response = await request(app.getHttpServer())
        .get('/api/v1/barters')
        .set('Authorization', await asUser(FATURISTA));
      expect(response.body.data[0].events).toBeUndefined();
    });

    /**
     * O REGISTRO também nasce com a linha do tempo na resposta — um passo só,
     * que é o dele. Toda resposta de UMA permuta é do tamanho do detalhe; quem
     * não carrega histórico é a listagem.
     */
    it('a permuta recém-registrada já volta com o primeiro passo', async () => {
      const created = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send(validPayload);

      expect(created.status).toBe(201);
      expect(created.body.data.events).toHaveLength(1);
      expect(created.body.data.events[0]).toMatchObject({
        action: 'register',
        fromStatus: null,
        toStatus: 'sentToManager',
        actorName: 'João Silva',
      });
    });

    /** O consultor acompanha o andamento da PRÓPRIA permuta pelo mesmo caminho. */
    it('o consultor enxerga a linha do tempo da permuta dele', async () => {
      const response = await request(app.getHttpServer())
        .get('/api/v1/barters/PRM-2026-005')
        .set('Authorization', await asUser(JOAO));
      expect(response.status).toBe(200);
      expect(response.body.data.events).toHaveLength(1);
      expect(response.body.data.waitingFor).toBe('manager');
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
