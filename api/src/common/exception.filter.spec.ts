import { ForbiddenException, HttpException, HttpStatus, Logger } from '@nestjs/common';
import type { ArgumentsHost } from '@nestjs/common';
import { AllExceptionsFilter } from './exception.filter';

/**
 * O app mostra `message` direto para o usuário. Este filtro é o último ponto
 * por onde todo erro passa, então é aqui que se garante que nada chegue à tela
 * em inglês, com detalhe interno, ou sem mensagem nenhuma.
 */
describe('AllExceptionsFilter', () => {
  /** Dispara o filtro e devolve o status e o corpo que ele escreveu. */
  function handle(exception: unknown): { status: number; body: Record<string, unknown> } {
    let status = 0;
    let body: Record<string, unknown> = {};
    const response = {
      status: (code: number) => {
        status = code;
        return { json: (payload: Record<string, unknown>) => (body = payload) };
      },
    };
    const host = {
      switchToHttp: () => ({
        getRequest: () => ({ method: 'GET', originalUrl: '/api/v1/qualquer' }),
        getResponse: () => response,
      }),
    } as unknown as ArgumentsHost;

    new AllExceptionsFilter().catch(exception, host);
    return { status, body };
  }

  beforeAll(() => {
    // O 500 registra o erro de propósito; nos testes isso só polui a saída.
    jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
  });
  afterAll(() => jest.restoreAllMocks());

  it('preserva as exceções de negócio como já eram', () => {
    const { status, body } = handle(new ForbiddenException('Você não tem acesso a esta permuta'));
    expect(status).toBe(403);
    expect(body.message).toBe('Você não tem acesso a esta permuta');
  });

  /**
   * O limitador de requisições responde "ThrottlerException: Too many
   * requests" — texto de biblioteca, em inglês, que ia direto para a tela.
   */
  it('traduz o 429 do limitador', () => {
    const { status, body } = handle(
      new HttpException('ThrottlerException: Too many requests', HttpStatus.TOO_MANY_REQUESTS),
    );
    expect(status).toBe(429);
    expect(body.message).toBe(
      'Muitas tentativas em pouco tempo. Aguarde um minuto e tente de novo.',
    );
  });

  it('reduz a lista de erros de validação à primeira frase', () => {
    const { body } = handle(
      new HttpException(
        { message: ['primeiro problema', 'segundo problema'], statusCode: 422 },
        422,
      ),
    );
    expect(body.message).toBe('primeiro problema');
  });

  describe('erros do Prisma viram resposta de negócio', () => {
    it('índice único violado (P2002) vira 422', () => {
      const { status, body } = handle({ code: 'P2002', meta: { target: ['email'] } });
      expect(status).toBe(422);
      expect(body.message).toBe('Já existe um registro com estes dados.');
    });

    it('registro sumido (P2025) vira 404', () => {
      expect(handle({ code: 'P2025' }).status).toBe(404);
    });

    it('código desconhecido do Prisma continua sendo 500', () => {
      expect(handle({ code: 'P9999' }).status).toBe(500);
    });
  });

  /**
   * O 500 é a única resposta que o usuário não pode entender — então ela não
   * pode carregar detalhe interno. Sai um id, e o detalhe fica no log.
   */
  it('erro inesperado não vaza detalhe interno e ganha um id rastreável', () => {
    const { status, body } = handle(new Error('connect ECONNREFUSED 10.0.0.7:5432'));
    expect(status).toBe(500);
    expect(body.message).toBe('Erro inesperado no servidor. Tente novamente.');
    expect(JSON.stringify(body)).not.toContain('ECONNREFUSED');
    expect(typeof body.requestId).toBe('string');
  });

  it('erros do parser de corpo não são tratados como bug do servidor', () => {
    expect(handle({ type: 'entity.too.large' }).status).toBe(413);
    expect(handle({ type: 'entity.parse.failed' }).status).toBe(400);
  });
});
