import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import {
  ADMIN,
  BACK_OFFICE,
  COMITE,
  JOAO,
  MANAGER,
  UNIT,
  createTestApp,
  loginAs,
  resetDb,
} from './utils';

/**
 * As rotas de provisionamento — uma por papel.
 *
 * O que estes testes protegem é a promessa de ter separado as rotas: cada uma
 * enxerga e altera SÓ o próprio papel. Um motor compartilhado que recebesse o
 * papel errado (ou nenhum) transformaria `/billers/:id` numa porta para
 * qualquer usuário do sistema — o oposto do que a separação existe para dar.
 *
 * Três delas cadastram PESSOAS e são plurais. A do comitê cadastra um ÓRGÃO — é
 * uma reunião, e a conta é uma só —, então ela é singular e tem um bloco
 * próprio no fim deste arquivo.
 */
describe('Usuários — uma rota por papel (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const asUser = async (email: string) => `Bearer ${await loginAs(app, email)}`;
  const admin = () => asUser(ADMIN);

  /** As rotas de PESSOAS e o papel que cada uma gerencia, com um id do seed. */
  const ROUTES = [
    { path: 'consultants', role: 'consultant', seedId: 2 }, // João
    { path: 'managers', role: 'manager', seedId: 7 }, // Beatriz
    { path: 'billers', role: 'biller', seedId: 9 }, // Patrícia
  ];

  /** O id da conta do comitê no seed — o alvo "de papel alheio" das outras rotas. */
  const COMITE_ID = 8;

  const novoUsuario = (email: string) => ({
    fullName: 'Pessoa Nova',
    email,
    unitId: UNIT.matriz,
    // Só a rota de consultor declara `managerId`; nas outras três o whitelist
    // do ValidationPipe o descarta, que é justamente o que se quer provar.
    managerId: MANAGER.beatriz,
  });

  it('cada rota lista apenas o próprio papel', async () => {
    const auth = await admin();
    for (const route of ROUTES) {
      const response = await request(app.getHttpServer())
        .get(`/api/v1/${route.path}`)
        .set('Authorization', auth);
      expect(response.status).toBe(200);
      expect(response.body.data.length).toBeGreaterThan(0);
      expect(response.body.data.map((u: { role: string }) => u.role)).toEqual(
        Array(response.body.data.length).fill(route.role),
      );
    }
  });

  it('cada rota cria com o papel DELA', async () => {
    const auth = await admin();
    for (const route of ROUTES) {
      const response = await request(app.getHttpServer())
        .post(`/api/v1/${route.path}`)
        .set('Authorization', auth)
        .send(novoUsuario(`novo.${route.role}@agrobarter.com.br`));
      expect(response.status).toBe(201);
      expect(response.body.data.role).toBe(route.role);
      expect(response.body.data.mustChangePassword).toBe(true);
      expect(response.body.data.provisionalPassword).toEqual(expect.any(String));
    }
  });

  /**
   * O papel vem da ROTA. Se viesse do corpo, `POST /billers` com
   * `"role": "admin"` seria uma escalada de privilégio ao alcance de qualquer
   * admin distraído — e de qualquer um que roubasse a sessão de um.
   */
  it('`role` no corpo é ignorado: a rota é que decide o papel', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/billers')
      .set('Authorization', await admin())
      .send({ ...novoUsuario('tentativa@agrobarter.com.br'), role: 'admin' });
    expect(response.status).toBe(201);
    expect(response.body.data.role).toBe('biller');
  });

  it('nenhuma rota alcança usuário de papel alheio', async () => {
    const auth = await admin();
    for (const route of ROUTES) {
      // Os ids dos OUTROS papéis, que esta rota não pode tocar — o do comitê
      // inclusive: ele não tem rota com `:id`, e nenhuma das outras o alcança.
      const alheios = [
        ...ROUTES.filter((r) => r.path !== route.path).map((r) => r.seedId),
        COMITE_ID,
      ];
      for (const id of alheios) {
        const put = await request(app.getHttpServer())
          .put(`/api/v1/${route.path}/${id}`)
          .set('Authorization', auth)
          .send(novoUsuario('qualquer@agrobarter.com.br'));
        expect(put.status).toBe(404);

        const reset = await request(app.getHttpServer())
          .post(`/api/v1/${route.path}/${id}/reset-password`)
          .set('Authorization', auth);
        expect(reset.status).toBe(404);

        const del = await request(app.getHttpServer())
          .delete(`/api/v1/${route.path}/${id}`)
          .set('Authorization', auth);
        expect(del.status).toBe(404);
      }
    }
  });

  /** Não existe rota que crie ou gerencie admin — nem por um id. Ver ManagedRole. */
  it('o admin (id 1) não é gerenciado por nenhuma das rotas', async () => {
    const auth = await admin();
    for (const route of ROUTES) {
      await request(app.getHttpServer())
        .post(`/api/v1/${route.path}/1/reset-password`)
        .set('Authorization', auth)
        .expect(404);
      await request(app.getHttpServer())
        .delete(`/api/v1/${route.path}/1`)
        .set('Authorization', auth)
        .expect(404);
    }
  });

  it('e-mail é único entre papéis diferentes — o login não sabe de papel', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/managers')
      .set('Authorization', await admin())
      .send(novoUsuario(JOAO)); // e-mail de um consultor
    expect(response.status).toBe(422);
    expect(response.body.message).toContain('já está em uso');
  });

  it('provisionar → entrar com a provisória → trocar a senha, em qualquer papel', async () => {
    for (const route of ROUTES) {
      const email = `ciclo.${route.role}@agrobarter.com.br`;
      const created = await request(app.getHttpServer())
        .post(`/api/v1/${route.path}`)
        .set('Authorization', await admin())
        .send(novoUsuario(email));
      const provisoria = created.body.data.provisionalPassword as string;

      const login = await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email, password: provisoria });
      expect(login.status).toBe(200);
      expect(login.body.data.user.mustChangePassword).toBe(true);

      const auth = { Authorization: `Bearer ${login.body.data.token}` };

      // Com a senha ainda provisória, a API inteira está fechada.
      await request(app.getHttpServer()).get('/api/v1/barters').set(auth).expect(403);

      await request(app.getHttpServer())
        .post('/api/v1/auth/password')
        .set(auth)
        // Não pode conter o nome de quem escolhe (fullName é "Pessoa Nova"),
        // então nada de "…-nova-…": ver src/auth/password-policy.ts.
        .send({ currentPassword: provisoria, newPassword: 'trilha-do-cerrado-9' })
        .expect(200);

      // E agora entra, no papel que a rota deu.
      const me = await request(app.getHttpServer()).get('/api/v1/me').set(auth);
      expect(me.status).toBe(200);
      expect(me.body.data.role).toBe(route.role);
      expect(me.body.data.mustChangePassword).toBe(false);
    }
  });

  it('reset derruba as sessões abertas do titular, em qualquer papel', async () => {
    for (const route of ROUTES) {
      const email = `reset.${route.role}@agrobarter.com.br`;
      const created = await request(app.getHttpServer())
        .post(`/api/v1/${route.path}`)
        .set('Authorization', await admin())
        .send(novoUsuario(email));
      const id = created.body.data.id as number;

      const login = await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email, password: created.body.data.provisionalPassword });
      const auth = { Authorization: `Bearer ${login.body.data.token}` };

      await request(app.getHttpServer())
        .post(`/api/v1/${route.path}/${id}/reset-password`)
        .set('Authorization', await admin())
        .expect(200);

      await request(app.getHttpServer()).get('/api/v1/me').set(auth).expect(401);
    }
  });

  it('provisionar usuário é do admin: consultor e retaguarda levam 403', async () => {
    for (const email of [JOAO, ...BACK_OFFICE]) {
      const auth = await asUser(email);
      for (const route of ROUTES) {
        await request(app.getHttpServer())
          .get(`/api/v1/${route.path}`)
          .set('Authorization', auth)
          .expect(403);
        await request(app.getHttpServer())
          .post(`/api/v1/${route.path}`)
          .set('Authorization', auth)
          .send(novoUsuario('intruso@agrobarter.com.br'))
          .expect(403);
      }
      await request(app.getHttpServer())
        .get('/api/v1/committee')
        .set('Authorization', auth)
        .expect(403);
    }
  });

  /**
   * O COMITÊ É UM CADASTRO SÓ — porque ele é uma REUNIÃO, não uma pessoa.
   *
   * É a diferença que estes testes existem para segurar. Com uma conta por
   * integrante, a decisão do colegiado sairia assinada por um nome, entrar no
   * comitê viraria cadastro de usuário e a operação poderia acabar com dois
   * órgãos decidindo a mesma fila sem saber um do outro.
   */
  describe('o comitê é um cadastro só', () => {
    const novoComite = {
      fullName: 'Comitê de Permutas',
      email: 'comite.novo@agrobarter.com.br',
      unitId: UNIT.matriz,
    };

    /** Tira o comitê do banco — o estado de um sistema recém-instalado. */
    const semComite = async () => {
      await app.get(PrismaService).user.deleteMany({ where: { role: 'committee' } });
    };

    it('a rota é singular: não há `:id`, e não há como excluir', async () => {
      const auth = await admin();
      // Não existe rota com id — nem para editar, nem para apagar.
      await request(app.getHttpServer())
        .put(`/api/v1/committee/${COMITE_ID}`)
        .set('Authorization', auth)
        .send(novoComite)
        .expect(404);
      await request(app.getHttpServer())
        .delete('/api/v1/committee')
        .set('Authorization', auth)
        .expect(404);
      await request(app.getHttpServer())
        .delete(`/api/v1/committee/${COMITE_ID}`)
        .set('Authorization', auth)
        .expect(404);
    });

    it('sem cadastro, a resposta é vazia — não é erro, é o primeiro dia', async () => {
      await semComite();
      const response = await request(app.getHttpServer())
        .get('/api/v1/committee')
        .set('Authorization', await admin());
      expect(response.status).toBe(200);
      expect(response.body.data).toBeNull();
    });

    it('o admin cadastra o comitê uma vez, e a segunda é recusada', async () => {
      await semComite();
      const auth = await admin();

      const criado = await request(app.getHttpServer())
        .post('/api/v1/committee')
        .set('Authorization', auth)
        .send(novoComite);
      expect(criado.status).toBe(201);
      expect(criado.body.data.role).toBe('committee');
      expect(criado.body.data.fullName).toBe('Comitê de Permutas');
      expect(criado.body.data.provisionalPassword).toEqual(expect.any(String));

      // A UNICIDADE é do PAPEL, não do e-mail: outro endereço não abre exceção.
      const segundo = await request(app.getHttpServer())
        .post('/api/v1/committee')
        .set('Authorization', auth)
        .send({ ...novoComite, email: 'outro.comite@agrobarter.com.br' });
      expect(segundo.status).toBe(422);
      expect(segundo.body.message).toContain('único');

      const lista = await request(app.getHttpServer())
        .get('/api/v1/committee')
        .set('Authorization', auth);
      expect(lista.body.data.email).toBe(novoComite.email);
    });

    /** O que o admin cadastra é o que ENTRA — e decide. */
    it('o comitê recém-cadastrado entra e decide a permuta', async () => {
      await semComite();
      const criado = await request(app.getHttpServer())
        .post('/api/v1/committee')
        .set('Authorization', await admin())
        .send(novoComite);
      const provisoria = criado.body.data.provisionalPassword as string;

      const login = await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: novoComite.email, password: provisoria });
      expect(login.status).toBe(200);
      expect(login.body.data.user.role).toBe('committee');
      // A senha da reunião nasce provisória, como a de qualquer conta nova.
      expect(login.body.data.user.mustChangePassword).toBe(true);

      const auth = { Authorization: `Bearer ${login.body.data.token}` };
      await request(app.getHttpServer())
        .post('/api/v1/auth/password')
        .set(auth)
        .send({ currentPassword: provisoria, newPassword: 'trilha-do-cerrado-9' })
        .expect(200);

      // E aí sim ele decide — e a permuta sai assinada pelo ÓRGÃO.
      const decisão = await request(app.getHttpServer())
        .post('/api/v1/barters/PRM-2026-002/review')
        .set(auth)
        .send({ status: 'approved', note: 'Ata da reunião de 12/05: aprovada por unanimidade.' });
      expect(decisão.status).toBe(200);
      expect(decisão.body.data.reviewedBy).toBe('Comitê de Permutas');
    });

    it('o cadastro se corrige sem id, e a senha se redefine derrubando as sessões', async () => {
      const auth = await admin();
      const token = await loginAs(app, COMITE);

      const editado = await request(app.getHttpServer())
        .put('/api/v1/committee')
        .set('Authorization', auth)
        .send({ ...novoComite, fullName: 'Comitê de Crédito e Permutas' });
      expect(editado.status).toBe(200);
      expect(editado.body.data.fullName).toBe('Comitê de Crédito e Permutas');

      const redefinida = await request(app.getHttpServer())
        .post('/api/v1/committee/reset-password')
        .set('Authorization', auth);
      expect(redefinida.status).toBe(200);
      expect(redefinida.body.data.provisionalPassword).toEqual(expect.any(String));

      // A senha circula entre quem participa da reunião: trocá-la precisa
      // expulsar quem estava dentro, senão o reset não resolve o caso que
      // importa (a composição mudou).
      await request(app.getHttpServer())
        .get('/api/v1/me')
        .set('Authorization', `Bearer ${token}`)
        .expect(401);
    });

    it('sem cadastro, editar e redefinir respondem que ele ainda não existe', async () => {
      await semComite();
      const auth = await admin();
      const editar = await request(app.getHttpServer())
        .put('/api/v1/committee')
        .set('Authorization', auth)
        .send(novoComite);
      expect(editar.status).toBe(404);
      expect(editar.body.message).toContain('ainda não tem cadastro');

      await request(app.getHttpServer())
        .post('/api/v1/committee/reset-password')
        .set('Authorization', auth)
        .expect(404);
    });
  });
});
