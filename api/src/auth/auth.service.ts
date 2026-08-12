import { BadRequestException, Injectable, UnprocessableEntityException } from '@nestjs/common';
import type { User } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { hashPassword, verifyPassword } from './password.util';
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
    if (!user || !(await verifyPassword(password, user.password))) {
      throw new BadRequestException('Credenciais inválidas');
    }

    const token = generateToken();
    await this.prisma.accessToken.create({
      data: { hash: hashToken(token), userId: user.id, expiresAt: tokenExpiry() },
    });
    return { user, token };
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
