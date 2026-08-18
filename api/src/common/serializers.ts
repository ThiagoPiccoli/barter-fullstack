import { CAPABILITY, can, capabilitiesOf } from './policy';
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

/**
 * A LENTE DE VALOR: por quais olhos este JSON está sendo montado.
 *
 * Existe porque "o consultor não vê R$" deixou de ser regra de tela e passou a
 * ser regra da API. Enquanto era só da tela, o JSON carregava a tabela inteira
 * do fornecedor e bastava um `curl` com o token do consultor para lê-la — e,
 * depois do cache offline, ela ainda ia parar gravada no aparelho dele.
 *
 * Para quem NÃO vê R$, os valores saem convertidos em SACAS do grão da safra:
 * `sacksPerUnit` no lugar de `price`, `sacksPerHa` no lugar do mínimo em R$ por
 * hectare. É a mesma informação que ele já usava — a prévia dele sempre foi em
 * sacas —, sem o numerador.
 *
 * A conversão precisa da cotação da saca, e é por isso que a lente a carrega.
 * `grainPrice` zero ou ausente significa que não há tabela pela qual converter:
 * aí o campo simplesmente não vai, e a tela do consultor cai no "Barter fechado"
 * — que é a verdade.
 */
export type ValueLens = {
  /** Pode ler valores em R$ diretamente. */
  showsCurrency: boolean;
  /** Cotação da saca usada na conversão, quando não pode. */
  grainPrice: number;
};

export function lensFor(viewer: Pick<User, 'role'> | undefined, grainPrice = 0): ValueLens {
  return {
    showsCurrency: viewer ? can(viewer, CAPABILITY.pricesRead) : false,
    grainPrice,
  };
}

/** A lente da retaguarda — para os pontos que só ela alcança. */
export const CURRENCY_LENS: ValueLens = { showsCurrency: true, grainPrice: 0 };

/**
 * Um valor em R$ traduzido para sacas do grão, ou `undefined` quando não há
 * cotação pela qual converter.
 *
 * Sem arredondamento de propósito. O app soma `quantidade × sacksPerUnit` e só
 * então arredonda, exatamente como o servidor soma em R$ e só então divide —
 * arredondar cada item aqui introduziria uma diferença por linha, e a prévia da
 * tela deixaria de bater com o que é gravado. Ver `barter-math.ts`.
 */
function inSacks(value: number, grainPrice: number): number | undefined {
  return grainPrice > 0 ? value / grainPrice : undefined;
}

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

/**
 * O produtor, com a CARTEIRA como lista.
 *
 * `consultantIds` substituiu o antigo `consultantId` — e substituiu mesmo, sem
 * deixar o campo velho para trás: mantê-lo obrigaria a eleger um dos
 * consultores como "o" consultor, e o primeiro da lista viraria dono por
 * acidente de ordenação. Os dois lados deste repositório sobem juntos; um
 * campo que mente é pior do que um campo que sumiu.
 *
 * Vazio significa produtor esperando realocação (o último consultor vinculado
 * foi excluído) — só a retaguarda o enxerga até o admin designar alguém.
 */
