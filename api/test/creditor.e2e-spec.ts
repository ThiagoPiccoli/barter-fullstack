import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import {
  ADMIN,
  COMITE,
  EMISSOR,
  FATURISTA,
  GERENTE,
  JOAO,
  createTestApp,
  loginAs,
  resetDb,
} from './utils';

/**
 * A CREDORA — o cadastro que dá o timbre aos documentos que a empresa emite.
 *
 * O que estas provas travam:
 *
 * 1. **dois donos, de propósito**: admin E EMISSOR. É a única capacidade que o
 *    admin divide com um posto da linha, e a razão é que a credora não decide
 *    permuta nem concede acesso — é o cabeçalho do papel timbrado, e quem
 *    percebe o CNPJ errado é quem leva o título a registro. Ela já foi do
 *    FATURISTA, e mudou de mãos junto com a cédula: o timbre segue quem emite o
 *    papel, não quem emite a nota;
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
   * A DIVISÃO DA CANETA. O emissor escreve o cadastro junto com o admin — e este
   * teste é o que impede a linha de sumir de policy.ts sem alguém notar.
   */
  it('o emissor mantém o cadastro, junto com o admin', async () => {
    const salvo = await save(await asUser(EMISSOR), {
      name: 'agroBarter Cooperativa Agroindustrial Ltda.',
      cnpj: '98.765.432/0001-10',
      address: 'Avenida Colombo',
      addressNumber: '4750',
      city: 'Maringá/PR',
    });

    expect(salvo.status).toBe(200);
    expect(salvo.body.data.cnpj).toBe('98.765.432/0001-10');
    // Com dois donos, "quem mexeu?" é pergunta que aparece — e a linha responde.
    expect(salvo.body.data.updatedBy).toBe('Renata Bicudo');
  });

  /**
   * Os OUTROS QUATRO não escrevem, e nem leem. O comitê decide permuta, o
   * gerente opina sobre o time dele, o consultor registra e o FATURISTA fatura —
   * nenhum dos quatro emite o título em nome da empresa.
   *
   * O faturista está nesta lista desde que a cédula saiu das mãos dele, e a
   * presença dele aqui é o que trava a mudança: devolver-lhe `creditor.manage`
   * quebra este teste.
   */
  it('comitê, gerente, consultor e faturista não alcançam o cadastro', async () => {
    for (const email of [COMITE, GERENTE, JOAO, FATURISTA]) {
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
    await save(await asUser(EMISSOR), {
      name: 'agroBarter Cooperativa Agroindustrial Ltda.',
      cnpj: '98.765.432/0001-10',
      city: 'Maringá/PR',
    });

    const trilha = await request(app.getHttpServer())
      .get('/api/v1/audit-logs?action=creditor.updated')
      .set('Authorization', await asUser(ADMIN));

    expect(trilha.status).toBe(200);
    expect(trilha.body.data[0].actorName).toBe('Renata Bicudo');
    expect(trilha.body.data[0].detail).toContain('98.765.432/0001-10');
  });

  /**
   * A MARGEM DE SEGURANÇA DO PENHOR — a exceção da tela da credora, e a razão de
   * ela existir.
   *
   * Tudo o mais neste cadastro é TIMBRE: razão social, CNPJ, endereço, foro. Nada
   * disso decide nada, e é por isso que o emissor escreve — ele é quem percebe o
   * dígito errado ao levar o título a registro. A margem é de outra natureza: ela
   * diz quanta terra a empresa exige em garantia de TODA permuta registrada dali
   * em diante. Baixá-la de 20% para 10% corta a garantia pela metade.
   *
   * Ela chegou dentro do `CreditorDto` porque o número é da empresa e esta é a
   * linha da empresa — e com isso o emissor ganhou, sem que ninguém decidisse,
   * a caneta de uma política de risco. A correção foi separar por AUTORIDADE: rota
   * própria, capacidade própria (`pledge.policy`), só do admin.
   */
  describe('a margem de segurança do penhor', () => {
    const setMargin = async (auth: string, pledgeMarginPercent: unknown) =>
      request(app.getHttpServer())
        .put('/api/v1/creditor/pledge-margin')
        .set('Authorization', auth)
        .send({ pledgeMarginPercent });

    it('o admin define a margem, e ela volta no cadastro', async () => {
      const admin = await asUser(ADMIN);
      expect((await read(admin)).body.data.pledgeMarginPercent).toBe(20);

      const salvo = await setMargin(admin, 35);
      expect(salvo.status).toBe(200);
      expect(salvo.body.data.pledgeMarginPercent).toBe(35);
      expect((await read(admin)).body.data.pledgeMarginPercent).toBe(35);
    });

    /**
     * O EMISSOR É O PONTO DESTE ARQUIVO. Ele mantém o cadastro — é o único posto
     * da linha que divide `creditor.manage` com o admin — e mesmo assim não toca
     * na margem. As duas asserções juntas são a regra: o timbre sim, o risco não.
     */
    it('o emissor mantém o cadastro e NÃO mexe na margem', async () => {
      const emissor = await asUser(EMISSOR);

      // O timbre é dele: lê e escreve.
      expect((await read(emissor)).status).toBe(200);
      const timbre = await request(app.getHttpServer())
        .put('/api/v1/creditor')
        .set('Authorization', emissor)
        .send({ name: 'agroBarter Cooperativa Agroindustrial Ltda.', cnpj: '12.345.678/0001-90' });
      expect(timbre.status).toBe(200);

      // O risco não é.
      expect((await setMargin(emissor, 0)).status).toBe(403);

      // E a tentativa não deixou rastro no número: ele continua o que o admin
      // definiu. É a metade que importa — um 403 que já tivesse gravado seria pior
      // do que nenhuma trava.
      expect((await read(emissor)).body.data.pledgeMarginPercent).toBe(20);
    });

    /**
     * A MARGEM NÃO ENTRA MAIS PELA PORTA DO CADASTRO, e este é o teste que impede
     * o campo de voltar ao `CreditorDto` sem alguém decidir isso: o `whitelist` do
     * ValidationPipe descarta o que o DTO não declara, então mandá-la ali é um
     * no-op silencioso — e não uma porta dos fundos.
     */
    it('mandar a margem no corpo do cadastro não a muda', async () => {
      const emissor = await asUser(EMISSOR);
      const resposta = await request(app.getHttpServer())
        .put('/api/v1/creditor')
        .set('Authorization', emissor)
        .send({ name: 'agroBarter', cnpj: '12.345.678/0001-90', pledgeMarginPercent: 0 });

      expect(resposta.status).toBe(200);
      expect(resposta.body.data.pledgeMarginPercent).toBe(20);
    });

    it('margem negativa ou acima de 100% é recusada', async () => {
      const admin = await asUser(ADMIN);
      // 422, e não 400: é a resposta que este servidor dá a corpo que chega bem
      // formado e com valor inaceitável. Ver o ValidationPipe em app.setup.ts.
      expect((await setMargin(admin, -5)).status).toBe(422);
      expect((await setMargin(admin, 101)).status).toBe(422);
      // Zero é resposta legítima: a credora que não exige folga nenhuma.
      expect((await setMargin(admin, 0)).status).toBe(200);
    });

    /**
     * A MUDANÇA ENTRA NA TRILHA com o DE-PARA, e não só com o valor novo.
     *
     * Ela não reescreve permuta já registrada (a margem é congelada no ato do
     * registro), então a pergunta que alguém vai trazer aqui é "desde quando
     * passamos a exigir menos terra?" — e ela só se responde com a data e os dois
     * números lado a lado.
     */
    it('mudar a margem entra na trilha, com o de-para', async () => {
      const admin = await asUser(ADMIN);
      await setMargin(admin, 30);

      const trilha = await request(app.getHttpServer())
        .get('/api/v1/audit-logs?action=creditor.pledge-margin-changed')
        .set('Authorization', admin);

      expect(trilha.status).toBe(200);
      expect(trilha.body.data).toHaveLength(1);
      expect(trilha.body.data[0].detail).toContain('20% → 30%');

      // Reenviar o MESMO número não gera linha: a trilha guarda atos, e não
      // cliques em "salvar".
      await setMargin(admin, 30);
      const depois = await request(app.getHttpServer())
        .get('/api/v1/audit-logs?action=creditor.pledge-margin-changed')
        .set('Authorization', admin);
      expect(depois.body.data).toHaveLength(1);
    });
  });
});
