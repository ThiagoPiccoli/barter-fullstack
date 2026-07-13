import { BadRequestException, Injectable } from '@nestjs/common';
import type { User } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { verifyPassword } from './password.util';
import { generateToken, hashToken } from './token.util';

@Injectable()
export class AuthService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Verifica credenciais e emite um token opaco. Erro genérico (400) sem
   * distinguir "e-mail não existe" de "senha errada".
   */
  async login(email: string, password: string): Promise<{ user: User; token: string }> {
    const user = await this.prisma.user.findUnique({ where: { email } });
    if (!user || !(await verifyPassword(password, user.password))) {
      throw new BadRequestException('Credenciais inválidas');
    }

    const token = generateToken();
    await this.prisma.accessToken.create({
      data: { hash: hashToken(token), userId: user.id },
    });
    return { user, token };
  }

  /** Revoga o token da sessão atual (idempotente). */
  async logout(tokenHash: string): Promise<void> {
    await this.prisma.accessToken.deleteMany({ where: { hash: tokenHash } });
  }
}
