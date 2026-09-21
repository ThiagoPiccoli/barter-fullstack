import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import {
  ADMIN,
  ANA,
  COMITE,
  EMISSOR,
  FATURISTA,
  GERENTE,
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
 * E o que a reunião exigia ("com aval", "condicionada a garantia real") saía
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
 * 4. **as exigências são campos** — avalista, garantia real e seguro deixam de
 *    ser interpretação de parágrafo;
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
      expect(
        resposta.body.data.creditFiles.map((peça: { kindLabel: string }) => peça.kindLabel),
      ).toEqual(['Consulta ao Serasa', 'Endividamento na cooperativa']);
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
    it('o admin não junta peça ao dossiê', async () => {
      const resposta = await anexar(await asUser(ADMIN));
      expect(resposta.status).toBe(403);
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

  /* ── As exigências da decisão ──────────────────────────────────────── */

  describe('as exigências do comitê', () => {
    const decidir = async (body: object) =>
      request(app.getHttpServer())
        .post(`/api/v1/barters/${CODE}/review`)
        .set('Authorization', await asUser(COMITE))
        .send(body);

    /**
     * AVALISTA, GARANTIA E SEGURO — as três se acumulam, e é por isso que são
     * três campos e não um tipo de ressalva: a mesma decisão pede duas delas com
     * frequência, e um campo único obrigaria a eleger a principal.
     */
    it('a ressalva carrega o que foi exigido, e o texto diz qual', async () => {
      const ressalva =
        'Exigir aval do cônjuge e garantia real sobre a matrícula 12.345 antes da retirada.';
      const decisão = await decidir({
        status: 'approvedWithConditions',
        note: ressalva,
        requiresGuarantor: true,
        requiresCollateral: true,
      });

      expect(decisão.status).toBe(200);
      expect(decisão.body.data).toMatchObject({
        status: 'approvedWithConditions',
        reviewNote: ressalva,
        requiresGuarantor: true,
        requiresCollateral: true,
        requiresInsurance: false,
      });

      // ELAS VÃO PARA QUEM VAI TER DE CUMPRI-LAS: a consultora que levou a
      // permuta lê a exigência na tela, e não num parágrafo.
      const daConsultora = await ler(ANA);
      expect(daConsultora.body.data.requiresGuarantor).toBe(true);
      expect(daConsultora.body.data.requiresCollateral).toBe(true);
    });

    /**
     * NA LINHA DO TEMPO elas ficam por escrito, e não só nas colunas da permuta:
     * o aceite de um pedido de alteração devolve a permuta a rascunho e apaga a
     * decisão atual, exigências inclusive. Sem isto, "o que o comitê exigiu da
     * primeira vez?" não teria resposta depois da segunda decisão.
     */
    it('o evento da decisão guarda as exigências por extenso', async () => {
      await decidir({
        status: 'approvedWithConditions',
        note: 'Exigir seguro agrícola da área plantada.',
        requiresInsurance: true,
      });

      const detalhe = await ler(COMITE);
      const evento = (detalhe.body.data.events as { action: string; note: string }[])
        .filter((linha) => linha.action === 'review')
        .pop();
      expect(evento?.note).toContain('Exigir seguro agrícola da área plantada.');
      expect(evento?.note).toContain('Exigências: Seguro.');
    });

    /**
     * A NEGATIVA NÃO EXIGE NADA. Pedir avalista de uma permuta negada é pedir
     * garantia para um negócio que não vai acontecer — e a exigência ficaria
     * pendurada na tela de quem levou a negativa ao produtor.
     */
    it('a negativa zera as exigências, mesmo se elas vierem marcadas', async () => {
      const decisão = await decidir({
        status: 'denied',
        note: 'Fora da política de risco desta safra.',
        requiresGuarantor: true,
        requiresCollateral: true,
        requiresInsurance: true,
      });

      expect(decisão.status).toBe(200);
      expect(decisão.body.data).toMatchObject({
        status: 'denied',
        requiresGuarantor: false,
        requiresCollateral: false,
        requiresInsurance: false,
      });
    });

    /** A aprovação limpa continua limpa: sem texto obrigatório e sem exigência. */
    it('a aprovação sem ressalva não exige nada', async () => {
      const decisão = await decidir({ status: 'approved' });

      expect(decisão.status).toBe(200);
      expect(decisão.body.data).toMatchObject({
        requiresGuarantor: false,
        requiresCollateral: false,
        requiresInsurance: false,
      });
    });
  });
});
