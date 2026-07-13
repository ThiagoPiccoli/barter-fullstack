import type {
  Barter,
  BarterItem,
  InputCategory,
  PriceHistoryEntry,
  Producer,
  Product,
  User,
} from '@prisma/client';

/**
 * O CONTRATO da API em um só lugar. As formas abaixo são exatamente as que o
 * app Flutter espera (mesmo shape da versão AdonisJS) — mudou aqui, mudou o
 * cliente. Datas saem como Date e viram ISO na serialização JSON do Nest.
 */

/** Iniciais (até 2 letras) para o avatar, calculadas do nome. */
export function initialsOf(name: string): string {
  const words = name.trim().split(/\s+/).filter(Boolean);
  if (words.length === 0) return '?';
  if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
  return (words[0][0] + words[words.length - 1][0]).toUpperCase();
}

export function toUserJson(user: User) {
  return {
    id: user.id,
    fullName: user.fullName,
    email: user.email,
    role: user.role,
    phone: user.phone,
    branch: user.branch,
    createdAt: user.createdAt,
    initials: initialsOf(user.fullName),
  };
}

export function toProducerJson(producer: Producer) {
  return {
    id: producer.id,
    name: producer.name,
    sellerId: producer.sellerId,
    document: producer.document,
    phone: producer.phone,
    farmName: producer.farmName,
    city: producer.city,
    areaHa: producer.areaHa,
    createdAt: producer.createdAt,
    initials: initialsOf(producer.name),
  };
}

export function toCategoryJson(category: InputCategory) {
  return {
    id: category.id,
    name: category.name,
    ruleType: category.ruleType,
    ruleValue: category.ruleValue,
  };
}

export function toPriceEntryJson(entry: PriceHistoryEntry) {
  return {
    price: entry.price,
    changedBy: entry.changedBy,
    changedAt: entry.changedAt,
  };
}

export function toProductJson(product: Product & { priceHistory?: PriceHistoryEntry[] }) {
  return {
    id: product.id,
    name: product.name,
    unit: product.unit,
    type: product.type,
    currentPrice: product.currentPrice,
    requiredPerHa: product.requiredPerHa,
    categoryId: product.categoryId,
    priceHistory: product.priceHistory?.map(toPriceEntryJson),
  };
}

export function toBarterItemJson(item: BarterItem) {
  return {
    kind: item.kind,
    productId: item.productId,
    productName: item.productName,
    unit: item.unit,
    quantity: item.quantity,
    unitValue: item.unitValue,
  };
}

export function toBarterJson(barter: Barter & { items?: BarterItem[] }) {
  return {
    id: barter.id,
    code: barter.code,
    sellerId: barter.sellerId,
    sellerName: barter.sellerName,
    sellerBranch: barter.sellerBranch,
    producerId: barter.producerId,
    producerName: barter.producerName,
    status: barter.status,
    adminNote: barter.adminNote,
    reviewedBy: barter.reviewedBy,
    reviewedAt: barter.reviewedAt,
    createdAt: barter.createdAt,
    items: barter.items?.map(toBarterItemJson),
  };
}
