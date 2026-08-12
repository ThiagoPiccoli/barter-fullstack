import { SetMetadata, createParamDecorator, type ExecutionContext } from '@nestjs/common';
import type { User } from '@prisma/client';

export const IS_PUBLIC_KEY = 'isPublic';

/** Libera a rota do guard global de autenticação (ex.: login, raiz). */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

export const ALLOWS_PROVISIONAL_PASSWORD_KEY = 'allowsProvisionalPassword';

/**
 * Libera a rota para quem ainda está com a senha provisória (ver
 * mustChangePassword). Só o necessário para SAIR dessa condição deve usar
 * isto: consultar quem se é, trocar a senha e desistir e sair. Todo o resto
 * da API fica fechado até a troca — ver o AuthGuard.
 */
export const AllowProvisionalPassword = () =>
  SetMetadata(ALLOWS_PROVISIONAL_PASSWORD_KEY, true);

/** Usuário autenticado, colocado na request pelo AuthGuard. */
export const CurrentUser = createParamDecorator((_data: unknown, context: ExecutionContext): User => {
  return context.switchToHttp().getRequest().user as User;
});
