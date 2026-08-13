import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { ADMIN, ANA, JOAO, createTestApp, loginAs, resetDb } from './utils';

describe('Producers — carteira (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const get = (path: string, token: string) =>
    request(app.getHttpServer()).get(path).set('Authorization', `Bearer ${token}`);

  it('consultor enxerga apenas a própria carteira', async () => {
    const token = await loginAs(app, JOAO);
    const response = await get('/api/v1/producers', token);

    expect(response.status).toBe(200);
    const names = response.body.data.map((p: { name: string }) => p.name);
    expect(names.sort()).toEqual(['Antônio Carvalho', 'Sebastião Ramos']);
  });

  it('admin enxerga todas as carteiras e pode filtrar por consultor', async () => {
    const token = await loginAs(app, ADMIN);

    const all = await get('/api/v1/producers', token);
    expect(all.body.data).toHaveLength(7);

    // Ana é o usuário id 3 no seed.
    const filtered = await get('/api/v1/producers?consultantId=3', token);
    const names = filtered.body.data.map((p: { name: string }) => p.name);
    expect(names.sort()).toEqual(['Cláudia Nunes', 'Helena Prado']);
  });

  it('consultor não acessa produtor de outra carteira', async () => {
    const token = await loginAs(app, JOAO);
    // Helena Prado (id 2) pertence à carteira da Ana.
    const response = await get('/api/v1/producers/2', token);
    expect(response.status).toBe(403);
  });

  it('cadastro de produtor é ato do admin', async () => {
    const payload = {
      name: 'Produtor Novo',
      consultantId: 2, // João
      document: 'CPF 999.999.999-99',
      farmName: 'Fazenda Teste',
      city: 'Maringá/PR',
      areaHa: 55,
    };

    const asConsultant = await request(app.getHttpServer())
      .post('/api/v1/producers')
      .set('Authorization', `Bearer ${await loginAs(app, JOAO)}`)
      .send(payload);
    expect(asConsultant.status).toBe(403);

    const asAdmin = await request(app.getHttpServer())
      .post('/api/v1/producers')
      .set('Authorization', `Bearer ${await loginAs(app, ADMIN)}`)
      .send(payload);
    expect(asAdmin.status).toBe(201);
    expect(asAdmin.body.data.consultantId).toBe(2);
  });

  it('produtor precisa nascer na carteira de um consultor válido', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/producers')
      .set('Authorization', `Bearer ${await loginAs(app, ADMIN)}`)
      .send({
        name: 'Sem Carteira',
        consultantId: 1, // admin não tem carteira
        document: 'CPF 111.222.333-44',
        farmName: 'Fazenda X',
        city: 'Cidade/PR',
        areaHa: 10,
      });
    expect(response.status).toBe(422);
    expect(response.body.message).toContain('consultor');
  });

  it('consultores diferentes têm carteiras diferentes', async () => {
    const token = await loginAs(app, ANA);
    const response = await get('/api/v1/producers', token);
    const names = response.body.data.map((p: { name: string }) => p.name);
    expect(names).not.toContain('Antônio Carvalho');
    expect(names).toContain('Helena Prado');
  });

  /**
   * O mesmo produtor cadastrado duas vezes divide a carteira ao meio: metade
   * das permutas vai para um registro, metade para o outro, e a área usada nos
   * mínimos por hectare passa a existir em dobro.
   */
  describe('documento identifica o produtor', () => {
    const base = {
      name: 'Produtor Repetido',
      consultantId: 2,
      farmName: 'Fazenda Nova',
      city: 'Maringá/PR',
      areaHa: 30,
    };

    const create = async (document: string) =>
      request(app.getHttpServer())
        .post('/api/v1/producers')
        .set('Authorization', `Bearer ${await loginAs(app, ADMIN)}`)
        .send({ ...base, document });

    it('documento já cadastrado é recusado, apontando quem o usa', async () => {
      // Antônio Carvalho (produtor 1) já tem o CPF 123.456.789-00.
      const response = await create('CPF 123.456.789-00');
      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Antônio Carvalho');
    });

    it('a formatação não cria um produtor novo: compara-se por dígitos', async () => {
      const response = await create('12345678900');
      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Antônio Carvalho');
    });

    it('documento com contagem de dígitos que não é CPF nem CNPJ é recusado', async () => {
      for (const invalid of ['CPF 000', '123', '1234567890123456789']) {
        const response = await create(invalid);
        expect(response.status).toBe(422);
        expect(response.body.message).toContain('CPF');
      }
    });

    it('editar o próprio produtor não esbarra no próprio documento', async () => {
      const response = await request(app.getHttpServer())
        .put('/api/v1/producers/1')
        .set('Authorization', `Bearer ${await loginAs(app, ADMIN)}`)
        .send({
          name: 'Antônio Carvalho',
          consultantId: 2,
          document: 'CPF 123.456.789-00',
          farmName: 'Fazenda Boa Vista II',
          city: 'Maringá/PR',
          areaHa: 130,
        });
      expect(response.status).toBe(200);
      expect(response.body.data.farmName).toBe('Fazenda Boa Vista II');
    });
  });

  /**
   * Filtro que a API não entende precisa RECUSAR. Ignorá-lo devolvia a base
   * inteira com aparência de lista filtrada — o admin veria todas as carteiras
   * achando que estava vendo a de um consultor só.
   */
  describe('filtros e paginação', () => {
    it('consultantId que não é número é recusado, não ignorado', async () => {
      const token = await loginAs(app, ADMIN);
      const response = await get('/api/v1/producers?consultantId=abc', token);
      expect(response.status).toBe(422);
      expect(response.body.message).toContain('consultantId');
    });

    it('consultantId válido filtra de verdade', async () => {
      const token = await loginAs(app, ADMIN);
      const response = await get('/api/v1/producers?consultantId=2', token);
      expect(response.status).toBe(200);
      const owners = response.body.data.map((p: { consultantId: number }) => p.consultantId);
      expect(new Set(owners)).toEqual(new Set([2]));
    });

    it('a página vem com meta.total do conjunto inteiro', async () => {
      const token = await loginAs(app, ADMIN);
      const first = await get('/api/v1/producers?limit=2', token);
      expect(first.status).toBe(200);
      expect(first.body.data).toHaveLength(2);
      expect(first.body.meta).toEqual({ total: 7, limit: 2, offset: 0 });

      const second = await get('/api/v1/producers?limit=2&offset=2', token);
      const ids = (rows: { id: number }[]) => rows.map((r) => r.id);
      expect(ids(second.body.data)).not.toEqual(ids(first.body.data));
      expect(second.body.meta.offset).toBe(2);
    });

    it('limite acima do teto é recusado em vez de cortado em silêncio', async () => {
      const token = await loginAs(app, ADMIN);
      expect((await get('/api/v1/producers?limit=99999', token)).status).toBe(422);
      expect((await get('/api/v1/producers?limit=0', token)).status).toBe(422);
      expect((await get('/api/v1/producers?offset=-1', token)).status).toBe(422);
    });
  });
});
