import { Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import type { User } from '@prisma/client';
import { hashPassword } from '../auth/password.util';
import { PrismaService } from '../prisma/prisma.service';
import { CreateSellerDto, UpdateSellerDto } from './dto/seller.dto';

/**
 * Senha de primeira entrada quando o admin não define uma na criação. Vale
 * uma única vez: o vendedor cai direto na troca de senha ao entrar com ela
 * (ver mustChangePassword em create). Pode ser trocada por SELLER_DEFAULT_PASSWORD.
 *
 * Lida na hora de criar, e não numa constante de topo de módulo: este arquivo
 * é importado antes do ConfigModule carregar o .env, então uma constante
 * congelaria o padrão e ignoraria a variável em silêncio — justamente no
 * ponto em que ela existe para tirar o '123456' do caminho.
 */
function defaultPassword(): string {
  return process.env.SELLER_DEFAULT_PASSWORD || '123456';
}

/** Gestão de VENDEDORES pelo admin — não existe signup público. */
@Injectable()
export class SellersService {
  constructor(private readonly prisma: PrismaService) {}

  async list(): Promise<User[]> {
    return this.prisma.user.findMany({ where: { role: 'seller' }, orderBy: { id: 'asc' } });
  }

  async create(dto: CreateSellerDto): Promise<User> {
    const emailTaken = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (emailTaken) {
      throw new UnprocessableEntityException('Este e-mail já está em uso por outro usuário');
    }
    // A senha definida aqui é PROVISÓRIA: quem entra com ela é obrigado a
    // trocá-la antes de usar o app (mustChangePassword), então ela nunca vira
    // a senha permanente de ninguém.
    const { password, ...data } = dto;
    return this.prisma.user.create({
      data: {
        ...data,
        password: await hashPassword(password ?? defaultPassword()),
        role: 'seller',
        mustChangePassword: true,
      },
    });
  }

  async update(id: number, dto: UpdateSellerDto): Promise<User> {
    const seller = await this.findSeller(id);
    const emailTaken = await this.prisma.user.findFirst({
      where: { email: dto.email, NOT: { id: seller.id } },
    });
    if (emailTaken) {
      throw new UnprocessableEntityException('Este e-mail já está em uso por outro usuário');
    }
    return this.prisma.user.update({ where: { id: seller.id }, data: dto });
  }

  /**
   * Excluir um vendedor não apaga permutas (snapshot + FK NULL) e deixa os
   * produtores da carteira "sem vendedor" até o admin realocá-los.
   */
  async delete(id: number): Promise<void> {
    const seller = await this.findSeller(id);
    await this.prisma.user.delete({ where: { id: seller.id } });
  }

  /** Só registros role=seller passam por aqui — admin não se gerencia nesta rota. */
  private async findSeller(id: number): Promise<User> {
    const seller = await this.prisma.user.findFirst({ where: { id, role: 'seller' } });
    if (!seller) throw new NotFoundException('Registro não encontrado.');
    return seller;
  }
}
