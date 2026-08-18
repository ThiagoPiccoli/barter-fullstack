import { capabilitiesOf } from './policy';
import { isOpenAt, type Goal, type Realized } from '../seasons/version-progress';
import type {
  AuditLog,
  Barter,
  BarterItem,
  BarterVersion,
  ProductClass,
  PriceHistoryEntry,
  Producer,
  Product,
  Season,
  Unit,
  User,
  VersionPrice,
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

/**
 * O usuário. `manager` chega preenchido nas rotas que o incluem (a listagem e o
 * provisionamento de consultores) — é o que dá `managerName` sem obrigar o app
 * a ter a lista de gerentes, que é rota de admin.
 */
export function toUserJson(user: User & { manager?: { id: number; fullName: string } | null }) {
  return {
    id: user.id,
    fullName: user.fullName,
    email: user.email,
    role: user.role,
    phone: user.phone,
    // A UNIDADE da pessoa, e o nome dela congelado no cadastro. `branch`
    // continua no contrato porque é o que as telas mostram e o que os rankings
    // agrupam; `unitId` é o que o formulário usa para escolher. Ver o campo
    // `branch` no schema — quem escreve os dois é o provisionamento.
    unitId: user.unitId,
    branch: user.branch,
    // O GERENTE desta pessoa. Só o consultor tem, e para ele é obrigatório: é a
    // ele que as permutas do consultor são enviadas. Null nos outros papéis.
    managerId: user.managerId,
    managerName: user.manager?.fullName ?? null,
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
export function toProvisionedUserJson(provisioned: {
  user: User & { manager?: { id: number; fullName: string } | null };
  provisionalPassword: string;
}) {
  return {
    ...toUserJson(provisioned.user),
    provisionalPassword: provisioned.provisionalPassword,
  };
}

/**
 * A UNIDADE de retirada — o lugar onde o produtor busca os insumos.
 *
 * Curta porque a unidade é curta: ela não tem responsável e não participa do
 * fluxo de análise. Quem dá o parecer é o gerente do consultor (ver
 * `toBarterJson`), e a retirada pode ser em qualquer praça.
 */
export function toUnitJson(unit: Unit) {
  return {
    id: unit.id,
    name: unit.name,
    city: unit.city,
    createdAt: unit.createdAt,
    initials: initialsOf(unit.name),
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

/**
 * A classe de produto. `slug` é o identificador estável — é por ele que a
 * planilha e o app se referem a ela; `name` é só o que a pessoa lê.
 */
export function toProductClassJson(productClass: ProductClass) {
  return {
    id: productClass.id,
    slug: productClass.slug,
    name: productClass.name,
    position: productClass.position,
    ruleType: productClass.ruleType,
    ruleValue: productClass.ruleValue,
  };
}

export function toPriceEntryJson(entry: PriceHistoryEntry) {
  return {
    price: entry.price,
    changedBy: entry.changedBy,
    changedAt: entry.changedAt,
  };
}

/** O cadastro do produto, sem nada do histórico. Base das duas formas abaixo. */
function productFields(product: Product) {
  return {
    id: product.id,
    name: product.name,
    unit: product.unit,
    type: product.type,
    // Último valor PUBLICADO, não a autoridade: quem precifica uma permuta é a
    // tabela da versão vigente (ver toBarterVersionJson).
    currentPrice: product.currentPrice,
    sku: product.sku,
    // "a unidade deste item é palpite" — o app mostra o aviso e oferece o
    // filtro para o admin resolver a lista de uma vez.
    unitPending: product.unitPending,
    requiredPerHa: product.requiredPerHa,
    classId: product.classId,
  };
}

/**
 * O produto com a linha do tempo INTEIRA — a forma do detalhe
 * (`GET /products/:id`) e das respostas de criação e edição.
 */
export function toProductJson(product: Product & { priceHistory?: PriceHistoryEntry[] }) {
  return {
    ...productFields(product),
    priceHistory: product.priceHistory?.map(toPriceEntryJson),
  };
}

/**
 * O produto como a LISTAGEM o devolve: sem a série, com o resumo dela.
 *
 * Existe separado de `toProductJson` de propósito. A listagem carrega só o
 * primeiro ponto do histórico (para calcular a variação) e a contagem —
 * despejar isso no campo `priceHistory` entregaria um array de um elemento com
 * cara de linha do tempo completa, e a tela de relatório desenharia um gráfico
 * de um ponto só achando que era o histórico do produto.
 *
 * `firstPrice` é null quando não há histórico: sem ele não existe variação a
 * mostrar, e zero seria um valor com significado errado.
 */
export function toProductListJson(
  product: Product & { priceHistory: PriceHistoryEntry[]; _count: { priceHistory: number } },
) {
  return {
    ...productFields(product),
    firstPrice: product.priceHistory[0]?.price ?? null,
    priceHistoryCount: product._count.priceHistory,
  };
}

/* ── Barter: safra e versões ──────────────────────────────────────────── */

export function toSeasonJson(season: Season & { versions?: BarterVersion[] }) {
  return {
    id: season.id,
    code: season.code,
    name: season.name,
    year: season.year,
    grainId: season.grainId,
    grainName: season.grainName,
    grainUnit: season.grainUnit,
    status: season.status,
    openedAt: season.openedAt,
    closedAt: season.closedAt,
    versions: season.versions?.map((version) => toBarterVersionJson(version)),
  };
}

export function toVersionPriceJson(price: VersionPrice) {
  return {
    productId: price.productId,
    productName: price.productName,
    unit: price.unit,
    price: price.price,
  };
}

/**
 * A versão do Barter. Três públicos, um formato:
 *
 * - o consultor precisa de `grainPrice` e da tabela `prices` para a prévia das
 *   sacas (a tela esconde o R$, mas a conta é a mesma do servidor);
 * - o admin precisa de `progress` para saber o quanto falta para a meta;
 * - os dois precisam de `isOpen`, que é a resposta pronta para "dá para
 *   registrar permuta agora?" — calculada aqui para o app não reimplementar a
 *   regra de vigência.
 *
 * `progress` só vai quando quem chamou pode gerenciar o Barter: meta é número
 * de retaguarda, e o consultor não vê valores.
 */
export function toBarterVersionJson(
  version: BarterVersion & { season?: Season; prices?: VersionPrice[] },
  extra?: { realized: Realized; goals: Goal[] },
) {
  return {
    id: version.id,
    code: version.code,
    number: version.number,
    seasonId: version.seasonId,
    seasonCode: version.season?.code,
    seasonName: version.season?.name,
    grainId: version.season?.grainId,
    grainName: version.season?.grainName,
    grainUnit: version.season?.grainUnit,
    grainPrice: version.grainPrice,
    status: version.status,
    isOpen: isOpenAt(version, new Date()),
    startsAt: version.startsAt,
    endsAt: version.endsAt,
    targetSales: version.targetSales,
    targetSacks: version.targetSacks,
    targetBarters: version.targetBarters,
    sourceFile: version.sourceFile,
    note: version.note,
    closedAt: version.closedAt,
    closedBy: version.closedBy,
    prices: version.prices?.map(toVersionPriceJson),
    ...(extra ? { realized: extra.realized, goals: extra.goals } : {}),
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
    // Em qual gestão esta permuta foi fechada — vai no detalhe e no comprovante.
    versionCode: barter.versionCode,
    consultantId: barter.consultantId,
    consultantName: barter.consultantName,
    consultantBranch: barter.consultantBranch,
    producerId: barter.producerId,
    producerName: barter.producerName,
    // Onde o produtor retira. É logística: não decide quem analisa a permuta.
    // Vazio nas permutas anteriores ao cadastro de unidades.
    unitId: barter.unitId,
    unitName: barter.unitName,
    status: barter.status,
    // A QUEM esta permuta foi enviada — o gerente do consultor no momento do
    // registro — e o parecer dele. `managerId`/`managerName` vêm preenchidos
    // desde a criação (é o destinatário); `managerNote` e `managerReviewedAt`
    // só quando o parecer é escrito, e é o app que lê essa diferença para saber
    // se a etapa terminou.
    managerId: barter.managerId,
    managerName: barter.managerName,
    managerNote: barter.managerNote,
    managerReviewedAt: barter.managerReviewedAt,
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
