import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { ADMIN, BACK_OFFICE, JOAO, createTestApp, loginAs, resetDb } from './utils';

/**
 * As quatro rotas de provisionamento — uma por papel.
 *
 * O que estes testes protegem é a promessa de ter separado as rotas: cada uma
 * enxerga e altera SÓ o próprio papel. Um motor compartilhado que recebesse o
 * papel errado (ou nenhum) transformaria `/billers/:id` numa porta para
 * qualquer usuário do sistema — o oposto do que a separação existe para dar.
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

  /** As quatro rotas e o papel que cada uma gerencia, com um id do seed. */
  const ROUTES = [
    { path: 'consultants', role: 'consultant', seedId: 2 }, // João
    { path: 'managers', role: 'manager', seedId: 7 }, // Beatriz
    { path: 'committee-members', role: 'committee', seedId: 8 }, // Ricardo
    { path: 'billers', role: 'biller', seedId: 9 }, // Patrícia
  ];

  const novoUsuario = (email: string) => ({
    fullName: 'Pessoa Nova',
    email,
    branch: 'Matriz',
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
      // Os ids dos OUTROS papéis, que esta rota não pode tocar.
      const alheios = ROUTES.filter((r) => r.path !== route.path).map((r) => r.seedId);
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
    }
  });
});
