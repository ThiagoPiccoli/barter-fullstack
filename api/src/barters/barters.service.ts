import {
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import type { Barter, BarterItem, Prisma, User } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import {
  MONEY_EPSILON,
  categoryRequired,
  categorySpend,
  inputCost,
  minQuantityFor,
  sacksToCover,
  type PricedInput,
} from './barter-math';
import { CreateBarterDto, ReviewBarterDto } from './dto/barter.dto';

type BarterWithItems = Barter & { items: BarterItem[] };

/**
 * Regras de negócio da permuta. O servidor é a autoridade: preços saem do
 * banco (nunca do cliente), mínimos por hectare e por categoria travam a
 * criação, e as sacas do grão são calculadas aqui.
 */
@Injectable()
export class BartersService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Permutas visíveis para o usuário: vendedor enxerga apenas as próprias;
   * admin enxerga todas. Regra de acesso central do domínio.
   */
  async listFor(user: User, status?: string): Promise<BarterWithItems[]> {
    return this.prisma.barter.findMany({
      where: {
        ...(user.role === 'admin' ? {} : { sellerId: user.id }),
        ...(status && ['pending', 'approved', 'denied'].includes(status) ? { status } : {}),
      },
      include: { items: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  /** Uma permuta pelo código público, respeitando o escopo do usuário. */
  async findFor(user: User, code: string): Promise<BarterWithItems> {
    const barter = await this.prisma.barter.findUnique({
      where: { code },
      include: { items: true },
    });
    if (!barter) throw new NotFoundException('Registro não encontrado.');
    if (user.role !== 'admin' && barter.sellerId !== user.id) {
      throw new ForbiddenException('Você não tem acesso a esta permuta');
    }
    return barter;
  }

  /**
   * Registra uma permuta para um produtor da carteira do vendedor. Fluxo:
   * 1. produtor precisa pertencer à carteira de quem registra;
   * 2. todo insumo com exigência por hectare é obrigatório, no mínimo
   *    `taxa × área` (o app pré-preenche, o servidor confere);
   * 3. as regras de mínimo das categorias precisam estar satisfeitas;
   * 4. o custo é precificado com os valores vigentes do banco e convertido em
   *    sacas do grão de pagamento — o item de grão é criado pelo servidor.
   */
  async create(seller: User, dto: CreateBarterDto): Promise<BarterWithItems> {
    if (seller.role === 'admin') {
      throw new ForbiddenException('Permutas são registradas pelo vendedor da carteira');
    }

    const producer = await this.prisma.producer.findUnique({ where: { id: dto.producerId } });
    if (!producer) {
      throw new UnprocessableEntityException('Produtor não encontrado');
    }
    if (producer.sellerId !== seller.id) {
      throw new ForbiddenException('Este produtor não pertence à sua carteira');
    }

    const grain = await this.prisma.product.findUnique({ where: { id: dto.grainId } });
    if (!grain || grain.type !== 'grain') {
      throw new UnprocessableEntityException('Escolha um grão de pagamento válido');
    }
    if (grain.currentPrice <= 0) {
      throw new UnprocessableEntityException(`O grão ${grain.name} está sem valor de referência`);
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

    const pricedInputs: PricedInput[] = products.map((product) => ({
      productId: product.id,
      quantity: quantities.get(product.id)!,
      unitPrice: product.currentPrice,
      categoryId: product.categoryId,
    }));

    if (pricedInputs.some((item) => item.quantity <= 0)) {
      throw new UnprocessableEntityException('Quantidades de insumo devem ser maiores que zero');
    }

    // 2. Insumos com exigência por hectare são obrigatórios para a área do produtor.
    const requiredProducts = await this.prisma.product.findMany({
      where: { type: 'input', requiredPerHa: { gt: 0 } },
    });
    for (const product of requiredProducts) {
      const min = minQuantityFor(product.requiredPerHa, producer.areaHa);
      const chosen = quantities.get(product.id) ?? 0;
      if (chosen + 0.005 < min) {
        throw new UnprocessableEntityException(
          `${product.name} exige no mínimo ${min} ${product.unit} para ${producer.areaHa} ha`,
        );
      }
    }

    // 3. Regras de mínimo por categoria ("pasta") travam o envio.
    const totalCost = inputCost(pricedInputs);
    if (totalCost <= 0) {
      throw new UnprocessableEntityException('Escolha ao menos um insumo para retirar');
    }

    const ruledCategories = (
      await this.prisma.inputCategory.findMany({ where: { NOT: { ruleType: 'none' } } })
    ).filter((category) => category.ruleValue > 0);
    const unmet = ruledCategories.filter((category) => {
      const required = categoryRequired(category, { totalCost, areaHa: producer.areaHa });
      return required > 0 && categorySpend(pricedInputs, category.id) < required - MONEY_EPSILON;
    });
    if (unmet.length > 0) {
      throw new UnprocessableEntityException(
        `Mínimo da categoria não atingido: ${unmet.map((c) => c.name).join(', ')}`,
      );
    }

    // 4. Converte o custo em sacas do grão — o coração do escambo.
    const sacks = sacksToCover(totalCost, grain.currentPrice);

    return this.prisma.$transaction(async (tx) => {
      return tx.barter.create({
        data: {
          code: await this.nextCode(tx),
          sellerId: seller.id,
          sellerName: seller.fullName,
          sellerBranch: seller.branch ?? '',
          producerId: producer.id,
          producerName: producer.name,
          status: 'pending',
          items: {
            create: [
              {
                productId: grain.id,
                kind: 'grain',
                productName: grain.name,
                unit: grain.unit,
                quantity: sacks,
                unitValue: grain.currentPrice,
              },
              ...products.map((product) => ({
                productId: product.id,
                kind: 'input',
                productName: product.name,
                unit: product.unit,
                quantity: quantities.get(product.id)!,
                unitValue: product.currentPrice,
              })),
            ],
          },
        },
        include: { items: true },
      });
    });
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

    return this.prisma.barter.update({
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
