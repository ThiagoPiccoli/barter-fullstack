import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { ALLOWS_PROVISIONAL_PASSWORD_KEY, IS_PUBLIC_KEY } from '../common/decorators';
import { PrismaService } from '../prisma/prisma.service';
import { hashToken } from './token.util';

/**
 * Guard GLOBAL de autenticação por token Bearer. Rotas marcadas com @Public()
 * passam direto; nas demais, o token é resolvido no banco (revogável) e o
 * usuário fica disponível via @CurrentUser().
 */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const request = context
      .switchToHttp()
      .getRequest<Request & { user?: unknown; tokenHash?: string }>();
    const header = request.headers.authorization ?? '';
    const token = header.startsWith('Bearer ') ? header.slice('Bearer '.length) : '';
    if (!token) {
      throw new UnauthorizedException('Sessão inválida. Faça login novamente.');
    }

    const tokenHash = hashToken(token);
    const access = await this.prisma.accessToken.findUnique({
      where: { hash: tokenHash },
      include: { user: true },
    });
    if (!access) {
      throw new UnauthorizedException('Sessão inválida. Faça login novamente.');
    }

    // Sessão vencida morre na primeira tentativa de uso: a linha some do banco
    // e o 401 leva o app de volta ao login.
    if (access.expiresAt.getTime() <= Date.now()) {
      await this.prisma.accessToken.deleteMany({ where: { id: access.id } });
      throw new UnauthorizedException('Sessão expirada. Faça login novamente.');
    }

    // A senha provisória do provisionamento abre a conta, mas não a API: até a
    // troca, só valem as rotas que levam para fora dessa condição. Sem esta
    // trava a obrigatoriedade viveria apenas no app — e quem chamasse a API
    // direto usaria o sistema inteiro com a senha que o admin cadastrou.
    if (access.user.mustChangePassword && !this.allowsProvisionalPassword(context)) {
      throw new ForbiddenException('Defina uma nova senha para continuar.');
    }

    request.user = access.user;
    request.tokenHash = tokenHash;
    return true;
  }

  private allowsProvisionalPassword(context: ExecutionContext): boolean {
    return (
      this.reflector.getAllAndOverride<boolean>(ALLOWS_PROVISIONAL_PASSWORD_KEY, [
        context.getHandler(),
        context.getClass(),
      ]) ?? false
    );
  }
}
