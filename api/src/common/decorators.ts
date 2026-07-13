import { SetMetadata, createParamDecorator, type ExecutionContext } from '@nestjs/common';
import type { User } from '@prisma/client';

export const IS_PUBLIC_KEY = 'isPublic';

/** Libera a rota do guard global de autenticação (ex.: login, raiz). */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

/** Usuário autenticado, colocado na request pelo AuthGuard. */
export const CurrentUser = createParamDecorator((_data: unknown, context: ExecutionContext): User => {
  return context.switchToHttp().getRequest().user as User;
});
