import {
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import type { Prisma, User } from '@prisma/client';
import { Paginated, windowOf } from '../common/pagination';
import { PrismaService } from '../prisma/prisma.service';
import { CAPABILITY, can } from '../common/policy';
import { ROLE } from '../common/roles';
import { documentDigitsOf } from './document';
import { ListProducersQuery, ProducerDto } from './dto/producer.dto';

/**
 * O produtor SEMPRE sai daqui com a carteira junto — é ela que o serializador
 * transforma em `consultantIds`, e é ela que o app usa para saber quem atende
 * quem. Buscar o produtor sem os vínculos devolveria um cadastro que parece
 * não ter consultor nenhum.
 */
const WITH_CONSULTANTS = {
  consultants: { select: { consultantId: true }, orderBy: { consultantId: 'asc' } },
} satisfies Prisma.ProducerInclude;

export type ProducerWithConsultants = Prisma.ProducerGetPayload<{
  include: typeof WITH_CONSULTANTS;
}>;

@Injectable()
export class ProducersService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Carteira visível: consultor enxerga os produtores que ATENDE — os próprios
   * e os que divide com colegas —; os papéis de retaguarda (admin, gerente,
   * comitê, faturista) enxergam todos, com filtro opcional por consultor. É a
   * regra de acesso central do domínio.
   */
  async listFor(
    user: User,
    query: ListProducersQuery,
  ): Promise<Paginated<ProducerWithConsultants>> {
    const { take, skip } = windowOf(query);
    const where = can(user, CAPABILITY.producersReadAll)
      ? query.consultantId
        ? this.attendedBy(query.consultantId)
        : {}
      : this.attendedBy(user.id);

    const [items, total] = await this.prisma.$transaction([
      this.prisma.producer.findMany({
        where,
        include: WITH_CONSULTANTS,
        orderBy: { id: 'asc' },
        take,
        skip,
      }),
      this.prisma.producer.count({ where }),
    ]);

    return new Paginated(items, total, take, skip);
  }

  /**
   * "Este consultor atende o produtor?" — a pergunta que virou o recorte da
   * carteira quando ela deixou de ser uma coluna. `some` e não `every`: o
   * produtor está na carteira de quem pergunta, mesmo que também esteja na de
   * outros.
   */
  private attendedBy(consultantId: number): Prisma.ProducerWhereInput {
    return { consultants: { some: { consultantId } } };
  }

  async findFor(user: User, id: number): Promise<ProducerWithConsultants> {
    const producer = await this.prisma.producer.findUnique({
      where: { id },
      include: WITH_CONSULTANTS,
    });
    if (!producer) throw new NotFoundException('Registro não encontrado.');
    if (!can(user, CAPABILITY.producersReadAll) && !this.isAttendedBy(producer, user.id)) {
      throw new ForbiddenException('Este produtor não pertence à sua carteira');
    }
    return producer;
  }

  /** A mesma pergunta de `attendedBy`, sobre um registro já carregado. */
  private isAttendedBy(producer: ProducerWithConsultants, consultantId: number): boolean {
    return producer.consultants.some((link) => link.consultantId === consultantId);
  }

  /** Cadastro é ato do admin: todo produtor nasce na carteira de alguém. */
  async create(dto: ProducerDto): Promise<ProducerWithConsultants> {
    await this.ensureConsultants(dto.consultantIds);
    await this.ensureDocumentIsFree(dto.document);
    const { consultantIds, ...fields } = dto;
    return this.prisma.producer.create({
      data: {
        ...this.withDocumentDigits(fields),
        consultants: { create: consultantIds.map((consultantId) => ({ consultantId })) },
      },
      include: WITH_CONSULTANTS,
    });
  }

  /**
   * A lista de consultores do payload SUBSTITUI a que estava lá — quem sai do
   * formulário sai da carteira. Vínculo que permanece não é reescrito: apagar e
   * recriar todos zeraria o `assignedAt` de quem já atendia o produtor, e a
   * data de quando o compartilhamento começou é justamente o que se quer saber
   * depois.
   */
  async update(id: number, dto: ProducerDto): Promise<ProducerWithConsultants> {
    const current = await this.ensureExists(id);
    await this.ensureConsultants(dto.consultantIds);
    await this.ensureDocumentIsFree(dto.document, id);

    const { consultantIds, ...fields } = dto;
    const existing = new Set(current.consultants.map((link) => link.consultantId));

    return this.prisma.producer.update({
      where: { id },
      data: {
        ...this.withDocumentDigits(fields),
        consultants: {
          deleteMany: { consultantId: { notIn: consultantIds } },
          create: consultantIds
            .filter((consultantId) => !existing.has(consultantId))
            .map((consultantId) => ({ consultantId })),
        },
      },
      include: WITH_CONSULTANTS,
    });
  }

  /** Grava junto a forma canônica do documento, que é onde mora a unicidade. */
  private withDocumentDigits(fields: Omit<ProducerDto, 'consultantIds'>) {
    return { ...fields, documentDigits: documentDigitsOf(fields.document) };
  }

  /**
   * O índice único do banco é a garantia final, mas ele só sabe dizer "valor
   * repetido". Conferir antes permite apontar QUEM já usa o documento — que é
   * a informação de que o admin precisa para decidir o que fazer.
   *
   * Repare que o caminho para "o mesmo produtor, agora atendido por outro
   * consultor" não passa mais por aqui: é edição da carteira dele, não cadastro
   * novo. Antes, com um consultor por produtor, cadastrar de novo era a única
   * saída — e esta mensagem era o fim da linha.
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

  private async ensureExists(id: number): Promise<ProducerWithConsultants> {
    const producer = await this.prisma.producer.findUnique({
      where: { id },
      include: WITH_CONSULTANTS,
    });
    if (!producer) throw new NotFoundException('Registro não encontrado.');
    return producer;
  }

  /**
   * Todos os ids precisam ser de CONSULTOR. A conferência é uma consulta só, e
   * a mensagem nomeia quem não serve: com uma lista, "escolha um consultor
   * válido" deixaria o admin adivinhando qual dos quatro nomes derrubou o
   * cadastro.
   */
  private async ensureConsultants(consultantIds: number[]): Promise<void> {
    const found = await this.prisma.user.findMany({
      where: { id: { in: consultantIds } },
      select: { id: true, fullName: true, role: true },
    });

    const valid = new Map(
      found.filter((user) => user.role === ROLE.consultant).map((user) => [user.id, user]),
    );
    const rejected = consultantIds.filter((id) => !valid.has(id));
    if (rejected.length === 0) return;

    const named = rejected
      .map((id) => found.find((user) => user.id === id)?.fullName)
      .filter((name): name is string => Boolean(name));

    throw new UnprocessableEntityException(
      named.length > 0
        ? `Escolha apenas consultores para a carteira — ${named.join(', ')} não é consultor`
        : 'Escolha um consultor válido para a carteira',
    );
  }
}
