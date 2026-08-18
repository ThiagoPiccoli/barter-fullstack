import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import {
  ADMIN,
  COMITE,
  GERENTE,
  GERENTE_SUL,
  JOAO,
  UNIT,
  createTestApp,
  loginAs,
  resetDb,
} from './utils';

/**
 * As UNIDADES de retirada — e, principalmente, o que elas NÃO são.
 *
 * A unidade é um lugar: onde o produtor busca os insumos. Ela não tem
 * responsável, não escolhe quem analisa a permuta e não trava nada. Metade
 * destes testes existe para prender essa ausência, porque ela é fácil de perder
 * de vista: "unidade" e "gerente" aparecem juntos no fluxo o tempo todo, e o
 * erro natural é amarrar um ao outro.
 *
 * O que ela resolve é o que o texto livre não resolvia: "Filial 02" e
 * "FILIAL 02" eram dois lugares em qualquer lista.
 */
describe('Unidades (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const asUser = async (email: string) => `Bearer ${await loginAs(app, email)}`;
  const nova = { name: 'Filial 45 – Gran. Ivaí', city: 'Ivaiporã/PR' };

  it('a lista é de todo mundo: o consultor precisa dela para escolher a retirada', async () => {
    for (const email of [ADMIN, JOAO, GERENTE, COMITE]) {
      const response = await request(app.getHttpServer())
        .get('/api/v1/units')
        .set('Authorization', await asUser(email));
      expect(response.status).toBe(200);
      expect(response.body.data).toHaveLength(6);
    }
  });

  /**
   * A unidade é um LOCAL. Se um dia alguém acrescentar um responsável a ela, é
   * aqui que a decisão aparece — e ela precisa ser tomada de propósito, porque
   * o fluxo inteiro assume que quem analisa a permuta é o gerente do consultor.
   */
  it('a unidade não tem responsável — ela é um local, não uma alçada', async () => {
    const response = await request(app.getHttpServer())
      .get('/api/v1/units')
      .set('Authorization', await asUser(JOAO));

    for (const unit of response.body.data) {
      expect(Object.keys(unit).sort()).toEqual(
        ['id', 'name', 'city', 'createdAt', 'initials'].sort(),
      );
    }
  });

  it('só o admin cadastra unidade', async () => {
    for (const email of [JOAO, GERENTE, COMITE]) {
      const response = await request(app.getHttpServer())
        .post('/api/v1/units')
        .set('Authorization', await asUser(email))
        .send(nova);
      expect(response.status).toBe(403);
    }

    const admin = await request(app.getHttpServer())
      .post('/api/v1/units')
      .set('Authorization', await asUser(ADMIN))
      .send(nova);
    expect(admin.status).toBe(201);
    expect(admin.body.data.name).toBe(nova.name);
  });

  /**
   * "Filial 02" e "FILIAL  02" viravam duas unidades, e a mesma praça aparecia
   * duas vezes na hora de escolher onde retirar.
   */
  it('nome repetido é recusado, mesmo escrito com outra caixa ou espaçamento', async () => {
    const admin = await asUser(ADMIN);
    for (const name of ['Matriz', 'MATRIZ', '  matriz  ']) {
      const response = await request(app.getHttpServer())
        .post('/api/v1/units')
        .set('Authorization', admin)
        .send({ name, city: 'Maringá/PR' });
      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Matriz');
    }
  });

  /**
   * A prova de que a unidade não participa do fluxo: excluir a de retirada de
   * uma permuta que ainda espera parecer não muda nada da etapa do gerente.
   */
  it('excluir a unidade preserva as permutas dela e não mexe na fila do gerente', async () => {
    const admin = await asUser(ADMIN);

    // PRM-2026-005 espera o parecer da Beatriz e é retirada na Filial 02.
    await request(app.getHttpServer())
      .delete(`/api/v1/units/${UNIT.filial02}`)
      .set('Authorization', admin)
      .expect(204);

    const barter = await request(app.getHttpServer())
      .get('/api/v1/barters/PRM-2026-005')
      .set('Authorization', admin);
    expect(barter.status).toBe(200);
    // O vínculo cai, o nome congelado fica — o comprovante continua legível.
    expect(barter.body.data.unitId).toBeNull();
    expect(barter.body.data.unitName).toBe('Filial 02 – Gran. Santa T.');
    expect(barter.body.data.status).toBe('sentToManager');

    // E a etapa do gerente segue exatamente como estava.
    await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-005/opinion')
      .set('Authorization', await asUser(GERENTE))
      .send({ note: 'Estoque conferido, pode seguir para análise.' })
      .expect(200);
  });

  it('a troca de nome deixa rastro na trilha', async () => {
    const admin = await asUser(ADMIN);
    await request(app.getHttpServer())
      .put(`/api/v1/units/${UNIT.filial02}`)
      .set('Authorization', admin)
      .send({ name: 'Filial 02 – Santa Terezinha', city: 'Sarandi/PR' })
      .expect(200);

    const trilha = await request(app.getHttpServer())
      .get('/api/v1/audit-logs?action=unit.updated')
      .set('Authorization', admin);
    expect(trilha.body.data).toHaveLength(1);
    expect(trilha.body.data[0].detail).toBe(
      'nome: Filial 02 – Gran. Santa T. → Filial 02 – Santa Terezinha',
    );
  });

  /**
   * O cadastro de usuário deixou de aceitar filial digitada: ele aponta uma
   * unidade que existe, e é dela que o rótulo `branch` sai.
   */
  it('o usuário nasce em uma unidade — e o rótulo dela vem do cadastro, não do payload', async () => {
    const admin = await asUser(ADMIN);

    const invalida = await request(app.getHttpServer())
      .post('/api/v1/consultants')
      .set('Authorization', admin)
      .send({
        fullName: 'Sem Unidade',
        email: 'sem.unidade@agrobarter.com.br',
        unitId: 999,
        managerId: 7,
      });
    expect(invalida.status).toBe(422);
    expect(invalida.body.message).toContain('unidade');

    const criado = await request(app.getHttpServer())
      .post('/api/v1/consultants')
      .set('Authorization', admin)
      .send({
        fullName: 'Consultor Novo',
        email: 'consultor.novo@agrobarter.com.br',
        unitId: UNIT.filial18,
        managerId: 7,
      });
    expect(criado.status).toBe(201);
    expect(criado.body.data.unitId).toBe(UNIT.filial18);
    expect(criado.body.data.branch).toBe('Filial 18 – Gran. São Joa.');
  });

  /**
   * A LOTAÇÃO e o TIME são coisas diferentes, e o dataset já as separa: Roberto
   * trabalha na Filial 34 e é gerenciado pelo Gustavo; Ana trabalha na Filial
   * 04 e é gerenciada pela Beatriz. Nada obriga as duas a coincidirem — e este
   * teste existe para que uma "simplificação" futura não as junte.
   */
  it('a unidade da pessoa não decide quem a gerencia', async () => {
    const consultores = await request(app.getHttpServer())
      .get('/api/v1/consultants')
      .set('Authorization', await asUser(ADMIN));

    const porNome = new Map(
      consultores.body.data.map((u: { fullName: string }) => [u.fullName, u]),
    );
    const roberto = porNome.get('Roberto Souza') as { branch: string; managerName: string };
    const ana = porNome.get('Ana Paula Ferreira') as { branch: string; managerName: string };

    expect(roberto.branch).toBe('Filial 34 – Gran. Jari');
    expect(roberto.managerName).toBe('Gustavo Ramires');
    expect(ana.branch).toBe('Filial 04 – Gran. Inharap.');
    expect(ana.managerName).toBe('Beatriz Nogueira');
  });

  /**
   * O consultor manda a retirada para onde o produtor combinou. A permuta
   * continua sendo do gerente DELE — a unidade não muda o destinatário.
   */
  it('retirada em qualquer praça não muda de quem é o parecer', async () => {
    const criada = await request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', await asUser(JOAO))
      .send({
        producerId: 1,
        unitId: UNIT.filial34, // praça do Gustavo, consultor é do time da Beatriz
        inputs: [
          { productId: 5, quantity: 48 },
          { productId: 6, quantity: 300 },
          { productId: 7, quantity: 18 },
        ],
      });
    expect(criada.status).toBe(201);
    expect(criada.body.data.unitName).toBe('Filial 34 – Gran. Jari');
    expect(criada.body.data.managerName).toBe('Beatriz Nogueira');

    const code = criada.body.data.code as string;
    await request(app.getHttpServer())
      .post(`/api/v1/barters/${code}/opinion`)
      .set('Authorization', await asUser(GERENTE_SUL))
      .send({ note: 'A retirada é aqui, mas o consultor não é do meu time.' })
      .expect(403);

    await request(app.getHttpServer())
      .post(`/api/v1/barters/${code}/opinion`)
      .set('Authorization', await asUser(GERENTE))
      .send({ note: 'Consultor do meu time; retirada combinada em outra praça.' })
      .expect(200);
  });
});
