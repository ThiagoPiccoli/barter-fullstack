import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import {
  ADMIN,
  ANA,
  COMITE,
  EMISSOR,
  FATURISTA,
  GERENTE,
  UNIT,
  createTestApp,
  loginAs,
  resetDb,
} from './utils';

/**
 * A MESA DO COMITÊ — o dossiê que fundamenta a decisão, e as exigências que
 * saem dela.
 *
 * As duas coisas nasceram do mesmo buraco. A permuta chegava ao comitê com o
 * pedido do consultor e o parecer do gerente; o resto da análise — a consulta
 * ao Serasa, o extrato do que o produtor já deve à cooperativa — circulava por
 * e-mail entre os integrantes da reunião e morria na caixa de quem a convocou.
 * E o que a reunião exigia ("com aval", "condicionada a hipoteca") saía
 * escrito em prosa dentro do texto da decisão, diferente a cada ata.
 *
 * O que estas provas travam:
 *
 * 1. **o dossiê é do comitê** — ele junta, ele e o admin leem, e MAIS NINGUÉM:
 *    é a única leitura de anexo restrita do sistema;
 * 2. **nem o admin escreve nele** — quem põe prova dentro de uma decisão é quem
 *    decide, e a leitura do admin existe para auditar isso;
 * 3. **a janela fecha na decisão** — juntar documento a uma permuta já aprovada
 *    seria acrescentar fundamento a uma decisão tomada;
 * 4. **as exigências são uma etapa** — avalista, hipoteca e seguro são pedidos
 *    antes da decisão, devolvem a permuta à consultora e voltam direto ao
 *    comitê quando cumpridos, com o gerente avisado nas duas pontas;
 * 5. **o SCR chega ao comitê sem a cédula junto** — o endividamento no Bacen é
 *    peça de decisão; o formulário do título não é.
 */
