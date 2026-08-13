import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import type { Request } from 'express';
import { Observable, map } from 'rxjs';
import { Paginated } from './pagination';

/**
 * Envelopa toda resposta de sucesso em `{ data: ... }` — o formato que o app
 * Flutter desembrulha. Respostas sem corpo (204) passam intactas, e a rota
 * raiz (fora de /api/v1) fica sem envelope.
 *
 * Listas paginadas ganham um `meta` ao lado: `data` continua sendo o array
 * puro (o cliente não muda como lê a lista) e `meta.total` conta o que existe
 * além da página atual.
 */
@Injectable()
export class EnvelopeInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<Request>();
    if (request.path === '/') {
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
