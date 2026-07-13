import { Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import type { PriceHistoryEntry, Product, User } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateProductDto, UpdateProductDto } from './dto/product.dto';

type ProductWithHistory = Product & { priceHistory: PriceHistoryEntry[] };

/** Histórico sempre em ordem cronológica (o app assume o mais antigo primeiro). */
const withHistory = {
  priceHistory: { orderBy: { changedAt: 'asc' as const } },
};

@Injectable()
export class ProductsService {
  constructor(private readonly prisma: PrismaService) {}

  async list(type?: string): Promise<ProductWithHistory[]> {
    return this.prisma.product.findMany({
      where: type === 'grain' || type === 'input' ? { type } : {},
      include: withHistory,
      orderBy: { id: 'asc' },
    });
  }

  async find(id: number): Promise<ProductWithHistory> {
    const product = await this.prisma.product.findUnique({ where: { id }, include: withHistory });
    if (!product) throw new NotFoundException('Registro não encontrado.');
    return product;
  }

  /** Todo produto nasce com o primeiro ponto da linha do tempo de valores. */
  async create(admin: User, dto: CreateProductDto): Promise<ProductWithHistory> {
    await this.ensureCategory(dto.categoryId ?? null, dto.type);
    return this.prisma.product.create({
      data: {
        name: dto.name,
        unit: dto.unit,
        type: dto.type,
        currentPrice: dto.currentPrice,
        requiredPerHa: dto.requiredPerHa ?? 0,
        categoryId: dto.categoryId ?? null,
        priceHistory: {
          create: {
            price: dto.currentPrice,
            changedBy: admin.fullName,
            changedById: admin.id,
            changedAt: new Date(),
          },
        },
      },
      include: withHistory,
    });
  }

  async update(id: number, dto: UpdateProductDto): Promise<ProductWithHistory> {
    const product = await this.find(id);
    if (dto.categoryId !== undefined) {
      await this.ensureCategory(dto.categoryId, product.type);
    }
    return this.prisma.product.update({ where: { id }, data: dto, include: withHistory });
  }

  /**
   * Reajuste do valor de referência — a "taxa de câmbio" das novas permutas.
   * Sempre acrescenta um ponto ao histórico; permutas antigas não mudam
   * (guardam snapshot de preço nos itens).
   */
  async updatePrice(admin: User, id: number, price: number): Promise<ProductWithHistory> {
    await this.find(id);
    const [updated] = await this.prisma.$transaction([
      this.prisma.product.update({
        where: { id },
        data: {
          currentPrice: price,
          priceHistory: {
            create: {
              price,
              changedBy: admin.fullName,
              changedById: admin.id,
              changedAt: new Date(),
            },
          },
        },
        include: withHistory,
      }),
    ]);
    return updated;
  }

  private async ensureCategory(categoryId: number | null, type: string): Promise<void> {
    if (categoryId === null) return;
    if (type !== 'input') {
      throw new UnprocessableEntityException('Apenas insumos podem pertencer a uma categoria');
    }
    const category = await this.prisma.inputCategory.findUnique({ where: { id: categoryId } });
    if (!category) throw new UnprocessableEntityException('Categoria não encontrada');
  }
}
