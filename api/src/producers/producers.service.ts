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
    // A CARTEIRA é opcional no DTO (o formulário do consultor não a tem) e
    // obrigatória AQUI: um produtor que nasce sem consultor nenhum não aparece
    // para quem registra permuta. A frase é a mesma da validação de entrada,
    // porque é a mesma regra — o que muda é só onde ela cabe.
    const consultantIds = dto.consultantIds ?? [];
    if (consultantIds.length === 0) {
      throw new UnprocessableEntityException('Escolha pelo menos um consultor para a carteira');
    }
    await this.ensureConsultants(consultantIds);
    await this.ensureDocumentIsFree(dto.document);
    const fields = { ...dto, consultantIds: undefined };
    delete (fields as { consultantIds?: unknown }).consultantIds;
    return this.prisma.producer.create({
      data: {
        ...this.withDocumentDigits(fields),
        consultants: { create: consultantIds.map((consultantId) => ({ consultantId })) },
      },
      include: WITH_CONSULTANTS,
    });
  }

  /**
   * A EDIÇÃO, com DOIS donos e alcances diferentes.
   *
   * O ADMIN edita qualquer produtor e todos os campos, inclusive a carteira: a
   * lista de consultores do payload SUBSTITUI a que estava lá — quem sai do
   * formulário sai da carteira. Vínculo que permanece não é reescrito: apagar e
   * recriar todos zeraria o `assignedAt` de quem já atendia o produtor, e a data
   * de quando o compartilhamento começou é justamente o que se quer saber
   * depois.
   *
   * O CONSULTOR edita os produtores da PRÓPRIA CARTEIRA, e só os dados de
   * contato e endereço deles — ver `assertEditable`, que é onde a lista do que
   * ele não toca está escrita com o porquê de cada um. Ele não mexe na carteira:
   * a ausência de `consultantIds` significa "não mexa em quem atende", e mandá-la
   * sem poder é recusado com a frase que diz a quem pedir.
   *
   * A carteira AUSENTE preserva a atual para os dois, e não é permissividade: é
   * a diferença entre "não mandei este campo" e "mandei este campo vazio", que a
   * validação de entrada já recusa.
   */
  async update(actor: User, id: number, dto: ProducerDto): Promise<ProducerWithConsultants> {
    const current = await this.ensureExists(id);
    const manages = can(actor, CAPABILITY.producersManage);

    if (!manages) {
      if (!this.isAttendedBy(current, actor.id)) {
        throw new ForbiddenException('Este produtor não pertence à sua carteira');
      }
      this.assertEditable(current, dto);
    }

    if (dto.consultantIds && !manages) {
      throw new ForbiddenException(
        'Quem atende o produtor é definido pelo administrador. Peça a ele para mudar a carteira',
      );
    }

    await this.ensureDocumentIsFree(dto.document, id);

    const { consultantIds, ...fields } = dto;
    const wallet = await this.walletUpdateOf(current, consultantIds);

    return this.prisma.producer.update({
      where: { id },
      data: { ...this.withDocumentDigits(fields), ...wallet },
      include: WITH_CONSULTANTS,
    });
  }

  /**
   * O QUE O CONSULTOR NÃO REESCREVE no cadastro do cliente dele.
   *
   * Os três são recusados por VALOR, e não por presença: o formulário manda o
   * registro inteiro de volta, e recusar o campo que veio igual ao que já está
   * gravado travaria toda edição de telefone. O que se recusa é a MUDANÇA.
   *
   * - o DOCUMENTO é a identidade do cadastro (a unicidade mora nele, ver
   *   `documentDigits`): trocá-lo transforma o cliente A no cliente B mantendo as
   *   permutas do A;
   * - a ÁREA CULTIVÁVEL é o denominador de toda régua da permuta — os mínimos por
   *   hectare, o custo do seguro, o investimento por hectare. Um arrendamento a
   *   mais muda quanto insumo o Barter exige daquele cliente, e isso é decisão de
   *   crédito, não atualização de contato;
   * - o REGIME DE FUNRURAL é a opção formal do produtor perante o fisco, e é dela
   *   que sai a alíquota gravada em cada entrega.
   *
   * Os três continuam existindo e continuam se corrigindo — pelo admin, que é
   * quem responde pelo cadastro. A frase diz isso, porque quem a lê precisa saber
   * o que fazer, e não só que não pode.
   */
  private assertEditable(current: ProducerWithConsultants, dto: ProducerDto): void {
    const locked: string[] = [];

    if (documentDigitsOf(dto.document) !== current.documentDigits) locked.push('o CPF/CNPJ');
    if (dto.areaHa !== current.areaHa) locked.push('a área cultivável');
    if ((dto.taxRegime ?? current.taxRegime) !== current.taxRegime) {
      locked.push('o regime de Funrural');
    }

    if (locked.length === 0) return;
    // "QUEM ALTERA … É O ADMINISTRADOR" em vez de "… é alterado por …": os três
    // campos têm gêneros diferentes ("o CPF/CNPJ", "a área cultivável"), e
    // qualquer particípio concordaria com um e erraria o outro. A frase também
    // diz o que fazer — uma recusa que só nega manda o consultor concluir que o
    // app está quebrado.
    const lista =
      locked.length > 1
        ? `${locked.slice(0, -1).join(', ')} e ${locked[locked.length - 1]}`
        : locked[0];
    throw new ForbiddenException(
      `Quem altera ${lista} é o administrador. Peça a ele para corrigir e ` +
        'edite o restante normalmente',
    );
  }

  /**
   * A parte da gravação que mexe na CARTEIRA — ou nada, quando o payload não a
   * traz.
   *
   * Separada porque ela é a única parte da edição que é de outro dono, e porque
   * a forma dela é peculiar: `deleteMany` + `create` do que falta, para não
   * reescrever o vínculo que permanece.
   */
  private async walletUpdateOf(
    current: ProducerWithConsultants,
    consultantIds: number[] | undefined,
  ): Promise<Prisma.ProducerUpdateInput> {
    if (!consultantIds) return {};
    await this.ensureConsultants(consultantIds);

    const existing = new Set(current.consultants.map((link) => link.consultantId));
    return {
      consultants: {
        deleteMany: { consultantId: { notIn: consultantIds } },
        create: consultantIds
          .filter((consultantId) => !existing.has(consultantId))
          .map((consultantId) => ({ consultantId })),
      },
    };
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
        ? `Escolha apenas consultores para a carteira: ${named.join(', ')} não é consultor`
        : 'Escolha um consultor válido para a carteira',
    );
  }
}