export function toProducerJson(producer: Producer & { consultants: { consultantId: number }[] }) {
  return {
    id: producer.id,
    name: producer.name,
    consultantIds: producer.consultants.map((link) => link.consultantId),
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
/**
 * A classe de produto e a regra de mínimo dela.
 *
 * `ruleValue` muda de UNIDADE conforme a lente, e por isso vem acompanhado de
 * `ruleUnit`. A regra percentual é uma proporção e atravessa sem tradução — 20%
 * do custo é 20% das sacas. Já `valuePerHa` é R$ por hectare, e para quem não vê
 * R$ ela sai em SACAS por hectare.
 *
 * `ruleUnit` é explícito em vez de deduzido do papel: o cliente não deveria ter
 * que saber quem ele é para entender o número que recebeu.
 */
export function toProductClassJson(productClass: ProductClass, lens: ValueLens = CURRENCY_LENS) {
  const isPerHa = productClass.ruleType === 'valuePerHa';
  const converted =
    isPerHa && !lens.showsCurrency
      ? inSacks(productClass.ruleValue, lens.grainPrice)
      : productClass.ruleValue;

  return {
    id: productClass.id,
    slug: productClass.slug,
    name: productClass.name,
    position: productClass.position,
    ruleType: productClass.ruleType,
    // Sem cotação para converter, a regra por hectare não tem como ser dita a
    // quem não vê R$ — e ela vai como zero, que o app lê como "sem exigência".
    // Não é permissivo: sem Barter aberto ele não monta permuta nenhuma, e quem
    // cobra o mínimo de verdade continua sendo o servidor, no envio.
    ruleValue: converted ?? 0,
    ruleUnit: isPerHa && !lens.showsCurrency ? 'sacksPerHa' : isPerHa ? 'currencyPerHa' : 'percent',
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
function productFields(product: Product, lens: ValueLens) {
  return {
    id: product.id,
    name: product.name,
    unit: product.unit,
    type: product.type,
    // Último valor PUBLICADO, não a autoridade: quem precifica uma permuta é a
    // tabela da versão vigente (ver toBarterVersionJson).
    //
    // Some inteiro para quem não vê R$, sem virar sacas: o consultor nunca
    // precisou dele — a prévia da permuta é feita com a tabela da VERSÃO, e
    // este campo é o último valor de catálogo, que é outra coisa.
    ...(lens.showsCurrency ? { currentPrice: product.currentPrice } : {}),
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
export function toProductJson(
  product: Product & { priceHistory?: PriceHistoryEntry[] },
  lens: ValueLens = CURRENCY_LENS,
) {
  return {
    ...productFields(product, lens),
    // A linha do tempo é uma série de R$ — não há versão dela em sacas, porque
    // cada ponto foi cotado contra um grão diferente ao longo das safras.
    ...(lens.showsCurrency ? { priceHistory: product.priceHistory?.map(toPriceEntryJson) } : {}),
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
  lens: ValueLens = CURRENCY_LENS,
) {
  return {
    ...productFields(product, lens),
    ...(lens.showsCurrency
      ? {
          firstPrice: product.priceHistory[0]?.price ?? null,
          priceHistoryCount: product._count.priceHistory,
        }
      : {}),
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

/**
 * Uma linha da tabela da versão.
 *
 * Para quem vê R$, `price`. Para quem não vê, `sacksPerUnit` — quantas sacas do
 * grão cobrem UMA unidade deste insumo. É com esse número que o app monta a
 * prévia, e ele é tudo de que ela precisa: a permuta do consultor sempre foi
 * "tantos insumos → tantas sacas".
 */
export function toVersionPriceJson(price: VersionPrice, lens: ValueLens = CURRENCY_LENS) {
  return {
    productId: price.productId,
    productName: price.productName,
    unit: price.unit,
    ...(lens.showsCurrency
      ? { price: price.price }
      : { sacksPerUnit: inSacks(price.price, lens.grainPrice) ?? 0 }),
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
  viewer?: Pick<User, 'role'>,
) {
  // A cotação da saca DESTA versão é o divisor da conversão — por isso a lente
  // nasce aqui, e não na porta da requisição: cada versão tem a sua.
  const lens = lensFor(viewer, version.grainPrice);
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
    // A COTAÇÃO DA SACA é o divisor de tudo: entregá-la a quem recebe
    // `sacksPerUnit` devolveria os R$ por multiplicação, e a conversão não teria
    // servido para nada.
    ...(lens.showsCurrency ? { grainPrice: version.grainPrice } : {}),
    status: version.status,
    isOpen: isOpenAt(version, new Date()),
    startsAt: version.startsAt,
    endsAt: version.endsAt,
    // Metas são número de retaguarda; `targetSales` é R$ direto.
    ...(lens.showsCurrency
      ? {
          targetSales: version.targetSales,
          targetBarters: version.targetBarters,
        }
      : {}),
    targetSacks: version.targetSacks,
    sourceFile: version.sourceFile,
    note: version.note,
    closedAt: version.closedAt,
    closedBy: version.closedBy,
    prices: version.prices?.map((price) => toVersionPriceJson(price, lens)),
    ...(extra ? { realized: extra.realized, goals: extra.goals } : {}),
  };
}

/**
 * Um item da permuta gravada.
 *
 * `unitValue` é o valor congelado em R$ e só vai para quem vê R$. O consultor
 * nunca o exibiu — o comprovante dele sai com `showValues: false` —, e mandá-lo
 * assim mesmo era o vazamento mais silencioso dos quatro: a tabela do
 * fornecedor saía inteira pelas permutas dele.
 *
 * Não vira sacas porque o item de GRÃO já é a resposta em sacas: a permuta diz,
 * na própria linha do grão, quantas sacas cobrem os insumos.
 */
export function toBarterItemJson(item: BarterItem, lens: ValueLens = CURRENCY_LENS) {
  return {
    kind: item.kind,
    productId: item.productId,
    productName: item.productName,
    unit: item.unit,
    quantity: item.quantity,
    ...(lens.showsCurrency ? { unitValue: item.unitValue } : {}),
  };
}

export function toBarterJson(
  barter: Barter & { items?: BarterItem[] },
  viewer?: Pick<User, 'role'>,
) {
  const lens = lensFor(viewer);
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
    // O IMPOSTO DA ENTREGA: a forma de recolhimento escolhida no fechamento e a
    // alíquota que ela produziu, como ficaram no registro.
    //
    // A alíquota vai para todo mundo, inclusive o consultor: é um PERCENTUAL, e
    // não um valor em R$ — quem não vê moeda aplica os mesmos % sobre as sacas
    // e chega ao imposto na unidade em que enxerga a permuta. Ver `ValueLens`.
    taxRegime: barter.taxRegime,
    taxRate: barter.taxRate,
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
    items: barter.items?.map((item) => toBarterItemJson(item, lens)),
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
