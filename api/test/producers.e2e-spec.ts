import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { ADMIN, ANA, CONSULTANT, JOAO, ROBERTO, createTestApp, loginAs, resetDb } from './utils';

describe('Producers — carteira (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const get = (path: string, token: string) =>
    request(app.getHttpServer()).get(path).set('Authorization', `Bearer ${token}`);

  const namesOf = (body: { data: { name: string }[] }) => body.data.map((p) => p.name).sort();

  it('consultor enxerga a própria carteira — inclusive o que divide com outro', async () => {
    const token = await loginAs(app, JOAO);
    const response = await get('/api/v1/producers', token);

    expect(response.status).toBe(200);
    // Joaquim Tavares é do Roberto TAMBÉM: região compartilhada, um produtor,
    // duas carteiras.
    expect(namesOf(response.body)).toEqual([
      'Antônio Carvalho',
      'Joaquim Tavares',
      'Sebastião Ramos',
    ]);
  });

  it('admin enxerga todas as carteiras e pode filtrar por consultor', async () => {
    const token = await loginAs(app, ADMIN);

    const all = await get('/api/v1/producers', token);
    expect(all.body.data).toHaveLength(7);

    // Ana é o usuário id 3 no seed.
    const filtered = await get(`/api/v1/producers?consultantId=${CONSULTANT.ana}`, token);
    expect(namesOf(filtered.body)).toEqual(['Cláudia Nunes', 'Helena Prado']);
  });

  it('consultor não acessa produtor de carteira em que não está', async () => {
    const token = await loginAs(app, JOAO);
    // Helena Prado (id 2) é atendida só pela Ana.
    const response = await get('/api/v1/producers/2', token);
    expect(response.status).toBe(403);
  });

  it('cadastro de produtor é ato do admin', async () => {
    const payload = {
      name: 'Produtor Novo',
      consultantIds: [CONSULTANT.joao],
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
    expect(asAdmin.body.data.consultantIds).toEqual([CONSULTANT.joao]);
  });

  it('produtor precisa nascer na carteira de pelo menos um consultor válido', async () => {
    const admin = await loginAs(app, ADMIN);
    const create = (consultantIds: unknown) =>
      request(app.getHttpServer())
        .post('/api/v1/producers')
        .set('Authorization', `Bearer ${admin}`)
        .send({
          name: 'Sem Carteira',
          consultantIds,
          document: 'CPF 111.222.333-44',
          farmName: 'Fazenda X',
          city: 'Cidade/PR',
          areaHa: 10,
        });

    // Lista vazia: um produtor que ninguém atende não aparece para ninguém.
    const empty = await create([]);
    expect(empty.status).toBe(422);
    expect(empty.body.message).toContain('consultor');

    // O admin não tem carteira — e a mensagem NOMEIA quem não serve, porque com
    // uma lista "escolha um consultor válido" deixaria adivinhando qual dos ids.
    const notConsultant = await create([1]);
    expect(notConsultant.status).toBe(422);
    expect(notConsultant.body.message).toContain('Carlos Mendes');

    // Um id válido ao lado de um inválido também recusa: a carteira é gravada
    // inteira ou não é gravada.
    const mixed = await create([CONSULTANT.joao, 1]);
    expect(mixed.status).toBe(422);

    // E o mesmo consultor duas vezes é engano de quem chama, não um vínculo
    // duplicado esbarrando na chave primária.
    const repeated = await create([CONSULTANT.joao, CONSULTANT.joao]);
    expect(repeated.status).toBe(422);
  });

  it('consultores diferentes têm carteiras diferentes', async () => {
    const token = await loginAs(app, ANA);
    const response = await get('/api/v1/producers', token);
    const names = response.body.data.map((p: { name: string }) => p.name);
    expect(names).not.toContain('Antônio Carvalho');
    expect(names).toContain('Helena Prado');
  });

  /**
   * O ponto da carteira compartilhada: consultores dividem região, e o mesmo
   * produtor é atendido por mais de um. Antes disso, a única forma de
   * representar essa realidade era cadastrar o produtor duas vezes — e aí a
   * área cultivável passava a existir em dobro (os mínimos por hectare saem
   * dela) e as permutas do mesmo cliente se partiam entre dois registros.
   */
  describe('um produtor, várias carteiras', () => {
    const admin = () => loginAs(app, ADMIN);

    it('os dois consultores enxergam o mesmo produtor', async () => {
      const doJoao = await get('/api/v1/producers/3', await loginAs(app, JOAO));
      const doRoberto = await get('/api/v1/producers/3', await loginAs(app, ROBERTO));

      expect(doJoao.status).toBe(200);
      expect(doRoberto.status).toBe(200);
      expect(doJoao.body.data.name).toBe('Joaquim Tavares');
      // O MESMO registro, com a mesma área: é isso que o cadastro duplicado
      // quebrava.
      expect(doRoberto.body.data.id).toBe(doJoao.body.data.id);
      expect(doRoberto.body.data.areaHa).toBe(doJoao.body.data.areaHa);
    });

    it('a carteira sai na resposta como lista, com todos os vínculos', async () => {
      const response = await get('/api/v1/producers/3', await admin());
      expect(new Set(response.body.data.consultantIds)).toEqual(
        new Set([CONSULTANT.joao, CONSULTANT.roberto]),
      );
    });

    it('o filtro por consultor acha o produtor pelos dois lados', async () => {
      const token = await admin();
      for (const id of [CONSULTANT.joao, CONSULTANT.roberto]) {
        const response = await get(`/api/v1/producers?consultantId=${id}`, token);
        expect(namesOf(response.body)).toContain('Joaquim Tavares');
      }
    });

    it('o admin compartilha um produtor acrescentando um consultor à carteira', async () => {
      const token = await admin();
      // Antônio Carvalho (id 1) é só do João. A Ana passa a atendê-lo também.
      const response = await request(app.getHttpServer())
        .put('/api/v1/producers/1')
        .set('Authorization', `Bearer ${token}`)
        .send({
          name: 'Antônio Carvalho',
          consultantIds: [CONSULTANT.joao, CONSULTANT.ana],
          document: 'CPF 123.456.789-00',
          farmName: 'Fazenda Boa Vista',
          city: 'Maringá/PR',
          areaHa: 120,
        });
      expect(response.status).toBe(200);
      expect(new Set(response.body.data.consultantIds)).toEqual(
        new Set([CONSULTANT.joao, CONSULTANT.ana]),
      );

      // E ele aparece na carteira da Ana a partir de agora.
      const daAna = await get('/api/v1/producers', await loginAs(app, ANA));
      expect(namesOf(daAna.body)).toContain('Antônio Carvalho');
    });

    it('tirar um consultor da lista tira o produtor da carteira dele', async () => {
      const token = await admin();
      // Joaquim (id 3) deixa de ser atendido pelo João; segue com o Roberto.
      const response = await request(app.getHttpServer())
        .put('/api/v1/producers/3')
        .set('Authorization', `Bearer ${token}`)
        .send({
          name: 'Joaquim Tavares',
          consultantIds: [CONSULTANT.roberto],
          document: 'CNPJ 12.345.678/0001-90',
          farmName: 'Fazenda Santa Rita',
          city: 'Mandaguari/PR',
          areaHa: 320,
        });
      expect(response.status).toBe(200);
      expect(response.body.data.consultantIds).toEqual([CONSULTANT.roberto]);

      const doJoao = await get('/api/v1/producers/3', await loginAs(app, JOAO));
      expect(doJoao.status).toBe(403);
      const doRoberto = await get('/api/v1/producers/3', await loginAs(app, ROBERTO));
      expect(doRoberto.status).toBe(200);
    });

    /**
     * Editar o produtor sem mexer na carteira não pode reescrever os vínculos:
     * `assignedAt` é desde quando aquele consultor atende o cliente, e apagar e
     * recriar todos a cada salvamento diria que todo compartilhamento começou
     * no último salvamento do cadastro.
     *
     * A conferência é no BANCO porque `assignedAt` não sai na resposta — ele é
     * memória do vínculo, não campo de tela. O teste desce até lá justamente
     * porque a regressão seria invisível pela API.
     */
    it('editar outros campos preserva a data dos vínculos que ficam', async () => {
      const prisma = app.get(PrismaService);
      const token = await admin();
      const before = await prisma.producerConsultant.findMany({
        where: { producerId: 3 },
        orderBy: { consultantId: 'asc' },
      });

      await request(app.getHttpServer())
        .put('/api/v1/producers/3')
        .set('Authorization', `Bearer ${token}`)
        .send({
          name: 'Joaquim Tavares',
          consultantIds: before.map((link) => link.consultantId),
          document: 'CNPJ 12.345.678/0001-90',
          farmName: 'Fazenda Santa Rita II',
          city: 'Mandaguari/PR',
          areaHa: 320,
        })
        .expect(200);

      const after = await prisma.producerConsultant.findMany({
        where: { producerId: 3 },
        orderBy: { consultantId: 'asc' },
      });
      expect(after).toEqual(before);
    });

    /** O vínculo NOVO, por outro lado, nasce agora — e não na data do produtor. */
    it('o vínculo acrescentado hoje é datado de hoje', async () => {
      const prisma = app.get(PrismaService);
      const token = await admin();
      const antes = new Date();

      await request(app.getHttpServer())
        .put('/api/v1/producers/1')
        .set('Authorization', `Bearer ${token}`)
        .send({
          name: 'Antônio Carvalho',
          consultantIds: [CONSULTANT.joao, CONSULTANT.ana],
          document: 'CPF 123.456.789-00',
          farmName: 'Fazenda Boa Vista',
          city: 'Maringá/PR',
          areaHa: 120,
        })
        .expect(200);

      const novo = await prisma.producerConsultant.findUnique({
        where: { producerId_consultantId: { producerId: 1, consultantId: CONSULTANT.ana } },
      });
      expect(novo!.assignedAt.getTime()).toBeGreaterThanOrEqual(antes.getTime() - 1000);
    });
  });

  /**
   * O mesmo produtor cadastrado duas vezes divide a carteira ao meio: metade
   * das permutas vai para um registro, metade para o outro, e a área usada nos
   * mínimos por hectare passa a existir em dobro.
   */
  describe('documento identifica o produtor', () => {
    const base = {
      name: 'Produtor Repetido',
      consultantIds: [CONSULTANT.joao],
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
          consultantIds: [CONSULTANT.joao],
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
      const response = await get(`/api/v1/producers?consultantId=${CONSULTANT.joao}`, token);
      expect(response.status).toBe(200);
      // Todo produtor da resposta é atendido pelo João — e algum deles pode ser
      // atendido por mais gente, que é o que a carteira compartilhada permite.
      for (const producer of response.body.data as { consultantIds: number[] }[]) {
        expect(producer.consultantIds).toContain(CONSULTANT.joao);
      }
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
