import { BadRequestException, Injectable, UnprocessableEntityException } from '@nestjs/common';
import type { User } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { burnPasswordTime, hashPassword, needsRehash, verifyPassword } from './password.util';
import { generateToken, hashToken, tokenExpiry } from './token.util';

@Injectable()
export class AuthService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Verifica credenciais e emite um token opaco com prazo. Erro genérico (400)
   * sem distinguir "e-mail não existe" de "senha errada".
   */
  async login(email: string, password: string): Promise<{ user: User; token: string }> {
    const user = await this.prisma.user.findUnique({ where: { email } });

    // E-mail desconhecido também paga o preço de um scrypt. Sem isso a
    // resposta volta rápido demais e o TEMPO responde o que a mensagem
    // genérica esconde: quais e-mails estão cadastrados.
    if (!user) {
      await burnPasswordTime();
      throw new BadRequestException('Credenciais inválidas');
    }
    if (!(await verifyPassword(password, user.password))) {
      throw new BadRequestException('Credenciais inválidas');
    }

    const current = await this.upgradeHashIfStale(user, password);

    const token = generateToken();
    await this.prisma.accessToken.create({
      data: { hash: hashToken(token), userId: user.id, expiresAt: tokenExpiry() },
    });
    return { user: current, token };
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

    const updated = await this.prisma.user.update({
      where: { id: user.id },
      data: { password: await hashPassword(newPassword), mustChangePassword: false },
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
