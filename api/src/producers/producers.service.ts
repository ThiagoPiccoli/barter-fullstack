import {
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import type { Producer, User } from '@prisma/client';
import { Paginated, windowOf } from '../common/pagination';
import { PrismaService } from '../prisma/prisma.service';
import { CAPABILITY, can } from '../common/policy';
import { ROLE } from '../common/roles';
import { documentDigitsOf } from './document';
import { ListProducersQuery, ProducerDto } from './dto/producer.dto';

@Injectable()
export class ProducersService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Carteira visível: consultor enxerga apenas os próprios produtores; os
   * papéis de retaguarda (admin, gerente, comitê, faturista) enxergam todos,
   * com filtro opcional por consultor. É a regra de acesso central do domínio.
   */
  async listFor(user: User, query: ListProducersQuery): Promise<Paginated<Producer>> {
    const { take, skip } = windowOf(query);
    const where = can(user, CAPABILITY.producersReadAll)
      ? query.consultantId
        ? { consultantId: query.consultantId }
        : {}
      : { consultantId: user.id };

    const [items, total] = await this.prisma.$transaction([
      this.prisma.producer.findMany({ where, orderBy: { id: 'asc' }, take, skip }),
      this.prisma.producer.count({ where }),
    ]);

    return new Paginated(items, total, take, skip);
  }

  async findFor(user: User, id: number): Promise<Producer> {
    const producer = await this.prisma.producer.findUnique({ where: { id } });
    if (!producer) throw new NotFoundException('Registro não encontrado.');
    if (!can(user, CAPABILITY.producersReadAll) && producer.consultantId !== user.id) {
      throw new ForbiddenException('Este produtor não pertence à sua carteira');
    }
    return producer;
  }

  /** Cadastro é ato do admin: todo produtor nasce na carteira de um consultor. */
  async create(dto: ProducerDto): Promise<Producer> {
    await this.ensureConsultant(dto.consultantId);
    await this.ensureDocumentIsFree(dto.document);
    return this.prisma.producer.create({ data: this.withDocumentDigits(dto) });
  }

  async update(id: number, dto: ProducerDto): Promise<Producer> {
    await this.ensureExists(id);
    await this.ensureConsultant(dto.consultantId);
    await this.ensureDocumentIsFree(dto.document, id);
    return this.prisma.producer.update({
      where: { id },
      data: this.withDocumentDigits(dto),
    });
  }

  /** Grava junto a forma canônica do documento, que é onde mora a unicidade. */
  private withDocumentDigits(dto: ProducerDto) {
    return { ...dto, documentDigits: documentDigitsOf(dto.document) };
  }

  /**
   * O índice único do banco é a garantia final, mas ele só sabe dizer "valor
   * repetido". Conferir antes permite apontar QUEM já usa o documento — que é
   * a informação de que o admin precisa para decidir o que fazer.
   */
  private async ensureDocumentIsFree(document: string, ignoreId?: number): Promise<void> {
    const existing = await this.prisma.producer.findUnique({
      where: { documentDigits: documentDigitsOf(document) },
    });
    if (!existing || existing.id === ignoreId) return;
    throw new UnprocessableEntityException(
      `Este documento já está cadastrado para "${existing.name}"`,
    );
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

  private async ensureConsultant(consultantId: number): Promise<void> {
    const consultant = await this.prisma.user.findUnique({ where: { id: consultantId } });
    if (!consultant || consultant.role !== ROLE.consultant) {
      throw new UnprocessableEntityException('Escolha um consultor válido para a carteira');
    }
  }
}
