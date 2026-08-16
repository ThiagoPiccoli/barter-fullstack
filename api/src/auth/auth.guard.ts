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
import { hashToken, isIdle } from './token.util';

/**
 * De quanto em quanto tempo o "visto por último" da sessão é regravado.
 *
 * A expiração por inatividade precisa saber quando o token foi usado, e o
 * caminho ingênuo — anotar a cada requisição — transformaria TODA chamada
 * autenticada da API num UPDATE a mais, no caminho crítico, para mover um
 * relógio em alguns milissegundos. Uma hora de granularidade é irrelevante
 * para um limite medido em dias e derruba a escrita para uma por sessão ativa
 * por hora.
 */
const TOUCH_INTERVAL_MS = 60 * 60 * 1000;

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
    // e o 401 leva o app de volta ao login. Dois jeitos de vencer — o prazo
    // absoluto e o tempo parada (ver tokenIdleDays) —, e o efeito é o mesmo.
    const now = new Date();
    if (access.expiresAt.getTime() <= now.getTime() || isIdle(access.lastUsedAt, now)) {
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

    await this.touch(access.id, access.lastUsedAt, now);

    request.user = access.user;
    request.tokenHash = tokenHash;
    return true;
  }

  /**
   * Anota que a sessão foi usada — no máximo uma vez por hora (ver
   * TOUCH_INTERVAL_MS).
   *
   * A falha é engolida de propósito: não conseguir mover o relógio da sessão é
   * problema de manutenção, não motivo para recusar uma requisição que está
   * autenticada e autorizada. O pior caso de não gravar é a sessão parecer mais
   * parada do que está — ou seja, o erro cai para o lado seguro.
   */
  private async touch(id: number, lastUsedAt: Date, now: Date): Promise<void> {
    if (now.getTime() - lastUsedAt.getTime() < TOUCH_INTERVAL_MS) return;
    try {
      await this.prisma.accessToken.update({ where: { id }, data: { lastUsedAt: now } });
    } catch {
      // Sessão revogada entre a leitura e agora: a próxima requisição resolve.
    }
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
