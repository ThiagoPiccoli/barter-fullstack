import { BadRequestException, Injectable, UnprocessableEntityException } from '@nestjs/common';
import type { User } from '@prisma/client';
import { AUDIT_ACTION, AuditService } from '../audit/audit.service';
import { PrismaService } from '../prisma/prisma.service';
import {
  CLEARED_LOCKOUT,
  LOCK_MINUTES,
  MAX_FAILED_ATTEMPTS,
  isLocked,
  lockExpiryFrom,
} from './lockout';
import { burnPasswordTime, hashPassword, needsRehash, verifyPassword } from './password.util';
import { passwordProblem } from './password-policy';
import { generateToken, hashToken, tokenExpiry } from './token.util';

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  /**
   * Verifica credenciais e emite um token opaco com prazo. Erro genérico (400)
   * sem distinguir "e-mail não existe" de "senha errada" — nem, agora, de
   * "conta trancada": dizer qual dos três seria dizer quais e-mails existem.
   */
  async login(email: string, password: string): Promise<{ user: User; token: string }> {
    const user = await this.prisma.user.findUnique({ where: { email } });

    // E-mail desconhecido também paga o preço de um scrypt. Sem isso a
    // resposta volta rápido demais e o TEMPO responde o que a mensagem
    // genérica esconde: quais e-mails estão cadastrados.
    if (!user) {
      await burnPasswordTime();
      await this.recordFailure(email, 'e-mail sem cadastro');
      throw new BadRequestException('Credenciais inválidas');
    }

    // Conta trancada paga o mesmo scrypt, pelo mesmo motivo: responder rápido
    // aqui e devagar ali diria, pelo relógio, que esta conta existe.
    if (isLocked(user)) {
      await burnPasswordTime();
      await this.recordFailure(email, 'conta temporariamente bloqueada', user);
      throw new BadRequestException('Credenciais inválidas');
    }

    if (!(await verifyPassword(password, user.password))) {
      await this.registerFailedAttempt(user);
      throw new BadRequestException('Credenciais inválidas');
    }

    const current = await this.clearFailures(await this.upgradeHashIfStale(user, password));

    const token = generateToken();
    await this.prisma.accessToken.create({
      data: { hash: hashToken(token), userId: user.id, expiresAt: tokenExpiry() },
    });

    await this.audit.record({
      actor: current,
      action: AUDIT_ACTION.sessionStarted,
      targetType: 'session',
      targetId: current.id,
      targetLabel: current.email,
    });
    return { user: current, token };
  }

  /**
   * Conta a tentativa errada e, no teto, tranca a conta.
   *
   * O contador zera junto com a trava: as dez tentativas seguintes começam do
   * zero, e não a um passo de trancar de novo para sempre.
   */
  private async registerFailedAttempt(user: User): Promise<void> {
    const attempts = user.failedLoginAttempts + 1;
    const locking = attempts >= MAX_FAILED_ATTEMPTS;

    await this.prisma.user.update({
      where: { id: user.id },
      data: locking
        ? { failedLoginAttempts: 0, lockedUntil: lockExpiryFrom() }
        : { failedLoginAttempts: attempts },
    });

    if (locking) {
      await this.audit.record({
        actor: user,
        action: AUDIT_ACTION.sessionLocked,
        targetType: 'session',
        targetId: user.id,
        targetLabel: user.email,
        detail: `${MAX_FAILED_ATTEMPTS} tentativas erradas — bloqueada por ${LOCK_MINUTES} min`,
      });
      return;
    }
    await this.recordFailure(user.email, `senha incorreta (${attempts}ª tentativa)`, user);
  }

  /** Acertou: o contador e a trava somem, senão a conta erraria por herança. */
  private async clearFailures(user: User): Promise<User> {
    if (user.failedLoginAttempts === 0 && user.lockedUntil === null) return user;
    return this.prisma.user.update({ where: { id: user.id }, data: CLEARED_LOCKOUT });
  }

  /**
   * A tentativa que não virou sessão. Sem conta a que se referir (e-mail
   * inexistente), o ator é o próprio e-mail tentado — é o que sobra de
   * identificável, e é o que se procura ao investigar depois.
   */
  private async recordFailure(email: string, reason: string, user?: User): Promise<void> {
    await this.audit.record({
      actor: user ?? { id: null, name: email, role: 'desconhecido' },
      action: AUDIT_ACTION.sessionFailed,
      targetType: 'session',
      targetId: user?.id ?? null,
      targetLabel: email,
      detail: reason,
    });
  }

  /**
   * Senha guardada com custo menor que o de hoje é reescrita no login, com a
   * senha que o usuário acabou de digitar em mãos. É o que permite subir o
   * custo do scrypt depois sem pedir troca de senha a ninguém.
   */
  private async upgradeHashIfStale(user: User, password: string): Promise<User> {
    if (!needsRehash(user.password)) return user;
    return this.prisma.user.update({
      where: { id: user.id },
      data: { password: await hashPassword(password) },
    });
  }

  /** Revoga o token da sessão atual (idempotente). */
  async logout(tokenHash: string): Promise<void> {
    await this.prisma.accessToken.deleteMany({ where: { hash: tokenHash } });
  }

  /**
   * Troca a própria senha. Exige a senha atual — sem isso, um token roubado
   * viraria posse permanente da conta. As demais sessões do usuário caem
   * junto: trocar a senha é como alguém expulsa quem entrou indevidamente.
   */
  async changePassword(
    user: User,
    currentPassword: string,
    newPassword: string,
    currentTokenHash?: string,
  ): Promise<User> {
    if (!(await verifyPassword(currentPassword, user.password))) {
      throw new BadRequestException('Senha atual incorreta');
    }
    if (await verifyPassword(newPassword, user.password)) {
      throw new UnprocessableEntityException('A nova senha precisa ser diferente da atual');
    }

    // A metade da política que o DTO não alcança: a senha não pode conter o
    // nome nem o e-mail de quem a escolhe, e nenhum dos dois vem no corpo da
    // requisição — quem sabe de quem é a conta é este serviço.
    const problem = passwordProblem(newPassword, user);
    if (problem) throw new UnprocessableEntityException(problem);

    // A trava sai junto. Quem chegou até aqui digitou a senha ATUAL corretamente
    // — é a mesma prova que o login exige —, e a conta pode estar trancada sem
    // culpa do titular: basta alguém que saiba o e-mail ter errado dez vezes de
    // propósito enquanto ele já estava logado. Deixar a trava de pé aqui faria
    // a senha nova não entrar no próximo login.
    const updated = await this.prisma.user.update({
      where: { id: user.id },
      data: {
        password: await hashPassword(newPassword),
        mustChangePassword: false,
        ...CLEARED_LOCKOUT,
      },
    });

    await this.prisma.accessToken.deleteMany({
      where: {
        userId: user.id,
        ...(currentTokenHash ? { NOT: { hash: currentTokenHash } } : {}),
      },
    });

    return updated;
  }
}
