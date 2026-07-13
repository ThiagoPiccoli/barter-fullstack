import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import type { Request } from 'express';
import { Observable, map } from 'rxjs';

/**
 * Envelopa toda resposta de sucesso em `{ data: ... }` — o formato que o app
 * Flutter desembrulha. Respostas sem corpo (204) passam intactas, e a rota
 * raiz (fora de /api/v1) fica sem envelope.
 */
@Injectable()
export class EnvelopeInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<Request>();
    if (request.path === '/') {
      return next.handle();
    }
    return next.handle().pipe(map((data) => (data === undefined ? undefined : { data })));
  }
}
