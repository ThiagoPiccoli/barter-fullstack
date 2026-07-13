import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { IS_PUBLIC_KEY } from '../common/decorators';
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

    const request = context.switchToHttp().getRequest<Request & { user?: unknown; tokenHash?: string }>();
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

    request.user = access.user;
    request.tokenHash = tokenHash;
    return true;
  }
}
