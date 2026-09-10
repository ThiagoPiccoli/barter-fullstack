import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { ADMIN, COMITE, FATURISTA, GERENTE, JOAO, createTestApp, loginAs, resetDb } from './utils';

/**
 * A CREDORA — o cadastro que dá o timbre aos documentos que a empresa emite.
 *
 * O que estas provas travam:
 *
 * 1. **dois donos, de propósito**: admin E faturista. É a única capacidade que o
 *    admin divide com um posto da linha, e a razão é que a credora não decide
 *    permuta nem concede acesso — é o cabeçalho do papel timbrado, e quem
 *    percebe o CNPJ errado é quem monta a cédula;
 * 2. **cadastro único**: rota no singular, sem `:id` e sem exclusão;
 * 3. **nunca 404**: a instalação nova abre com o formulário em branco, e não com
 *    uma tela de erro.
 */
describe('Credora (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const asUser = async (email: string) => `Bearer ${await loginAs(app, email)}`;

  const read = async (auth: string) =>
    request(app.getHttpServer()).get('/api/v1/creditor').set('Authorization', auth);

  const save = async (auth: string, body: Record<string, unknown>) =>
    request(app.getHttpServer()).put('/api/v1/creditor').set('Authorization', auth).send(body);

  it('o dataset já traz a credora cadastrada', async () => {
    const resposta = await read(await asUser(ADMIN));

    expect(resposta.status).toBe(200);
    expect(resposta.body.data.name).toBe('agroBarter Cooperativa Agroindustrial Ltda.');
    expect(resposta.body.data.cnpj).toBe('12.345.678/0001-90');
    expect(resposta.body.data.gaps).toEqual([]);
  });

  /**
   * O FORO em branco é o caso NORMAL — elege-se a comarca da própria sede. Por
   * isso ele sai em dois campos: o que foi escolhido (para o formulário) e o que
   * vale (para o documento). Obrigar a redigitar a mesma cidade num segundo
   * campo só criaria a chance de os dois discordarem.
   */
  it('o foro em branco vale como a comarca da sede', async () => {
    const padrao = await read(await asUser(ADMIN));
    expect(padrao.body.data.forum).toBe('');
    expect(padrao.body.data.effectiveForum).toBe('Maringá/PR');

    const eleito = await save(await asUser(ADMIN), {
      name: 'agroBarter Cooperativa Agroindustrial Ltda.',
      cnpj: '12.345.678/0001-90',
      address: 'Avenida Colombo',
      addressNumber: '4750',
      city: 'Maringá/PR',
      forum: 'Curitiba/PR',
    });
    expect(eleito.body.data.forum).toBe('Curitiba/PR');
    expect(eleito.body.data.effectiveForum).toBe('Curitiba/PR');
  });

  /**
   * A DIVISÃO DA CANETA. O faturista escreve o cadastro junto com o admin — e
   * este teste é o que impede a linha de sumir de policy.ts sem alguém notar.
   */
  it('o faturista mantém o cadastro, junto com o admin', async () => {
    const salvo = await save(await asUser(FATURISTA), {
      name: 'agroBarter Cooperativa Agroindustrial Ltda.',
      cnpj: '98.765.432/0001-10',
      address: 'Avenida Colombo',
      addressNumber: '4750',
      city: 'Maringá/PR',
    });

    expect(salvo.status).toBe(200);
    expect(salvo.body.data.cnpj).toBe('98.765.432/0001-10');
    // Com dois donos, "quem mexeu?" é pergunta que aparece — e a linha responde.
    expect(salvo.body.data.updatedBy).toBe('Patrícia Lemos');
  });

  /**
   * Os OUTROS TRÊS não escrevem, e nem leem. O comitê decide permuta, o gerente
   * opina sobre o time dele e o consultor registra — nenhum dos três emite
   * documento em nome da empresa.
   */
  it('comitê, gerente e consultor não alcançam o cadastro', async () => {
    for (const email of [COMITE, GERENTE, JOAO]) {
      const leitura = await read(await asUser(email));
      expect([email, leitura.status]).toEqual([email, 403]);

      const escrita = await save(await asUser(email), { name: 'Outra Empresa' });
      expect([email, escrita.status]).toEqual([email, 403]);
    }
  });

  /**
   * Instalação NOVA: ninguém cadastrou nada ainda. A resposta é o vazio, e não
   * um 404 — a ausência do cadastro é o estado inicial, e devolver "não
   * encontrado" transformaria o primeiro dia de uso numa tela de erro.
   */
  it('sem cadastro nenhum, a leitura devolve o vazio com as pendências', async () => {
    await app.get(PrismaService).creditor.deleteMany();

    const resposta = await read(await asUser(ADMIN));
    expect(resposta.status).toBe(200);
    expect(resposta.body.data.name).toBe('');
    expect(resposta.body.data.gaps).toEqual([
      'razão social',
      'CNPJ',
      'logradouro da sede',
      'número do endereço',
      'cidade/UF',
    ]);
  });

  /** O cadastro é UM. Não há rota com `:id`, nem exclusão. */
  it('não existe segunda credora, nem exclusão', async () => {
    const admin = await asUser(ADMIN);
    const comId = await request(app.getHttpServer())
      .put('/api/v1/creditor/2')
      .set('Authorization', admin)
      .send({ name: 'Outra' });
    expect(comId.status).toBe(404);

    const excluir = await request(app.getHttpServer())
      .delete('/api/v1/creditor')
      .set('Authorization', admin);
    expect(excluir.status).toBe(404);
  });

  /**
   * O campo AUSENTE vira vazio aqui, ao contrário do rascunho da cédula — e a
   * diferença é o formulário: este é curto, mostrado inteiro, lido de cima a
   * baixo antes de salvar. Preservar o ausente tornaria impossível APAGAR um
   * foro eleito que deixou de valer.
   */
  it('salvar sem um campo o apaga — é formulário inteiro, não rascunho', async () => {
    const admin = await asUser(ADMIN);
    await save(admin, { name: 'Empresa', cnpj: '00.000.000/0001-00', forum: 'Curitiba/PR' });

    const semForo = await save(admin, { name: 'Empresa', cnpj: '00.000.000/0001-00' });
    expect(semForo.body.data.forum).toBe('');
  });

  /**
   * A trilha registra a mudança pelo mesmo critério dos atos que decidem
   * dinheiro: um CNPJ trocado aqui vale para todas as cédulas emitidas daí em
   * diante, e a linha do tempo da permuta não alcança isto — ela é do registro,
   * e a credora é global.
   */
  it('mexer na credora deixa rastro na trilha', async () => {
    await save(await asUser(FATURISTA), {
      name: 'agroBarter Cooperativa Agroindustrial Ltda.',
      cnpj: '98.765.432/0001-10',
      city: 'Maringá/PR',
    });

    const trilha = await request(app.getHttpServer())
      .get('/api/v1/audit-logs?action=creditor.updated')
      .set('Authorization', await asUser(ADMIN));

    expect(trilha.status).toBe(200);
    expect(trilha.body.data[0].actorName).toBe('Patrícia Lemos');
    expect(trilha.body.data[0].detail).toContain('98.765.432/0001-10');
  });
});
