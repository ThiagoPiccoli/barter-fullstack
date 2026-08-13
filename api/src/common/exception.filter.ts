import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { Request, Response } from 'express';

/**
 * Rede de segurança das respostas de erro.
 *
 * Sem ela, qualquer falha não prevista (um erro do Prisma, um bug numa regra)
 * virava um 500 pelado: nada no log para investigar depois e, dependendo do
 * erro, detalhe interno vazando no corpo da resposta. Aqui todo erro sai no
 * MESMO formato que o app já entende — `{ message, statusCode }`, com
 * `message` sempre uma frase em pt-BR pronta para exibir.
 */

/** Erros do Prisma que têm um significado claro para quem chamou a API. */
const PRISMA_ERRORS: Record<string, { status: number; message: string }> = {
  // Índice único violado — dois registros disputando o mesmo valor.
  P2002: {
    status: HttpStatus.UNPROCESSABLE_ENTITY,
    message: 'Já existe um registro com estes dados.',
  },
  // Chave estrangeira apontando para algo que não existe.
  P2003: {
    status: HttpStatus.UNPROCESSABLE_ENTITY,
    message: 'Registro relacionado não encontrado.',
  },
  // Update/delete de uma linha que sumiu no meio do caminho.
  P2025: { status: HttpStatus.NOT_FOUND, message: 'Registro não encontrado.' },
};

interface ErrorBody {
  message: string;
  statusCode: number;
  error?: string;
  requestId?: string;
}

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger('HTTP');

  catch(exception: unknown, host: ArgumentsHost): void {
    const context = host.switchToHttp();
    const request = context.getRequest<Request>();
    const response = context.getResponse<Response>();

    const body = this.describe(exception);

    // 5xx é bug nosso: registra o erro inteiro com um id e devolve só o id.
    // O usuário tem o que citar no suporte, e o detalhe interno fica no log.
    if (body.statusCode >= 500) {
      body.requestId = randomUUID();
      this.logger.error(
        `${request.method} ${request.originalUrl} → 500 [${body.requestId}]`,
        exception instanceof Error ? exception.stack : String(exception),
      );
    }

    response.status(body.statusCode).json(body);
  }

  private describe(exception: unknown): ErrorBody {
    if (exception instanceof HttpException) {
      return this.fromHttpException(exception);
    }

    return (
      this.fromPrisma(exception) ??
      this.fromBodyParser(exception) ?? {
        message: 'Erro inesperado no servidor. Tente novamente.',
        statusCode: HttpStatus.INTERNAL_SERVER_ERROR,
      }
    );
  }

  /**
   * Erros do parser de corpo (corpo grande demais, JSON malformado). Eles não
   * são HttpException — vinham como 500 e ficavam registrados como bug do
   * servidor, quando na verdade são requisições malformadas do cliente.
   */
  private fromBodyParser(exception: unknown): ErrorBody | null {
    const error = exception as { type?: unknown; status?: unknown };
    if (error?.type === 'entity.too.large') {
      return {
        message: 'O conteúdo enviado é grande demais.',
        statusCode: HttpStatus.PAYLOAD_TOO_LARGE,
      };
    }
    if (error?.type === 'entity.parse.failed') {
      return {
        message: 'O conteúdo enviado não é um JSON válido.',
        statusCode: HttpStatus.BAD_REQUEST,
      };
    }
    return null;
  }

  /**
   * Preserva o corpo que o Nest já montaria — é o contrato que o app consome
   * hoje — só normalizando os dois casos que chegariam estranhos ao usuário:
   * uma `message` que não é string, e o texto em inglês do limitador de
   * requisições.
   */
  private fromHttpException(exception: HttpException): ErrorBody {
    const status = exception.getStatus();
    const payload = exception.getResponse();

    if (status === Number(HttpStatus.TOO_MANY_REQUESTS)) {
      return {
        message: 'Muitas tentativas em pouco tempo. Aguarde um minuto e tente de novo.',
        error: 'Too Many Requests',
        statusCode: status,
      };
    }

    if (typeof payload === 'string') {
      return { message: payload, statusCode: status };
    }

    const object = payload as Record<string, unknown>;
    const message = object.message;
    return {
      ...object,
      message:
        typeof message === 'string'
          ? message
          : Array.isArray(message) && typeof message[0] === 'string'
            ? message[0]
            : exception.message,
      statusCode: status,
    };
  }

  /** Erros conhecidos do Prisma viram resposta de negócio em vez de 500. */
  private fromPrisma(exception: unknown): ErrorBody | null {
    const code = (exception as { code?: unknown })?.code;
    if (typeof code !== 'string') return null;
    const known = PRISMA_ERRORS[code];
    if (!known) return null;
    return { message: known.message, statusCode: known.status };
  }
}
