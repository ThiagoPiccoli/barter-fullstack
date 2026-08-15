import { Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import type { PriceHistoryEntry, Product, User } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateProductDto, ListProductsQuery, UpdateProductDto } from './dto/product.dto';

type ProductWithHistory = Product & { priceHistory: PriceHistoryEntry[] };

/**
 * Produto como a LISTAGEM o carrega: sem a linha do tempo, mas com o que se
 * lê dela na tela de lista — o primeiro ponto e quantos pontos existem.
 */
export type ProductWithHistorySummary = Product & {
  priceHistory: PriceHistoryEntry[];
  _count: { priceHistory: number };
};

/** Histórico sempre em ordem cronológica (o app assume o mais antigo primeiro). */
const withHistory = {
  priceHistory: { orderBy: { changedAt: 'asc' as const } },
};

/**
 * O que a listagem traz do histórico: o ponto MAIS ANTIGO e a contagem.
 *
 * A linha do tempo inteira não cabe aqui. Cada versão do Barter publicada
 * acrescenta um ponto por produto, então ela cresce a cada lançamento, sem
 * teto — e o app pede o catálogo a cada login e a cada refresh. A tela de
 * lista usa dois números dela (a variação contra o primeiro valor e a
 * quantidade de registros); quem precisa da série inteira é o relatório de um
 * produto, que agora a busca em `GET /products/:id`.
 */
const withHistorySummary = {
  priceHistory: { orderBy: { changedAt: 'asc' as const }, take: 1 },
  _count: { select: { priceHistory: true } },
};

@Injectable()
export class ProductsService {
  constructor(private readonly prisma: PrismaService) {}

  async list(query: ListProductsQuery): Promise<ProductWithHistorySummary[]> {
    return this.prisma.product.findMany({
      where: query.type ? { type: query.type } : {},
      include: withHistorySummary,
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
    await this.ensureClass(dto.classId ?? null, dto.type);
    const sku = dto.sku?.trim() || (await this.nextSku(dto.type));
    await this.ensureFreeSku(sku, null);
    return this.prisma.product.create({
      data: {
        name: dto.name,
        unit: dto.unit,
        type: dto.type,
        sku,
        currentPrice: dto.currentPrice,
        requiredPerHa: dto.requiredPerHa ?? 0,
        classId: dto.classId ?? null,
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
    if (dto.classId !== undefined) {
      await this.ensureClass(dto.classId, product.type);
    }
    const sku = dto.sku?.trim();
    if (sku) await this.ensureFreeSku(sku, id);
    return this.prisma.product.update({
      where: { id },
      data: {
        ...dto,
        // Código vazio não apaga o que existe: quem quer trocar, digita outro.
        ...(sku ? { sku } : { sku: undefined }),
        // Escrever a unidade é exatamente a revisão que a marca pedia.
        ...(dto.unit ? { unitPending: false } : {}),
      },
      include: withHistory,
    });
  }

  /**
   * O próximo código automático do tipo: `GRA-0003`, `INS-0012`.
   *
   * Serve para nenhum item ficar sem código — é por ele que se procura o item
   * na busca, e "sem código" obrigaria a lembrar o nome exato. Quando a
   * planilha do fornecedor traz o código dela, é ELE que vale: este aqui é o
   * padrão de quem cadastra à mão.
   */
  private async nextSku(type: string): Promise<string> {
    const prefix = type === 'grain' ? 'GRA-' : 'INS-';
    const existing = await this.prisma.product.findMany({
      where: { sku: { startsWith: prefix } },
      select: { sku: true },
    });
    let max = 0;
    for (const row of existing) {
      const sequence = Number.parseInt((row.sku ?? '').slice(prefix.length), 10);
      if (Number.isFinite(sequence) && sequence > max) max = sequence;
    }
    return `${prefix}${String(max + 1).padStart(4, '0')}`;
  }

  /**
   * O código é único no catálogo — é o que faz dele uma chave de busca e de
   * casamento com a planilha. A checagem aqui existe para o erro sair legível:
   * sem ela, a violação do índice viraria um 500 genérico.
   */
  private async ensureFreeSku(sku: string, exceptId: number | null): Promise<void> {
    const owner = await this.prisma.product.findUnique({ where: { sku } });
    if (owner && owner.id !== exceptId) {
      throw new UnprocessableEntityException(`O código ${sku} já é do item ${owner.name}`);
    }
  }

  /**
   * Tira o produto do catálogo. O HISTÓRICO sobrevive: os itens das permutas
   * já registradas guardam nome, unidade e preço no próprio registro, e o FK
   * apenas vira NULL (SetNull no schema). Ou seja, apagar um insumo descontinuado
   * não reescreve nenhuma permuta antiga — só impede novas.
   *
   * A linha do tempo de PREÇOS, essa sim, vai junto (Cascade): ela só faz
   * sentido enquanto o produto existe.
   */
  async delete(id: number): Promise<void> {
    await this.find(id);
    await this.prisma.product.delete({ where: { id } });
  }

  private async ensureClass(classId: number | null, type: string): Promise<void> {
    if (classId === null) return;
    if (type !== 'input') {
      throw new UnprocessableEntityException('Apenas insumos pertencem a uma classe');
    }
    const found = await this.prisma.productClass.findUnique({ where: { id: classId } });
    if (!found) throw new UnprocessableEntityException('Classe não encontrada');
  }
}
