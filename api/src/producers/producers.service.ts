import {
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import type { Producer, User } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ProducerDto } from './dto/producer.dto';

@Injectable()
export class ProducersService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Carteira visível: vendedor enxerga apenas os próprios produtores; admin
   * enxerga todos (com filtro opcional por vendedor). É a regra de acesso
   * central do domínio.
   */
  async listFor(user: User, sellerIdFilter?: number): Promise<Producer[]> {
    const where =
      user.role === 'admin'
        ? sellerIdFilter
          ? { sellerId: sellerIdFilter }
          : {}
        : { sellerId: user.id };
    return this.prisma.producer.findMany({ where, orderBy: { id: 'asc' } });
  }

  async findFor(user: User, id: number): Promise<Producer> {
    const producer = await this.prisma.producer.findUnique({ where: { id } });
    if (!producer) throw new NotFoundException('Registro não encontrado.');
    if (user.role !== 'admin' && producer.sellerId !== user.id) {
      throw new ForbiddenException('Este produtor não pertence à sua carteira');
    }
    return producer;
  }

  /** Cadastro é ato do admin: todo produtor nasce na carteira de um vendedor. */
  async create(dto: ProducerDto): Promise<Producer> {
    await this.ensureSeller(dto.sellerId);
    return this.prisma.producer.create({ data: dto });
  }

  async update(id: number, dto: ProducerDto): Promise<Producer> {
    await this.ensureExists(id);
    await this.ensureSeller(dto.sellerId);
    return this.prisma.producer.update({ where: { id }, data: dto });
  }

  /**
   * Exclusão não apaga o histórico: permutas antigas guardam o nome do
   * produtor no próprio registro (snapshot) e o FK vira NULL.
   */
  async delete(id: number): Promise<void> {
    await this.ensureExists(id);
    await this.prisma.producer.delete({ where: { id } });
  }

  private async ensureExists(id: number): Promise<void> {
    const producer = await this.prisma.producer.findUnique({ where: { id } });
    if (!producer) throw new NotFoundException('Registro não encontrado.');
  }

  private async ensureSeller(sellerId: number): Promise<void> {
    const seller = await this.prisma.user.findUnique({ where: { id: sellerId } });
    if (!seller || seller.role !== 'seller') {
      throw new UnprocessableEntityException('Escolha um vendedor válido para a carteira');
    }
  }
}