describe('A mesa do comitê (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const asUser = async (email: string) => `Bearer ${await loginAs(app, email)}`;

  /** PRM-2026-002 está `pending` — na mesa do comitê, esperando decisão. */
  const CODE = 'PRM-2026-002';

  /** PRM-2026-001 é a única já faturada, e a única com cédula e SCR no dataset. */
  const FATURADA = 'PRM-2026-001';

  const anexar = async (auth: string, code = CODE, kind = 'serasa') =>
    request(app.getHttpServer())
      .post(`/api/v1/barters/${code}/credit-files`)
      .set('Authorization', auth)
      .field('kind', kind)
      .field('note', 'Consulta de 20/04, sem restrições.')
      .attach('file', Buffer.from('%PDF-1.4\n%%EOF\n'), {
        filename: 'serasa.pdf',
        contentType: 'application/pdf',
      });

  const ler = async (email: string, code = CODE) =>
    request(app.getHttpServer())
      .get(`/api/v1/barters/${code}`)
      .set('Authorization', await asUser(email));

  /* ── O dossiê ──────────────────────────────────────────────────────── */

  describe('o dossiê da análise de crédito', () => {
    it('o comitê junta a peça, e ela passa a aparecer na permuta com o tipo por extenso', async () => {
      const resposta = await anexar(await asUser(COMITE));

      expect(resposta.status).toBe(200);
      const [peça] = resposta.body.data.creditFiles;
      expect(peça).toMatchObject({
        kind: 'serasa',
        kindLabel: 'Consulta ao Serasa',
        note: 'Consulta de 20/04, sem restrições.',
        attachedBy: 'Comitê de Permutas',
      });
      expect(peça.file).toMatchObject({
        fileName: 'serasa.pdf',
        contentType: 'application/pdf',
      });
      // O ARQUIVO sai como metadado, nunca com os bytes: quem quer o documento
      // pede o documento.
      expect(peça.file.content).toBeUndefined();

      const baixado = await request(app.getHttpServer())
        .get(`/api/v1/barters/${CODE}/credit-files/${peça.id}/file`)
        .set('Authorization', await asUser(COMITE));
      expect(baixado.status).toBe(200);
      expect(baixado.headers['content-disposition']).toContain('serasa.pdf');
    });

    it('o endividamento na cooperativa é uma peça própria, ao lado da consulta', async () => {
      await anexar(await asUser(COMITE), CODE, 'serasa');
      const resposta = await anexar(await asUser(COMITE), CODE, 'indebtedness');

      expect(resposta.body.data.creditFiles).toHaveLength(2);
      // A peça mais recente primeiro.
      expect(
        resposta.body.data.creditFiles.map((peça: { kindLabel: string }) => peça.kindLabel),
      ).toEqual(['Endividamento na cooperativa', 'Consulta ao Serasa']);
    });

    /**
     * A RESTRIÇÃO É A PEÇA INTEIRA, e não só o download: o campo `creditFiles`
     * SOME do JSON de quem não pode lê-lo — não vem vazio.
     *
     * Vazio diria "o comitê não apurou nada", e o consultor concluiria que a
     * permuta dele foi decidida no escuro. O que é verdade é outra coisa: o
     * dossiê existe, e não é dele.
     */
    it('o admin lê o dossiê; consultor, gerente, faturista e emissor não sabem que ele existe', async () => {
      const anexada = await anexar(await asUser(COMITE));
      const id = anexada.body.data.creditFiles[0].id as number;

      const doAdmin = await ler(ADMIN);
      expect(doAdmin.body.data.creditFiles).toHaveLength(1);

      for (const email of [ANA, GERENTE, FATURISTA, EMISSOR]) {
        const resposta = await ler(email);
        // A permuta continua visível para quem a alcança — o que some é o
        // dossiê. (O emissor e o faturista não alcançam esta permuta, que ainda
        // está no comitê; o que importa aqui é que NENHUM deles recebe a lista.)
        expect(resposta.body.data?.creditFiles).toBeUndefined();

        const baixado = await request(app.getHttpServer())
          .get(`/api/v1/barters/${CODE}/credit-files/${id}/file`)
          .set('Authorization', await asUser(email));
        expect(baixado.status).toBe(403);
      }
    });

    /**
     * O ADMIN LÊ E NÃO ESCREVE. Ele é o único papel do sistema com essa forma —
     * em todos os outros cadastros ele é quem escreve —, e é deliberado: a
     * leitura dele existe para auditar uma decisão que não é dele, e escrever no
     * dossiê seria mexer na fundamentação dela.
     */
    it('o admin também junta peça ao dossiê — ele tem todas as capacidades', async () => {
      const resposta = await anexar(await asUser(ADMIN));
      expect(resposta.status).toBe(200);
    });

    it('a peça anexada por engano se remove, e o arquivo vai junto', async () => {
      const anexada = await anexar(await asUser(COMITE));
      const id = anexada.body.data.creditFiles[0].id as number;

      const removida = await request(app.getHttpServer())
        .delete(`/api/v1/barters/${CODE}/credit-files/${id}`)
        .set('Authorization', await asUser(COMITE));

      expect(removida.status).toBe(200);
      expect(removida.body.data.creditFiles).toEqual([]);

      const baixado = await request(app.getHttpServer())
        .get(`/api/v1/barters/${CODE}/credit-files/${id}/file`)
        .set('Authorization', await asUser(COMITE));
      expect(baixado.status).toBe(404);
    });

    /**
     * A JANELA FECHA NA DECISÃO, nos dois sentidos: não se junta e não se
     * apaga.
     *
     * O dossiê existe para DECIDIR. Depois da decisão ele é prova — e o que
     * fundamentou uma aprovação não se altera por quem a tomou, que é
     * exatamente o registro que alguém vai procurar quando a decisão for
     * questionada.
     */
    it('decidida a permuta, o dossiê não recebe nem perde peça', async () => {
      const anexada = await anexar(await asUser(COMITE));
      const id = anexada.body.data.creditFiles[0].id as number;

      const decisão = await request(app.getHttpServer())
        .post(`/api/v1/barters/${CODE}/review`)
        .set('Authorization', await asUser(COMITE))
        .send({ status: 'approved' });
      expect(decisão.status).toBe(200);

      const tardia = await anexar(await asUser(COMITE));
      expect(tardia.status).toBe(422);
      expect(tardia.body.message).toContain('já foi decidida');
      expect(tardia.body.message).toContain('Peça a alteração');

      const remoção = await request(app.getHttpServer())
        .delete(`/api/v1/barters/${CODE}/credit-files/${id}`)
        .set('Authorization', await asUser(COMITE));
      expect(remoção.status).toBe(422);

      // E a peça continua lá, legível por quem pode lê-la.
      expect((await ler(COMITE)).body.data.creditFiles).toHaveLength(1);
    });

    /** A trilha guarda as duas pontas — anexar e remover. */
    it('juntar e remover peça entram na trilha de auditoria', async () => {
      const anexada = await anexar(await asUser(COMITE));
      const id = anexada.body.data.creditFiles[0].id as number;
      await request(app.getHttpServer())
        .delete(`/api/v1/barters/${CODE}/credit-files/${id}`)
        .set('Authorization', await asUser(COMITE));

      const trilha = await request(app.getHttpServer())
        .get('/api/v1/audit-logs')
        .set('Authorization', await asUser(ADMIN));

      const ações = (trilha.body.data as { action: string }[]).map((linha) => linha.action);
      expect(ações).toContain('barter.credit-file-attached');
      expect(ações).toContain('barter.credit-file-removed');
    });
  });

  /* ── O SCR na mesa do comitê ───────────────────────────────────────── */

  /**
   * O SCR é o retrato do endividamento do produtor no Banco Central, e ele já
   * está na permuta quando o comitê decide — quem o anexa é o consultor, junto
   * com a cédula. Faltava só o comitê poder abri-lo.
   *
   * Ele chega pela porta do DOSSIÊ (`barters.creditRead`), e não pela da cédula:
   * `bartersCprRead` traria junto o formulário do título, que é assunto de quem
   * emite e não de quem decide o negócio.
   */
  it('o comitê abre o SCR do produtor sem receber a cédula junto', async () => {
    const scr = await request(app.getHttpServer())
      .get(`/api/v1/barters/${FATURADA}/cpr/scr`)
      .set('Authorization', await asUser(COMITE));
    expect(scr.status).toBe(200);

    const cédula = await request(app.getHttpServer())
      .get(`/api/v1/barters/${FATURADA}/cpr`)
      .set('Authorization', await asUser(COMITE));
    expect(cédula.status).toBe(403);
  });

  /* ── As exigências do comitê ───────────────────────────────────────── */

  /**
   * AVALISTA, HIPOTECA E SEGURO — pedidos ANTES de decidir.
   *
   * O comitê marca o que exige, a permuta volta ao CONSULTOR e o GERENTE é
   * avisado. Cumpridas as exigências (na cédula), ela volta DIRETO ao comitê —
   * sem um segundo parecer — e o gerente é avisado de novo.
   */
  describe('as exigências do comitê', () => {
    const exigir = async (body: object, code = CODE) =>
      request(app.getHttpServer())
        .post(`/api/v1/barters/${code}/requirements`)
        .set('Authorization', await asUser(COMITE))
        .send(body);

    const cumprir = async (code = CODE, body: object = {}) =>
      request(app.getHttpServer())
        .post(`/api/v1/barters/${code}/requirements/fulfill`)
        .set('Authorization', await asUser(ANA))
        .send(body);

    const decidir = async (body: object) =>
      request(app.getHttpServer())
        .post(`/api/v1/barters/${CODE}/review`)
        .set('Authorization', await asUser(COMITE))
        .send(body);

    const avisosDe = async (email: string) =>
      request(app.getHttpServer())
        .get('/api/v1/notices')
        .set('Authorization', await asUser(email));

    /** Um PDF anexado numa rota de anexo da cédula. */
    const anexarPdf = async (auth: string, caminho: string, nome: string) =>
      request(app.getHttpServer())
        .put(`/api/v1/barters/${CODE}/cpr/${caminho}`)
        .set('Authorization', auth)
        .attach('file', Buffer.from('%PDF-1.4\nANEXO\n%%EOF\n'), {
          filename: nome,
          contentType: 'application/pdf',
        });

    /**
     * A cédula da PRM-2026-002 com a parte do consultor pronta. Os avalistas e
     * bens que vierem em `extra` recebem os ANEXOS (o SCR de cada avalista, o
     * documento de cada bem) — salvo `semAnexos`, que é o caso de quem testa a
     * falta deles.
     */
    const preencherCedula = async (extra: object = {}, { semAnexos = false } = {}) => {
      const auth = await asUser(ANA);
      const salvo = await request(app.getHttpServer())
        .put(`/api/v1/barters/${CODE}/cpr`)
        .set('Authorization', auth)
        .send({
          emitterNationality: 'brasileira',
          emitterMaritalStatus: 'solteira',
          emitterProfession: 'produtora rural',
          emitterRg: '10.234.567-8',
          emitterAddress: 'Rua das Acácias',
          emitterAddressNumber: '340',
          emitterCity: 'Maringá/PR',
          deliveryUnitId: UNIT.filial04,
          cultivar: 'BMX Ativa RR',
          maxMoisture: 14,
          maxImpurities: 1,
          oilContent: 18,
          areas: [
            {
              locality: 'Água Boa',
              city: 'Maringá/PR',
              areaHa: 30,
              registryNumber: '55.001',
              registryBook: '2-RG',
              registryDistrict: 'Maringá/PR',
              owners: [{ name: 'Helena Prado', document: '111.222.333-44' }],
            },
          ],
          ...extra,
        });
      expect(salvo.status).toBe(200);
      const scr = await request(app.getHttpServer())
        .put(`/api/v1/barters/${CODE}/cpr/scr`)
        .set('Authorization', auth)
        .attach('file', Buffer.from('%PDF-1.4\nSCR\n%%EOF\n'), {
          filename: 'scr.pdf',
          contentType: 'application/pdf',
        });
      expect(scr.status).toBe(200);
      if (semAnexos) return scr;

      const { guarantors, mortgages } = scr.body.data.cpr as {
        guarantors: { id: number }[];
        mortgages: { id: number }[];
      };
      let mesa = scr;
      for (const { id } of guarantors) {
        mesa = await anexarPdf(auth, `guarantors/${id}/scr`, 'scr-avalista.pdf');
        expect(mesa.status).toBe(200);
      }
      for (const { id } of mortgages) {
        mesa = await anexarPdf(auth, `mortgages/${id}/document`, 'matricula.pdf');
        expect(mesa.status).toBe(200);
      }
      return mesa;
    };

    /** Um bem em hipoteca cadastrado por inteiro — o documento sobe à parte. */
    const bem = {
      description: 'Imóvel rural — sede da fazenda, 40 ha',
      registryNumber: '9.876',
      registryDistrict: 'Maringá/PR',
      city: 'Maringá/PR',
      ownerName: 'Helena Prado',
      ownerDocument: '111.222.333-44',
      appraisedValue: 1500000,
    };

    const avalista = {
      name: 'Carlos Prado',
      document: '222.333.444-55',
      rg: '9.876.543-2',
      nationality: 'brasileiro',
      profession: 'comerciante',
      maritalStatus: 'solteiro',
      address: 'Rua das Palmeiras',
      addressNumber: '12',
      city: 'Maringá/PR',
    };

    const PEDIDO = 'Aval do irmão, sócio na área, e hipoteca da sede da fazenda.';

    it('o comitê exige, e a permuta volta para a consultora', async () => {
      const resposta = await exigir({
        requiresGuarantor: true,
        requiresCollateral: true,
        note: PEDIDO,
      });

      expect(resposta.status).toBe(200);
      expect(resposta.body.data).toMatchObject({
        status: 'awaitingRequirements',
        statusLabel: 'Exigências do comitê, com o consultor',
        waitingFor: 'consultant',
        nextAction: 'fulfill',
        requiresGuarantor: true,
        requiresCollateral: true,
        // EXIGIR NÃO É DECIDIR: os campos da decisão continuam vazios, e a
        // permuta não diz "decidida por" enquanto espera a consultora.
        reviewedBy: null,
        reviewNote: null,
      });

      // O QUAL vai na linha do tempo, com as caixas por extenso.
      const evento = (resposta.body.data.events as { action: string; note: string }[]).find(
        (linha) => linha.action === 'require',
      );
      expect(evento?.note).toContain(PEDIDO);
      expect(evento?.note).toContain('Exigências: Avalista, Hipoteca.');

      // A CONSULTORA a tem de volta, e lê o que trazer.
      const daConsultora = await ler(ANA);
      expect(daConsultora.body.data.requiresGuarantor).toBe(true);
      expect(daConsultora.body.data.waitingFor).toBe('consultant');
    });

    it('o gerente é avisado — e o aviso é só dele', async () => {
      await exigir({
        requiresCollateral: true,
        note: 'Hipoteca da sede da fazenda, matrícula atualizada.',
      });

      const doGerente = await avisosDe(GERENTE);
      expect(doGerente.status).toBe(200);
      expect(doGerente.body.data).toHaveLength(1);
      expect(doGerente.body.data[0]).toMatchObject({ barterCode: CODE, readAt: null });
      expect(doGerente.body.data[0].message).toContain('voltou ao consultor');
      expect(doGerente.body.data[0].message).toContain('hipoteca');

      // Ninguém mais recebe: o aviso é para quem deu o parecer e não age agora.
      for (const email of [ANA, COMITE, ADMIN]) {
        expect((await avisosDe(email)).body.data).toEqual([]);
      }
    });

    it('dispensado, o aviso some — e o de outra pessoa não se dispensa', async () => {
      await exigir({
        requiresCollateral: true,
        note: 'Hipoteca da sede da fazenda, matrícula atualizada.',
      });
      const [aviso] = (await avisosDe(GERENTE)).body.data as { id: number }[];

      const deOutro = await request(app.getHttpServer())
        .post(`/api/v1/notices/${aviso.id}/read`)
        .set('Authorization', await asUser(ANA));
      expect(deOutro.status).toBe(404);

      const visto = await request(app.getHttpServer())
        .post(`/api/v1/notices/${aviso.id}/read`)
        .set('Authorization', await asUser(GERENTE));
      expect(visto.status).toBe(200);
      expect(visto.body.data.readAt).not.toBeNull();

      expect((await avisosDe(GERENTE)).body.data).toEqual([]);
    });

    /** Devolver sem dizer o quê mandaria a consultora adivinhar o que trazer. */
    it('sem marcar nada, ou sem dizer qual, a permuta não volta', async () => {
      const semCaixa = await exigir({ note: PEDIDO });
      expect(semCaixa.status).toBe(422);
      expect(semCaixa.body.message).toContain('Marque o que o comitê exige');

      const semTexto = await exigir({ requiresGuarantor: true });
      expect(semTexto.status).toBe(422);

      expect((await ler(COMITE)).body.data.status).toBe('pending');
    });

    /** Só o comitê exige: é a alternativa a decidir, na mesma mesa. */
    it('o gerente e a consultora não exigem nada', async () => {
      for (const email of [GERENTE, ANA]) {
        const resposta = await request(app.getHttpServer())
          .post(`/api/v1/barters/${CODE}/requirements`)
          .set('Authorization', await asUser(email))
          .send({ requiresGuarantor: true, note: PEDIDO });
        expect(resposta.status).toBe(403);
      }
    });

    /**
     * A PERMUTA DEVOLVIDA NÃO SE DECIDE: ela não está na mesa do comitê. A
     * recusa diz com quem ela está e o que falta — e não "já foi decidida", que
     * é justamente o que ela não foi.
     */
    it('o comitê não decide a permuta enquanto ela está com a consultora', async () => {
      await exigir({ requiresGuarantor: true, note: PEDIDO });

      const decisão = await decidir({ status: 'approved' });
      expect(decisão.status).toBe(422);
      expect(decisão.body.message).toBe(
        'Esta permuta aguarda o consultor providenciar o que o comitê exigiu: avalista',
      );
    });

    /**
     * O CUMPRIMENTO É A CÉDULA: a consultora não devolve a permuta sem o
     * avalista que o comitê pediu, e a recusa diz isso.
     */
    it('a consultora não devolve sem trazer o que foi exigido', async () => {
      await exigir({ requiresGuarantor: true, note: PEDIDO });
      await preencherCedula();

      const resposta = await cumprir();
      expect(resposta.status).toBe(422);
      expect(resposta.body.message).toContain('antes de devolvê-la ao comitê');
      expect(resposta.body.message).toContain('ao menos um avalista (exigido pelo comitê)');
    });

    /**
     * O AVALISTA SEM SCR não cumpre o aval, e o BEM SEM DOCUMENTO não cumpre a
     * hipoteca: os dois anexos são parte do que o comitê exigiu.
     */
    it('avalista sem SCR e bem sem documento não cumprem a exigência', async () => {
      await exigir({ requiresGuarantor: true, requiresCollateral: true, note: PEDIDO });
      await preencherCedula({ guarantors: [avalista], mortgages: [bem] }, { semAnexos: true });

      const resposta = await cumprir();
      expect(resposta.status).toBe(422);
      expect(resposta.body.message).toContain('o SCR do 1º avalista');

      const mesa = await request(app.getHttpServer())
        .get(`/api/v1/barters/${CODE}/cpr`)
        .set('Authorization', await asUser(ANA));
      expect(mesa.body.data.consultantGaps).toEqual(
        expect.arrayContaining([
          'o SCR do 1º avalista (anexo obrigatório, com o consultor)',
          'o documento do 1º bem em hipoteca (matrícula atualizada, anexo obrigatório)',
        ]),
      );
    });

    /**
     * O COMITÊ ABRE os anexos das garantias que exigiu — o SCR do avalista e a
     * matrícula do bem —, pela mesma porta do SCR do emitente, sem receber a
     * cédula junto.
     */
    it('o comitê lê o SCR do avalista e o documento do bem', async () => {
      await exigir({ requiresGuarantor: true, requiresCollateral: true, note: PEDIDO });
      const mesa = await preencherCedula({ guarantors: [avalista], mortgages: [bem] });
      const { guarantors, mortgages } = mesa.body.data.cpr as {
        guarantors: { id: number; scrFile: { fileName: string } }[];
        mortgages: { id: number; documentFile: { fileName: string } }[];
      };
      expect(guarantors[0].scrFile.fileName).toBe('scr-avalista.pdf');
      expect(mortgages[0].documentFile.fileName).toBe('matricula.pdf');

      const comite = await asUser(COMITE);
      for (const caminho of [
        `guarantors/${guarantors[0].id}/scr`,
        `mortgages/${mortgages[0].id}/document`,
      ]) {
        const arquivo = await request(app.getHttpServer())
          .get(`/api/v1/barters/${CODE}/cpr/${caminho}`)
          .set('Authorization', comite);
        expect(arquivo.status).toBe(200);
      }

      // O GERENTE não tem nem a cédula nem o dossiê.
      const doGerente = await request(app.getHttpServer())
        .get(`/api/v1/barters/${CODE}/cpr/guarantors/${guarantors[0].id}/scr`)
        .set('Authorization', await asUser(GERENTE));
      expect(doGerente.status).toBe(403);
    });

    /**
     * CUMPRIDAS, ela volta DIRETO ao comitê: o parecer do gerente continua o
     * mesmo, e ele é avisado — não chamado a agir.
     */
    it('cumpridas as exigências, a permuta volta direto ao comitê', async () => {
      const antes = (await ler(COMITE)).body.data;
      await exigir({ requiresGuarantor: true, requiresCollateral: true, note: PEDIDO });
      await preencherCedula({ guarantors: [avalista], mortgages: [bem] });

      const resposta = await cumprir(CODE, { note: 'O avalista é o irmão, como pedido.' });
      expect(resposta.status).toBe(200);
      expect(resposta.body.data).toMatchObject({
        status: 'pending',
        waitingFor: 'committee',
        // SEM SEGUNDO PARECER: o do gerente é o mesmo de antes.
        managerNote: antes.managerNote,
        managerReviewedAt: antes.managerReviewedAt,
        // As exigências ficam: a decisão será tomada contando com elas.
        requiresGuarantor: true,
        requiresCollateral: true,
      });
      const ações = (resposta.body.data.events as { action: string }[]).map((e) => e.action);
      expect(ações.filter((ação) => ação === 'opinion')).toHaveLength(1);
      expect(ações).toContain('fulfill');

      // O GERENTE foi avisado das duas pontas: a ida e a volta.
      const avisos = (await avisosDe(GERENTE)).body.data as { message: string }[];
      expect(avisos.map((aviso) => aviso.message)).toEqual([
        expect.stringContaining('voltou ao comitê'),
        expect.stringContaining('voltou ao consultor'),
      ]);

      // E o comitê decide, com as exigências mantidas na permuta.
      const decisão = await decidir({ status: 'approved' });
      expect(decisão.status).toBe(200);
      expect(decisão.body.data).toMatchObject({
        status: 'approved',
        requiresGuarantor: true,
        requiresCollateral: true,
      });
    });

    /**
     * NA SEGUNDA LEITURA o comitê pode pedir mais — e soma, não substitui: o
     * aval que a cédula já tem continua exigido.
     */
    it('as exigências se acumulam entre as rodadas', async () => {
      await exigir({ requiresGuarantor: true, note: PEDIDO });
      await preencherCedula({ guarantors: [avalista] });
      expect((await cumprir()).status).toBe(200);

      const segunda = await exigir({
        requiresCollateral: true,
        note: 'Agora também a hipoteca da sede da fazenda.',
      });
      expect(segunda.status).toBe(200);
      expect(segunda.body.data).toMatchObject({
        status: 'awaitingRequirements',
        requiresGuarantor: true,
        requiresCollateral: true,
      });
    });

    /**
     * O SEGURO SAIU DAS EXIGÊNCIAS: a apólice é da seguradora, e o seguro da
     * permuta é o da versão. Pedi-lo sozinho é não pedir nada — e a caixa nem
     * existe mais no JSON.
     */
    it('o seguro não é mais exigência do comitê', async () => {
      const resposta = await exigir({
        requiresInsurance: true,
        note: 'Apólice própria da área, cobrindo a safra.',
      });
      expect(resposta.status).toBe(422);
      expect(resposta.body.message).toBe(
        'Marque o que o comitê exige — avalista e/ou hipoteca — para devolver a permuta ao consultor',
      );
      expect((await ler(ANA)).body.data).not.toHaveProperty('requiresInsurance');
    });

    /**
     * A NEGATIVA apaga as exigências: pedir avalista de uma permuta negada é
     * pedir garantia para um negócio que não vai acontecer. O que foi pedido
     * continua na linha do tempo.
     */
    it('a negativa zera as exigências, e a linha do tempo guarda o que foi pedido', async () => {
      await exigir({ requiresGuarantor: true, note: PEDIDO });
      await preencherCedula({ guarantors: [avalista] });
      await cumprir();

      const decisão = await decidir({
        status: 'denied',
        note: 'Fora da política de risco desta safra.',
      });
      expect(decisão.status).toBe(200);
      expect(decisão.body.data).toMatchObject({
        status: 'denied',
        requiresGuarantor: false,
        requiresCollateral: false,
      });
      const pedido = (decisão.body.data.events as { action: string; note: string }[]).find(
        (linha) => linha.action === 'require',
      );
      expect(pedido?.note).toContain('Exigências: Avalista.');
    });

    /**
     * AS CAIXAS SAÍRAM DA DECISÃO: elas vêm antes, e devolvem a permuta. Uma
     * aprovação que as trouxesse seria uma aprovação condicionada a algo que
     * ninguém foi buscar — e o campo é descartado.
     */
    it('a decisão não carrega mais exigência', async () => {
      const decisão = await decidir({
        status: 'approvedWithConditions',
        note: 'Retirada só depois da confirmação do plantio.',
        requiresGuarantor: true,
      });

      expect(decisão.status).toBe(200);
      expect(decisão.body.data).toMatchObject({
        status: 'approvedWithConditions',
        requiresGuarantor: false,
        requiresCollateral: false,
      });
    });
  });
});
