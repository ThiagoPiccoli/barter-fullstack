import { capabilitiesOf } from './policy';
import type {
  AuditLog,
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
    // O app usa isto para exigir a troca da senha provisória antes de deixar
    // o usuário entrar no painel.
    mustChangePassword: user.mustChangePassword,
    // O que esta pessoa pode fazer, resolvido pelo SERVIDOR a partir de
    // policy.ts. É com isto que o app monta as abas e decide quais botões
    // existem — em vez de perguntar "é admin?" e manter uma segunda cópia das
    // regras em Dart. Conceder um serviço a um papel passa a ser uma linha no
    // servidor, e o app se ajusta na próxima sessão, sem versão nova.
    capabilities: capabilitiesOf(user),
  };
}

/**
 * Resposta do provisionamento (criação e reset de senha de QUALQUER papel): o
 * cadastro mais a senha de primeira entrada em texto puro. É a única resposta
 * da API que carrega uma senha, e ela existe uma vez só — depois disto o valor
 * só existe como hash, e nem o admin consegue lê-lo de volta.
 *
 * A FORMA é a mesma para os quatro papéis, de propósito: o app tem um só
 * diálogo de "anote esta senha", e ele não precisa saber quem foi cadastrado.
 */
export function toProvisionedUserJson(provisioned: { user: User; provisionalPassword: string }) {
  return {
    ...toUserJson(provisioned.user),
    provisionalPassword: provisioned.provisionalPassword,
  };
}

export function toProducerJson(producer: Producer) {
  return {
    id: producer.id,
    name: producer.name,
    consultantId: producer.consultantId,
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
    consultantId: barter.consultantId,
    consultantName: barter.consultantName,
    consultantBranch: barter.consultantBranch,
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

/**
 * Linha da trilha de auditoria. Sai com o autor e o alvo já em texto — quem lê
 * precisa entender o ocorrido mesmo que a conta envolvida não exista mais.
 */
export function toAuditLogJson(entry: AuditLog) {
  return {
    id: entry.id,
    at: entry.at,
    actorId: entry.actorId,
    actorName: entry.actorName,
    actorRole: entry.actorRole,
    action: entry.action,
    targetType: entry.targetType,
    targetId: entry.targetId,
    targetLabel: entry.targetLabel,
    detail: entry.detail,
  };
}
