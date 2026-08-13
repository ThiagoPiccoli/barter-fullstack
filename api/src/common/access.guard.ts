import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  Logger,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { User } from '@prisma/client';
import { ANY_ROLE_KEY, IS_PUBLIC_KEY, REQUIRED_CAPABILITIES_KEY, ROLES_KEY } from './decorators';
import { can, rolesWith, type Capability } from './policy';
import { ROLE_LABELS, type Role } from './roles';

/**
 * Autorização. Global, rodando depois do AuthGuard (que é quem põe o usuário
 * na request).
 *
 * A regra que importa: **nega por padrão**. Toda rota precisa declarar a sua
 * política — @RequireCapability, @AnyRole ou @Public. Rota que não declara
 * NADA é recusada.
 *
 * Isso inverte o desenho anterior, em que ausência de decorator significava
 * "liberado para qualquer autenticado". Naquele arranjo, acrescentar um
 * `@Delete(':id')` e esquecer a linha de acesso nascia funcionando — para todo
 * consultor da cooperativa. Não havia erro, nem teste vermelho, nem sintoma: a
 * rota simplesmente atendia quem não devia. Agora o esquecimento vira 403 na
 * primeira chamada e um ERRO no log dizendo qual handler está sem política.
 */
@Injectable()
export class AccessGuard implements CanActivate {
  private readonly logger = new Logger('Access');

  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    if (this.metadata<boolean>(context, IS_PUBLIC_KEY)) return true;

    const capabilities = this.metadata<Capability[]>(context, REQUIRED_CAPABILITIES_KEY);
    if (capabilities?.length) {
      return this.checkCapabilities(context, capabilities);
    }

    const roles = this.metadata<Role[]>(context, ROLES_KEY);
    if (roles?.length) {
      return this.checkRoles(context, roles);
    }

    if (this.metadata<boolean>(context, ANY_ROLE_KEY)) return true;

    // Erro de programação, não do usuário: alguém criou uma rota e não disse
    // quem pode chamá-la. A resposta fecha (403) e o log aponta o culpado —
    // porque uma rota sem política é uma decisão que ninguém tomou.
    this.logger.error(
      `Rota sem política de acesso declarada: ${context.getClass().name}.${context.getHandler().name}. ` +
        'Marque com @RequireCapability(), @AnyRole() ou @Public().',
    );
    throw new ForbiddenException('Esta ação não está disponível.');
  }

  /** Metadado do handler, caindo para o do controller. */
  private metadata<T>(context: ExecutionContext, key: string): T | undefined {
    return this.reflector.getAllAndOverride<T>(key, [context.getHandler(), context.getClass()]);
  }

  private checkCapabilities(context: ExecutionContext, required: Capability[]): boolean {
    const user = this.userOf(context);
    const missing = required.find((capability) => !user || !can(user, capability));
    if (!missing) return true;
    throw new ForbiddenException(this.denialMessage(rolesWith(missing)));
  }

  private checkRoles(context: ExecutionContext, allowed: Role[]): boolean {
    const user = this.userOf(context);
    if (user && (allowed as string[]).includes(user.role)) return true;
    throw new ForbiddenException(this.denialMessage(allowed));
  }

  private userOf(context: ExecutionContext): User | undefined {
    return context.switchToHttp().getRequest<{ user?: User }>().user;
  }

  /** Diz QUEM pode executar a ação — é a informação que resolve a dúvida. */
  private denialMessage(allowed: Role[]): string {
    if (allowed.length === 0) return 'Esta ação não está disponível.';
    return `Ação permitida apenas para: ${allowed.map((role) => ROLE_LABELS[role]).join(', ')}`;
  }
}
