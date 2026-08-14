import {
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import type { Barter, BarterItem, Prisma, User } from '@prisma/client';
import { AUDIT_ACTION, AuditService } from '../audit/audit.service';
import { PrismaService } from '../prisma/prisma.service';
import {
  MONEY_EPSILON,
  classRequired,
  classSpend,
  inputCost,
  minQuantityFor,
  sacksToCover,
  type PricedInput,
} from './barter-math';
import { Paginated, windowOf } from '../common/pagination';
import { CAPABILITY, can } from '../common/policy';
import { ROLE } from '../common/roles';
import { SeasonsService } from '../seasons/seasons.service';
import { CreateBarterDto, ListBartersQuery, ReviewBarterDto } from './dto/barter.dto';

type BarterWithItems = Barter & { items: BarterItem[] };

/**
 * Regras de negócio da permuta. O servidor é a autoridade: preços saem do
 * banco (nunca do cliente), mínimos por hectare e por classe travam a
 * criação, e as sacas do grão são calculadas aqui.
 */
@Injectable()
export class BartersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly seasons: SeasonsService,
  ) {}

  /**
   * Permutas visíveis para o usuário: consultor enxerga apenas as próprias; os
   * papéis de retaguarda (admin, gerente, comitê, faturista) enxergam todas.
   * Regra de acesso central do domínio.
   *
   * O `id` desempata a ordenação por data. Sem ele, permutas criadas no mesmo
   * instante sairiam em ordem arbitrária a cada consulta e a paginação
   * repetiria umas e pularia outras entre uma página e a seguinte.
   */
  async listFor(user: User, query: ListBartersQuery): Promise<Paginated<BarterWithItems>> {
    const { take, skip } = windowOf(query);
    const where = {
      ...(can(user, CAPABILITY.bartersReadAll) ? {} : { consultantId: user.id }),
      ...(query.status ? { status: query.status } : {}),
    };

    const [items, total] = await this.prisma.$transaction([
      this.prisma.barter.findMany({
        where,
        include: { items: true },
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        take,
        skip,
      }),
      this.prisma.barter.count({ where }),
    ]);

    return new Paginated(items, total, take, skip);
  }

  /** Uma permuta pelo código público, respeitando o escopo do usuário. */
  async findFor(user: User, code: string): Promise<BarterWithItems> {
    const barter = await this.prisma.barter.findUnique({
      where: { code },
      include: { items: true },
    });
    if (!barter) throw new NotFoundException('Registro não encontrado.');
    if (!can(user, CAPABILITY.bartersReadAll) && barter.consultantId !== user.id) {
      throw new ForbiddenException('Você não tem acesso a esta permuta');
    }
    return barter;
  }

  /**
   * Registra uma permuta para um produtor da carteira do consultor. Fluxo:
   * 1. precisa haver um Barter (versão) aberto — é ele quem diz por quanto se
   *    permuta hoje, e qual é o grão de pagamento;
   * 2. produtor precisa pertencer à carteira de quem registra;
   * 3. todo insumo com exigência por hectare é obrigatório, no mínimo
   *    `taxa × área` (o app pré-preenche, o servidor confere);
   * 4. as regras de mínimo das classes precisam estar satisfeitas;
   * 5. o custo é precificado com a TABELA DA VERSÃO e convertido em sacas do
   *    grão da safra — o item de grão é criado pelo servidor.
   *
   * O consultor não escolhe mais o grão: ele é da safra. E os preços não vêm
   * mais do catálogo — vêm da versão, que é o acordo publicado. Um insumo fora
   * da tabela da versão simplesmente não é permutável naquela gestão.
   */
  async create(consultant: User, dto: CreateBarterDto): Promise<BarterWithItems> {
    // A rota já exige a capacidade `barters.register`; aqui a regra é repetida
    // como invariante do DOMÍNIO, e na forma de LISTA DE PERMITIDOS. Enquanto
    // isto perguntava "é admin?", cada papel novo entrava por omissão — gerente,
    // comitê e faturista registrariam permuta sem ninguém ter decidido isso.
    if (consultant.role !== ROLE.consultant) {
      throw new ForbiddenException('Permutas são registradas pelo consultor da carteira');
    }

    // 1. O Barter vigente é o primeiro portão: sem lançamento aberto não existe
    //    tabela de valores, e uma permuta sem tabela seria um acordo sem preço.
    const version = await this.seasons.requireOpenVersion();
    if (version.grainPrice <= 0) {
      throw new UnprocessableEntityException(
        `O Barter ${version.code} está sem valor para a saca de ${version.season.grainName}`,
      );
    }

    const producer = await this.prisma.producer.findUnique({ where: { id: dto.producerId } });
    if (!producer) {
      throw new UnprocessableEntityException('Produtor não encontrado');
    }
    if (producer.consultantId !== consultant.id) {
      throw new ForbiddenException('Este produtor não pertence à sua carteira');
    }

    // Consolida quantidades por produto (payload pode repetir ids).
    const quantities = new Map<number, number>();
    for (const item of dto.inputs) {
      quantities.set(item.productId, (quantities.get(item.productId) ?? 0) + item.quantity);
    }

    const products = await this.prisma.product.findMany({
      where: { id: { in: [...quantities.keys()] }, type: 'input' },
    });
    if (products.length !== quantities.size) {
      throw new UnprocessableEntityException('A permuta contém insumos inexistentes');
    }

    // Os valores saem da versão, nunca do catálogo. Insumo que o admin não
    // lançou nesta versão não tem preço acordado — e um preço "de reserva"
    // vindo do cadastro é justamente o tipo de valor que ninguém combinou.
    const valueOf = new Map(version.prices.map((row) => [row.productId, row]));
    const missing = products.filter((product) => !valueOf.has(product.id));
    if (missing.length > 0) {
      throw new UnprocessableEntityException(
        `Fora do Barter ${version.code}: ${missing.map((product) => product.name).join(', ')}`,
      );
    }

    const pricedInputs: PricedInput[] = products.map((product) => ({
      productId: product.id,
      quantity: quantities.get(product.id)!,
      unitPrice: valueOf.get(product.id)!.price,
      classId: product.classId,
    }));

    if (pricedInputs.some((item) => item.quantity <= 0)) {
      throw new UnprocessableEntityException('Quantidades de insumo devem ser maiores que zero');
    }

    // 3. Insumos com exigência por hectare são obrigatórios para a área do
    //    produtor — mas só os que ESTÃO na versão: exigir o que o Barter não
    //    lançou travaria toda permuta da gestão.
    const requiredProducts = (
      await this.prisma.product.findMany({
        where: { type: 'input', requiredPerHa: { gt: 0 } },
      })
    ).filter((product) => valueOf.has(product.id));
    for (const product of requiredProducts) {
      const min = minQuantityFor(product.requiredPerHa, producer.areaHa);
      const chosen = quantities.get(product.id) ?? 0;
      if (chosen + 0.005 < min) {
        throw new UnprocessableEntityException(
          `${product.name} exige no mínimo ${min} ${product.unit} para ${producer.areaHa} ha`,
        );
      }
    }

    // 4. Regras de mínimo por CLASSE travam o envio.
    const totalCost = inputCost(pricedInputs);
    if (totalCost <= 0) {
      throw new UnprocessableEntityException('Escolha ao menos um insumo para retirar');
    }

    const ruledClasses = (
      await this.prisma.productClass.findMany({ where: { NOT: { ruleType: 'none' } } })
    ).filter((productClass) => productClass.ruleValue > 0);
    const unmet = ruledClasses.filter((productClass) => {
      const required = classRequired(productClass, { totalCost, areaHa: producer.areaHa });
      return required > 0 && classSpend(pricedInputs, productClass.id) < required - MONEY_EPSILON;
    });
    if (unmet.length > 0) {
      throw new UnprocessableEntityException(
        `Mínimo da classe não atingido: ${unmet.map((c) => c.name).join(', ')}`,
      );
    }

    // 5. Converte o custo em sacas do grão da safra — o coração do escambo.
    const sacks = sacksToCover(totalCost, version.grainPrice);

    const items = [
      {
        productId: version.season.grainId,
        kind: 'grain',
        productName: version.season.grainName,
        unit: version.season.grainUnit,
        quantity: sacks,
        unitValue: version.grainPrice,
        unitCost: 0,
      },
      ...products.map((product) => ({
        productId: product.id,
        kind: 'input',
        productName: product.name,
        unit: product.unit,
        quantity: quantities.get(product.id)!,
        unitValue: valueOf.get(product.id)!.price,
        // O custo é congelado junto com o preço: sem ele, corrigir um custo
        // depois reescreveria o lucro de permutas já fechadas.
        unitCost: valueOf.get(product.id)!.cost,
      })),
    ];

    return this.createWithCode({
      versionId: version.id,
      versionCode: version.code,
      consultantId: consultant.id,
      consultantName: consultant.fullName,
      consultantBranch: consultant.branch ?? '',
      producerId: producer.id,
      producerName: producer.name,
      status: 'pending',
      items: { create: items },
    });
  }

  /**
   * Grava a permuta reservando o próximo código público.
   *
   * O código é decidido lendo o maior já usado e somando um, e entre a leitura
   * e a gravação existe uma fresta: dois registros simultâneos podem escolher
   * o mesmo número. Hoje isso não acontece porque o SQLite serializa as
   * escritas dentro do processo, mas essa é uma garantia do BANCO ATUAL, não
   * do código — bastaria uma segunda instância, ou uma troca para Postgres,
   * para a corrida aparecer. O índice único em `code` transforma a colisão
   * numa falha limpa, e aqui ela vira simplesmente "pegue o próximo".
   */
  private async createWithCode(
    data: Omit<Prisma.BarterUncheckedCreateInput, 'code'>,
  ): Promise<BarterWithItems> {
    const MAX_ATTEMPTS = 5;
    for (let attempt = 1; ; attempt++) {
      try {
        return await this.prisma.$transaction(async (tx) =>
          tx.barter.create({
            data: { ...data, code: await this.nextCode(tx) },
            include: { items: true },
          }),
        );
      } catch (error) {
        if (attempt >= MAX_ATTEMPTS || !this.isDuplicateCode(error)) throw error;
      }
    }
  }

  /** Violação do índice único de `code` (P2002) — outra permuta chegou antes. */
  private isDuplicateCode(error: unknown): boolean {
    const known = error as { code?: string; meta?: { target?: unknown } };
    if (known?.code !== 'P2002') return false;
    const target = known.meta?.target;
    const fields = Array.isArray(target) ? target : [target];
    return fields.some((field) => typeof field === 'string' && field.includes('code'));
  }

  /**
   * Revisão do admin: aprova ou nega uma permuta pendente, com observação
   * opcional. Grava o snapshot do revisor e o momento da revisão.
   */
  async review(admin: User, code: string, dto: ReviewBarterDto): Promise<BarterWithItems> {
    const barter = await this.prisma.barter.findUnique({ where: { code } });
    if (!barter) throw new NotFoundException('Registro não encontrado.');
    if (barter.status !== 'pending') {
      throw new UnprocessableEntityException('Esta permuta já foi revisada');
    }

    const reviewed = await this.prisma.barter.update({
      where: { code },
      data: {
        status: dto.status,
        adminNote: dto.note?.trim() ? dto.note.trim() : null,
        reviewedBy: admin.fullName,
        reviewedById: admin.id,
        reviewedAt: new Date(),
      },
      include: { items: true },
    });

    // A permuta já guarda `reviewedBy`, mas ele é sobrescrito a cada revisão e
    // vive dentro do próprio registro. A trilha é outra coisa: fica fora, não
    // se reescreve, e é onde se lê a SEQUÊNCIA de decisões — que é o que o
    // fluxo de aprovação por etapas vai precisar.
    await this.audit.record({
      actor: admin,
      action: AUDIT_ACTION.barterReviewed,
      targetType: 'barter',
      targetId: reviewed.id,
      targetLabel: reviewed.code,
      detail: `${dto.status === 'approved' ? 'aprovada' : 'negada'}${
        reviewed.adminNote ? ` — ${reviewed.adminNote}` : ''
      }`,
    });
    return reviewed;
  }

  /**
   * Próximo código público no formato PRM-<ano>-NNN, sequencial dentro do ano.
   * Roda dentro da transação de criação para evitar corrida.
   */
  private async nextCode(tx: Prisma.TransactionClient): Promise<string> {
    const year = new Date().getFullYear();
    const prefix = `PRM-${year}-`;
    const rows = await tx.barter.findMany({
      where: { code: { startsWith: prefix } },
      select: { code: true },
    });
    let max = 0;
    for (const row of rows) {
      const sequence = Number.parseInt(row.code.slice(prefix.length), 10);
      if (Number.isFinite(sequence) && sequence > max) {
        max = sequence;
      }
    }
    return `${prefix}${String(max + 1).padStart(3, '0')}`;
  }
}
