import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { ADMIN, ANA, JOAO, createTestApp, loginAs, resetDb } from './utils';

describe('Consultants — gestão pelo admin (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const asUser = async (email: string) => `Bearer ${await loginAs(app, email)}`;

  it('lista de consultores é restrita ao admin', async () => {
    const asConsultant = await request(app.getHttpServer())
      .get('/api/v1/consultants')
      .set('Authorization', await asUser(JOAO));
    expect(asConsultant.status).toBe(403);

    const asAdmin = await request(app.getHttpServer())
      .get('/api/v1/consultants')
      .set('Authorization', await asUser(ADMIN));
    expect(asAdmin.status).toBe(200);
    expect(asAdmin.body.data).toHaveLength(5);
    expect(asAdmin.body.data.map((s: { role: string }) => s.role)).not.toContain('admin');
  });

  it('consultor criado pelo admin loga com a senha provisória devolvida na criação', async () => {
    const created = await request(app.getHttpServer())
      .post('/api/v1/consultants')
      .set('Authorization', await asUser(ADMIN))
      .send({
        fullName: 'Novo Consultor',
        email: 'novo.consultor@barter.com.br',
        branch: 'Filial 99',
      });
    expect(created.status).toBe(201);
    expect(created.body.data.role).toBe('consultant');

    const login = await request(app.getHttpServer()).post('/api/v1/auth/login').send({
      email: 'novo.consultor@barter.com.br',
      password: created.body.data.provisionalPassword,
    });
    expect(login.status).toBe(200);
  });

  /**
   * A senha provisória aparece UMA vez, na resposta de quem a gerou. Se
   * vazasse na listagem, ela deixaria de ser um segredo entre o admin e o
   * consultor e voltaria a ser um caminho aberto para a conta.
   */
  it('a senha provisória não aparece em nenhuma outra resposta', async () => {
    const admin = await asUser(ADMIN);
    await request(app.getHttpServer())
      .post('/api/v1/consultants')
      .set('Authorization', admin)
      .send({ fullName: 'Efêmero', email: 'efemero@barter.com.br', branch: 'F1' })
      .expect(201);

    const list = await request(app.getHttpServer())
      .get('/api/v1/consultants')
      .set('Authorization', admin)
      .expect(200);
    for (const consultant of list.body.data) {
      expect(consultant.provisionalPassword).toBeUndefined();
      expect(consultant.password).toBeUndefined();
    }

    const updated = await request(app.getHttpServer())
      .put('/api/v1/consultants/2')
      .set('Authorization', admin)
      .send({ fullName: 'João Silva', email: 'joao.silva@barter.com.br', branch: 'Filial 02' })
      .expect(200);
    expect(updated.body.data.provisionalPassword).toBeUndefined();
  });

  it('e-mail duplicado é rejeitado na criação e na edição', async () => {
    const admin = await asUser(ADMIN);

    const duplicateCreate = await request(app.getHttpServer())
      .post('/api/v1/consultants')
      .set('Authorization', admin)
      .send({ fullName: 'Clone', email: JOAO, branch: 'Filial X' });
    expect(duplicateCreate.status).toBe(422);

    // João é o usuário id 2 no seed; tenta assumir o e-mail da Ana.
    const duplicateUpdate = await request(app.getHttpServer())
      .put('/api/v1/consultants/2')
      .set('Authorization', admin)
      .send({ fullName: 'João Silva', email: ANA, branch: 'Filial 02' });
    expect(duplicateUpdate.status).toBe(422);
  });

  it('excluir consultor deixa a carteira sem dono e preserva permutas', async () => {
    const admin = await asUser(ADMIN);

    await request(app.getHttpServer())
      .delete('/api/v1/consultants/2') // João
      .set('Authorization', admin)
      .expect(204);

    // Antônio Carvalho (id 1) era da carteira do João → fica sem consultor.
    const producer = await request(app.getHttpServer())
      .get('/api/v1/producers/1')
      .set('Authorization', admin);
    expect(producer.body.data.consultantId).toBeNull();

    // A permuta histórica preserva o nome do consultor (snapshot).
    const barter = await request(app.getHttpServer())
      .get('/api/v1/barters/PRM-2026-001')
      .set('Authorization', admin);
    expect(barter.body.data.consultantName).toBe('João Silva');
    expect(barter.body.data.consultantId).toBeNull();
  });

  it('rota de consultores não gerencia o admin', async () => {
    const response = await request(app.getHttpServer())
      .delete('/api/v1/consultants/1') // admin
      .set('Authorization', await asUser(ADMIN));
    expect(response.status).toBe(404);
  });
});
