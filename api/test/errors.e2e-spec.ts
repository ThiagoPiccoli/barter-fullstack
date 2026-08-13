import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { ADMIN, createTestApp, loginAs, resetDb } from './utils';

/**
 * O CONTRATO DE ERRO. O app mostra `message` direto para o usuário — é o que
 * ele lê de toda resposta com status >= 400 (ver api_client.dart). Então toda
 * falha, venha de onde vier, precisa sair com `message` sendo uma frase única
 * em português. Estes testes prendem esse contrato nas bordas em que ele já
 * escapou: erros do middleware, que nascem fora do alcance dos guards e pipes.
 */
describe('Contrato de erro (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  it('JSON malformado responde 400 em português, não a mensagem crua do motor', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .set('Content-Type', 'application/json')
      .send('{quebrado');

    expect(response.status).toBe(400);
    expect(response.body.message).toBe('O conteúdo enviado não é um JSON válido.');
  });

  /**
   * Antes do limite explícito, um corpo gigante era interpretado inteiro; e
   * quando passou a ser recusado, a recusa chegava como 500 — registrada como
   * bug do servidor, quando é requisição malformada do cliente.
   */
  it('corpo acima do limite responde 413, não 500', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .set('Content-Type', 'application/json')
      .send(JSON.stringify({ email: 'a@b.co', password: 'x'.repeat(300_000) }));

    expect(response.status).toBe(413);
    expect(response.body.message).toBe('O conteúdo enviado é grande demais.');
  });

  it('erro de validação continua saindo como 422 com uma frase única', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/producers')
      .set('Authorization', `Bearer ${await loginAs(app, ADMIN)}`)
      .send({ name: 'X' });

    expect(response.status).toBe(422);
    expect(typeof response.body.message).toBe('string');
  });

  it('rota inexistente responde 404 com o mesmo formato', async () => {
    const response = await request(app.getHttpServer())
      .get('/api/v1/nao-existe')
      .set('Authorization', `Bearer ${await loginAs(app, ADMIN)}`);

    expect(response.status).toBe(404);
    expect(typeof response.body.message).toBe('string');
    expect(response.body.statusCode).toBe(404);
  });

  // O 429 e os erros do Prisma são cobertos em src/common/exception.filter.spec.ts:
  // aqui eles dependeriam de estourar o limite de verdade (que o .env.test
  // afrouxa para a suíte caber) ou de forjar uma falha de banco.
});
