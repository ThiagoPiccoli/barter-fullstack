import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { hashToken } from '../src/auth/token.util';
import { ADMIN, JOAO, createTestApp, loginAs, resetDb } from './utils';

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

  it('sessão vencida é recusada e apagada', async () => {
    const token = await loginAs(app, JOAO);
    const prisma = app.get(PrismaService);
    // Empurra a validade para o passado, como se o prazo tivesse corrido.
    await prisma.accessToken.update({
      where: { hash: hashToken(token) },
      data: { expiresAt: new Date(Date.now() - 1000) },
    });

    await request(app.getHttpServer())
      .get('/api/v1/me')
      .set({ Authorization: `Bearer ${token}` })
      .expect(401);

    expect(await prisma.accessToken.count({ where: { hash: hashToken(token) } })).toBe(0);
  });

  it('troca de senha exige a senha atual', async () => {
    const token = await loginAs(app, JOAO);
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/password')
      .set({ Authorization: `Bearer ${token}` })
      .send({ currentPassword: 'chute', newPassword: 'nova-senha-123' });
    expect(response.status).toBe(400);
  });

  it('troca de senha passa a valer, mantém a sessão atual e derruba as outras', async () => {
    const antiga = await loginAs(app, JOAO);
    const outraSessao = await loginAs(app, JOAO);

    await request(app.getHttpServer())
      .post('/api/v1/auth/password')
      .set({ Authorization: `Bearer ${antiga}` })
      .send({ currentPassword: '123456', newPassword: 'nova-senha-123' })
      .expect(200);

    // A sessão que trocou continua valendo; a outra caiu.
    await request(app.getHttpServer())
      .get('/api/v1/me')
      .set({ Authorization: `Bearer ${antiga}` })
      .expect(200);
    await request(app.getHttpServer())
      .get('/api/v1/me')
      .set({ Authorization: `Bearer ${outraSessao}` })
      .expect(401);

    // A senha antiga não abre mais; a nova abre.
    await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email: JOAO, password: '123456' })
      .expect(400);
    await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email: JOAO, password: 'nova-senha-123' })
      .expect(200);
  });

  it('vendedor provisionado pelo admin nasce obrigado a trocar a senha', async () => {
    const adminToken = await loginAs(app, ADMIN);
    const created = await request(app.getHttpServer())
      .post('/api/v1/sellers')
      .set({ Authorization: `Bearer ${adminToken}` })
      .send({ fullName: 'Novo Vendedor', email: 'novo@barter.com.br', branch: 'Filial 99' })
      .expect(201);
    expect(created.body.data.mustChangePassword).toBe(true);

    // Entra com a senha provisória e o app recebe o aviso de troca obrigatória.
    const login = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email: 'novo@barter.com.br', password: '123456' })
      .expect(200);
    expect(login.body.data.user.mustChangePassword).toBe(true);

    // Depois da troca, o aviso some.
    const changed = await request(app.getHttpServer())
      .post('/api/v1/auth/password')
      .set({ Authorization: `Bearer ${login.body.data.token}` })
      .send({ currentPassword: '123456', newPassword: 'senha-propria-1' })
      .expect(200);
    expect(changed.body.data.mustChangePassword).toBe(false);
  });

  it('usuários do seed entram direto (o acesso rápido da demo continua valendo)', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email: ADMIN, password: '123456' })
      .expect(200);
    expect(response.body.data.user.mustChangePassword).toBe(false);
  });

  /**
   * A obrigatoriedade de trocar a senha vale no SERVIDOR, não só no app. A
   * senha provisória é conhecida (o '123456' do provisionamento), então quem
   * chamasse a API direto usaria o sistema inteiro sem nunca abrir o app —
   * a tela de troca obrigatória não protegeria nada.
   */
  describe('senha provisória não abre a API', () => {
    /** Cria um vendedor pelo admin e devolve o token da senha provisória. */
    async function provisionedSellerToken(): Promise<string> {
      const adminToken = await loginAs(app, ADMIN);
      await request(app.getHttpServer())
        .post('/api/v1/sellers')
        .set({ Authorization: `Bearer ${adminToken}` })
        .send({ fullName: 'Recém Provisionado', email: 'recem@barter.com.br', branch: 'Filial 7' })
        .expect(201);

      const login = await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: 'recem@barter.com.br', password: '123456' })
        .expect(200);
      return login.body.data.token as string;
    }

    it('rotas de negócio ficam fechadas até a troca', async () => {
      const token = await provisionedSellerToken();
      const auth = { Authorization: `Bearer ${token}` };

      await request(app.getHttpServer()).get('/api/v1/producers').set(auth).expect(403);
      await request(app.getHttpServer()).get('/api/v1/barters').set(auth).expect(403);
      await request(app.getHttpServer()).get('/api/v1/products').set(auth).expect(403);
      await request(app.getHttpServer())
        .post('/api/v1/barters')
        .set(auth)
        .send({ producerId: 1, grainId: 1, inputs: [{ productId: 5, quantity: 1 }] })
        .expect(403);
    });

    it('o caminho para SAIR da senha provisória continua aberto', async () => {
      const token = await provisionedSellerToken();
      const auth = { Authorization: `Bearer ${token}` };

      // Sem /me o app não descobre que precisa trocar; sem /auth/password não
      // há como trocar; sem /auth/logout não há como desistir e sair.
      await request(app.getHttpServer()).get('/api/v1/me').set(auth).expect(200);
      await request(app.getHttpServer())
        .post('/api/v1/auth/password')
        .set(auth)
        .send({ currentPassword: '123456', newPassword: 'senha-propria-1' })
        .expect(200);
      await request(app.getHttpServer()).post('/api/v1/auth/logout').set(auth).expect(200);
    });

    it('trocada a senha, a API libera na mesma sessão', async () => {
      const token = await provisionedSellerToken();
      const auth = { Authorization: `Bearer ${token}` };

      await request(app.getHttpServer()).get('/api/v1/producers').set(auth).expect(403);
      await request(app.getHttpServer())
        .post('/api/v1/auth/password')
        .set(auth)
        .send({ currentPassword: '123456', newPassword: 'senha-propria-1' })
        .expect(200);
      await request(app.getHttpServer()).get('/api/v1/producers').set(auth).expect(200);
    });
  });

  /**
   * Regressão: SELLER_DEFAULT_PASSWORD era lido numa constante de topo de
   * módulo, avaliada antes do ConfigModule carregar o .env — quem configurasse
   * a variável continuava provisionando vendedores com '123456' sem aviso.
   */
  it('SELLER_DEFAULT_PASSWORD vale de verdade na criação do vendedor', async () => {
    const saved = process.env.SELLER_DEFAULT_PASSWORD;
    process.env.SELLER_DEFAULT_PASSWORD = 'provisoria-da-cooperativa';
    try {
      const adminToken = await loginAs(app, ADMIN);
      await request(app.getHttpServer())
        .post('/api/v1/sellers')
        .set({ Authorization: `Bearer ${adminToken}` })
        .send({ fullName: 'Com Senha do Ambiente', email: 'ambiente@barter.com.br', branch: 'F1' })
        .expect(201);

      // O '123456' não vale mais...
      await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: 'ambiente@barter.com.br', password: '123456' })
        .expect(400);
      // ...e a senha configurada, sim.
      await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: 'ambiente@barter.com.br', password: 'provisoria-da-cooperativa' })
        .expect(200);
    } finally {
      if (saved === undefined) delete process.env.SELLER_DEFAULT_PASSWORD;
      else process.env.SELLER_DEFAULT_PASSWORD = saved;
    }
  });
});
