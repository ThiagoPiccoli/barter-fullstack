import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import {
  ADMIN,
  BACK_OFFICE,
  COMITE,
  FATURISTA,
  JOAO,
  SEED_PASSWORD,
  MANAGER,
  UNIT,
  createTestApp,
  loginAs,
  resetDb,
} from './utils';

interface AuditRow {
  action: string;
  actorName: string;
  actorRole: string;
  targetType: string;
  targetLabel: string;
  detail: string | null;
}

/**
 * A TRILHA DE AUDITORIA.
 *
 * O que ela protege: `reset-password` sorteia senha nova e derruba as sessões
 * abertas do titular — é a primitiva de tomada de conta do sistema. Sem
 * registro, uma sessão de admin comprometida faria isso com qualquer usuário e
 * não haveria como reconstruir o ocorrido depois.
 *
 * Estes testes valem por um motivo a mais: a gravação é deliberadamente
 * tolerante a falha (auditoria quebrada não pode derrubar o atendimento). Essa
 * escolha tem um preço — se a trilha parar de gravar, nada reclama em
 * produção. Quem reclama é esta suíte.
 */
describe('Auditoria (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const asUser = async (email: string) => `Bearer ${await loginAs(app, email)}`;
  const admin = () => asUser(ADMIN);

  const allRows = async (query = ''): Promise<AuditRow[]> => {
    const response = await request(app.getHttpServer())
      .get(`/api/v1/audit-logs${query}`)
      .set('Authorization', await admin());
    expect(response.status).toBe(200);
    return response.body.data as AuditRow[];
  };

  /**
   * A trilha SEM os eventos de sessão.
   *
   * Entrar no sistema passou a deixar rastro, e cada `admin()` daqui é um
   * login — inclusive o que este próprio ajudante faz para poder ler a trilha.
   * Sem o filtro, todo teste sobre atos administrativos passaria a contar
   * também os logins do teste, e o que ele afirma ("provisionar deixa QUATRO
   * linhas") viraria uma conta sobre a maquinaria do teste, não sobre o
   * comportamento. Os eventos de sessão têm os seus próprios testes abaixo.
   */
  const trail = async (query = ''): Promise<AuditRow[]> =>
    (await allRows(query)).filter((row) => row.targetType !== 'session');

  const sessionTrail = () => allRows('?targetType=session');

  it('a trilha começa vazia e é lida do mais recente para o mais antigo', async () => {
    expect(await trail()).toEqual([]);

    const auth = await admin();
    for (const email of ['primeiro@agrobarter.com.br', 'segundo@agrobarter.com.br']) {
      await request(app.getHttpServer())
        .post('/api/v1/managers')
        .set('Authorization', auth)
        .send({ fullName: 'Pessoa Nova', email, unitId: UNIT.matriz });
    }

    const rows = await trail();
    expect(rows).toHaveLength(2);
    expect(rows[0].targetLabel).toBe('segundo@agrobarter.com.br');
    expect(rows[1].targetLabel).toBe('primeiro@agrobarter.com.br');
  });

  it('provisionar, editar, resetar senha e excluir deixam rastro — com autor e alvo', async () => {
    const auth = await admin();

    const created = await request(app.getHttpServer())
      .post('/api/v1/billers')
      .set('Authorization', auth)
      .send({
        fullName: 'Faturista Novo',
        email: 'faturista.novo@agrobarter.com.br',
        unitId: UNIT.matriz,
      });
    const id = created.body.data.id as number;

    await request(app.getHttpServer())
      .put(`/api/v1/billers/${id}`)
      .set('Authorization', auth)
      .send({
        fullName: 'Faturista Novo',
        email: 'outro.email@agrobarter.com.br',
        unitId: UNIT.matriz,
      })
      .expect(200);

    await request(app.getHttpServer())
      .post(`/api/v1/billers/${id}/reset-password`)
      .set('Authorization', auth)
      .expect(200);

    await request(app.getHttpServer())
      .delete(`/api/v1/billers/${id}`)
      .set('Authorization', auth)
      .expect(204);

    const rows = await trail();
    expect(rows.map((r) => r.action)).toEqual([
      'user.deleted',
      'user.password-reset',
      'user.updated',
      'user.created',
    ]);

    // Toda linha diz QUEM fez, com o papel congelado no momento do ato.
    for (const row of rows) {
      expect(row.actorName).toBe('Carlos Mendes');
      expect(row.actorRole).toBe('admin');
      expect(row.targetType).toBe('user');
    }

    const criacao = rows.find((r) => r.action === 'user.created')!;
    expect(criacao.targetLabel).toBe('faturista.novo@agrobarter.com.br');
    expect(criacao.detail).toContain('Faturista');

    // Trocar o e-mail é trocar a chave de login: o de/para precisa estar lá.
    const edicao = rows.find((r) => r.action === 'user.updated')!;
    expect(edicao.detail).toContain('faturista.novo@agrobarter.com.br');
    expect(edicao.detail).toContain('outro.email@agrobarter.com.br');

    const reset = rows.find((r) => r.action === 'user.password-reset')!;
    expect(reset.detail).toContain('sessões abertas encerradas');
  });

  /**
   * A LINHA DE PRODUÇÃO inteira na trilha global: a decisão do comitê e o
   * faturamento, com quem os praticou.
   *
   * Cada permuta também tem a própria linha do tempo (ver o histórico em
   * barters.e2e-spec.ts), e as duas coisas convivem de propósito: aquela conta a
   * história DE UM registro, esta responde "o que aconteceu no sistema" — e é a
   * segunda que atravessa contas, unidades e permutas quando alguém investiga.
   */
  it('a decisão do comitê e o faturamento deixam rastro, com o ator de cada etapa', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-002/review')
      .set('Authorization', `Bearer ${await loginAs(app, COMITE)}`)
      .send({ status: 'approved', note: 'ok pelo comitê' })
      .expect(200);

    await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-002/invoice')
      .set('Authorization', `Bearer ${await loginAs(app, FATURISTA)}`)
      .send({ note: 'NF 4471' })
      .expect(200);

    const rows = await trail('?targetType=barter');
    expect(rows).toHaveLength(2);
    // Mais recentes primeiro: o faturamento veio depois da decisão.
    expect(rows.map((r) => [r.action, r.actorName])).toEqual([
      ['barter.invoiced', 'Patrícia Lemos'],
      ['barter.reviewed', 'Comitê de Permutas'],
    ]);
    expect(rows[0].detail).toBe('faturada — NF 4471');
    expect(rows[1].targetLabel).toBe('PRM-2026-002');
    expect(rows[1].detail).toBe('aprovada — ok pelo comitê');
  });

  /**
   * O ponto da trilha ser SNAPSHOT em texto: ela precisa continuar legível
   * depois que a conta some — que é exatamente o caso em que alguém vai
   * querer lê-la ("quem era esse usuário que foi excluído?").
   */
  it('a linha sobrevive à exclusão do alvo e do autor', async () => {
    const auth = await admin();
    const created = await request(app.getHttpServer())
      .post('/api/v1/consultants')
      .set('Authorization', auth)
      .send({
        fullName: 'Some Depois',
        email: 'some.depois@agrobarter.com.br',
        unitId: UNIT.filial02,
        managerId: MANAGER.beatriz,
      });

    await request(app.getHttpServer())
      .delete(`/api/v1/consultants/${created.body.data.id}`)
      .set('Authorization', auth)
      .expect(204);

    const rows = await trail('?action=user.created');
    expect(rows).toHaveLength(1);
    expect(rows[0].targetLabel).toBe('some.depois@agrobarter.com.br');
    expect(rows[0].actorName).toBe('Carlos Mendes');
  });

  it('ações que não mudam acesso nem decidem dinheiro não poluem a trilha', async () => {
    const auth = await admin();
    await request(app.getHttpServer()).get('/api/v1/producers').set('Authorization', auth);
    await request(app.getHttpServer()).get('/api/v1/barters').set('Authorization', auth);
    await request(app.getHttpServer()).get('/api/v1/products').set('Authorization', auth);
    expect(await trail()).toEqual([]);
  });

  /**
   * A ENTRADA no sistema.
   *
   * A trilha registrava com cuidado o que se faz depois de entrar e nada sobre
   * o entrar — que é a primeira pergunta de qualquer investigação e a única
   * evidência de um ataque em andamento. Dez senhas erradas na conta do admin
   * não produziam linha nenhuma, porque nenhum ato administrativo aconteceu.
   */
  describe('sessão', () => {
    const login = (email: string, password: string) =>
      request(app.getHttpServer()).post('/api/v1/auth/login').send({ email, password });

    it('entrar deixa rastro com a conta que entrou', async () => {
      await login(JOAO, SEED_PASSWORD).expect(200);

      const rows = await sessionTrail();
      const entrada = rows.find((row) => row.targetLabel === JOAO)!;
      expect(entrada.action).toBe('session.started');
      expect(entrada.actorName).toBe('João Silva');
      expect(entrada.actorRole).toBe('consultant');
    });

    it('senha errada deixa rastro, dizendo de qual conta', async () => {
      await login(JOAO, 'chute-que-nao-e-a-senha').expect(400);

      const falha = (await sessionTrail()).find((row) => row.action === 'session.failed')!;
      expect(falha.targetLabel).toBe(JOAO);
      expect(falha.detail).toContain('senha incorreta');
    });

    /**
     * Tentativa em e-mail que não existe também é registrada — e é ela que
     * mostra alguém VARRENDO e-mails. Sem conta a que se referir, o ator é o
     * próprio e-mail tentado: é o que sobra de identificável.
     */
    it('tentativa em e-mail inexistente registra o e-mail tentado', async () => {
      await login('ninguem@agrobarter.com.br', 'seja-o-que-for').expect(400);

      const falha = (await sessionTrail()).find((row) => row.action === 'session.failed')!;
      expect(falha.targetLabel).toBe('ninguem@agrobarter.com.br');
      expect(falha.actorName).toBe('ninguem@agrobarter.com.br');
      expect(falha.actorRole).toBe('desconhecido');
      expect(falha.detail).toContain('sem cadastro');
    });

    /**
     * O limite por IP protege o servidor; este protege a CONTA. Depois do
     * teto, nem a senha certa entra — é o que impede a adivinhação distribuída
     * por muitos IPs, que passaria pelo limitador sem esforço.
     */
    it('depois de 10 senhas erradas a conta descansa — e recusa até a senha certa', async () => {
      for (let attempt = 0; attempt < 10; attempt++) {
        await login(JOAO, `errada-${attempt}`).expect(400);
      }

      await login(JOAO, SEED_PASSWORD).expect(400);

      const bloqueio = (await sessionTrail()).find((row) => row.action === 'session.locked')!;
      expect(bloqueio.targetLabel).toBe(JOAO);
      expect(bloqueio.detail).toContain('bloqueada');
    });

    /** Acertar zera o contador: nove erros hoje não deixam a conta a um passo. */
    it('um acerto no meio do caminho zera as tentativas', async () => {
      for (let attempt = 0; attempt < 9; attempt++) {
        await login(JOAO, `errada-${attempt}`).expect(400);
      }
      await login(JOAO, SEED_PASSWORD).expect(200);

      for (let attempt = 0; attempt < 9; attempt++) {
        await login(JOAO, `errada-de-novo-${attempt}`).expect(400);
      }
      // Se o contador não tivesse zerado, o 10º erro do segundo bloco já teria
      // trancado a conta e esta senha correta não entraria.
      await login(JOAO, SEED_PASSWORD).expect(200);
      expect((await sessionTrail()).find((row) => row.action === 'session.locked')).toBeUndefined();
    });
  });

  it('ler a trilha exige a capacidade: consultor e retaguarda levam 403', async () => {
    for (const email of [JOAO, ...BACK_OFFICE]) {
      await request(app.getHttpServer())
        .get('/api/v1/audit-logs')
        .set('Authorization', await asUser(email))
        .expect(403);
    }
  });

  it('não há rota que altere ou apague a trilha', async () => {
    const auth = await admin();
    await request(app.getHttpServer())
      .post('/api/v1/audit-logs')
      .set('Authorization', auth)
      .send({ action: 'inventado' })
      .expect(404);
    await request(app.getHttpServer())
      .delete('/api/v1/audit-logs/1')
      .set('Authorization', auth)
      .expect(404);
  });
});
