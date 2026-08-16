import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import type { Request } from 'express';
import { Observable, map } from 'rxjs';
import { Paginated } from './pagination';

/**
 * Envelopa toda resposta de sucesso em `{ data: ... }` — o formato que o app
 * Flutter desembrulha. Respostas sem corpo (204) passam intactas, e as rotas
 * de fora do /api/v1 ficam sem envelope.
 *
 * Listas paginadas ganham um `meta` ao lado: `data` continua sendo o array
 * puro (o cliente não muda como lê a lista) e `meta.total` conta o que existe
 * além da página atual.
 */

/**
 * As rotas que não são da API: a raiz e a sonda de saúde. Quem as consome não
 * é o app — é gente digitando a URL e balanceador de carga —, e nenhum dos
 * dois espera desembrulhar um `data`.
 */
const UNWRAPPED_PATHS = new Set(['/', '/health']);

@Injectable()
export class EnvelopeInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<Request>();
    if (UNWRAPPED_PATHS.has(request.path)) {
      return next.handle();
    }
    return next.handle().pipe(
      // `next.handle()` é um Observable<any>; anotar aqui mantém o restante do
      // interceptor honestamente tipado em vez de espalhar `any`.
      map((payload: unknown) => {
        if (payload === undefined) return undefined;
        if (Paginated.is(payload)) {
          return {
            data: payload.items,
            meta: { total: payload.total, limit: payload.limit, offset: payload.offset },
          };
        }
        return { data: payload };
      }),
    );
  }
}
