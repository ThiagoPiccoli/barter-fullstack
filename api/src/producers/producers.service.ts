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

  /** Cadastro é ato do admin: todo produtor nasce na carteira de alguém. */
  async create(dto: ProducerDto): Promise<Producer> {
    // A CARTEIRA é opcional no DTO (o formulário do consultor não a escreve) e
    // obrigatória AQUI: um produtor que nasce sem consultor não aparece para
    // quem registra permuta.
    if (dto.consultantId === undefined) {
      throw new UnprocessableEntityException('Escolha o consultor que atende este produtor');
    }
    await this.ensureConsultant(dto.consultantId);
    await this.ensureDocumentIsFree(dto.document);
    return this.prisma.producer.create({ data: this.withDocumentDigits(dto) });
  }

  /**
   * A EDIÇÃO, com DOIS donos e alcances diferentes.
   *
   * O ADMIN edita qualquer produtor e todos os campos, inclusive a carteira:
   * trocar o `consultantId` passa o produtor para outro consultor.
   *
   * O CONSULTOR edita os produtores da PRÓPRIA CARTEIRA, e só os dados de
   * contato e endereço deles — ver `assertEditable`, que é onde a lista do que
   * ele não toca está escrita com o porquê de cada um, a carteira inclusive.
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
    await this.ensureDocumentIsFree(dto.document, id);

    return this.prisma.producer.update({
      where: { id },
      data: this.withDocumentDigits(dto),
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
  private assertEditable(current: Producer, dto: ProducerDto): void {
    // A CARTEIRA também é por valor — e pelo mesmo motivo: o app manda o
    // cadastro inteiro, com o consultor que já estava lá. Recusar a presença
    // do campo travaria a edição de telefone do próprio cliente.
    if (dto.consultantId !== undefined && dto.consultantId !== current.consultantId) {
      throw new ForbiddenException(
        'Quem atende o produtor é definido pelo administrador. Peça a ele para mudar a carteira',
      );
    }

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

  /** Grava junto a forma canônica do documento, que é onde mora a unicidade. */
  private withDocumentDigits(fields: ProducerDto) {
    return { ...fields, documentDigits: documentDigitsOf(fields.document) };
  }

  /**
   * O índice único do banco é a garantia final, mas ele só sabe dizer "valor
   * repetido". Conferir antes permite apontar QUEM já usa o documento — que é
   * a informação de que o admin precisa para decidir o que fazer.
   *
   * O caminho para "o mesmo produtor, agora atendido por outro consultor" não
   * passa por aqui: é a troca de consultor na edição dele, não cadastro novo.
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
