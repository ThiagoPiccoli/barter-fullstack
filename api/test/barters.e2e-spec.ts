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
  MANAGER,
  ROBERTO,
  UNIT,
  attachInvoice,
  createTestApp,
  fillCpr,
  loginAs,
  resetDb,
} from './utils';
import { PrismaService } from '../src/prisma/prisma.service';

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

  /** O parecer do consultor usado por quem só precisa que a permuta ande. */
  const PARECER_DO_CONSULTOR = 'Cliente antigo, pagou as três últimas safras em dia.';

  /**
   * ENCAMINHA um rascunho ao gerente — a segunda metade do que o registro fazia
   * sozinho antes de o parecer do consultor existir.
   *
   * Ela aparece em quase todo caso daqui para baixo, e é exatamente esse o
   * ponto: uma permuta recém-registrada agora é RASCUNHO, e não está na mesa de
   * ninguém. Os casos que falam do gerente para a frente precisam dizer, em
   * algum lugar, que alguém a mandou — e este helper é esse lugar.
   */
  /// A CÉDULA vai junto porque ela é PRÉ-REQUISITO do encaminhamento: a coleta
  /// acontece na visita, com o produtor por perto, e não semanas depois. Para os
  /// casos daqui para baixo ela é preâmbulo — quem testa o portão em si é
  /// "a cédula é pré-requisito do encaminhamento", mais abaixo.
  const encaminhar = async (code: string, auth: string, note = PARECER_DO_CONSULTOR) => {
    await fillCpr(app, auth, code);
    return request(app.getHttpServer())
      .post(`/api/v1/barters/${code}/forward`)
      .set('Authorization', auth)
      .send({ note });
  };

  /** Registra e encaminha numa tacada — o fluxo completo do consultor. */
  const registrarEEncaminhar = async (email: string, payload: object = validPayload) => {
    const auth = await asUser(email);
    const criada = await request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', auth)
      .send(payload);
    expect(criada.status).toBe(201);
    return encaminhar(criada.body.data.code as string, auth);
  };

  it('listagem é escopada: consultor vê as suas, admin vê todas', async () => {
    const asJoao = await request(app.getHttpServer())
      .get('/api/v1/barters')
      .set('Authorization', await asUser(JOAO));
    expect(asJoao.status).toBe(200);
    expect(asJoao.body.data.map((b: { code: string }) => b.code).sort()).toEqual([
      'PRM-2026-001',
      'PRM-2026-005',
      // O RASCUNHO dele. Ele aparece só aqui: nem o admin o enxerga.
      'PRM-2026-009',
    ]);

    const admin = await asUser(ADMIN);
    const asAdmin = await request(app.getHttpServer())
      .get('/api/v1/barters')
      .set('Authorization', admin);
    // Oito das nove: o rascunho do João não é fila de ninguém, e quem enxerga
    // TUDO enxerga tudo o que foi proposto — não o que ainda está sendo escrito.
    expect(asAdmin.body.data).toHaveLength(8);
    expect(asAdmin.body.data.map((b: { code: string }) => b.code)).not.toContain('PRM-2026-009');

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
    expect(barter.code).toBe('PRM-2026-010');
    // Ela NASCE RASCUNHO: registrada, com as contas congeladas, e ainda na mão
    // do consultor. Quem a põe na mesa do gerente é o encaminhamento — e é por
    // isso que ela ainda não tem destinatário.
    expect(barter.status).toBe('draft');
    expect(barter.waitingFor).toBe('consultant');
    expect(barter.managerName).toBeNull();
    expect(barter.unitName).toBe('Filial 02 (Gran. Santa T.)');
    expect(barter.producerName).toBe('Antônio Carvalho');

    const grains = barter.items.filter((i: { kind: string }) => i.kind === 'grain');
    expect(grains).toHaveLength(1);
    // 11946 / 148.5 = 80.4444 sacas de soja
    expect(grains[0].quantity).toBe(80.4444);
    // A conta em SACAS é toda a resposta que o consultor recebe: o valor da saca
    // é R$, e R$ não atravessa a lente dele (ver `ValueLens`). Quem confere o
    // valor congelado é a retaguarda, abaixo.
    expect(grains[0].unitValue).toBeUndefined();

    // A retaguarda só a alcança depois de encaminhada: rascunho é do dono (ver
    // `scopeFor`). Encaminhar não recalcula nada — o valor congelado no registro
    // é o que ela lê.
    expect((await encaminhar(barter.code as string, await asUser(JOAO))).status).toBe(200);
    const daRetaguarda = await request(app.getHttpServer())
      .get(`/api/v1/barters/${barter.code}`)
      .set('Authorization', await asUser(ADMIN));
    const grainEmReais = daRetaguarda.body.data.items.find(
      (i: { kind: string }) => i.kind === 'grain',
    );
    expect(grainEmReais.unitValue).toBe(148.5);
  });

  /**
   * AS CULTURAS COEXISTEM, e a permuta escolhe UMA.
   *
   * O Barter vigente do seed aceita soja e milho ao mesmo tempo, com cotações,
   * produtividades e vencimentos próprios sobre a MESMA tabela de insumos. O que
   * estes casos fixam é o que a escolha produz: as sacas saem da cotação daquela
   * cultura, o penhor da produtividade dela, e o mesmo produtor pode fechar as
   * duas — que é justamente o que uma safra por grão impedia.
   */
  describe('a cultura da permuta', () => {
    const emMilho = { ...validPayload, grainId: 2 };

    it('a mesma permuta paga em milho rende outra quantidade de sacas', async () => {
      const consultor = await asUser(JOAO);
      const soja = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', consultor)
        .send(validPayload);
      const milho = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', consultor)
        .send(emMilho);

      expect(soja.status).toBe(201);
      expect(milho.status).toBe(201);

      const graoDe = (body: {
        data: { items: { kind: string; productName: string; quantity: number }[] };
      }) => body.data.items.find((item) => item.kind === 'grain');

      // O MESMO custo (R$ 11.946,00) e as MESMAS sacas em duas moedas: 148,50
      // a saca de soja, 64,50 a de milho.
      expect(graoDe(soja.body)).toMatchObject({ productName: 'Soja', quantity: 80.4444 });
      expect(graoDe(milho.body)).toMatchObject({ productName: 'Milho', quantity: 185.2093 });
    });

    /**
     * O PENHOR é dimensionado pela produtividade DAQUELA cultura: 60 sc/ha de
     * soja e 170 de milho. Fosse a mesma taxa para as duas, a permuta de milho
     * pediria quase três vezes a área que a lavoura precisa.
     */
    it('o penhor usa a produtividade da cultura escolhida', async () => {
      const consultor = await asUser(JOAO);
      const criada = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', consultor)
        .send(emMilho);
      await encaminhar(criada.body.data.code as string, consultor);

      const detalhe = await request(app.getHttpServer())
        .get(`/api/v1/barters/${criada.body.data.code}`)
        .set('Authorization', await asUser(ADMIN));
      // 185,2093 sacas ÷ 170 sc/ha × 1,20 de margem = 1,31 ha.
      expect(detalhe.body.data.pledgeAreaHa).toBeCloseTo(1.31, 2);
    });

    /** Cultura que o lançamento não aceita é recusada dizendo o que ele aceita. */
    it('cultura fora do lançamento é recusada, nomeando as que estão abertas', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send({ ...validPayload, grainId: 3 });

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Soja e Milho');
    });

    /** Sem cultura não há como pagar: o campo é obrigatório, e não tem padrão. */
    it('permuta sem cultura é recusada', async () => {
      const semCultura = { ...validPayload, grainId: undefined };
      const response = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send(semCultura);

      expect(response.status).toBe(422);
      expect(JSON.stringify(response.body.message)).toContain('cultura');
    });

    /**
     * A TROCA no rascunho: o produtor decide na conversa que aquele talhão vai
     * de milho. Os insumos ficam, a moeda muda — e com ela as sacas e a
     * produtividade que dimensiona o penhor.
     */
    it('o rascunho troca de cultura sem perder os insumos', async () => {
      const consultor = await asUser(JOAO);
      const criada = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', consultor)
        .send(validPayload);
      const code = criada.body.data.code as string;

      const trocada = await request(app.getHttpServer())
        .put(`/api/v1/barters/${code}/culture`)
        .set('Authorization', consultor)
        .send({ grainId: 2 });

      expect(trocada.status).toBe(200);
      const grao = trocada.body.data.items.find((item: { kind: string }) => item.kind === 'grain');
      expect(grao).toMatchObject({ productName: 'Milho', quantity: 185.2093 });
      // OS INSUMOS seguem os mesmos: trocar de cultura não é refazer a permuta.
      const insumos = trocada.body.data.items
        .filter((item: { kind: string }) => item.kind === 'input')
        .map((item: { productId: number; quantity: number }) => [item.productId, item.quantity]);
      expect(insumos).toEqual([
        [5, 48],
        [6, 300],
        [7, 18],
      ]);
    });

    /**
     * Depois do encaminhamento a permuta está na mesa de alguém, e trocar a
     * cultura por baixo mudaria o negócio que aquela pessoa está analisando. O
     * caminho de lá é o pedido de alteração.
     */
    it('permuta encaminhada não troca de cultura', async () => {
      const consultor = await asUser(JOAO);
      const encaminhada = await registrarEEncaminhar(JOAO);
      const code = encaminhada.body.data.code as string;

      const response = await request(app.getHttpServer())
        .put(`/api/v1/barters/${code}/culture`)
        .set('Authorization', consultor)
        .send({ grainId: 2 });

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('já foi encaminhada');
    });

    /**
     * AS DUAS CONVIVEM NO MESMO PRODUTOR, e é isto que a safra por grão
     * impedia: soja no verão e milho safrinha, no mesmo cliente, na mesma
     * gestão, cada uma com o seu vencimento de cédula.
     */
    it('o mesmo produtor fecha uma permuta de cada cultura na mesma gestão', async () => {
      const soja = (await registrarEEncaminhar(JOAO, validPayload)).body.data;
      const milho = (await registrarEEncaminhar(JOAO, emMilho)).body.data;

      // A MESMA gestão, o MESMO produtor, duas culturas. Antes isto exigia duas
      // safras abertas — e a pergunta "por quanto se permuta agora?" passava a
      // ter duas respostas.
      expect(soja.versionCode).toBe(milho.versionCode);
      expect(soja.producerName).toBe(milho.producerName);

      const graoDe = (data: { items: { kind: string; productName: string }[] }) =>
        data.items.find((item) => item.kind === 'grain')!.productName;
      expect([graoDe(soja), graoDe(milho)]).toEqual(['Soja', 'Milho']);
    });
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

    /**
     * O REGIME É DO PRODUTOR, e a permuta o herda sem perguntar: a opção pela
     * folha é feita uma vez, perante o fisco, e vale para todas as entregas
     * dele. Enquanto a pergunta era feita permuta a permuta, o consultor
     * respondia de memória — e a segunda permuta do mesmo produtor saía num
     * regime diferente da primeira sem nada ter mudado no mundo.
     */
    it('a permuta herda o regime do cadastro do produtor', async () => {
      // Cláudia Nunes (id 4, CPF, 80 ha) optou pela FOLHA no cadastro, e a
      // carteira dela é da Ana. Nada de `taxRegime` no corpo.
      const response = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', await asUser(ANA))
        .send({
          producerId: 4,
          unitId: UNIT.filial04,
          grainId: 1,
          inputs: [
            { productId: 5, quantity: 32 },
            { productId: 6, quantity: 200 },
            { productId: 7, quantity: 12 },
          ],
        });

      expect(response.status).toBe(201);
      expect(response.body.data.taxRegime).toBe('folha');
      // Sobra o Senar de CPF.
      expect(response.body.data.taxRate).toBe(0.2);
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
    expect((await encaminhar(response.body.data.code as string, await asUser(JOAO))).status).toBe(
      200,
    );
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
    // PRM-2026-004 já está aprovada no dataset. O motivo vai junto porque a
    // negativa não existe sem texto — e o que este caso prende é a ETAPA, que é
    // conferida depois de o corpo ser válido.
    const response = await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-004/review')
      .set('Authorization', await asUser(COMITE))
      .send({ status: 'denied', note: 'Mudamos de ideia depois de aprovada.' });
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

    it('a permuta encaminhada vai ao gerente do consultor, esperando o parecer', async () => {
      const created = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send(validPayload);

      expect(created.status).toBe(201);
      const code = created.body.data.code as string;

      // O DESTINATÁRIO é gravado no ENVIO, e o envio é o encaminhamento: no
      // rascunho ela ainda não é de gerente nenhum.
      expect(created.body.data.managerName).toBeNull();

      const enviada = await encaminhar(code, await asUser(JOAO));
      expect(enviada.status).toBe(200);
      // João é do time da Beatriz — e é para ela que a permuta vai, esteja a
      // retirada onde estiver.
      expect(enviada.body.data.managerName).toBe('Beatriz Nogueira');
      expect(enviada.body.data.managerNote).toBeNull();
      expect(enviada.body.data.consultantNote).toBe(PARECER_DO_CONSULTOR);
      expect(enviada.body.data.consultantSentAt).toBeTruthy();
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

      // A PRÓXIMA vai para o gerente novo — quem decide é o vínculo do momento
      // do ENCAMINHAMENTO, que é quando o envio acontece.
      const nova = await registrarEEncaminhar(JOAO);
      expect(nova.status).toBe(200);
      expect(nova.body.data.managerName).toBe('Gustavo Ramires');
    });

    /**
     * O cadastro exige gerente, e o gerente com time não é excluído: é assim
     * que nenhum consultor fica sem a quem encaminhar.
     *
     * A recusa é o que sustenta a única guarda do encaminhamento — sem ela, o
     * consultor mandaria uma permuta para ninguém, e ela ficaria em
     * `sentToManager` para sempre, sem erro e sem a quem cobrar.
     */
    it('gerente com time não é excluído: os consultores dele ficariam sem a quem encaminhar', async () => {
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
   * O RASCUNHO E O PARECER DO CONSULTOR — o começo da linha, que antes não
   * existia.
   *
   * O que estes casos prendem é a diferença entre REGISTRAR e ENCAMINHAR. Ela é
   * a razão de ser da etapa: montar a permuta e ter a conversa com o produtor
   * são dois momentos, e enquanto os dois eram um ato só, o que o consultor
   * sabia do cliente não chegava escrito a lugar nenhum.
   */
  describe('parecer do consultor e rascunho', () => {
    /** Registra e devolve o código do rascunho recém-criado. */
    const rascunho = async (email = JOAO) => {
      const criada = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', await asUser(email))
        .send(validPayload);
      expect(criada.status).toBe(201);
      return criada.body.data.code as string;
    };

    it('o parecer pode vir no registro, e a permuta ainda assim é rascunho', async () => {
      const criada = await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set('Authorization', await asUser(JOAO))
        .send({ ...validPayload, note: PARECER_DO_CONSULTOR });

      expect(criada.status).toBe(201);
      expect(criada.body.data.consultantNote).toBe(PARECER_DO_CONSULTOR);
      // Escrever o parecer NÃO encaminha: são dois atos, e o segundo é do
      // consultor também. Quem tem o texto na mão no dia do registro só precisa
      // dar mais um clique.
      expect(criada.body.data.status).toBe('draft');
      expect(criada.body.data.consultantSentAt).toBeNull();
    });

    it('o rascunho é salvo em partes, e o último texto é o que vale', async () => {
      const code = await rascunho();
      const joao = await asUser(JOAO);
      const salvar = (note: string) =>
        request(app.getHttpServer())
          .put(`/api/v1/barters/${code}/note`)
          .set('Authorization', joao)
          .send({ note });

      const meio = await salvar('Conversei com o produtor ontem,');
      expect(meio.status).toBe(200);
      expect(meio.body.data.consultantNote).toBe('Conversei com o produtor ontem,');
      // Salvar não move a permuta nem gera passo: é rascunho sendo editado pelo
      // próprio autor, e não um ato do fluxo.
      expect(meio.body.data.status).toBe('draft');
      expect(meio.body.data.events).toHaveLength(1);

      const inteiro = await salvar(PARECER_DO_CONSULTOR);
      expect(inteiro.body.data.consultantNote).toBe(PARECER_DO_CONSULTOR);

      // E encaminhar sem repetir o texto usa o que está salvo. (A cédula é o
      // outro pré-requisito, e vai antes — ela não é o assunto deste caso.)
      await fillCpr(app, joao, code);
      const enviada = await request(app.getHttpServer())
        .post(`/api/v1/barters/${code}/forward`)
        .set('Authorization', joao)
        .send({});
      expect(enviada.status).toBe(200);
      expect(enviada.body.data.status).toBe('sentToManager');
      expect(enviada.body.data.consultantNote).toBe(PARECER_DO_CONSULTOR);
    });

    /**
     * A CÉDULA É PRÉ-REQUISITO DO ENCAMINHAMENTO — o portão novo.
     *
     * Ela é coletada AGORA, com o produtor ainda por perto, e não semanas
     * depois: o emissor descobrindo que falta a matrícula de uma lavoura com a
     * permuta já faturada e o insumo já retirado é o caso que este portão existe
     * para não acontecer. O custo de voltar atrás cresce a cada posto, e o
     * encaminhamento é o último momento em que ele é zero.
     *
     * SÓ AS PENDÊNCIAS DO CONSULTOR são cobradas: a nota fiscal não existe antes
     * do faturamento, o vencimento é da safra e o número da cédula é do emissor.
     * Exigi-los aqui travaria a esteira num impossível — e é essa metade que o
     * segundo caso prova.
     */
    it('a cédula é pré-requisito do encaminhamento', async () => {
      const code = await rascunho();
      const joao = await asUser(JOAO);

      const semCedula = await request(app.getHttpServer())
        .post(`/api/v1/barters/${code}/forward`)
        .set('Authorization', joao)
        .send({ note: PARECER_DO_CONSULTOR });
      expect(semCedula.status).toBe(422);
      expect(semCedula.body.message).toContain('Preencha a cédula');
      // A frase NOMEIA o que falta, e conta o resto: uma parede com as vinte
      // pendências de uma cédula em branco vira "deu erro" na leitura.
      expect(semCedula.body.message).toContain('RG do emitente');
      expect(semCedula.body.message).toContain('e mais');

      // E ela CONTINUA rascunho: o ato não aconteceu.
      const parada = await request(app.getHttpServer())
        .get(`/api/v1/barters/${code}`)
        .set('Authorization', joao);
      expect(parada.body.data.status).toBe('draft');

      // A MESA DIZ A MESMA COISA, e é assim que a tela avisa ANTES do clique: o
      // que trava o encaminhamento sai em `consultantGaps`, e o que a recusa
      // nomeia veio de lá. Duas listas para a mesma cédula seria um aviso
      // prometendo o que a recusa desmente.
      const mesa = await request(app.getHttpServer())
        .get(`/api/v1/barters/${code}/cpr`)
        .set('Authorization', joao);
      expect(mesa.body.data.consultantGaps).toContain('RG do emitente');
      for (const pendencia of mesa.body.data.consultantGaps) {
        expect(mesa.body.data.gaps).toContain(pendencia);
      }

      await fillCpr(app, joao, code);
      const enviada = await request(app.getHttpServer())
        .post(`/api/v1/barters/${code}/forward`)
        .set('Authorization', joao)
        .send({ note: PARECER_DO_CONSULTOR });
      expect(enviada.status).toBe(200);
      expect(enviada.body.data.status).toBe('sentToManager');
    });

    /**
     * O PORTÃO COBRA SÓ O QUE É DO CONSULTOR.
     *
     * É a metade que impede a regra de virar um impossível: no encaminhamento
     * não existe nota fiscal (a permuta nem foi decidida), o vencimento é da
     * safra e o número da cédula só aparece na emissão. Se qualquer um deles
     * entrasse na conta, nenhuma permuta sairia do rascunho.
     */
    it('o encaminhamento não cobra o que é de outro posto', async () => {
      const code = await rascunho();
      const joao = await asUser(JOAO);
      await fillCpr(app, joao, code);

      // A cédula tem o que é do consultor, e MESMO ASSIM está incompleta para
      // emitir: faltam a nota e o número. Ela encaminha do mesmo jeito.
      const mesa = await request(app.getHttpServer())
        .get(`/api/v1/barters/${code}/cpr`)
        .set('Authorization', joao);
      expect(mesa.body.data.complete).toBe(false);
      expect(mesa.body.data.gaps.join(' ')).toContain('nota fiscal');
      expect(mesa.body.data.gaps.join(' ')).toContain('número da CPR');
      // E a lista DELE está vazia — é ela que a tela lê para ligar o botão de
      // encaminhar, e não `gaps`, que continua cheio do que é de outro posto.
      expect(mesa.body.data.consultantGaps).toEqual([]);

      const enviada = await request(app.getHttpServer())
        .post(`/api/v1/barters/${code}/forward`)
        .set('Authorization', joao)
        .send({ note: PARECER_DO_CONSULTOR });
      expect(enviada.status).toBe(200);
    });

    /**
     * ENCAMINHAR SEM PARECER não existe — é o mesmo motivo do parecer do
     * gerente: sem texto, o botão vira um "seguir" disfarçado e a peça que o
     * comitê mais precisa ler volta a viver no telefonema.
     */
    it('rascunho sem parecer não é encaminhado', async () => {
      const code = await rascunho();
      const joao = await asUser(JOAO);

      const vazio = await request(app.getHttpServer())
        .post(`/api/v1/barters/${code}/forward`)
        .set('Authorization', joao)
        .send({});
      expect(vazio.status).toBe(422);
      expect(vazio.body.message).toContain('parecer');

      const curto = await request(app.getHttpServer())
        .post(`/api/v1/barters/${code}/forward`)
        .set('Authorization', joao)
        .send({ note: 'ok' });
      expect(curto.status).toBe(422);

      // E ela continua rascunho, com o texto insuficiente NÃO gravado: o ato não
      // aconteceu, então não deixou rastro.
      const depois = await request(app.getHttpServer())
        .get(`/api/v1/barters/${code}`)
        .set('Authorization', joao);
      expect(depois.body.data.status).toBe('draft');
      expect(depois.body.data.consultantNote).toBeNull();
    });

    it('rascunho é do dono: nem a retaguarda nem outro consultor o alcançam', async () => {
      const code = await rascunho();

      for (const quem of [ADMIN, COMITE, GERENTE, FATURISTA, ANA]) {
        const resposta = await request(app.getHttpServer())
          .get(`/api/v1/barters/${code}`)
          .set('Authorization', await asUser(quem));
        expect(resposta.status).toBe(403);
      }

      // E ninguém escreve o parecer de outro: a rota é do consultor, e o escopo
      // decide de qual permuta.
      await request(app.getHttpServer())
        .put(`/api/v1/barters/${code}/note`)
        .set('Authorization', await asUser(ANA))
        .send({ note: 'Parecer escrito por quem não registrou.' })
        .expect(403);
    });

    /** Encaminhada uma vez, não se reescreve o parecer nem se reencaminha. */
    it('depois de encaminhada, o parecer do consultor fecha', async () => {
      const code = await rascunho();
      const joao = await asUser(JOAO);
      expect((await encaminhar(code, joao)).status).toBe(200);

      const reescrita = await request(app.getHttpServer())
        .put(`/api/v1/barters/${code}/note`)
        .set('Authorization', joao)
        .send({ note: 'Pensando melhor, o produtor tem uma pendência.' });
      expect(reescrita.status).toBe(422);
      expect(reescrita.body.message).toContain('já foi encaminhada');

      const denovo = await encaminhar(code, joao);
      expect(denovo.status).toBe(422);
      expect(denovo.body.message).toContain('já foi encaminhada');
    });

    /**
     * O GERENTE lê o parecer do consultor antes de escrever o dele — é a peça
     * que a etapa nova põe na mesa dele, e ela chega junto com a permuta.
     */
    it('o parecer do consultor chega inteiro ao gerente e ao comitê', async () => {
      const enviada = await registrarEEncaminhar(JOAO);
      const code = enviada.body.data.code as string;

      const noGerente = await request(app.getHttpServer())
        .get(`/api/v1/barters/${code}`)
        .set('Authorization', await asUser(GERENTE));
      expect(noGerente.body.data.consultantNote).toBe(PARECER_DO_CONSULTOR);

      await request(app.getHttpServer())
        .post(`/api/v1/barters/${code}/opinion`)
        .set('Authorization', await asUser(GERENTE))
        .send({ note: 'De acordo com o consultor: cliente sem pendência.' })
        .expect(200);

      // O parecer do consultor NÃO é sobrescrito pelo do gerente: são dois
      // textos, de duas pessoas, e o comitê lê os dois.
      const noComitê = await request(app.getHttpServer())
        .get(`/api/v1/barters/${code}`)
        .set('Authorization', await asUser(COMITE));
      expect(noComitê.body.data.consultantNote).toBe(PARECER_DO_CONSULTOR);
      expect(noComitê.body.data.managerNote).toContain('De acordo com o consultor');
    });
  });

  /**
   * O INVESTIMENTO POR HECTARE (sc/ha) — a régua que compara permutas de
   * tamanhos diferentes.
   */
  describe('investimento por hectare', () => {
    const permutaDe = async (code: string, email: string) => {
      const response = await request(app.getHttpServer())
        .get(`/api/v1/barters/${code}`)
        .set('Authorization', await asUser(email));
      expect(response.status).toBe(200);
      return response.body.data as {
        sacksPerHa?: number | null;
        producerAreaHa?: number;
        items: { kind: string; quantity: number }[];
      };
    };

    it('o número é as sacas da permuta divididas pela área congelada', async () => {
      // PRM-2026-001: 251,4142 sacas para os 120 ha do Antônio.
      const barter = await permutaDe('PRM-2026-001', COMITE);
      expect(barter.producerAreaHa).toBe(120);
      expect(barter.sacksPerHa).toBeCloseTo(251.4142 / 120, 6);
    });

    /**
     * A ÁREA é SNAPSHOT: mudar o cadastro do produtor não mexe no que já foi
     * decidido. Sem isso, quem aprovou 2,1 sc/ha veria 1,4 no dia da auditoria,
     * sem ninguém ter tocado na permuta.
     */
    it('mudar a área do produtor não reescreve o investimento das permutas dele', async () => {
      const antes = await permutaDe('PRM-2026-001', COMITE);

      await request(app.getHttpServer())
        .put('/api/v1/producers/1')
        .set('Authorization', await asUser(ADMIN))
        .send({
          name: 'Antônio Carvalho',
          document: 'CPF 123.456.789-00',
          farmName: 'Fazenda Boa Vista',
          city: 'Maringá/PR',
          // Área MENOR, e de propósito: os mínimos por hectare caem junto, e o
          // mesmo payload continua válido para a permuta seguinte.
          areaHa: 60,
          consultantIds: [2],
        })
        .expect(200);

      const depois = await permutaDe('PRM-2026-001', COMITE);
      expect(depois.producerAreaHa).toBe(120);
      expect(depois.sacksPerHa).toBe(antes.sacksPerHa);

      // A PRÓXIMA permuta é que nasce com a área nova.
      const nova = await registrarEEncaminhar(JOAO);
      expect(nova.status).toBe(200);
      const doAdmin = await permutaDe(nova.body.data.code as string, ADMIN);
      expect(doAdmin.producerAreaHa).toBe(60);
    });

    /**
     * Ele vai para QUEM COMPARA, e some para os outros dois. Não é sigilo: para
     * o consultor e para o gerente a permuta é UMA, e uma régua de comparação
     * sem com quem comparar é ruído na tela. Ver `barters.investmentPerHa`.
     */
    it('some para o consultor e para o gerente, e aparece para os três que comparam', async () => {
      for (const quem of [ADMIN, COMITE, FATURISTA]) {
        const barter = await permutaDe('PRM-2026-001', quem);
        expect(barter.sacksPerHa).toBeGreaterThan(0);
      }

      for (const quem of [JOAO, GERENTE]) {
        const barter = await permutaDe('PRM-2026-001', quem);
        expect(barter.sacksPerHa).toBeUndefined();
        expect(barter.producerAreaHa).toBeUndefined();
      }
    });

    /**
     * Permuta anterior ao campo de área devolve `null` — e não zero. Zero seria
     * um investimento por hectare de zero, que é uma afirmação, e falsa.
     */
    it('sem área registrada, o número não é inventado', async () => {
      // Área zerada não se cria pelo cadastro (o admin não consegue salvar
      // uma), e é justamente por isso que ela existe só no HISTÓRICO: as
      // permutas anteriores ao campo, que a migration não teve de onde
      // preencher. Aqui ela é escrita direto no banco, que é como elas estão.
      await app.get(PrismaService).barter.update({
        where: { code: 'PRM-2026-001' },
        data: { producerAreaHa: 0 },
      });

      const antiga = await permutaDe('PRM-2026-001', COMITE);
      expect(antiga.producerAreaHa).toBe(0);
      // `null`, e não zero: zero seria um investimento por hectare de zero, que
      // é uma afirmação, e falsa.
      expect(antiga.sacksPerHa).toBeNull();
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
     * A TERCEIRA SAÍDA: aprovar COM RESSALVA.
     *
     * Ela é um estado próprio, e não uma observação dentro da aprovação, porque
     * a ressalva é uma CONDIÇÃO do negócio — garantia real, seguro, aval — e
     * quem a cumpre não é quem a escreveu. Escondida dentro de `approved`, a
     * lista e o cartão diriam "Aprovada, a faturar" sobre uma permuta que
     * depende de alguém providenciar um aval.
     */
    it('aprovar com ressalva é um desfecho próprio, e ele exige o texto da exigência', async () => {
      const comitê = await asUser(COMITE);
      const ressalva =
        'Exigir garantia real sobre a matrícula 12.345 e seguro agrícola da área antes da retirada.';

      // Sem o texto, a decisão não passa: a exigência é o conteúdo do ato.
      const muda = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/review')
        .set('Authorization', comitê)
        .send({ status: 'approvedWithConditions' });
      expect(muda.status).toBe(422);
      expect(JSON.stringify(muda.body.message)).toContain('motivo da decisão');

      const decisão = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/review')
        .set('Authorization', comitê)
        .send({ status: 'approvedWithConditions', note: ressalva });
      expect(decisão.status).toBe(200);
      expect(decisão.body.data.status).toBe('approvedWithConditions');
      expect(decisão.body.data.statusLabel).toBe('Aprovada com ressalva, a faturar');
      expect(decisão.body.data.reviewNote).toBe(ressalva);
      // Ela é a fila do FATURISTA, como a aprovação limpa: a ressalva é
      // condição do negócio, não um portão deste fluxo.
      expect(decisão.body.data.waitingFor).toBe('biller');
      expect(decisão.body.data.nextAction).toBe('invoice');

      // E o andamento diz COMO a etapa terminou, com as três palavras
      // distinguíveis entre si.
      const passoDaDecisão = (
        decisão.body.data.steps as { action: string; outcomeLabel: string }[]
      ).find((step) => step.action === 'review');
      expect(passoDaDecisão?.outcomeLabel).toBe('Aprovada com ressalva');

      // O faturista a alcança, anexa a nota e a fatura.
      const faturista = await asUser(FATURISTA);
      await attachInvoice(app, faturista, 'PRM-2026-002');
      const faturada = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/invoice')
        .set('Authorization', faturista)
        .send({});
      expect(faturada.status).toBe(200);
      expect(faturada.body.data.status).toBe('invoiced');
      // A ressalva continua legível depois de faturada: ela é a condição que
      // alguém precisa ter cumprido.
      expect(faturada.body.data.reviewNote).toBe(ressalva);
    });

    /**
     * NEGAR também exige texto, e pelo mesmo motivo: é a resposta que o
     * consultor vai levar ao produtor. "Porque sim" manda a pessoa perguntar por
     * telefone — e a resposta não fica no registro.
     */
    it('negar sem dizer por quê não é decidir', async () => {
      const comitê = await asUser(COMITE);
      const muda = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/review')
        .set('Authorization', comitê)
        .send({ status: 'denied' });
      expect(muda.status).toBe(422);

      const curta = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/review')
        .set('Authorization', comitê)
        .send({ status: 'denied', note: 'não' });
      expect(curta.status).toBe(422);

      // A APROVAÇÃO LIMPA, essa segue sem texto: ela não tem o que explicar, e
      // exigi-lo produziria quinhentos "ok" no histórico.
      const aprovada = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/review')
        .set('Authorization', comitê)
        .send({ status: 'approved' });
      expect(aprovada.status).toBe(200);
      expect(aprovada.body.data.reviewNote).toBeNull();
    });

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

    it('a permuta aprovada é faturada pelo faturista, e aí ela passa ao emissor', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/review')
        .set('Authorization', await asUser(COMITE))
        .send({ status: 'approved' })
        .expect(200);

      const faturista = await asUser(FATURISTA);

      // SEM NOTA NÃO SE FATURA. A trava é nova, e ela existe porque a cédula
      // cita a nota como origem da dívida: uma permuta "faturada" sem nota
      // nenhuma é um faturamento que não aconteceu, ou que não deixou prova — e
      // as duas coisas só apareceriam dias depois, na mesa do emissor.
      const semNota = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/invoice')
        .set('Authorization', faturista)
        .send({ note: 'Nota emitida em 12/05.' });
      expect(semNota.status).toBe(422);
      expect(semNota.body.message).toContain('nota fiscal');

      const anexo = await attachInvoice(app, faturista, 'PRM-2026-002');
      expect(anexo.status).toBe(200);
      expect(anexo.body.data.invoices).toHaveLength(1);
      expect(anexo.body.data.invoices[0].number).toBe('55.318');
      expect(anexo.body.data.invoices[0].file.fileName).toBe('nota.pdf');

      const faturada = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/invoice')
        .set('Authorization', faturista)
        .send({ note: 'Nota emitida em 12/05.' });

      expect(faturada.status).toBe(200);
      expect(faturada.body.data.status).toBe('invoiced');
      expect(faturada.body.data.invoicedBy).toBe('Patrícia Lemos');
      expect(faturada.body.data.invoicedAt).toBeTruthy();
      expect(faturada.body.data.invoiceNote).toBe('Nota emitida em 12/05.');
      // NÃO é mais fim de linha: a permuta faturada ainda deve o título, e
      // quem está com ela agora é o EMISSOR. Era aqui que o fluxo antigo
      // afirmava que o trabalho tinha acabado.
      expect(faturada.body.data.waitingFor).toBe('emitter');
      expect(faturada.body.data.nextAction).toBe('cprIssue');
      expect(faturada.body.data.statusLabel).toBe('Faturada, a emitir a CPR');

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
        // Duas aprovadas limpas e uma COM RESSALVA: são estados diferentes, e é
        // por isso que a ressalva não se esconde dentro de "approved". A fila de
        // trabalho do faturista é a soma das duas — ver `lineFrom(invoice)`.
        [FATURISTA, 'approved', 2],
        [FATURISTA, 'approvedWithConditions', 1],
        [COMITE, 'pending', 1],
        [FATURISTA, 'invoiced', 1],
        // O RASCUNHO só aparece para quem o escreveu.
        [JOAO, 'draft', 1],
        [COMITE, 'draft', 0],
      ];

      for (const [email, status, quantas] of filas) {
        const response = await request(app.getHttpServer())
          .get(`/api/v1/barters?status=${status}`)
          .set('Authorization', await asUser(email));
        expect(response.status).toBe(200);
        expect(response.body.data).toHaveLength(quantas);
      }
    });

    /**
     * O FILTRO É RECORTE, NUNCA PERMISSÃO — e o caso do faturista é o que prova.
     *
     * O escopo dele é UM campo (`status`), e o filtro da listagem fala do mesmo
     * campo. Enquanto os dois eram mesclados num objeto só, o segundo apagava o
     * primeiro: `?status=pending` devolvia a mesa do comitê a quem só emite a
     * nota, e `?status=draft` devolvia o rascunho de um consultor — a permuta
     * que ainda não foi proposta a ninguém. Não era a fila errada na tela; era o
     * JSON inteiro, com valores e pareceres, para quem o recorte existe para
     * proteger.
     *
     * A pergunta do teste é a que importa: pedir um estado FORA do escopo
     * devolve vazio, e não o estado.
     */
    it('o filtro de status não abre o escopo de quem só enxerga um trecho', async () => {
      const faturista = await asUser(FATURISTA);

      for (const status of ['sentToManager', 'pending', 'denied', 'draft']) {
        const response = await request(app.getHttpServer())
          .get(`/api/v1/barters?status=${status}`)
          .set('Authorization', faturista);
        expect([status, response.status]).toEqual([status, 200]);
        expect([status, response.body.data]).toEqual([status, []]);
      }

      // E o recorte dele continua inteiro: o filtro estreita o que o escopo já
      // permitia, que é para o que ele serve.
      const dele = await request(app.getHttpServer())
        .get('/api/v1/barters?status=approved')
        .set('Authorization', faturista);
      expect(dele.body.data).toHaveLength(2);
    });

    /**
     * O MESMO, pelo outro campo: o escopo do gerente é `managerId`, e a
     * listagem tem um filtro com esse nome.
     *
     * `?managerId=` existe para o comitê e o admin recortarem a operação por
     * time. Na mão do gerente ele apagava o recorte dele: bastava o id do
     * colega para ler o time inteiro do outro, pareceres técnicos inclusive.
     */
    it('o filtro de gerente não dá a um gerente o time do outro', async () => {
      const gustavo = await asUser(GERENTE_SUL);

      const doColega = await request(app.getHttpServer())
        .get(`/api/v1/barters?managerId=${MANAGER.beatriz}`)
        .set('Authorization', gustavo);
      expect(doColega.status).toBe(200);
      expect(doColega.body.data).toEqual([]);

      // O dele continua respondendo — inclusive pedindo o próprio id.
      const dele = await request(app.getHttpServer())
        .get(`/api/v1/barters?managerId=${MANAGER.gustavo}`)
        .set('Authorization', gustavo);
      const semFiltro = await request(app.getHttpServer())
        .get('/api/v1/barters')
        .set('Authorization', gustavo);
      expect(dele.body.data).toHaveLength(semFiltro.body.data.length);
      expect(dele.body.data.length).toBeGreaterThan(0);
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
        ['register', null, 'draft'],
        ['forward', 'draft', 'sentToManager'],
        ['opinion', 'sentToManager', 'pending'],
        ['review', 'pending', 'approved'],
        ['invoice', 'approved', 'invoiced'],
      ]);
      expect(events.map((e) => e.actorRole)).toEqual([
        'consultant',
        // O ENCAMINHAMENTO é do mesmo consultor: os dois primeiros passos são
        // dele, e é isso que a etapa nova acrescentou ao começo da linha.
        'consultant',
        'manager',
        'committee',
        'biller',
      ]);
      expect(events.map((e) => e.actorName)).toEqual([
        'João Silva',
        'João Silva',
        'Beatriz Nogueira',
        'Comitê de Permutas',
        'Patrícia Lemos',
      ]);
      // O texto de cada etapa fica no evento, e não só no campo da permuta —
      // que é sobrescrito.
      expect(events[1].note).toContain('Cliente de cinco safras');
      expect(events[2].note).toContain('Volume compatível');
      expect(events[4].note).toContain('nota única');
      expect(events[0].actorRoleLabel).toBe('Consultor');
    });

    it('cada ato acrescenta um passo, e nenhum apaga o anterior', async () => {
      const antes = await request(app.getHttpServer())
        .get('/api/v1/barters/PRM-2026-002')
        .set('Authorization', await asUser(COMITE));
      // Registro, encaminhamento e parecer do gerente: três passos antes da
      // decisão.
      expect(antes.body.data.events).toHaveLength(3);

      const decisão = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/review')
        .set('Authorization', await asUser(COMITE))
        .send({ status: 'denied', note: 'Fora da política de risco desta safra.' });
      expect(decisão.status).toBe(200);

      // A RESPOSTA DO ATO já traz o passo que ele acabou de criar. Sem isso, a
      // tela que agiu ficaria com uma permuta sem histórico na mão, e a linha do
      // tempo sumiria no instante seguinte ao clique.
      expect(decisão.body.data.events).toHaveLength(4);

      const depois = await request(app.getHttpServer())
        .get('/api/v1/barters/PRM-2026-002')
        .set('Authorization', await asUser(COMITE));
      const events = depois.body.data.events;
      expect(events).toHaveLength(4);
      expect(events[3]).toMatchObject({
        action: 'review',
        fromStatus: 'pending',
        toStatus: 'denied',
        actorName: 'Comitê de Permutas',
        note: 'Fora da política de risco desta safra.',
      });
      // O parecer do gerente continua lá, intacto.
      expect(events[2].action).toBe('opinion');
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
        toStatus: 'draft',
        actorName: 'João Silva',
      });

      // O ENCAMINHAMENTO é o segundo passo, e leva o parecer do consultor junto:
      // o texto fica no evento, congelado, mesmo que o campo da permuta venha a
      // ser reescrito.
      const enviada = await encaminhar(created.body.data.code as string, await asUser(JOAO));
      expect(enviada.body.data.events).toHaveLength(2);
      expect(enviada.body.data.events[1]).toMatchObject({
        action: 'forward',
        fromStatus: 'draft',
        toStatus: 'sentToManager',
        actorName: 'João Silva',
        note: PARECER_DO_CONSULTOR,
      });
    });

    /** O consultor acompanha o andamento da PRÓPRIA permuta pelo mesmo caminho. */
    it('o consultor enxerga a linha do tempo da permuta dele', async () => {
      const response = await request(app.getHttpServer())
        .get('/api/v1/barters/PRM-2026-005')
        .set('Authorization', await asUser(JOAO));
      expect(response.status).toBe(200);
      // Os dois passos dele: registrou e encaminhou.
      expect(response.body.data.events.map((e: { action: string }) => e.action)).toEqual([
        'register',
        'forward',
      ]);
      expect(response.body.data.waitingFor).toBe('manager');
    });
  });

  /**
   * O ANDAMENTO — a esteira inteira dentro da permuta, com o que já aconteceu
   * preenchido.
   *
   * É o que separa uma CHECKLIST de uma linha do tempo, e é a pergunta que os
   * eventos sozinhos não respondem: uma permuta parada no comitê tem dois
   * eventos e nada neles diz que faltam duas etapas, nem com quem elas estão. O
   * consultor precisa dessa resposta porque é ela que ele repassa ao produtor.
   */
  describe('andamento da permuta', () => {
    type Step = {
      action: string;
      state: string;
      label: string;
      role: string | null;
      roleLabel: string | null;
      stateNote: string | null;
      actorName: string | null;
      note: string | null;
      outcomeLabel: string | null;
      at: string | null;
    };

    const stepsOf = async (code: string, user: string) => {
      const response = await request(app.getHttpServer())
        .get(`/api/v1/barters/${code}`)
        .set('Authorization', await asUser(user));
      expect(response.status).toBe(200);
      return response.body.data.steps as Step[];
    };

    it('a permuta recém-enviada já mostra as OITO etapas, e quem falta', async () => {
      // PRM-2026-005 está na mesa do gerente: dois eventos, oito etapas.
      const steps = await stepsOf('PRM-2026-005', JOAO);

      expect(steps.map((s) => [s.action, s.state])).toEqual([
        ['register', 'done'],
        ['forward', 'done'],
        ['opinion', 'current'],
        ['review', 'ahead'],
        ['invoice', 'ahead'],
        // O TRECHO DA CÉDULA aparece desde o primeiro dia, e é a diferença
        // entre uma checklist e uma linha do tempo: a emissão do título não
        // surge do nada depois do faturamento — ela estava prevista o tempo
        // todo, e o consultor pode dizer isso ao produtor.
        ['cprIssue', 'ahead'],
        ['cprSign', 'ahead'],
        ['cprRegister', 'ahead'],
      ]);
      expect(steps.map((s) => s.label)).toEqual([
        'Registro do consultor',
        'Parecer do consultor',
        'Parecer do gerente',
        'Decisão do comitê',
        'Faturamento',
        'Emissão da CPR',
        'Coleta de assinaturas',
        'Registro da CPR',
      ]);

      // A etapa cumprida vem ASSINADA (do evento); as que ainda vêm, não têm
      // autor — têm o papel de quem vai cumpri-las, que é o que a tela mostra.
      expect(steps[0].actorName).toBe('João Silva');
      expect(steps[0].at).not.toBeNull();
      expect(steps[1].actorName).toBe('João Silva');
      expect(steps[3].actorName).toBeNull();
      expect(steps[3].roleLabel).toBe('Comitê');
      expect(steps[4].roleLabel).toBe('Faturista');
      expect(steps[5].roleLabel).toBe('Emissor');

      // E a etapa de agora diz o que espera, com o nome de quem está com ela.
      expect(steps[2].stateNote).toBe('Esta permuta aguarda o parecer do gerente Beatriz Nogueira');
      expect(steps.filter((s) => s.stateNote !== null)).toHaveLength(1);
    });

    it('a permuta faturada ainda DEVE a cédula — e o andamento diz isso', async () => {
      const steps = await stepsOf('PRM-2026-001', FATURISTA);

      // Cinco cumpridas e TRÊS pela frente. Era aqui que a esteira antiga
      // mentia: ela mostrava cinco `done` e dava a permuta por concluída, com o
      // título que formaliza a entrega ainda por emitir.
      expect(steps.map((s) => s.state)).toEqual([
        'done',
        'done',
        'done',
        'done',
        'done',
        'current',
        'ahead',
        'ahead',
      ]);
      expect(steps.slice(0, 5).every((s) => s.actorName !== null)).toBe(true);
      // O texto de cada etapa vem do EVENTO, que não é sobrescrito pela etapa
      // seguinte — é o que os postos seguintes leem das etapas anteriores.
      expect(steps[1].note).toContain('Cliente de cinco safras');
      expect(steps[2].note).toContain('Volume compatível');
      // A decisão diz para que lado foi, e continua dizendo depois do
      // faturamento: a permuta está em `invoiced`, e a decisão foi "Aprovada".
      expect(steps[3].outcomeLabel).toBe('Aprovada');
      expect(steps[4].outcomeLabel).toBeNull();
      // E a etapa de agora diz com quem ela está.
      expect(steps[5].stateNote).toBe('Esta permuta aguarda a emissão da cédula');
      expect(steps[5].roleLabel).toBe('Emissor');
    });

    /**
     * NEGADA é fim de linha, e o andamento não promete um faturamento que não
     * vem. `halted` existe por causa deste caso: como `ahead`, ele deixaria a
     * tela dizendo que a permuta ainda vai ser faturada.
     */
    it('a permuta negada não fica devendo um faturamento', async () => {
      const decisão = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/review')
        .set('Authorization', await asUser(COMITE))
        .send({ status: 'denied', note: 'Fora da política de risco desta safra.' });
      expect(decisão.status).toBe(200);

      // A RESPOSTA DO ATO já traz o andamento novo — a tela que acabou de negar
      // não pode continuar mostrando a permuta esperando decisão.
      const steps = decisão.body.data.steps as Step[];
      expect(steps.map((s) => s.state)).toEqual([
        'done',
        'done',
        'done',
        'done',
        'halted',
        'halted',
        'halted',
        'halted',
      ]);
      expect(steps[3].outcomeLabel).toBe('Negada');
      expect(steps[3].note).toBe('Fora da política de risco desta safra.');
      // E as etapas que não vêm DIZEM que não vêm, em vez de ficar mudas —
      // mudas, elas se leriam como "ainda falta faturar e emitir a cédula".
      expect(steps[4].stateNote).toBe('Não acontece: a permuta foi negada');
      expect(steps[7].stateNote).toBe('Não acontece: a permuta foi negada');
      expect(steps[4].actorName).toBeNull();
    });

    /** Mesma regra dos eventos, pela mesma razão: listagem mostra estado. */
    it('a listagem não carrega o andamento de cada permuta', async () => {
      const response = await request(app.getHttpServer())
        .get('/api/v1/barters')
        .set('Authorization', await asUser(FATURISTA));
      expect(response.body.data[0].steps).toBeUndefined();
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
      const response = await registrarEEncaminhar(JOAO, {
        ...validPayload,
        unitId: UNIT.filial34,
      });
      expect(response.status).toBe(200);
      expect(response.body.data.unitName).toBe('Filial 34 (Gran. Jari)');
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

  /**
   * O DESVIO da esteira: o consultor pede alteração, o admin decide.
   *
   * É o único caminho de volta que a permuta tem, e o que estes casos protegem
   * é o preço dele: liberar apaga o parecer do gerente e a decisão do comitê.
   * Ver `barters/change-request.ts`.
   */
  describe('pedido de alteração', () => {
    const pedir = async (
      code: string,
      email: string,
      note = 'O produtor trocou o fungicida pelo inseticida na véspera da retirada.',
    ) =>
      request(app.getHttpServer())
        .post(`/api/v1/barters/${code}/change-request`)
        .set('Authorization', await asUser(email))
        .send({ note });

    const decidir = async (code: string, email: string, body: object) =>
      request(app.getHttpServer())
        .post(`/api/v1/barters/${code}/change-request/decision`)
        .set('Authorization', await asUser(email))
        .send(body);

    /**
     * O pedido NÃO move a permuta: ela continua na fila em que estava, com uma
     * bandeira. Devolvê-la na hora tiraria da mesa de terceiros um trabalho que
     * o admin ainda pode dizer que não precisa ser desfeito.
     */
    it('o pedido pendura a bandeira sem tirar a permuta da fila', async () => {
      // PRM-2026-005 é do João e está na mesa da Beatriz.
      const response = await pedir('PRM-2026-005', JOAO);

      expect(response.status).toBe(200);
      expect(response.body.data.status).toBe('sentToManager');
      expect(response.body.data.changeRequestStatus).toBe('open');
      expect(response.body.data.changeRequestBy).toBe('João Silva');
      expect(response.body.data.changeRequestFrom).toBe('sentToManager');
      expect(response.body.data.changeRequestNote).toContain('fungicida');
    });

    /** Quem tem a permuta na mesa PRECISA ver o pedido — é trabalho dele que está em jogo. */
    it('o gerente enxerga o pedido feito sobre a permuta que está com ele', async () => {
      await pedir('PRM-2026-005', JOAO);
      const response = await request(app.getHttpServer())
        .get('/api/v1/barters/PRM-2026-005')
        .set('Authorization', await asUser(GERENTE));

      expect(response.body.data.changeRequestStatus).toBe('open');
    });

    it('a liberação devolve a permuta ao rascunho e apaga parecer e decisão', async () => {
      // PRM-2026-004 é da Ana, já aprovada pelo comitê.
      await pedir('PRM-2026-004', ANA);
      const response = await decidir('PRM-2026-004', ADMIN, { accept: true });

      expect(response.status).toBe(200);
      expect(response.body.data.status).toBe('draft');
      expect(response.body.data.managerNote).toBeNull();
      expect(response.body.data.reviewedBy).toBeNull();
      expect(response.body.data.reviewNote).toBeNull();
      // O pedido atendido some: quem conta a história agora é o status.
      expect(response.body.data.changeRequestStatus).toBeNull();
      // O parecer do CONSULTOR fica: ele vai reencaminhar a permuta.
      expect(response.body.data.consultantNote).toContain('Área pequena');
      // E a história continua inteira na linha do tempo.
      const acoes = response.body.data.events.map((e: { action: string }) => e.action);
      expect(acoes).toContain('opinion');
      expect(acoes).toContain('review');
      expect(acoes).toContain('changeRequested');
      expect(acoes).toContain('changeAccepted');
    });

    /** Liberada, ela recomeça a esteira: passa pelo gerente e pelo comitê de novo. */
    it('a permuta liberada é remontada e reencaminhada pelo consultor', async () => {
      await pedir('PRM-2026-004', ANA);
      await decidir('PRM-2026-004', ADMIN, { accept: true });

      const asAna = await asUser(ANA);
      // Cláudia Nunes tem 80 ha: 32 NPK, 200 glifosato, 12 lambda são os mínimos.
      const alterada = await request(app.getHttpServer())
        .put('/api/v1/barters/PRM-2026-004/inputs')
        .set('Authorization', asAna)
        .send({
          inputs: [
            { productId: 5, quantity: 32 },
            { productId: 6, quantity: 200 },
            { productId: 7, quantity: 12 },
          ],
        });

      expect(alterada.status).toBe(200);
      const insumos = alterada.body.data.items.filter(
        (item: { kind: string }) => item.kind === 'input',
      );
      expect(insumos).toHaveLength(3);
      // 32×115 + 200×18,9 + 12×42 = R$ 7.964,00 → 53,6296 sacas de soja.
      const grao = alterada.body.data.items.find((item: { kind: string }) => item.kind === 'grain');
      expect(grao.quantity).toBeCloseTo(53.6296, 3);

      const reenviada = await encaminhar('PRM-2026-004', asAna, 'Permuta refeita com o produtor.');
      expect(reenviada.status).toBe(200);
      expect(reenviada.body.data.status).toBe('sentToManager');
    });

    it('a recusa mantém a permuta onde estava e devolve o motivo', async () => {
      await pedir('PRM-2026-004', ANA);
      const response = await decidir('PRM-2026-004', ADMIN, {
        accept: false,
        note: 'A retirada já foi separada no depósito — refaça na próxima permuta.',
      });

      expect(response.status).toBe(200);
      expect(response.body.data.status).toBe('approved');
      expect(response.body.data.changeRequestStatus).toBe('denied');
      expect(response.body.data.changeRequestReply).toContain('depósito');
      // O que a decisão do comitê escreveu continua lá: nada foi desfeito.
      expect(response.body.data.reviewedBy).toBe('Comitê de Permutas');
    });

    it('a recusa sem motivo é recusada', async () => {
      await pedir('PRM-2026-004', ANA);
      const response = await decidir('PRM-2026-004', ADMIN, { accept: false });
      expect(response.status).toBe(422);
      expect(response.body.message).toContain('motivo');
    });

    it('não se pede duas vezes antes de o admin responder', async () => {
      await pedir('PRM-2026-005', JOAO);
      const segundo = await pedir('PRM-2026-005', JOAO);
      expect(segundo.status).toBe(422);
      expect(segundo.body.message).toContain('Já existe');
    });

    it('a faturada não aceita pedido', async () => {
      // PRM-2026-001 é do João e é a única já faturada.
      const response = await pedir('PRM-2026-001', JOAO);
      expect(response.status).toBe(422);
      expect(response.body.message).toContain('faturada');
    });

    it('o pedido é de quem registrou: outro consultor nem enxerga a permuta', async () => {
      const response = await pedir('PRM-2026-005', ANA);
      expect(response.status).toBe(403);
    });

    /**
     * Quem decide é o ADMIN. O comitê decide o negócio e o gerente opina sobre
     * ele — nenhum dos dois administra a linha.
     */
    it('nem o comitê nem o gerente decidem o pedido', async () => {
      await pedir('PRM-2026-004', ANA);
      for (const quem of [COMITE, GERENTE, FATURISTA, ANA]) {
        const response = await decidir('PRM-2026-004', quem, { accept: true });
        expect(response.status).toBe(403);
      }
    });

    it('sem pedido em aberto não há o que decidir', async () => {
      const response = await decidir('PRM-2026-004', ADMIN, { accept: true });
      expect(response.status).toBe(422);
      expect(response.body.message).toContain('não tem pedido');
    });

    /**
     * A ALTERAÇÃO ATRAVESSA VERSÕES, enquanto o lançamento aberto ACEITAR a
     * cultura da permuta.
     *
     * A permuta paga em soja continua alterável quando a gestão seguinte já está
     * no ar: ela não foi faturada, e o que falta nela é uma correção de insumos.
     * Amarrá-la à versão vigente faria de cada publicação de tabela um prazo de
     * validade para as permutas em aberto.
     */
    it('a permuta de uma gestão anterior continua alterável', async () => {
      // A B2026.03 entra no ar, ainda com soja; a PRM-2026-005 continua sendo da
      // B2026.02.
      const publicada = await request(app.getHttpServer())
        .post('/api/v1/seasons/B2026/versions')
        .set('Authorization', await asUser(ADMIN))
        .send({
          grains: [{ grainId: 1, price: 150, estimatedYield: 60 }],
          prices: [
            { productId: 5, price: 120 },
            { productId: 6, price: 18.9 },
            { productId: 7, price: 42 },
          ],
        });
      expect(publicada.status).toBe(201);

      const pedido = await pedir('PRM-2026-005', JOAO);
      expect(pedido.status).toBe(200);
      expect(pedido.body.data.versionCode).toBe('B2026.02');

      const liberado = await decidir('PRM-2026-005', ADMIN, { accept: true });
      expect(liberado.body.data.status).toBe('draft');

      // E a remontagem é precificada pela tabela DA PERMUTA (NPK a 115, da
      // B2026.02), não pela que acabou de entrar (NPK a 120): o acordo foi
      // fechado naquela gestão, e publicar a seguinte não o reescreve.
      const alterada = await request(app.getHttpServer())
        .put('/api/v1/barters/PRM-2026-005/inputs')
        .set('Authorization', await asUser(JOAO))
        .send({
          inputs: [
            { productId: 5, quantity: 24 },
            { productId: 6, quantity: 150 },
            { productId: 7, quantity: 9 },
          ],
        });

      expect(alterada.status).toBe(200);
      // 24x115 + 150x18,9 + 9x42 = R$ 5.973,00, a 148,50 a saca: 40,2222 sacas.
      // Pela tabela NOVA (NPK a 120, saca a 150) dariam 40,62 — é essa diferença
      // que prova qual das duas gestões precificou a remontagem. O consultor não
      // vê R$, então quem denuncia a tabela errada é a conta em sacas.
      const grao = alterada.body.data.items.find((item: { kind: string }) => item.kind === 'grain');
      expect(grao.quantity).toBeCloseTo(40.2222, 3);
    });

    /**
     * A CULTURA é o limite, e agora o limite é uma LISTA: a permuta se altera
     * enquanto o Barter aberto ainda aceitar o grão que a paga. O trigo saiu do
     * lançamento, e remontar uma permuta de trigo na gestão da soja seria
     * montá-la com a régua errada — sem cotação e sem produtividade daquele grão.
     */
    it('permuta de cultura que saiu do lançamento não se altera', async () => {
      // PRM-2026-008 é do trigo (B2025.01), do Roberto; o Barter aberto paga em
      // soja e milho.
      const response = await pedir('PRM-2026-008', ROBERTO);

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Trigo');
      expect(response.body.message).toContain('Soja');
    });

    /**
     * A REESCRITA dos insumos só alcança o rascunho — é a mesma porta do parecer
     * salvo. Uma permuta na mesa de outra pessoa não se edita por baixo dela.
     */
    it('os insumos de uma permuta encaminhada não se reescrevem', async () => {
      const response = await request(app.getHttpServer())
        .put('/api/v1/barters/PRM-2026-005/inputs')
        .set('Authorization', await asUser(JOAO))
        .send({ inputs: [{ productId: 5, quantity: 24 }] });

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('já foi encaminhada');
    });

    /** A remontagem passa pelas MESMAS travas do registro. */
    it('a remontagem respeita o mínimo por hectare', async () => {
      // PRM-2026-009 é o rascunho do João, do Antônio (120 ha).
      const response = await request(app.getHttpServer())
        .put('/api/v1/barters/PRM-2026-009/inputs')
        .set('Authorization', await asUser(JOAO))
        .send({ inputs: [{ productId: 5, quantity: 10 }] });

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('no mínimo');
    });

    /**
     * A TERCEIRA SAÍDA: o admin atende o pedido mexendo no VALOR, e a permuta
     * não sai do lugar.
     *
     * A maior parte dos pedidos é de um número — o valor de um insumo saiu
     * diferente do que foi combinado com o produtor. Devolver a permuta ao
     * rascunho por causa disso joga fora dois pareceres e uma decisão para
     * corrigir o que o admin já tem na mão. Ver `priceChangeRefusal`.
     */
    describe('atendido no valor', () => {
      const alterar = async (code: string, email: string, body: object) =>
        request(app.getHttpServer())
          .post(`/api/v1/barters/${code}/change-request/prices`)
          .set('Authorization', await asUser(email))
          .send(body);

      /** O item de insumo desta permuta, pelo nome — como a tela o escolhe. */
      const itemDe = async (code: string, productName: string) => {
        const detalhe = await request(app.getHttpServer())
          .get(`/api/v1/barters/${code}`)
          .set('Authorization', await asUser(ADMIN));
        return detalhe.body.data.items.find(
          (item: { productName: string }) => item.productName === productName,
        ) as { id: number; unitValue: number };
      };

      /**
       * PRM-2026-005: semente a R$ 320 (50) + fungicida a R$ 87,50 (100) =
       * R$ 24.750, que a 148,50 a saca dão as 166,6667 do dataset. Com a
       * semente a R$ 300, o custo cai para R$ 23.750 — e as sacas TÊM de cair
       * junto, porque elas são o pagamento desse custo.
       */
      it('o valor muda, as sacas acompanham e a permuta fica onde estava', async () => {
        await pedir(
          'PRM-2026-005',
          JOAO,
          'O fornecedor fechou a semente a 300; corrija por favor.',
        );
        const semente = await itemDe('PRM-2026-005', 'Semente Soja RR TMG 7062');

        const response = await alterar('PRM-2026-005', ADMIN, {
          prices: [{ itemId: semente.id, unitValue: 300 }],
          note: 'Cotação do fornecedor confirmada por e-mail.',
        });

        expect(response.status).toBe(200);
        // A permuta NÃO voltou a rascunho: ela continua na mesa da Beatriz.
        expect(response.body.data.status).toBe('sentToManager');
        // E o pedido foi atendido — some, como na liberação.
        expect(response.body.data.changeRequestStatus).toBeNull();

        const alterado = response.body.data.items.find(
          (item: { id: number }) => item.id === semente.id,
        );
        expect(alterado.unitValue).toBe(300);
        // De onde o valor saiu, para a tela poder dizê-lo.
        expect(alterado.listValue).toBe(320);

        // 50×300 + 100×87,50 = R$ 23.750 → 159,9327 sacas.
        const grao = response.body.data.items.find(
          (item: { kind: string }) => item.kind === 'grain',
        );
        expect(grao.quantity).toBeCloseTo(159.9327, 3);

        // E a linha do tempo conta O QUE mudou, de quanto para quanto — é o que
        // o gerente vai ler para saber que a permuta não é mais a mesma.
        const evento = response.body.data.events.find(
          (e: { action: string }) => e.action === 'changeApplied',
        );
        expect(evento.note).toContain('R$ 320,00');
        expect(evento.note).toContain('R$ 300,00');
        expect(evento.note).toContain('Cotação do fornecedor');
      });

      /**
       * Alterar valor é ATENDER um pedido, e não um poder solto: sem pedido em
       * aberto, o admin estaria reprecificando permuta por conta própria — que
       * é decidir o negócio, o que ele não faz.
       */
      it('sem pedido em aberto, o valor não se altera', async () => {
        const semente = await itemDe('PRM-2026-005', 'Semente Soja RR TMG 7062');
        const response = await alterar('PRM-2026-005', ADMIN, {
          prices: [{ itemId: semente.id, unitValue: 300 }],
        });

        expect(response.status).toBe(422);
        expect(response.body.message).toContain('ATENDENDO a um pedido');
      });

      /** As sacas são o RESULTADO do custo: elas não se digitam. */
      it('o valor do grão não se altera por aqui', async () => {
        await pedir('PRM-2026-005', JOAO);
        const detalhe = await request(app.getHttpServer())
          .get('/api/v1/barters/PRM-2026-005')
          .set('Authorization', await asUser(ADMIN));
        const grao = detalhe.body.data.items.find(
          (item: { kind: string }) => item.kind === 'grain',
        );

        const response = await alterar('PRM-2026-005', ADMIN, {
          prices: [{ itemId: grao.id, unitValue: 160 }],
        });

        expect(response.status).toBe(422);
        expect(response.body.message).toContain('pagamento da permuta');
      });

      /** Reenviar o que já está gravado não é alteração — e não vira evento. */
      it('o valor igual ao gravado não vira alteração', async () => {
        await pedir('PRM-2026-005', JOAO);
        const semente = await itemDe('PRM-2026-005', 'Semente Soja RR TMG 7062');

        const response = await alterar('PRM-2026-005', ADMIN, {
          prices: [{ itemId: semente.id, unitValue: semente.unitValue }],
        });

        expect(response.status).toBe(422);
        expect(response.body.message).toContain('nada mudou');
      });

      /**
       * A SEGUNDA correção do mesmo item continua tendo partido da TABELA: o
       * que `listValue` guarda é de onde o valor saiu, não a lista de
       * tentativas.
       */
      it('a segunda correção não reescreve o valor de tabela', async () => {
        await pedir('PRM-2026-005', JOAO);
        const semente = await itemDe('PRM-2026-005', 'Semente Soja RR TMG 7062');
        await alterar('PRM-2026-005', ADMIN, {
          prices: [{ itemId: semente.id, unitValue: 300 }],
        });

        await pedir('PRM-2026-005', JOAO, 'O fornecedor corrigiu de novo: 290 a unidade.');
        const response = await alterar('PRM-2026-005', ADMIN, {
          prices: [{ itemId: semente.id, unitValue: 290 }],
        });

        const alterado = response.body.data.items.find(
          (item: { id: number }) => item.id === semente.id,
        );
        expect(alterado.unitValue).toBe(290);
        expect(alterado.listValue).toBe(320);
      });

      /** É do ADMIN, como a decisão do pedido: ninguém mais mexe em valor. */
      it('só o admin altera o valor', async () => {
        await pedir('PRM-2026-005', JOAO);
        const semente = await itemDe('PRM-2026-005', 'Semente Soja RR TMG 7062');

        for (const quem of [COMITE, GERENTE, FATURISTA, JOAO]) {
          const response = await alterar('PRM-2026-005', quem, {
            prices: [{ itemId: semente.id, unitValue: 300 }],
          });
          expect(response.status).toBe(403);
        }
      });
    });
  });

  /**
   * O PEDIDO DE FORA DO BARTER: o consultor pede um produto que a tabela da
   * versão não tem, e o admin o inclui naquela permuta com o valor que acertou.
   *
   * O que estes casos protegem é a JANELA (até a decisão do comitê, e o
   * rascunho dentro dela) e o EFEITO do item incluído: ele paga em sacas como
   * qualquer outro, não entra em régua nenhuma e sobrevive à remontagem do
   * rascunho. Ver `barters/product-request.ts`.
   */
  describe('pedido de fora do Barter', () => {
    const DRONE = {
      productName: 'Semeadura por drone',
      unit: 'ha',
      quantity: 40,
      note: 'O produtor quer a sobressemeadura de capim na área de soja.',
    };

    const pedirProduto = async (code: string, email: string, body: object = DRONE) =>
      request(app.getHttpServer())
        .post(`/api/v1/barters/${code}/product-requests`)
        .set('Authorization', await asUser(email))
        .send(body);

    const decidirProduto = async (code: string, id: number, email: string, body: object) =>
      request(app.getHttpServer())
        .post(`/api/v1/barters/${code}/product-requests/${id}/decision`)
        .set('Authorization', await asUser(email))
        .send(body);

    /** Pede, o admin atende, e devolve o id do pedido e a permuta resultante. */
    const pedirEAtender = async (code: string, email: string, unitValue = 250) => {
      const pedido = await pedirProduto(code, email);
      expect(pedido.status).toBe(200);
      const id = pedido.body.data.productRequests[0].id as number;
      const atendida = await decidirProduto(code, id, ADMIN, { accept: true, unitValue });
      expect(atendida.status).toBe(200);
      return { id, atendida };
    };

    /**
     * O pedido não move a permuta e não a tira da fila — como o de alteração,
     * ele pendura uma linha na mesa do admin. A diferença é que este vale já no
     * RASCUNHO: é ali que o consultor monta a permuta e topa com o que falta.
     */
    it('o consultor pede no próprio rascunho', async () => {
      const response = await pedirProduto('PRM-2026-009', JOAO);

      expect(response.status).toBe(200);
      expect(response.body.data.status).toBe('draft');
      const [pedido] = response.body.data.productRequests;
      expect(pedido.productName).toBe('Semeadura por drone');
      expect(pedido.quantity).toBe(40);
      expect(pedido.status).toBe('open');
      expect(pedido.requestedBy).toBe('João Silva');
      // Sem valor: ninguém precificou nada ainda.
      expect(pedido.sacksPerUnit).toBeNull();
      // E o consultor não recebe R$ — nem aqui, que é onde o valor vai nascer.
      expect(pedido.unitValue).toBeUndefined();
    });

    /**
     * ATENDER põe o item na permuta e recalcula as sacas: ele é custo retirado
     * como qualquer outro. O item entra MARCADO, sem produto no catálogo — é a
     * única maneira de explicar depois um valor que não está em tabela nenhuma.
     */
    it('o admin inclui o item com o valor acertado, e as sacas acompanham', async () => {
      const { atendida } = await pedirEAtender('PRM-2026-009', JOAO);

      const item = atendida.body.data.items.find(
        (i: { offBarter: boolean }) => i.offBarter === true,
      );
      expect(item.productName).toBe('Semeadura por drone');
      expect(item.quantity).toBe(40);
      expect(item.unitValue).toBe(250);
      expect(item.productId).toBeNull();

      // O rascunho custava R$ 15.216; com 40 ha a R$ 250 são R$ 25.216, que a
      // 148,50 a saca dão 169,8047.
      const grao = atendida.body.data.items.find((i: { kind: string }) => i.kind === 'grain');
      expect(grao.quantity).toBeCloseTo(169.8047, 3);

      // O pedido atendido CONTINUA existindo: é ele que diz de onde o item veio.
      const [pedido] = atendida.body.data.productRequests;
      expect(pedido.status).toBe('added');
      expect(pedido.unitValue).toBe(250);
      expect(pedido.decidedBy).toBe('Carlos Mendes');

      const evento = atendida.body.data.events.find(
        (e: { action: string }) => e.action === 'productAdded',
      );
      expect(evento.note).toContain('Semeadura por drone');
      expect(evento.note).toContain('R$ 250,00');
    });

    /** Quem pediu não vê R$: o valor chega a ele na moeda dele, em sacas. */
    it('o consultor lê o valor atendido em sacas', async () => {
      await pedirEAtender('PRM-2026-009', JOAO);

      const response = await request(app.getHttpServer())
        .get('/api/v1/barters/PRM-2026-009')
        .set('Authorization', await asUser(JOAO));

      const [pedido] = response.body.data.productRequests;
      expect(pedido.unitValue).toBeUndefined();
      // 250 / 148,50 = 1,6835 sacas por hectare de serviço.
      expect(pedido.sacksPerUnit).toBeCloseTo(1.6835, 3);
    });

    /**
     * O ITEM SOBREVIVE À REMONTAGEM — e é por isso que o pedido atendido não
     * some. Ele não vem no payload do consultor (não tem produto no catálogo
     * para apontar), então sem esta regra o primeiro ajuste de quantidade
     * apagaria o que o admin acabou de incluir.
     *
     * E ele não entra em RÉGUA nenhuma: R$ 10.000 de drone sobre R$ 15.216 de
     * insumos derrubariam o mínimo de 30% dos fertilizantes (o NPK é 45% do
     * catálogo e cairia para 27% do total) se o item contasse no denominador —
     * um pedido atendido derrubaria a permuta que ele veio ajudar.
     */
    it('o item incluído sobrevive à remontagem do rascunho, e não mede pasta', async () => {
      await pedirEAtender('PRM-2026-009', JOAO);

      const response = await request(app.getHttpServer())
        .put('/api/v1/barters/PRM-2026-009/inputs')
        .set('Authorization', await asUser(JOAO))
        .send({
          inputs: [
            { productId: 5, quantity: 60 },
            { productId: 6, quantity: 400 },
            { productId: 7, quantity: 18 },
          ],
        });

      expect(response.status).toBe(200);
      const fora = response.body.data.items.filter(
        (i: { offBarter: boolean }) => i.offBarter === true,
      );
      expect(fora).toHaveLength(1);
      expect(fora[0].quantity).toBe(40);
      const grao = response.body.data.items.find((i: { kind: string }) => i.kind === 'grain');
      expect(grao.quantity).toBeCloseTo(169.8047, 3);
    });

    /** Recusar não mexe na permuta — e o motivo é obrigatório, como sempre. */
    it('a recusa fecha o pedido com o motivo, e nada entra na permuta', async () => {
      const pedido = await pedirProduto('PRM-2026-009', JOAO);
      const id = pedido.body.data.productRequests[0].id as number;

      const semMotivo = await decidirProduto('PRM-2026-009', id, ADMIN, { accept: false });
      expect(semMotivo.status).toBe(422);

      const response = await decidirProduto('PRM-2026-009', id, ADMIN, {
        accept: false,
        note: 'Não temos fornecedor de drone com nota para a praça nesta safra.',
      });

      expect(response.status).toBe(200);
      expect(response.body.data.productRequests[0].status).toBe('denied');
      expect(response.body.data.productRequests[0].reply).toContain('fornecedor');
      expect(
        response.body.data.items.filter((i: { offBarter: boolean }) => i.offBarter === true),
      ).toHaveLength(0);
      // O rascunho continua com as 102,4646 sacas do dataset.
      const grao = response.body.data.items.find((i: { kind: string }) => i.kind === 'grain');
      expect(grao.quantity).toBeCloseTo(102.4646, 3);
    });

    /** Atender é precificar: sem valor não há o que incluir. */
    it('não se inclui item sem valor', async () => {
      const pedido = await pedirProduto('PRM-2026-009', JOAO);
      const id = pedido.body.data.productRequests[0].id as number;

      const response = await decidirProduto('PRM-2026-009', id, ADMIN, { accept: true });
      expect(response.status).toBe(422);
      expect(response.body.message).toContain('valor');
    });

    /** Um pedido se decide uma vez só: dois admins não incluem o item em dobro. */
    it('o pedido decidido não se decide de novo', async () => {
      const { id } = await pedirEAtender('PRM-2026-009', JOAO);

      const segunda = await decidirProduto('PRM-2026-009', id, ADMIN, {
        accept: true,
        unitValue: 300,
      });
      expect(segunda.status).toBe(422);
      expect(segunda.body.message).toContain('já foi incluído');
    });

    /**
     * Depois da DECISÃO DO COMITÊ, não: um insumo a mais mudaria o que foi
     * aprovado. A recusa manda a pessoa para o outro caminho — o pedido de
     * alteração, que devolve a permuta ao consultor.
     */
    it('a permuta já decidida não recebe mais item', async () => {
      // PRM-2026-004 é da Ana, já aprovada pelo comitê.
      const response = await pedirProduto('PRM-2026-004', ANA);

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Peça a alteração da permuta');
    });

    /**
     * Mas o pedido que ficou para trás ainda se RECUSA: limpar a mesa não
     * altera permuta nenhuma, e deixá-lo pendurado seria uma fila que não anda.
     */
    it('o pedido esquecido se recusa mesmo depois de a permuta ser decidida', async () => {
      // O rascunho do João, com um pedido aberto, percorre a linha inteira.
      const pedido = await pedirProduto('PRM-2026-009', JOAO);
      const id = pedido.body.data.productRequests[0].id as number;

      const asJoao = await asUser(JOAO);
      await encaminhar('PRM-2026-009', asJoao);
      await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-009/opinion')
        .set('Authorization', await asUser(GERENTE))
        .send({ note: 'Volume compatível com a área declarada pelo produtor.' });
      await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-009/review')
        .set('Authorization', await asUser(COMITE))
        .send({ status: 'approved' });

      const recusa = await decidirProduto('PRM-2026-009', id, ADMIN, {
        accept: false,
        note: 'A permuta já foi aprovada sem este item; entra na próxima.',
      });
      expect(recusa.status).toBe(200);
      expect(recusa.body.data.productRequests[0].status).toBe('denied');

      const inclusao = await decidirProduto('PRM-2026-009', id, ADMIN, {
        accept: true,
        unitValue: 250,
      });
      expect(inclusao.status).toBe(422);
    });

    /** O pedido é de quem registrou, como o de alteração. */
    it('outro consultor não pede na permuta alheia', async () => {
      const response = await pedirProduto('PRM-2026-005', ANA);
      expect(response.status).toBe(403);
    });

    /** E quem atende é o ADMIN: nenhum posto da linha precifica item. */
    it('nem o comitê nem o gerente atendem o pedido', async () => {
      const pedido = await pedirProduto('PRM-2026-009', JOAO);
      const id = pedido.body.data.productRequests[0].id as number;

      for (const quem of [COMITE, GERENTE, FATURISTA, JOAO]) {
        const response = await decidirProduto('PRM-2026-009', id, quem, {
          accept: true,
          unitValue: 250,
        });
        expect(response.status).toBe(403);
      }
    });

    /**
     * O pedido é lido DENTRO da permuta: um id de pedido de outra permuta não
     * atravessa a porta de uma permuta que o admin enxerga.
     */
    it('o pedido de uma permuta não se decide pela porta de outra', async () => {
      const pedido = await pedirProduto('PRM-2026-009', JOAO);
      const id = pedido.body.data.productRequests[0].id as number;

      const response = await decidirProduto('PRM-2026-005', id, ADMIN, {
        accept: true,
        unitValue: 250,
      });
      expect(response.status).toBe(404);
    });

    /**
     * O que o ADMIN escreve vence o que o consultor pediu: a descrição do
     * fornecedor é outra, e é o item dele que vai ser separado no balcão.
     */
    it('o admin corrige a descrição, a unidade e o código ao atender', async () => {
      const pedido = await pedirProduto('PRM-2026-009', JOAO);
      const id = pedido.body.data.productRequests[0].id as number;

      const response = await decidirProduto('PRM-2026-009', id, ADMIN, {
        accept: true,
        unitValue: 250,
        productName: 'Sobressemeadura aérea (drone) — serviço',
        unit: 'ha',
        sku: 'SRV-DRONE-01',
      });

      const item = response.body.data.items.find(
        (i: { offBarter: boolean }) => i.offBarter === true,
      );
      expect(item.productName).toBe('Sobressemeadura aérea (drone) — serviço');
      expect(item.sku).toBe('SRV-DRONE-01');
      expect(response.body.data.productRequests[0].productName).toBe(
        'Sobressemeadura aérea (drone) — serviço',
      );
    });

    /**
     * O item de fora do Barter NÃO entra no catálogo: ele é a lista do
     * fornecedor, e um produto criado a partir de um pedido apareceria no
     * relatório de preços e na carga seguinte como se fosse da praça.
     */
    it('o item incluído não vira produto do catálogo', async () => {
      const antes = await request(app.getHttpServer())
        .get('/api/v1/products')
        .set('Authorization', await asUser(ADMIN));

      await pedirEAtender('PRM-2026-009', JOAO);

      const depois = await request(app.getHttpServer())
        .get('/api/v1/products')
        .set('Authorization', await asUser(ADMIN));

      expect(depois.body.data).toHaveLength(antes.body.data.length);
      expect(depois.body.data.some((p: { name: string }) => p.name.includes('drone'))).toBe(false);
    });
  });
});
