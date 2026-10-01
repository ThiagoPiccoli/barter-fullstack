import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import {
  ADMIN,
  ANA,
  CONSULTANT,
  GERENTE,
  JOAO,
  ROBERTO,
  createTestApp,
  loginAs,
  resetDb,
} from './utils';

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

  it('consultor enxerga a própria carteira', async () => {
    const token = await loginAs(app, JOAO);
    const response = await get('/api/v1/producers', token);

    expect(response.status).toBe(200);
    expect(namesOf(response.body)).toEqual(['Antônio Carvalho', 'Sebastião Ramos']);
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

  it('o admin cadastra o produtor na carteira que escolher', async () => {
    const asAdmin = await request(app.getHttpServer())
      .post('/api/v1/producers')
      .set('Authorization', `Bearer ${await loginAs(app, ADMIN)}`)
      .send({
        name: 'Produtor Novo',
        consultantId: CONSULTANT.joao,
        document: 'CPF 999.999.999-99',
        farmName: 'Fazenda Teste',
        city: 'Maringá/PR',
        areaHa: 55,
      });
    expect(asAdmin.status).toBe(201);
    expect(asAdmin.body.data.consultantId).toBe(CONSULTANT.joao);

    // A carteira vem do MAIS RECENTE para o mais antigo: o recém-cadastrado
    // abre a lista.
    const carteira = await get('/api/v1/producers', await loginAs(app, JOAO));
    expect(carteira.body.data[0].name).toBe('Produtor Novo');
  });

  /**
   * O CONSULTOR CADASTRA O CLIENTE NOVO — e ele nasce na carteira dele, só na
   * dele. Quem conhece o cliente é quem foi à fazenda; mandá-lo pedir o
   * cadastro ao admin antes da primeira permuta fazia de cada cliente novo um
   * chamado.
   */
  describe('o consultor cadastra produtor', () => {
    const novo = {
      name: 'Produtor do João',
      document: 'CPF 999.999.999-99',
      farmName: 'Fazenda Nova Esperança',
      city: 'Maringá/PR',
      areaHa: 55,
      taxRegime: 'folha',
    };

    const cadastrar = async (email: string, body: Record<string, unknown>) =>
      request(app.getHttpServer())
        .post('/api/v1/producers')
        .set('Authorization', `Bearer ${await loginAs(app, email)}`)
        .send(body);

    it('sem dizer a carteira, o produtor nasce na dele', async () => {
      const response = await cadastrar(JOAO, novo);

      expect(response.status).toBe(201);
      expect(response.body.data).toMatchObject({
        consultantId: CONSULTANT.joao,
        areaHa: 55,
        taxRegime: 'folha',
      });

      // E é DELE: aparece na carteira do João e em nenhuma outra.
      const id = response.body.data.id;
      expect((await get(`/api/v1/producers/${id}`, await loginAs(app, JOAO))).status).toBe(200);
      expect((await get(`/api/v1/producers/${id}`, await loginAs(app, ANA))).status).toBe(403);
    });

    /** É o que o app manda: o formulário preenche a carteira com quem está logado. */
    it('mandar o próprio id como carteira é o mesmo que não mandar', async () => {
      const response = await cadastrar(JOAO, { ...novo, consultantId: CONSULTANT.joao });
      expect(response.status).toBe(201);
      expect(response.body.data.consultantId).toBe(CONSULTANT.joao);
    });

    /**
     * A carteira de outro consultor é RECUSADA, e não trocada em silêncio pela
     * dele: quem mandou outro id queria outra coisa.
     */
    it('a carteira de outro consultor é recusada, dizendo a quem pedir', async () => {
      const response = await cadastrar(JOAO, { ...novo, consultantId: CONSULTANT.ana });

      expect(response.status).toBe(403);
      expect(response.body.message).toContain('administrador');
      // E nada foi gravado.
      const ana = await get(
        `/api/v1/producers?consultantId=${CONSULTANT.ana}`,
        await loginAs(app, ADMIN),
      );
      expect(namesOf(ana.body)).not.toContain('Produtor do João');
    });

    /** O cliente que já é dele: a mensagem o nomeia, e o caminho é abrir o que existe. */
    it('CPF já cadastrado na carteira dele é barrado, nomeando o cliente', async () => {
      // Antônio Carvalho (id 1) é do João; a formatação não engana a regra.
      const response = await cadastrar(JOAO, { ...novo, document: '12345678900' });

      expect(response.status).toBe(422);
      expect(response.body.message).toBe(
        'Este CPF já está cadastrado na sua carteira, para "Antônio Carvalho". ' +
          'Use o cadastro que já existe',
      );
    });

    /**
     * O cliente que é de OUTRO consultor: barrado, mas sem nome e sem colega. A
     * recusa não pode virar uma consulta de "quem atende o CPF tal" — a carteira
     * dos outros não é dele.
     */
    it('CPF/CNPJ de outra carteira é barrado sem expor quem é nem quem atende', async () => {
      // Helena Prado (id 2) é da Ana.
      const cpf = await cadastrar(JOAO, { ...novo, document: 'CPF 234.567.890-11' });
      expect(cpf.status).toBe(422);
      expect(cpf.body.message).toBe(
        'Este CPF já está cadastrado e o produtor é atendido por outro consultor. ' +
          'Para passar a atendê-lo, fale com o administrador',
      );
      expect(cpf.body.message).not.toContain('Helena');
      expect(cpf.body.message).not.toContain('Ana');

      // Joaquim Tavares (id 3) é do Roberto, e é CNPJ — a mensagem diz CNPJ.
      const cnpj = await cadastrar(JOAO, { ...novo, document: '12.345.678/0001-90' });
      expect(cnpj.status).toBe(422);
      expect(cnpj.body.message).toContain('Este CNPJ já está cadastrado');
      expect(cnpj.body.message).not.toContain('Joaquim');
    });

    /** Quem enxerga todas as carteiras continua lendo o nome: é o que ele precisa para decidir. */
    it('para o admin, a recusa continua nomeando o produtor', async () => {
      const response = await cadastrar(ADMIN, {
        ...novo,
        consultantId: CONSULTANT.joao,
        document: 'CPF 234.567.890-11',
      });
      expect(response.status).toBe(422);
      expect(response.body.message).toBe('Este CPF já está cadastrado para "Helena Prado"');
    });

    /** Quem não é consultor nem admin não cadastra — a retaguarda lê, não escreve. */
    it('a retaguarda não cadastra', async () => {
      const response = await cadastrar(GERENTE, { ...novo, consultantId: CONSULTANT.joao });
      expect(response.status).toBe(403);
    });
  });

  /**
   * O REGIME DE RECOLHIMENTO é dado do produtor: a opção pela folha é feita uma
   * vez, perante o fisco, e vale para todas as entregas dele. É daqui que cada
   * permuta nova o herda (ver `Producer.taxRegime`).
   */
  describe('regime de recolhimento do Funrural', () => {
    const cadastrar = async (taxRegime?: string) =>
      request(app.getHttpServer())
        .post('/api/v1/producers')
        .set('Authorization', `Bearer ${await loginAs(app, ADMIN)}`)
        .send({
          name: 'Produtor da Folha',
          consultantId: CONSULTANT.joao,
          document: 'CPF 888.888.888-88',
          farmName: 'Fazenda da Folha',
          city: 'Maringá/PR',
          areaHa: 90,
          ...(taxRegime === undefined ? {} : { taxRegime }),
        });

    it('o cadastro guarda a opção do produtor', async () => {
      const response = await cadastrar('folha');
      expect(response.status).toBe(201);
      expect(response.body.data.taxRegime).toBe('folha');
    });

    /** Quem não fez opção nenhuma cai na comercialização — que é a maioria. */
    it('sem opção declarada, o produtor recolhe sobre a comercialização', async () => {
      const response = await cadastrar();
      expect(response.body.data.taxRegime).toBe('comercializacao');
    });

    it('regime que não existe é recusado', async () => {
      const response = await cadastrar('presumido');
      expect(response.status).toBe(422);
      expect(response.body.message).toContain('recolhimento');
    });

    it('a edição troca o regime do produtor já cadastrado', async () => {
      const admin = `Bearer ${await loginAs(app, ADMIN)}`;
      // Antônio Carvalho (id 1) está na comercialização no dataset.
      const response = await request(app.getHttpServer())
        .put('/api/v1/producers/1')
        .set('Authorization', admin)
        .send({
          name: 'Antônio Carvalho',
          consultantId: CONSULTANT.joao,
          document: 'CPF 123.456.789-00',
          farmName: 'Fazenda Boa Vista',
          city: 'Maringá/PR',
          areaHa: 120,
          taxRegime: 'folha',
        });

      expect(response.status).toBe(200);
      expect(response.body.data.taxRegime).toBe('folha');
    });
  });

  it('produtor precisa nascer na carteira de um consultor válido', async () => {
    const admin = await loginAs(app, ADMIN);
    const create = (extra: Record<string, unknown>) =>
      request(app.getHttpServer())
        .post('/api/v1/producers')
        .set('Authorization', `Bearer ${admin}`)
        .send({
          name: 'Sem Carteira',
          document: 'CPF 111.222.333-44',
          farmName: 'Fazenda X',
          city: 'Cidade/PR',
          areaHa: 10,
          ...extra,
        });

    // Sem consultor: um produtor que ninguém atende não aparece para ninguém.
    const missing = await create({});
    expect(missing.status).toBe(422);
    expect(missing.body.message).toContain('consultor');

    // O admin não tem carteira — e a mensagem NOMEIA quem não serve.
    const notConsultant = await create({ consultantId: 1 });
    expect(notConsultant.status).toBe(422);
    expect(notConsultant.body.message).toContain('Carlos Mendes');

    // Lista não é carteira: são dois consultores, e a regra é um.
    const list = await create({ consultantId: [CONSULTANT.joao, CONSULTANT.ana] });
    expect(list.status).toBe(422);
  });

  it('consultores diferentes têm carteiras diferentes', async () => {
    const token = await loginAs(app, ANA);
    const response = await get('/api/v1/producers', token);
    const names = response.body.data.map((p: { name: string }) => p.name);
    expect(names).not.toContain('Antônio Carvalho');
    expect(names).toContain('Helena Prado');
  });

  /**
   * UM CONSULTOR POR PRODUTOR. A troca de consultor é edição do cadastro, e o
   * que ela move é o PRODUTOR — as permutas continuam de quem as registrou.
   */
  describe('um consultor por produtor', () => {
    const admin = () => loginAs(app, ADMIN);

    /** Joaquim Tavares (id 3), do Roberto no seed. */
    const joaquim = {
      name: 'Joaquim Tavares',
      document: 'CNPJ 12.345.678/0001-90',
      farmName: 'Fazenda Santa Rita',
      city: 'Mandaguari/PR',
      areaHa: 320,
    };

    const transferir = async (consultantId: number) =>
      request(app.getHttpServer())
        .put('/api/v1/producers/3')
        .set('Authorization', `Bearer ${await admin()}`)
        .send({ ...joaquim, consultantId });

    it('o produtor está na carteira de um consultor só', async () => {
      const doRoberto = await get('/api/v1/producers/3', await loginAs(app, ROBERTO));
      expect(doRoberto.status).toBe(200);
      expect(doRoberto.body.data.consultantId).toBe(CONSULTANT.roberto);

      const doJoao = await get('/api/v1/producers/3', await loginAs(app, JOAO));
      expect(doJoao.status).toBe(403);
    });

    it('trocar o consultor passa o produtor para a carteira do outro', async () => {
      const response = await transferir(CONSULTANT.joao);
      expect(response.status).toBe(200);
      expect(response.body.data.consultantId).toBe(CONSULTANT.joao);

      expect((await get('/api/v1/producers/3', await loginAs(app, JOAO))).status).toBe(200);
      expect((await get('/api/v1/producers/3', await loginAs(app, ROBERTO))).status).toBe(403);
    });

    /**
     * A permuta é de quem a registrou (`Barter.consultantId`), não de quem
     * atende o produtor hoje: a troca de carteira não tira do Roberto as
     * permutas que ele fechou com o Joaquim, nem as entrega ao João.
     */
    it('a troca não leva as permutas que o consultor anterior registrou', async () => {
      await transferir(CONSULTANT.joao).then((r) => expect(r.status).toBe(200));

      const codes = async (email: string) =>
        (await get('/api/v1/barters', await loginAs(app, email))).body.data.map(
          (b: { code: string }) => b.code,
        );
      expect(await codes(ROBERTO)).toEqual(
        expect.arrayContaining(['PRM-2026-003', 'PRM-2026-008']),
      );
      expect(await codes(JOAO)).not.toContain('PRM-2026-003');
    });

    it('o filtro por consultor acompanha a troca', async () => {
      await transferir(CONSULTANT.joao).then((r) => expect(r.status).toBe(200));
      const token = await admin();

      const doJoao = await get(`/api/v1/producers?consultantId=${CONSULTANT.joao}`, token);
      expect(namesOf(doJoao.body)).toContain('Joaquim Tavares');
      const doRoberto = await get(`/api/v1/producers?consultantId=${CONSULTANT.roberto}`, token);
      expect(namesOf(doRoberto.body)).not.toContain('Joaquim Tavares');
    });

    it('editar sem mandar o consultor mantém o que estava', async () => {
      const response = await request(app.getHttpServer())
        .put('/api/v1/producers/3')
        .set('Authorization', `Bearer ${await admin()}`)
        .send({ ...joaquim, farmName: 'Fazenda Santa Rita II' });

      expect(response.status).toBe(200);
      expect(response.body.data.consultantId).toBe(CONSULTANT.roberto);
    });

    it('a troca só aceita consultor', async () => {
      const response = await transferir(1); // admin
      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Carlos Mendes');
    });
  });

  /**
   * OS DADOS DO PRODUTOR SÃO GERIDOS PELO CONSULTOR — e até onde.
   *
   * Quem visita a fazenda é quem sabe que o telefone mudou, que o cliente
   * arrendou mais terra para esta cultura e que o CPF saiu errado no cadastro.
   * Ele altera TODOS os dados do cliente dele — o documento, a área do Barter e
   * o regime de Funrural inclusive.
   *
   * O que ele NÃO alcança é o outro lado da mesma regra, e é o que estes testes
   * fixam: o produtor de outra carteira e a própria carteira — quem atende
   * quem é decisão de quem administra.
   */
  describe('o consultor gere os dados do produtor da carteira dele', () => {
    /** Antônio Carvalho (id 1), da carteira do João, como está no seed. */
    const antonio = {
      name: 'Antônio Carvalho',
      document: 'CPF 123.456.789-00',
      farmName: 'Fazenda Boa Vista',
      city: 'Maringá/PR',
      areaHa: 120,
    };

    const editar = async (id: number, email: string, body: Record<string, unknown>) =>
      request(app.getHttpServer())
        .put(`/api/v1/producers/${id}`)
        .set('Authorization', `Bearer ${await loginAs(app, email)}`)
        .send(body);

    it('o consultor corrige contato e endereço do próprio cliente', async () => {
      const response = await editar(1, JOAO, {
        ...antonio,
        phone: '(44) 99999-1234',
        farmName: 'Fazenda Boa Vista II',
        city: 'Mandaguari/PR',
      });

      expect(response.status).toBe(200);
      expect(response.body.data).toMatchObject({
        phone: '(44) 99999-1234',
        farmName: 'Fazenda Boa Vista II',
        city: 'Mandaguari/PR',
      });
      // E a carteira fica como estava: ele não mandou o campo, e o servidor não
      // o inventa.
      expect(response.body.data.consultantId).toBe(CONSULTANT.joao);
    });

    /**
     * O app manda o cadastro INTEIRO de volta, com o consultor que já estava lá.
     * A carteira é recusada por MUDANÇA, como a área e o documento — recusá-la
     * por presença travaria a edição de telefone do próprio cliente.
     */
    it('mandar o próprio consultor de volta não é mexer na carteira', async () => {
      const response = await editar(1, JOAO, {
        ...antonio,
        phone: '(44) 99999-1234',
        consultantId: CONSULTANT.joao,
      });

      expect(response.status).toBe(200);
      expect(response.body.data.consultantId).toBe(CONSULTANT.joao);
    });

    it('produtor de carteira alheia continua fora do alcance dele', async () => {
      // Helena Prado (id 2) é atendida só pela Ana.
      const response = await editar(2, JOAO, { ...antonio, name: 'Helena Prado' });
      expect(response.status).toBe(403);
      expect(response.body.message).toContain('não pertence à sua carteira');
    });

    /**
     * A ÁREA DO BARTER muda de uma cultura para outra, e quem sabe qual é a
     * desta safra é o consultor. O REGIME é a opção que o produtor fez perante o
     * fisco, e quem a traz da fazenda é ele também.
     */
    it('o consultor altera a área e o regime de Funrural do cliente dele', async () => {
      const response = await editar(1, JOAO, { ...antonio, areaHa: 400, taxRegime: 'folha' });

      expect(response.status).toBe(200);
      expect(response.body.data).toMatchObject({ areaHa: 400, taxRegime: 'folha' });
    });

    /**
     * A permuta JÁ REGISTRADA não acompanha: ela congelou a área que usou, e é
     * o denominador do sc/ha que alguém já aprovou.
     */
    it('a área nova não reescreve a das permutas já registradas', async () => {
      // Lida pelo admin: `producerAreaHa` vai só para quem vê o sc/ha.
      const auth = `Bearer ${await loginAs(app, ADMIN)}`;
      const antes = await request(app.getHttpServer())
        .get('/api/v1/barters')
        .set('Authorization', auth);
      const doAntonio = antes.body.data.find(
        (b: { producerId: number; producerAreaHa: number }) =>
          b.producerId === 1 && b.producerAreaHa > 0,
      );
      expect(doAntonio).toBeDefined();

      await editar(1, JOAO, { ...antonio, areaHa: 400 }).then((r) => expect(r.status).toBe(200));

      const depois = await request(app.getHttpServer())
        .get(`/api/v1/barters/${doAntonio.code}`)
        .set('Authorization', auth);
      expect(depois.body.data.producerAreaHa).toBe(doAntonio.producerAreaHa);
    });

    /** O CPF/CNPJ também: um dígito trocado no cadastro, quem percebe é ele. */
    it('o consultor corrige o CPF/CNPJ do cliente dele', async () => {
      const response = await editar(1, JOAO, { ...antonio, document: 'CPF 111.222.333-44' });

      expect(response.status).toBe(200);
      expect(response.body.data.document).toBe('CPF 111.222.333-44');
    });

    /**
     * Mas a UNICIDADE vale na edição também: trocar para o CPF de um cliente que
     * já existe transformaria o A no B. E a recusa não expõe a carteira alheia.
     */
    it('trocar para um CPF/CNPJ já cadastrado é barrado', async () => {
      // Helena Prado (id 2) é da Ana.
      const response = await editar(1, JOAO, { ...antonio, document: 'CPF 234.567.890-11' });

      expect(response.status).toBe(422);
      expect(response.body.message).toContain('Este CPF já está cadastrado');
      expect(response.body.message).not.toContain('Helena');
    });

    /**
     * A CARTEIRA é de quem administra: um consultor que a escrevesse poderia
     * passar o próprio cliente adiante sem que ninguém tivesse decidido isso.
     */
    it('a carteira continua sendo do admin', async () => {
      const response = await editar(1, JOAO, { ...antonio, consultantId: CONSULTANT.ana });

      expect(response.status).toBe(403);
      expect(response.body.message).toContain('administrador');
    });

    /** Excluir continua onde estava: quem sai da base é decisão do admin. */
    it('excluir continua fora do alcance do consultor', async () => {
      const token = `Bearer ${await loginAs(app, JOAO)}`;
      const excluido = await request(app.getHttpServer())
        .delete('/api/v1/producers/1')
        .set('Authorization', token);
      expect(excluido.status).toBe(403);
    });

    /** E o admin continua alcançando tudo — inclusive o que o consultor não alcança. */
    it('o admin continua alterando a área, o documento e a carteira', async () => {
      const response = await editar(1, ADMIN, {
        ...antonio,
        areaHa: 400,
        taxRegime: 'folha',
        consultantId: CONSULTANT.ana,
      });

      expect(response.status).toBe(200);
      expect(response.body.data).toMatchObject({
        areaHa: 400,
        taxRegime: 'folha',
        consultantId: CONSULTANT.ana,
      });
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
      consultantId: CONSULTANT.joao,
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
          consultantId: CONSULTANT.joao,
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
      expect(response.body.data.length).toBeGreaterThan(0);
      for (const producer of response.body.data as { consultantId: number }[]) {
        expect(producer.consultantId).toBe(CONSULTANT.joao);
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
