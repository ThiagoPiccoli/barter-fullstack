import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { ADMIN, BACK_OFFICE, JOAO, createTestApp, loginAs, resetDb } from './utils';

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

  const trail = async (query = ''): Promise<AuditRow[]> => {
    const response = await request(app.getHttpServer())
      .get(`/api/v1/audit-logs${query}`)
      .set('Authorization', await admin());
    expect(response.status).toBe(200);
    return response.body.data as AuditRow[];
  };

  it('a trilha começa vazia e é lida do mais recente para o mais antigo', async () => {
    expect(await trail()).toEqual([]);

    const auth = await admin();
    for (const email of ['primeiro@agrobarter.com.br', 'segundo@agrobarter.com.br']) {
      await request(app.getHttpServer())
        .post('/api/v1/managers')
        .set('Authorization', auth)
        .send({ fullName: 'Pessoa Nova', email, branch: 'Matriz' });
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
        branch: 'Matriz',
      });
    const id = created.body.data.id as number;

    await request(app.getHttpServer())
      .put(`/api/v1/billers/${id}`)
      .set('Authorization', auth)
      .send({
        fullName: 'Faturista Novo',
        email: 'outro.email@agrobarter.com.br',
        branch: 'Matriz',
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

  it('a revisão de permuta deixa rastro com a decisão e a observação', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/barters/PRM-2026-002/review')
      .set('Authorization', await admin())
      .send({ status: 'approved', note: 'ok pelo comitê' })
      .expect(200);

    const rows = await trail('?targetType=barter');
    expect(rows).toHaveLength(1);
    expect(rows[0].action).toBe('barter.reviewed');
    expect(rows[0].targetLabel).toBe('PRM-2026-002');
    expect(rows[0].detail).toBe('aprovada — ok pelo comitê');
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
        branch: 'Filial 99',
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
