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
    expect(response.body.data.user.role).toBe('consultant');
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
      .send({ email: 'intruso@agrobarter.com.br', password: '12345678' });
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

  it('consultor provisionado pelo admin nasce obrigado a trocar a senha', async () => {
    const adminToken = await loginAs(app, ADMIN);
    const created = await request(app.getHttpServer())
      .post('/api/v1/consultants')
      .set({ Authorization: `Bearer ${adminToken}` })
      .send({ fullName: 'Novo Consultor', email: 'novo@agrobarter.com.br', branch: 'Filial 99' })
      .expect(201);
    expect(created.body.data.mustChangePassword).toBe(true);

    // A senha de primeira entrada vem na resposta — é a única vez que ela
    // existe fora do hash, e é o que o admin dita para o consultor.
    const provisional = created.body.data.provisionalPassword as string;
    expect(typeof provisional).toBe('string');
    expect(provisional.length).toBeGreaterThanOrEqual(8);

    // Entra com a senha provisória e o app recebe o aviso de troca obrigatória.
    const login = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email: 'novo@agrobarter.com.br', password: provisional })
      .expect(200);
    expect(login.body.data.user.mustChangePassword).toBe(true);

    // Depois da troca, o aviso some.
    const changed = await request(app.getHttpServer())
      .post('/api/v1/auth/password')
      .set({ Authorization: `Bearer ${login.body.data.token}` })
      .send({ currentPassword: provisional, newPassword: 'senha-propria-1' })
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
   * A obrigatoriedade de trocar a senha vale no SERVIDOR, não só no app. Sem
   * essa trava, quem chamasse a API direto usaria o sistema inteiro com a
   * senha do provisionamento sem nunca abrir o app — e a tela de troca
   * obrigatória não protegeria nada.
   */
  describe('senha provisória não abre a API', () => {
    /** Cria um consultor pelo admin e devolve o token da senha provisória. */
    async function provisionedConsultantToken(): Promise<{ token: string; password: string }> {
      const adminToken = await loginAs(app, ADMIN);
      const created = await request(app.getHttpServer())
        .post('/api/v1/consultants')
        .set({ Authorization: `Bearer ${adminToken}` })
        .send({ fullName: 'Recém Provisionado', email: 'recem@agrobarter.com.br', branch: 'Filial 7' })
        .expect(201);
      const password = created.body.data.provisionalPassword as string;

      const login = await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: 'recem@agrobarter.com.br', password })
        .expect(200);
      return { token: login.body.data.token as string, password };
    }

    it('rotas de negócio ficam fechadas até a troca', async () => {
      const { token } = await provisionedConsultantToken();
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
      const { token, password } = await provisionedConsultantToken();
      const auth = { Authorization: `Bearer ${token}` };

      // Sem /me o app não descobre que precisa trocar; sem /auth/password não
      // há como trocar; sem /auth/logout não há como desistir e sair.
      await request(app.getHttpServer()).get('/api/v1/me').set(auth).expect(200);
      await request(app.getHttpServer())
        .post('/api/v1/auth/password')
        .set(auth)
        .send({ currentPassword: password, newPassword: 'senha-propria-1' })
        .expect(200);
      await request(app.getHttpServer()).post('/api/v1/auth/logout').set(auth).expect(200);
    });

    it('trocada a senha, a API libera na mesma sessão', async () => {
      const { token, password } = await provisionedConsultantToken();
      const auth = { Authorization: `Bearer ${token}` };

      await request(app.getHttpServer()).get('/api/v1/producers').set(auth).expect(403);
      await request(app.getHttpServer())
        .post('/api/v1/auth/password')
        .set(auth)
        .send({ currentPassword: password, newPassword: 'senha-propria-1' })
        .expect(200);
      await request(app.getHttpServer()).get('/api/v1/producers').set(auth).expect(200);
    });
  });

  /**
   * REGRESSÃO DO SEQUESTRO DE CONTA.
   *
   * A senha de primeira entrada já foi um valor fixo, igual para todo
   * consultor provisionado ('123456'). Com isso, qualquer um que soubesse o
   * e-mail de um consultor recém-cadastrado podia entrar antes dele, trocar a
   * senha e ficar com a conta — e como não existia rota de reset, o admin não
   * tinha como retomá-la: só apagar o consultor, o que desfazia a carteira
   * inteira de produtores dele.
   *
   * Os dois testes abaixo trancam as duas metades do problema: a senha nasce
   * imprevisível, e existe caminho de volta quando a conta se perde.
   */
  describe('a conta do consultor não pode ser sequestrada', () => {
    /** Provisiona um consultor e devolve a senha de primeira entrada. */
    async function provision(email: string, adminToken: string): Promise<string> {
      const created = await request(app.getHttpServer())
        .post('/api/v1/consultants')
        .set({ Authorization: `Bearer ${adminToken}` })
        .send({ fullName: 'Consultor Provisionado', email, branch: 'Filial 9' })
        .expect(201);
      return created.body.data.provisionalPassword as string;
    }

    it('cada consultor nasce com uma senha provisória diferente e imprevisível', async () => {
      const adminToken = await loginAs(app, ADMIN);
      const first = await provision('um@agrobarter.com.br', adminToken);
      const second = await provision('dois@agrobarter.com.br', adminToken);

      expect(first).not.toBe(second);

      // As senhas fixas que já valeram não abrem mais nenhuma conta nova.
      for (const guess of ['123456', 'senha', first.toLowerCase()]) {
        await request(app.getHttpServer())
          .post('/api/v1/auth/login')
          .send({ email: 'dois@agrobarter.com.br', password: guess })
          .expect(400);
      }
      await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: 'dois@agrobarter.com.br', password: second })
        .expect(200);
    });

    it('o admin retoma a conta perdida com um reset — e derruba quem estava dentro', async () => {
      const adminToken = await loginAs(app, ADMIN);
      const provisional = await provision('perdida@agrobarter.com.br', adminToken);
      const consultantId = (
        await request(app.getHttpServer())
          .get('/api/v1/consultants')
          .set({ Authorization: `Bearer ${adminToken}` })
      ).body.data.find((c: { email: string }) => c.email === 'perdida@agrobarter.com.br').id as number;

      // Alguém entra com a provisória e define a senha definitiva: a conta
      // está, para todos os efeitos, nas mãos dessa pessoa.
      const intruder = await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: 'perdida@agrobarter.com.br', password: provisional })
        .expect(200);
      await request(app.getHttpServer())
        .post('/api/v1/auth/password')
        .set({ Authorization: `Bearer ${intruder.body.data.token}` })
        .send({ currentPassword: provisional, newPassword: 'senha-do-invasor' })
        .expect(200);

      // O reset do admin devolve o acesso...
      const reset = await request(app.getHttpServer())
        .post(`/api/v1/consultants/${consultantId}/reset-password`)
        .set({ Authorization: `Bearer ${adminToken}` })
        .expect(200);
      const novaProvisoria = reset.body.data.provisionalPassword as string;
      expect(novaProvisoria).not.toBe(provisional);
      expect(reset.body.data.mustChangePassword).toBe(true);

      // ...invalida a senha que o invasor tinha definido...
      await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: 'perdida@agrobarter.com.br', password: 'senha-do-invasor' })
        .expect(400);

      // ...e derruba a sessão que ele já tinha aberta. Sem isto o reset não
      // resolveria nada: o invasor continuaria dentro com o token na mão.
      await request(app.getHttpServer())
        .get('/api/v1/me')
        .set({ Authorization: `Bearer ${intruder.body.data.token}` })
        .expect(401);

      // O consultor legítimo entra com a nova provisória.
      await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: 'perdida@agrobarter.com.br', password: novaProvisoria })
        .expect(200);
    });

    it('reset é do admin e só alcança consultores', async () => {
      const consultantToken = await loginAs(app, JOAO);
      await request(app.getHttpServer())
        .post('/api/v1/consultants/3/reset-password')
        .set({ Authorization: `Bearer ${consultantToken}` })
        .expect(403);

      // O admin (id 1) não é gerenciado por esta rota — nem para reset.
      await request(app.getHttpServer())
        .post('/api/v1/consultants/1/reset-password')
        .set({ Authorization: `Bearer ${await loginAs(app, ADMIN)}` })
        .expect(404);
    });
  });
});
