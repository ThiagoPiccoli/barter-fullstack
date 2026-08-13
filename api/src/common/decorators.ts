import { SetMetadata, createParamDecorator, type ExecutionContext } from '@nestjs/common';
import type { User } from '@prisma/client';
import type { Capability } from './policy';
import type { Role } from './roles';

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
export const AllowProvisionalPassword = () => SetMetadata(ALLOWS_PROVISIONAL_PASSWORD_KEY, true);

export const REQUIRED_CAPABILITIES_KEY = 'requiredCapabilities';

/**
 * Exige a(s) capacidade(s) para entrar na rota. A rota declara o que PRECISA;
 * quem tem isso está em policy.ts, num lugar só.
 *
 * Quem aplica é o AccessGuard, global: basta a anotação, sem @UseGuards junto.
 */
export const RequireCapability = (...capabilities: Capability[]) =>
  SetMetadata(REQUIRED_CAPABILITIES_KEY, capabilities);

export const ANY_ROLE_KEY = 'anyRole';

/**
 * Abre a rota a QUALQUER usuário autenticado, seja qual for o papel. Existe
 * para ser explícito: leituras escopadas (`GET /barters`, `GET /producers`)
 * são abertas de propósito porque quem limita o que cada um vê é o SERVICE,
 * linha a linha — não a porta.
 *
 * A marca é obrigatória. O AccessGuard NEGA rota que não declare política
 * nenhuma, então "abrir para todo mundo" passou a ser uma decisão escrita, e
 * não o que acontece quando alguém esquece o decorator.
 */
export const AnyRole = () => SetMetadata(ANY_ROLE_KEY, true);

export const ROLES_KEY = 'roles';

/**
 * Restringe a rota aos papéis listados, sem passar pelas capacidades.
 *
 * Prefira @RequireCapability: ele diz o que a rota FAZ, e a resposta de quem
 * pode fica na tabela. Este aqui é para o caso raro em que a rota é sobre o
 * papel em si, não sobre uma ação.
 */
export const Roles = (...roles: Role[]) => SetMetadata(ROLES_KEY, roles);

/** Usuário autenticado, colocado na request pelo AuthGuard. */
export const CurrentUser = createParamDecorator(
  (_data: unknown, context: ExecutionContext): User =>
    context.switchToHttp().getRequest<{ user: User }>().user,
);
