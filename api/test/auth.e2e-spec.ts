import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { JOAO, createTestApp, loginAs, resetDb } from './utils';

describe('Auth (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  it('login devolve token e o papel do usuário', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email: JOAO, password: '123456' });

    expect(response.status).toBe(200);
    expect(response.body.data.token).toBeDefined();
    expect(response.body.data.user.role).toBe('seller');
    expect(response.body.data.user.fullName).toBe('João Silva');
    expect(response.body.data.user.initials).toBe('JS');
  });

  it('senha errada não loga', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email: JOAO, password: 'senha-errada' });
    expect(response.status).toBe(400);
  });

  it('rotas autenticadas exigem token', async () => {
    const response = await request(app.getHttpServer()).get('/api/v1/me');
    expect(response.status).toBe(401);
  });

  it('logout revoga o token no servidor', async () => {
    const token = await loginAs(app, JOAO);
    const auth = { Authorization: `Bearer ${token}` };

    await request(app.getHttpServer()).post('/api/v1/auth/logout').set(auth).expect(200);
    await request(app.getHttpServer()).get('/api/v1/me').set(auth).expect(401);
  });

  it('não existe signup público', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/signup')
      .send({ email: 'intruso@barter.com.br', password: '12345678' });
    expect(response.status).toBe(404);
  });
});
