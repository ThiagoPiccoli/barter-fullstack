import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { passwordProblem } from '../src/auth/password-policy';
import { hashToken } from '../src/auth/token.util';
import {
  ADMIN,
  JOAO,
  MANAGER,
  SEED_PASSWORD,
  UNIT,
  createTestApp,
  loginAs,
  resetDb,
} from './utils';

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
      .send({ email: JOAO, password: SEED_PASSWORD });

    expect(response.status).toBe(200);
    expect(response.body.data.token).toBeDefined();
    expect(response.body.data.user.role).toBe('consultant');
    expect(response.body.data.user.fullName).toBe('João Silva');
    expect(response.body.data.user.initials).toBe('JS');
  });

  /**
   * O GERENTE do consultor vem em TODA porta de sessão — login, `/me` e a troca
   * de senha —, porque é dessas três, e só dessas três, que sai o usuário que o
   * app guarda como sessão. É o que faz a tela do consultor dizer "Meu gerente:
   * Beatriz Nogueira" e a confirmação de envio dizer para quem a permuta vai.
   *
   * Existe porque faltava: `managerName` era testado na listagem e no
   * provisionamento (rotas de admin, que sempre incluíram a relação) e em
   * nenhuma rota de sessão. As três respostas traziam `managerId` preenchido e
   * `managerName: null`, e o app caía nos textos genéricos ("—", "seu gerente")
   * com a suíte inteira verde.
   */
  describe('o usuário da sessão sabe quem é o gerente dele', () => {
    it('no login', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: JOAO, password: SEED_PASSWORD })
        .expect(200);

      expect(response.body.data.user.managerId).toBe(MANAGER.beatriz);
      expect(response.body.data.user.managerName).toBe('Beatriz Nogueira');
    });

    it('ao retomar a sessão pelo /me', async () => {
      const token = await loginAs(app, JOAO);
      const response = await request(app.getHttpServer())
        .get('/api/v1/me')
        .set({ Authorization: `Bearer ${token}` })
        .expect(200);

      expect(response.body.data.managerId).toBe(MANAGER.beatriz);
      expect(response.body.data.managerName).toBe('Beatriz Nogueira');
    });

    it('na resposta da troca de senha', async () => {
      const token = await loginAs(app, JOAO);
      const response = await request(app.getHttpServer())
        .post('/api/v1/auth/password')
        .set({ Authorization: `Bearer ${token}` })
        .send({ currentPassword: SEED_PASSWORD, newPassword: 'nova-senha-123' })
        .expect(200);

      expect(response.body.data.managerName).toBe('Beatriz Nogueira');
    });

    /**
     * O caminho ESCONDIDO: errar a senha antes de acertar faz o login reler o
     * usuário para zerar o contador de tentativas, e essa releitura é outra
     * consulta — que também precisa trazer o gerente. Quem tivesse errado a
     * senha uma vez entraria sem o nome, e só ele.
     */
    it('mesmo quando o login vem depois de uma tentativa errada', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: JOAO, password: 'senha-errada' })
        .expect(400);

      const response = await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: JOAO, password: SEED_PASSWORD })
        .expect(200);

      expect(response.body.data.user.managerName).toBe('Beatriz Nogueira');
    });

    /** Quem não tem gerente continua sem: o campo é do consultor. */
    it('e quem não tem gerente responde null, não um nome vazio', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: ADMIN, password: SEED_PASSWORD })
        .expect(200);

      expect(response.body.data.user.managerId).toBeNull();
      expect(response.body.data.user.managerName).toBeNull();
    });
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

  /**
   * A SEGUNDA morte da sessão. O prazo acima responde "esta sessão já é velha
   * demais"; esta responde "este aparelho ainda está com quem deveria?".
   *
   * Sem ela, o celular perdido no sábado continua sendo uma sessão válida por
   * até um mês — e é justamente no aparelho perdido que o prazo longo dói.
   */
  it('sessão parada tempo demais também morre, mesmo dentro do prazo', async () => {
    const token = await loginAs(app, JOAO);
    const prisma = app.get(PrismaService);
    const oitoDias = new Date(Date.now() - 8 * 24 * 60 * 60 * 1000);

    // O prazo absoluto continua lá na frente: quem mata aqui é a inatividade.
    await prisma.accessToken.update({
      where: { hash: hashToken(token) },
      data: { lastUsedAt: oitoDias },
    });

    await request(app.getHttpServer())
      .get('/api/v1/me')
      .set({ Authorization: `Bearer ${token}` })
      .expect(401);

    expect(await prisma.accessToken.count({ where: { hash: hashToken(token) } })).toBe(0);
  });

  /** Usar o app mantém a sessão viva — é o outro lado da regra acima. */
  it('sessão usada ontem continua valendo', async () => {
    const token = await loginAs(app, JOAO);
    const prisma = app.get(PrismaService);

    await prisma.accessToken.update({
      where: { hash: hashToken(token) },
      data: { lastUsedAt: new Date(Date.now() - 24 * 60 * 60 * 1000) },
    });

    await request(app.getHttpServer())
      .get('/api/v1/me')
      .set({ Authorization: `Bearer ${token}` })
      .expect(200);

    // E o uso REGRAVA o "visto por último": sem isso a sessão envelheceria
    // mesmo em uso diário, e morreria com o app aberto na mão do consultor.
    const sessao = await prisma.accessToken.findUnique({ where: { hash: hashToken(token) } });
    expect(Date.now() - sessao!.lastUsedAt.getTime()).toBeLessThan(60_000);
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
      .send({ currentPassword: SEED_PASSWORD, newPassword: 'nova-senha-123' })
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
      .send({ email: JOAO, password: SEED_PASSWORD })
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
      .send({
        fullName: 'Novo Consultor',
        email: 'novo@agrobarter.com.br',
        unitId: UNIT.filial02,
        managerId: MANAGER.beatriz,
      })
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
      .send({ email: ADMIN, password: SEED_PASSWORD })
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
        .send({
          fullName: 'Recém Provisionado',
          email: 'recem@agrobarter.com.br',
          unitId: UNIT.matriz,
          managerId: MANAGER.beatriz,
        })
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
        .send({
          fullName: 'Consultor Provisionado',
          email,
          unitId: UNIT.matriz,
          managerId: MANAGER.beatriz,
        })
        .expect(201);
      return created.body.data.provisionalPassword as string;
    }

    it('cada consultor nasce com uma senha provisória diferente e imprevisível', async () => {
      const adminToken = await loginAs(app, ADMIN);
      const first = await provision('um@agrobarter.com.br', adminToken);
      const second = await provision('dois@agrobarter.com.br', adminToken);

      expect(first).not.toBe(second);

      // As senhas fixas que já valeram não abrem mais nenhuma conta nova.
      for (const guess of ['123456', 'senha', SEED_PASSWORD, first.toLowerCase()]) {
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
      ).body.data.find((c: { email: string }) => c.email === 'perdida@agrobarter.com.br')
        .id as number;

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

  /**
   * O dataset de demonstração não pode nascer fora da própria política.
   *
   * A checagem é contra CADA usuário semeado, e não contra a senha sozinha,
   * porque metade da política é contextual: ela recusa a senha que contenha o
   * nome ou o e-mail de quem a usa. Uma conta nova no seed chamada, digamos,
   * "Demo Agro" passaria despercebida numa conferência a olho — e este teste
   * quebra na hora.
   *
   * Vale lembrar por que isto importa fora do ambiente de desenvolvimento: o
   * dataset só é bloqueado por `NODE_ENV === 'production'`, então uma
   * homologação que esqueça a variável sobe com estas contas de verdade.
   */
  it('todas as contas do seed usam uma senha que passa na política', async () => {
    const users = await app.get(PrismaService).user.findMany();
    expect(users.length).toBeGreaterThan(0);

    for (const user of users) {
      expect({ email: user.email, problema: passwordProblem(SEED_PASSWORD, user) }).toEqual({
        email: user.email,
        problema: null,
      });
    }
  });

  /**
   * A TRAVA POR TENTATIVAS NÃO PODE SOBREVIVER A UMA SENHA NOVA.
   *
   * O login confere a trava ANTES da senha. Enquanto os caminhos que definem
   * uma senha nova não a limpavam, o reset entregava uma credencial que não
   * entrava: o admin ditava a provisória ao telefone e ela era recusada por até
   * quinze minutos, sem que nada na resposta dissesse por quê.
   *
   * E o caso não era raro — é o mais provável de todos, porque quem procura o
   * admin é justamente quem acabou de errar a senha dez vezes.
   */
  describe('redefinir a senha devolve o acesso de verdade', () => {
    const JOAO_ID = 2;

    /** Erra o suficiente para a conta descansar. */
    async function lockOut(email: string): Promise<void> {
      for (let attempt = 0; attempt < 10; attempt++) {
        await request(app.getHttpServer())
          .post('/api/v1/auth/login')
          .send({ email, password: `errada-${attempt}` })
          .expect(400);
      }
      // A senha CERTA também é recusada: é isso que caracteriza a trava.
      await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email, password: SEED_PASSWORD })
        .expect(400);
    }

    it('o reset do admin destranca a conta bloqueada', async () => {
      const adminToken = await loginAs(app, ADMIN);
      await lockOut(JOAO);

      const reset = await request(app.getHttpServer())
        .post(`/api/v1/consultants/${JOAO_ID}/reset-password`)
        .set({ Authorization: `Bearer ${adminToken}` })
        .expect(200);

      // A provisória entra NA HORA. Sem CLEARED_LOCKOUT no reset, este login
      // levava 400 e o consultor ficava sem acesso com a senha na mão.
      await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: JOAO, password: reset.body.data.provisionalPassword as string })
        .expect(200);
    });

    it('trocar a própria senha destranca a conta bloqueada', async () => {
      // A sessão nasce ANTES da trava: quem já estava dentro não é expulso por
      // alguém errando a senha dele de propósito lá fora.
      const token = await loginAs(app, JOAO);
      await lockOut(JOAO);

      await request(app.getHttpServer())
        .post('/api/v1/auth/password')
        .set({ Authorization: `Bearer ${token}` })
        .send({ currentPassword: SEED_PASSWORD, newPassword: 'chuva-de-outubro' })
        .expect(200);

      await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: JOAO, password: 'chuva-de-outubro' })
        .expect(200);
    });

    /** O contador também zera — senão o primeiro engano tranca tudo de novo. */
    it('depois do reset a conta recomeça com o contador zerado', async () => {
      const adminToken = await loginAs(app, ADMIN);

      // Nove erros: um passo antes da trava, sem chegar nela.
      for (let attempt = 0; attempt < 9; attempt++) {
        await request(app.getHttpServer())
          .post('/api/v1/auth/login')
          .send({ email: JOAO, password: `errada-${attempt}` })
          .expect(400);
      }

      const reset = await request(app.getHttpServer())
        .post(`/api/v1/consultants/${JOAO_ID}/reset-password`)
        .set({ Authorization: `Bearer ${adminToken}` })
        .expect(200);
      const provisional = reset.body.data.provisionalPassword as string;

      // Um engano ao digitar a provisória ditada por telefone. Com o contador
      // herdado, ESTE erro seria o décimo e trancaria a conta.
      await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: JOAO, password: 'digitei-errado' })
        .expect(400);

      await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email: JOAO, password: provisional })
        .expect(200);
    });
  });
});
