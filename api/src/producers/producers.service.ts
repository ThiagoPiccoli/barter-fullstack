import {
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import type { Prisma, Producer, User } from '@prisma/client';
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
   * Carteira visível: consultor enxerga os produtores que ATENDE; os papéis de retaguarda (admin, gerente,
   * comitê, faturista) enxergam todos, com filtro opcional por consultor. É a
   * regra de acesso central do domínio.
   */
  async listFor(user: User, query: ListProducersQuery): Promise<Paginated<Producer>> {
    const { take, skip } = windowOf(query);
    const where = can(user, CAPABILITY.producersReadAll)
      ? query.consultantId
        ? this.attendedBy(query.consultantId)
        : {}
      : this.attendedBy(user.id);

    const [items, total] = await this.prisma.$transaction([
      this.prisma.producer.findMany({
        where,
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        take,
        skip,
      }),
      this.prisma.producer.count({ where }),
    ]);

    return new Paginated(items, total, take, skip);
  }

  /** "Este consultor atende o produtor?" — o recorte da carteira. */
  private attendedBy(consultantId: number): Prisma.ProducerWhereInput {
    return { consultantId };
  }

  async findFor(user: User, id: number): Promise<Producer> {
    const producer = await this.prisma.producer.findUnique({ where: { id } });
    if (!producer) throw new NotFoundException('Registro não encontrado.');
    if (!can(user, CAPABILITY.producersReadAll) && !this.isAttendedBy(producer, user.id)) {
      throw new ForbiddenException('Este produtor não pertence à sua carteira');
    }
    return producer;
  }

  /** A mesma pergunta de `attendedBy`, sobre um registro já carregado. */
  private isAttendedBy(producer: Producer, consultantId: number): boolean {
    return producer.consultantId === consultantId;
  }

  /**
   * O CADASTRO, com DOIS donos: o admin e o consultor. Todo produtor nasce na
   * carteira de alguém — QUAL é a pergunta de `ownerOnCreate`.
   */
  async create(actor: User, dto: ProducerDto): Promise<Producer> {
    const consultantId = this.ownerOnCreate(actor, dto);
    await this.ensureConsultant(consultantId);
    await this.ensureDocumentIsFree(actor, dto.document);
    return this.prisma.producer.create({
      data: { ...this.withDocumentDigits(dto), consultantId },
    });
  }

  /**
   * EM QUE CARTEIRA o produtor novo nasce.
   *
   * O ADMIN escolhe, e a escolha é obrigatória: a carteira é opcional no DTO
   * (o formulário do consultor não a escreve), e um produtor que nasce sem
   * consultor não aparece para quem registra permuta.
   *
   * O CONSULTOR não escolhe: o produtor que ele cadastra é DELE, e só dele. O
   * campo ausente vira o id de quem cadastrou, e o próprio id de volta é aceito
   * (é o que o app manda). Qualquer outro é RECUSADO, e não trocado em silêncio
   * pelo dele — quem mandou outro consultor queria outra coisa, e gravar a
   * carteira errada sem avisar é pior do que dizer não.
   */
  private ownerOnCreate(actor: User, dto: ProducerDto): number {
    if (can(actor, CAPABILITY.producersManage)) {
      if (dto.consultantId === undefined) {
        throw new UnprocessableEntityException('Escolha o consultor que atende este produtor');
      }
      return dto.consultantId;
    }
    if (dto.consultantId !== undefined && dto.consultantId !== actor.id) {
      throw new ForbiddenException(
        'O produtor que você cadastra entra na sua carteira. Para cadastrá-lo na ' +
          'carteira de outro consultor, peça ao administrador',
      );
    }
    return actor.id;
  }

  /**
   * A EDIÇÃO, com DOIS donos e alcances diferentes.
   *
   * O ADMIN edita qualquer produtor e todos os campos, inclusive a carteira:
   * trocar o `consultantId` passa o produtor para outro consultor.
   *
   * O CONSULTOR edita os produtores da PRÓPRIA CARTEIRA, e todos os dados
   * deles — o documento, a área do Barter e o regime de Funrural inclusive. A
   * única coisa que ele não toca é a carteira (ver `assertEditable`).
   *
   * A carteira AUSENTE preserva a atual para os dois.
   */
  async update(actor: User, id: number, dto: ProducerDto): Promise<Producer> {
    const current = await this.ensureExists(id);
    const manages = can(actor, CAPABILITY.producersManage);

    if (!manages) {
      if (!this.isAttendedBy(current, actor.id)) {
        throw new ForbiddenException('Este produtor não pertence à sua carteira');
      }
      this.assertEditable(current, dto);
    }

    if (dto.consultantId !== undefined && dto.consultantId !== current.consultantId) {
      await this.ensureConsultant(dto.consultantId);
    }
    await this.ensureDocumentIsFree(actor, dto.document, id);

    return this.prisma.producer.update({
      where: { id },
      data: this.withDocumentDigits(dto),
    });
  }

  /**
   * O QUE O CONSULTOR NÃO REESCREVE no cadastro do cliente dele: a CARTEIRA.
   * Um consultor que a escrevesse poderia passar o próprio cliente adiante sem
   * que ninguém decidisse isso.
   *
   * Ela é recusada por VALOR, e não por presença: o app manda o cadastro
   * inteiro de volta, com o consultor que já estava lá, e recusar o campo que
   * veio igual ao gravado travaria toda edição de telefone. O que se recusa é a
   * MUDANÇA.
   *
   * O documento, a área e o regime de Funrural já estiveram nesta lista e
   * saíram dela — ver `producersEdit` em policy.ts. O documento continua
   * protegido, mas pela UNICIDADE (`ensureDocumentIsFree`), que vale para
   * qualquer um: trocar para o CPF de outro cliente é recusado igual ao
   * cadastro em duplicidade.
   */
  private assertEditable(current: Producer, dto: ProducerDto): void {
    if (dto.consultantId !== undefined && dto.consultantId !== current.consultantId) {
      throw new ForbiddenException(
        'Quem atende o produtor é definido pelo administrador. Peça a ele para mudar a carteira',
      );
    }
  }

  /** Grava junto a forma canônica do documento, que é onde mora a unicidade. */
  private withDocumentDigits(fields: ProducerDto) {
    return { ...fields, documentDigits: documentDigitsOf(fields.document) };
  }

  /**
   * O CPF/CNPJ JÁ CADASTRADO — no cadastro e na edição, para todo mundo.
   *
   * O índice único do banco é a garantia final, mas ele só sabe dizer "valor
   * repetido". Conferir antes permite dizer O QUE FAZER, e a resposta depende
   * de quem pergunta:
   *
   * - quem enxerga todas as carteiras (o admin) lê o NOME de quem já usa o
   *   documento — é a informação de que ele precisa para decidir;
   * - o consultor, se o cliente já é DELE, também lê o nome: ele cadastrou duas
   *   vezes o mesmo cliente, e o caminho é abrir o que já existe;
   * - o consultor, se o cliente é de OUTRA carteira, NÃO lê o nome nem o
   *   colega. A carteira dos outros não é dele (é a mesma regra de `findFor`),
   *   e a recusa não pode virar uma consulta de "quem atende o CPF tal". Ele lê
   *   o que precisa para agir: o cliente já existe, e quem muda a carteira é o
   *   administrador.
   *
   * O caminho para "o mesmo produtor, agora atendido por outro consultor" não
   * passa por aqui: é a troca de consultor na edição dele, não cadastro novo.
   */
  private async ensureDocumentIsFree(
    actor: User,
    document: string,
    ignoreId?: number,
  ): Promise<void> {
    const digits = documentDigitsOf(document);
    const existing = await this.prisma.producer.findUnique({ where: { documentDigits: digits } });
    if (!existing || existing.id === ignoreId) return;

    const kind = digits.length === 14 ? 'CNPJ' : 'CPF';
    if (can(actor, CAPABILITY.producersReadAll)) {
      throw new UnprocessableEntityException(
        `Este ${kind} já está cadastrado para "${existing.name}"`,
      );
    }
    if (this.isAttendedBy(existing, actor.id)) {
      throw new UnprocessableEntityException(
        `Este ${kind} já está cadastrado na sua carteira, para "${existing.name}". ` +
          'Use o cadastro que já existe',
      );
    }
    throw new UnprocessableEntityException(
      `Este ${kind} já está cadastrado e o produtor é atendido por outro consultor. ` +
        'Para passar a atendê-lo, fale com o administrador',
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

  private async ensureExists(id: number): Promise<Producer> {
    const producer = await this.prisma.producer.findUnique({ where: { id } });
    if (!producer) throw new NotFoundException('Registro não encontrado.');
    return producer;
  }

  /** O id precisa ser de um CONSULTOR — e a recusa nomeia quem não é. */
  private async ensureConsultant(consultantId: number): Promise<void> {
    const user = await this.prisma.user.findUnique({
      where: { id: consultantId },
      select: { fullName: true, role: true },
    });
    if (user?.role === ROLE.consultant) return;
    throw new UnprocessableEntityException(
      user
        ? `Escolha um consultor para a carteira: ${user.fullName} não é consultor`
        : 'Escolha um consultor válido para a carteira',
    );
  }
}
