import {
  BARTER_HOLDER,
  BARTER_STATUS_LABELS,
  nextActionOf,
  outcomeLabelOf,
  progressOf,
  type BarterStatus,
} from '../barters/barter-workflow';
import { CREDIT_FILE_LABELS, type CreditFileKind } from '../barters/credit-file';
import { CAPABILITY, can, capabilitiesOf } from './policy';
import { ROLE_LABELS, type Role } from './roles';
import { isOpenAt, type Goal, type Realized } from '../seasons/version-progress';
import { creditorGaps, forumOf } from './creditor';
import { pledgeAreaFor } from '../barters/barter-math';
import type {
  AuditLog,
  Barter,
  BarterCpr,
  BarterCreditFile,
  BarterEvent,
  BarterInvoice,
  BarterItem,
  BarterProductRequest,
  BarterVersion,
  CprArea,
  CprAreaOwner,
  CprGuarantor,
  Creditor,
  InsuranceRate,
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

/** Só o que o serializer precisa do gerente. Evita levar o hash de senha junto. */
export const MANAGER_FIELDS = { select: { id: true, fullName: true } } as const;

/**
 * O usuário COM o gerente resolvido — a única forma que [toUserJson] aceita.
 *
 * O `manager` é obrigatório de propósito, e essa obrigatoriedade é a correção de
 * um defeito: enquanto ele era opcional, qualquer `User` cru passava por aqui, e
 * as rotas de sessão (login, `/me`, troca de senha) passavam um — sem a relação
 * carregada. O consultor recebia `managerName: null` e o app dizia "Meu gerente:
 * —" e "Vai para: seu gerente" a quem tem gerente com nome e sobrenome.
 *
 * Nenhum teste pegou porque as asserções de `managerName` de usuário passam pela
 * listagem e pelo provisionamento, que sempre incluíram. Com o campo obrigatório
 * quem passa a cobrar é o compilador, em toda rota, inclusive nas que ainda não
 * existem — que é a única barreira que não depende de alguém lembrar.
 */
export type UserWithManager = User & { manager: Pick<User, 'id' | 'fullName'> | null };

/**
 * O usuário. `manager` vem das rotas que o incluem (com [MANAGER_FIELDS]) — é o
 * que dá `managerName` sem obrigar o app a ter a lista de gerentes, que é rota
 * de admin.
 */
export function toUserJson(user: UserWithManager) {
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
  user: UserWithManager;
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
    // COMO ELE RECOLHE o Funrural — a opção formal dele perante o fisco, que
    // vale para todas as entregas e por isso mora no cadastro. É o que a permuta
    // nova assume sem perguntar. Ver `Producer.taxRegime`.
    taxRegime: producer.taxRegime,
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

/**
 * UMA PRAÇA da base de seguros — o município e quanto custa segurar um hectare
 * nele.
 *
 * O valor sai pela LENTE, como tudo o mais: o admin lê "R$ 85,00 por hectare"; o
 * consultor, que não vê moeda, lê `sacksPerHa` — quantas sacas do grão cobrem
 * um hectare de seguro. É a mesma conversão de `toVersionPriceJson`, e existe
 * pela mesma razão: a prévia da tela dele precisa do número, e o R$ não pode
 * viajar no JSON de quem não pode lê-lo.
 *
 * A cotação que converte é a da VERSÃO VIGENTE, e ela chega de fora (a lente),
 * porque este cadastro não pertence a versão nenhuma: a base é do município, e
 * a saca é do Barter aberto hoje.
 */
export function toInsuranceRateJson(rate: InsuranceRate, lens: ValueLens = CURRENCY_LENS) {
  return {
    id: rate.id,
    city: rate.city,
    ...(lens.showsCurrency
      ? { valuePerHa: rate.valuePerHa }
      : { sacksPerHa: inSacks(rate.valuePerHa, lens.grainPrice) ?? 0 }),
    note: rate.note,
    updatedAt: rate.updatedAt,
  };
}

/* ── Barter: safra e versões ──────────────────────────────────────────── */

export function toSeasonJson(
  season: Season & { versions?: BarterVersion[] },
  viewer?: Pick<User, 'role'>,
) {
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
    // O VENCIMENTO DA CPR desta safra. Ele é da CULTURA, e não da cédula: todas
    // as CPRs da safra vencem no mesmo dia. `null` enquanto o admin não o
    // acertou — e aí nenhuma cédula da safra pode ser emitida.
    cprDueDate: season.cprDueDate,
    // O viewer atravessa: sem ele a lente cai no padrão fechado e a safra sairia
    // sem valor nenhum — inclusive para quem tem barterManage, que é o único
    // papel que chega a estas rotas.
    versions: season.versions?.map((version) => toBarterVersionJson(version, undefined, viewer)),
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
    // A PRODUTIVIDADE ESTIMADA vai para TODO MUNDO, inclusive para quem não vê
    // R$ — ela é sc/ha, e não moeda. É a outra metade da conversão que o preço
    // da saca começa, e é a única maneira de o consultor entender por que a
    // permuta dele pede a área que pede (ver `pledgeAreaHa` no detalhe).
    //
    // `0` é a versão anterior ao campo, e nela `POST /barters` recusa: a tela do
    // admin lê este zero para mostrar que o Barter está vigente e travado.
    estimatedYield: version.estimatedYield,
    // ESTE BARTER LEVA SEGURO? Vai para todo mundo, e não é valor: é uma regra
    // do lançamento, da mesma natureza de `closeOnGoal` e de `isOpen`.
    //
    // É ela que a tela do consultor lê para mostrar a linha do seguro na prévia
    // — e para avisar, antes de ele montar a permuta inteira, que a praça do
    // produtor ainda não tem taxa cadastrada. Ver `InsuranceRate`.
    insuranceRequired: version.insuranceRequired,
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
    // O MODO de encerramento vai para todo mundo, e não só para a retaguarda:
    // ele não é um valor, é uma regra de vigência — a mesma natureza de `isOpen`
    // e de `endsAt`, que o consultor já recebe. Saber que o Barter pode fechar ao
    // bater meta é o que explica a tela dele fechar no meio da tarde.
    closeOnGoal: version.closeOnGoal,
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
    // O ID DA LINHA. Ele existe no contrato porque o admin altera o valor de UM
    // item ao atender um pedido do consultor (`POST /change-request/prices`), e
    // o produto não serve de endereço: os itens de fora do Barter não têm
    // produto no catálogo, e são justamente os que mais mudam de valor.
    id: item.id,
    kind: item.kind,
    productId: item.productId,
    productName: item.productName,
    // O CÓDIGO congelado no registro. Ele acompanha o nome em toda tela e em
    // todo documento onde o item aparece: é por ele que o insumo é procurado no
    // depósito, conferido na retirada e batido contra a nota — e dois produtos
    // de nomes parecidos ("Glifosato 480 SL" e "Glifosato 480 WG") só se
    // distinguem por ele. Null nos itens anteriores ao campo.
    sku: item.productSku,
    unit: item.unit,
    quantity: item.quantity,
    // ESTE ITEM VEIO DE FORA DO BARTER — de um pedido que o admin atendeu, e
    // não da tabela de valores da versão (ver `barters/product-request.ts`).
    //
    // Vai para TODO MUNDO, inclusive para quem não vê R$: a marca não é sobre o
    // valor, é sobre a PROCEDÊNCIA. Quem confere a retirada no balcão precisa
    // saber que aquele item não está na lista da praça, e o consultor precisa
    // saber que ele está ali porque foi pedido — é dele o pedido.
    offBarter: item.offBarter,
    // ESTA LINHA É O SEGURO AGRÍCOLA, e não um insumo retirado.
    //
    // Vai para todo mundo pelo mesmo motivo de `offBarter`: é procedência, não
    // valor. Quem confere a retirada no balcão precisa saber que esta linha não
    // se separa em lugar nenhum (não há o que entregar), e o produtor precisa
    // ler no comprovante que parte das sacas dele paga a apólice, e não adubo.
    //
    // A conta fica legível na própria linha: `quantity` é a área cultivável
    // dele (ha) e `unitValue` é a taxa do município (ver `InsuranceRate`).
    insurance: item.insurance,
    // O VALOR DE TABELA, quando o admin escreveu outro por cima. Só para quem vê
    // R$, pelo mesmo motivo de `unitValue`: é dinheiro, e o consultor lê a
    // permuta em sacas. Null (ou ausente) é o caso normal — o item vale o que a
    // versão do Barter diz.
    ...(lens.showsCurrency ? { unitValue: item.unitValue, listValue: item.listValue } : {}),
  };
}

/**
 * UM PEDIDO DE FORA DO BARTER — o produto que o consultor pediu e o que o admin
 * respondeu (ver `barters/product-request.ts`).
 *
 * O VALOR sai pela lente, como tudo o mais: o admin lê "R$ 120,00 por litro"; o
 * consultor, que pediu o item, lê o que ele custa na moeda dele — sacas por
 * unidade. É o mesmo desenho de `toBarterVersionJson`, e existe pela mesma
 * razão: esconder R$ na tela deixaria o número viajando no JSON de quem não
 * pode lê-lo.
 *
 * `null` no valor enquanto o pedido não foi atendido — não há preço nenhum, e
 * um zero ali seria um item de graça.
 */
export function toBarterProductRequestJson(
  request: BarterProductRequest,
  lens: ValueLens = CURRENCY_LENS,
) {
  const value = request.unitValue;
  return {
    id: request.id,
    productName: request.productName,
    unit: request.unit,
    quantity: request.quantity,
    sku: request.sku,
    note: request.note,
    status: request.status,
    requestedBy: request.requestedBy,
    requestedAt: request.requestedAt,
    decidedBy: request.decidedBy,
    decidedAt: request.decidedAt,
    reply: request.reply,
    ...(lens.showsCurrency
      ? { unitValue: value }
      : { sacksPerUnit: value === null ? null : inSacks(value, lens.grainPrice) }),
  };
}

/**
 * Um passo da LINHA DO TEMPO da permuta.
 *
 * Sai com o autor já em texto, como a trilha de auditoria: quem lê precisa
 * entender o que houve mesmo que a conta envolvida não exista mais. E sai com a
 * transição inteira (`from` → `to`), não só o estado final — é o que permite ao
 * app desenhar "no gerente → no comitê" sem conhecer o desenho do fluxo.
 */
export function toBarterEventJson(event: BarterEvent) {
  return {
    id: event.id,
    action: event.action,
    fromStatus: event.fromStatus,
    toStatus: event.toStatus,
    actorId: event.actorId,
    actorName: event.actorName,
    actorRole: event.actorRole,
    // O rótulo do papel resolvido pelo SERVIDOR, pelo mesmo motivo de
    // `capabilities` em `toUserJson`: um papel novo aparece escrito certo nas
    // versões do app já instaladas.
    actorRoleLabel: ROLE_LABELS[event.actorRole as Role] ?? event.actorRole,
    note: event.note,
    at: event.at,
  };
}

/**
 * O ANDAMENTO da permuta: a esteira INTEIRA, com o que já aconteceu preenchido.
 *
 * É a linha do tempo e a checklist na mesma lista, e elas são a mesma lista de
 * propósito. `events` conta o que houve; sozinho, ele faz uma permuta parada no
 * comitê parecer terminada — mostra dois passos, e nada diz que faltam dois.
 * Aqui as quatro etapas aparecem sempre, e o evento entra em cada uma que já foi
 * cumprida: quem lê vê de uma vez onde a permuta está, por onde passou e quem
 * ainda precisa agir.
 *
 * Quem casa etapa e evento é o `action` — a etapa é a definição, o evento é o
 * fato. Etapa cumprida SEM evento é permuta anterior à linha do tempo: ela sai
 * marcada como cumprida e sem assinatura, que é a verdade, em vez de sumir da
 * lista ou de inventar um autor.
 */
function toBarterProgressJson(
  barter: Barter,
  events: BarterEvent[],
): ReturnType<typeof progressStepJson>[] {
  const byAction = new Map<string, BarterEvent>();
  // O primeiro evento de cada ato: um ato acontece uma vez só (a máquina de
  // estados não deixa repetir), e na dúvida vale o que veio antes.
  for (const event of events) {
    if (!byAction.has(event.action)) byAction.set(event.action, event);
  }

  return progressOf(barter).map((step) => progressStepJson(step, byAction.get(step.action)));
}

function progressStepJson(
  step: ReturnType<typeof progressOf>[number],
  event: BarterEvent | undefined,
) {
  return {
    action: step.action,
    state: step.state,
    label: step.label,
    // Quem é o dono da etapa, resolvido aqui pelo mesmo motivo de
    // `actorRoleLabel`: um papel novo aparece escrito certo no app já instalado.
    role: step.role,
    roleLabel: step.role ? (ROLE_LABELS[step.role] ?? step.role) : null,
    stateNote: step.stateNote,
    // A ASSINATURA da etapa cumprida, tirada do evento — quem, quando e o que
    // escreveu. Null enquanto ela não aconteceu.
    at: event?.at ?? null,
    // O estado que o ato ALCANÇOU. É por ele que a tela colore o passo, do mesmo
    // jeito que já colore a linha do tempo — e é o que distingue, no desenho, a
    // decisão que aprovou da que negou.
    toStatus: event?.toStatus ?? null,
    actorName: event?.actorName ?? null,
    actorRoleLabel: event ? (ROLE_LABELS[event.actorRole as Role] ?? event.actorRole) : null,
    note: event?.note ?? null,
    outcomeLabel: event ? outcomeLabelOf(event.action, event.toStatus) : null,
  };
}

/**
 * O INVESTIMENTO POR HECTARE — quantas sacas do grão esta permuta compromete
 * por hectare de área cultivável do produtor.
 *
 * É a régua que compara duas permutas de tamanhos diferentes: 12 sc/ha numa
 * fazenda de 300 ha e 12 sc/ha numa de 2.000 ha são o mesmo negócio em escalas
 * diferentes, e o total sozinho não diz isso. Em SACAS, e não em R$, porque é a
 * unidade em que a lavoura raciocina — "a soja paga o insumo com doze sacas do
 * que ela produz" — e porque é o número que sobrevive à cotação mudar.
 *
 * Ele vai para QUEM PODE COMPARAR (`barters.investmentPerHa`: admin, comitê e
 * faturista) e some para os outros — não por sigilo, mas porque uma régua sem
 * com quem comparar é ruído. Ver a capacidade em policy.ts.
 *
 * `null` — e não zero — quando não dá para dizer: permuta anterior ao campo de
 * área (`producerAreaHa` 0) ou resposta sem os itens (a listagem os traz; um
 * chamador futuro pode não trazer). Zero seria um investimento por hectare de
 * zero, que é uma afirmação, e falsa.
 */
function investmentPerHa(
  barter: Barter & { items?: BarterItem[] },
  viewer: Pick<User, 'role'> | undefined,
): { producerAreaHa: number; sacksPerHa: number | null } | Record<string, never> {
  if (!viewer || !can(viewer, CAPABILITY.bartersInvestmentPerHa)) return {};

  const sacks = barter.items
    ?.filter((item) => item.kind === 'grain')
    .reduce((total, item) => total + item.quantity, 0);

  return {
    producerAreaHa: barter.producerAreaHa,
    sacksPerHa:
      sacks === undefined || barter.producerAreaHa <= 0 ? null : sacks / barter.producerAreaHa,
  };
}

/**
 * O PENHOR desta permuta, do jeito que a tela precisa dele: a área exigida e as
 * duas taxas que a produziram.
 *
 * ELE NÃO CARREGA O QUE FOI PENHORADO, e essa ausência é escolha. A soma das
 * lavouras mora na CÉDULA, e a cédula é uma resposta à parte (`GET
 * /barters/:code/cpr`, ver `toCprJson`); trazê-la para cá obrigaria toda listagem
 * e todo detalhe de permuta a carregar as áreas e os proprietários de cada uma
 * para desenhar um número. O que o detalhe responde é "quanto esta permuta pede";
 * "quanto já foi dado" é pergunta do formulário que dá.
 *
 * `{}` — e não zeros — em dois casos, pelo mesmo motivo de `investmentPerHa`:
 * quando a resposta não trouxe os itens (a listagem não os carrega, e sem a linha
 * de grão não há sacas) e quando a permuta é anterior ao dimensionamento
 * (`pledgeYield` 0). Um `pledgeAreaHa: 0` no JSON seria o servidor afirmando que
 * esta permuta não exige garantia nenhuma, que é o oposto do que o silêncio
 * significa nos dois casos.
 */
function pledgeOf(
  barter: Barter & { items?: BarterItem[] },
):
  | { pledgeAreaHa: number; pledgeYield: number; pledgeMarginPercent: number }
  | Record<string, never> {
  if (!barter.items || barter.pledgeYield <= 0) return {};

  const sacks = barter.items.find((item) => item.kind === 'grain')?.quantity ?? 0;
  return {
    pledgeAreaHa: pledgeAreaFor(sacks, barter.pledgeYield, barter.pledgeMarginPercent),
    // AS DUAS TAXAS vão junto, e não só o resultado: "esta permuta pede 34 ha" é
    // um número que alguém vai contestar, e a resposta a "por quê?" são elas. Sem
    // as duas, a única maneira de conferir a conta é abrir o lançamento do Barter
    // — que o consultor não enxerga.
    pledgeYield: barter.pledgeYield,
    pledgeMarginPercent: barter.pledgeMarginPercent,
  };
}

/**
 * A COTAÇÃO DA SACA com que esta permuta foi fechada, lida do item de grão dela.
 *
 * É o que permite converter em sacas, para quem não vê R$, os valores que a
 * permuta carrega (hoje: o do pedido de fora do Barter). Sai daqui, e não da
 * versão vigente, pelo motivo de sempre — a permuta foi fechada naquela cotação,
 * e publicar a versão seguinte não reescreve o que já foi combinado.
 *
 * Zero quando não há item de grão (permutas anteriores a ele, ou uma resposta
 * sem os itens): a lente então não converte nada, e o campo some em vez de
 * afirmar um número.
 */
function grainPriceOf(barter: { items?: BarterItem[] }): number {
  return barter.items?.find((item) => item.kind === 'grain')?.unitValue ?? 0;
}

/**
 * UMA NOTA FISCAL do faturamento, com o anexo dela.
 *
 * O arquivo sai como METADADO — nome, tipo, tamanho, quem anexou —, e nunca com
 * o conteúdo: os bytes têm rota própria. `file` null é a nota herdada do campo
 * de texto que ficava dentro da cédula (ver a migration), e a tela a mostra como
 * pendente de anexo em vez de escondê-la.
 */
function toBarterInvoiceJson(invoice: BarterInvoice & { file?: BarterFileMeta | null }) {
  return {
    id: invoice.id,
    number: invoice.number,
    series: invoice.series,
    duplicateNumber: invoice.duplicateNumber,
    issuedAt: invoice.issuedAt,
    value: invoice.value,
    note: invoice.note,
    attachedBy: invoice.attachedBy,
    attachedAt: invoice.attachedAt,
    file: invoice.file ? toBarterFileJson(invoice.file) : null,
  };
}

/**
 * UMA PEÇA DA ANÁLISE DE CRÉDITO do comitê, com o anexo dela.
 *
 * Mesma forma da nota fiscal: o arquivo sai como METADADO — nome, tipo,
 * tamanho, quem anexou —, e os bytes têm rota própria. `kindLabel` vem resolvido
 * pelo mesmo motivo de `statusLabel`: o cliente não deveria precisar conhecer a
 * lista de tipos para escrever "Consulta ao Serasa" na tela.
 */
function toBarterCreditFileJson(credit: BarterCreditFile & { file?: BarterFileMeta | null }) {
  return {
    id: credit.id,
    kind: credit.kind,
    kindLabel: CREDIT_FILE_LABELS[credit.kind as CreditFileKind] ?? credit.kind,
    note: credit.note,
    attachedBy: credit.attachedBy,
    attachedAt: credit.attachedAt,
    file: credit.file ? toBarterFileJson(credit.file) : null,
  };
}

/** O anexo sem os bytes — a forma como ele aparece em toda resposta que não é download. */
function toBarterFileJson(file: BarterFileMeta) {
  return {
    id: file.id,
    fileName: file.fileName,
    contentType: file.contentType,
    size: file.size,
    uploadedBy: file.uploadedBy,
    uploadedAt: file.uploadedAt,
  };
}

/** O que um anexo carrega fora dos bytes. */
type BarterFileMeta = {
  id: number;
  fileName: string;
  contentType: string;
  size: number;
  uploadedBy: string;
  uploadedAt: Date;
};

export function toBarterJson(
  barter: Barter & {
    items?: BarterItem[];
    events?: BarterEvent[];
    productRequests?: BarterProductRequest[];
    invoices?: (BarterInvoice & { file?: BarterFileMeta | null })[];
    creditFiles?: (BarterCreditFile & { file?: BarterFileMeta | null })[];
  },
  viewer?: Pick<User, 'role'>,
) {
  const lens = lensFor(viewer, grainPriceOf(barter));
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
    // O PARECER DO CONSULTOR e o momento do encaminhamento. Os dois vazios
    // enquanto ela é rascunho — e é essa diferença que a tela dele lê para saber
    // se a permuta já saiu da mão dele.
    consultantNote: barter.consultantNote,
    consultantSentAt: barter.consultantSentAt,
    // A ÁREA congelada no registro e o INVESTIMENTO POR HECTARE que ela produz.
    // Ver `investmentPerHa`: o número só vai para quem pode compará-lo.
    ...investmentPerHa(barter, viewer),
    // O IMPOSTO DA ENTREGA: a forma de recolhimento escolhida no fechamento e a
    // alíquota que ela produziu, como ficaram no registro.
    //
    // A alíquota vai para todo mundo, inclusive o consultor: é um PERCENTUAL, e
    // não um valor em R$ — quem não vê moeda aplica os mesmos % sobre as sacas
    // e chega ao imposto na unidade em que enxerga a permuta. Ver `ValueLens`.
    taxRegime: barter.taxRegime,
    taxRate: barter.taxRate,
    // O PENHOR — quanta área de lavoura esta permuta precisa dar em garantia.
    //
    // Vai para TODO MUNDO, inclusive o consultor, pelo mesmo motivo de `taxRate`:
    // é hectare e é percentual, não é R$. E vai no DETALHE DA PERMUTA, e não só
    // na mesa da cédula, porque este é o primeiro lugar em que o consultor pode
    // lê-lo — logo depois de registrar, com o produtor ainda por perto. Descobrir
    // "esta permuta pede 34 ha" na tela da cédula já é tarde para renegociar o
    // tamanho dela; descobrir na emissão é tarde para tudo.
    //
    // `undefined` quando os itens não vieram (a listagem não os carrega): sem a
    // linha de grão não há sacas, e um `0` ali seria a listagem afirmando que a
    // permuta não exige penhor nenhum. Mesma regra de presença de `steps`.
    ...pledgeOf(barter),
    // A QUEM esta permuta foi enviada — o gerente do consultor no momento do
    // registro — e o parecer dele. `managerId`/`managerName` vêm preenchidos
    // desde a criação (é o destinatário); `managerNote` e `managerReviewedAt`
    // só quando o parecer é escrito, e é o app que lê essa diferença para saber
    // se a etapa terminou.
    managerId: barter.managerId,
    managerName: barter.managerName,
    managerNote: barter.managerNote,
    managerReviewedAt: barter.managerReviewedAt,
    // A DECISÃO DO COMITÊ. `reviewNote` se chamava `adminNote` até o admin deixar
    // de decidir permuta — os dois lados deste repositório sobem juntos, e um
    // campo que mente sobre quem decidiu é pior do que um campo que sumiu.
    reviewNote: barter.reviewNote,
    reviewedBy: barter.reviewedBy,
    reviewedAt: barter.reviewedAt,
    // AS EXIGÊNCIAS DO COMITÊ — avalista, garantia real, seguro.
    //
    // Vão para TODO MUNDO que enxerga a permuta, e não só para quem decidiu:
    // elas são trabalho para OUTRA pessoa. O consultor precisa levá-las ao
    // produtor, o faturista precisa saber que a retirada foi condicionada, e o
    // emissor precisa saber que aquele título espera um avalista antes de ser
    // assinado. Enquanto isso viveu dentro do texto da decisão, a única maneira
    // de descobrir era ler o parágrafo até o fim.
    //
    // Elas não substituem `reviewNote`: as caixas dizem O QUÊ, e só o texto diz
    // QUAL — qual matrícula, qual valor segurado, quem se espera como avalista.
    requiresGuarantor: barter.requiresGuarantor,
    requiresCollateral: barter.requiresCollateral,
    requiresInsurance: barter.requiresInsurance,
    // O SEGURO AGRÍCOLA desta permuta: a praça que o precificou e a taxa
    // congelada no registro. `insuranceCity` vazio é permuta sem seguro — ou
    // porque o Barter dela não leva, ou porque ela é anterior à regra.
    //
    // A TAXA sai pela lente, como todo R$: quem não vê moeda lê o seguro pela
    // própria linha da permuta, em que a quantidade é a área e o total já está
    // dentro das sacas do grão.
    insuranceCity: barter.insuranceCity,
    ...(lens.showsCurrency ? { insuranceRatePerHa: barter.insuranceRatePerHa } : {}),
    // AS PEÇAS DA ANÁLISE DE CRÉDITO — a consulta ao Serasa, o endividamento do
    // produtor dentro da cooperativa.
    //
    // Só para quem pode abri-las (`barters.creditRead`: comitê e admin), e o
    // campo SOME para os outros em vez de vir vazio: uma lista vazia diria "não
    // há dossiê", e o consultor concluiria que o comitê decidiu sem apurar
    // nada. Ver `BarterCreditFile`.
    ...(viewer && can(viewer, CAPABILITY.bartersCreditRead)
      ? { creditFiles: barter.creditFiles?.map(toBarterCreditFileJson) }
      : {}),
    // O FATURAMENTO. Null enquanto ela não foi faturada.
    invoicedBy: barter.invoicedBy,
    invoicedAt: barter.invoicedAt,
    invoiceNote: barter.invoiceNote,
    // AS NOTAS FISCAIS anexadas, com o arquivo de cada uma (sem os bytes: o
    // conteúdo se baixa em `GET /barters/:code/invoices/:id/file`).
    //
    // Vão na LISTAGEM também, como os pedidos de produto, porque são ESTADO: a
    // fila do faturista precisa distinguir a permuta aprovada sem nota nenhuma
    // da que já tem as três dela. `undefined` quando a resposta não as carrega —
    // o app distingue "não veio" de "não tem".
    invoices: barter.invoices?.map(toBarterInvoiceJson),
    // A EMISSÃO DA CÉDULA — os três atos do emissor, cada um null até acontecer.
    // É essa diferença que a tela lê para saber em que pé a CPR está, do mesmo
    // jeito que `managerNote` diz se o parecer saiu.
    cprEmittedBy: barter.cprEmittedBy,
    cprEmittedAt: barter.cprEmittedAt,
    cprEmissionNote: barter.cprEmissionNote,
    cprSignedAt: barter.cprSignedAt,
    cprSignatureNote: barter.cprSignatureNote,
    cprRegisteredAt: barter.cprRegisteredAt,
    cprRegistryNumber: barter.cprRegistryNumber,
    cprRegistryPlace: barter.cprRegistryPlace,
    // O PEDIDO DE ALTERAÇÃO em aberto (ou a recusa do último), com o texto dos
    // dois lados. Ver `barters/change-request.ts`.
    //
    // Vai para TODO MUNDO que enxerga a permuta, e não só para o consultor e o
    // admin: quem tem a permuta na mesa precisa saber que o consultor pediu para
    // refazê-la — dar um parecer técnico sobre insumos que estão prestes a mudar
    // é trabalho jogado fora, e hoje a única maneira de descobrir isso era o
    // telefonema que este pedido existe para substituir.
    changeRequestStatus: barter.changeRequestStatus,
    changeRequestNote: barter.changeRequestNote,
    changeRequestBy: barter.changeRequestBy,
    changeRequestAt: barter.changeRequestAt,
    changeRequestFrom: barter.changeRequestFrom,
    changeRequestReply: barter.changeRequestReply,
    // OS PEDIDOS DE FORA DO BARTER desta permuta — os que esperam o admin, os
    // que ele atendeu e os que recusou (ver `barters/product-request.ts`).
    //
    // Vão na LISTAGEM também, e não só no detalhe como a linha do tempo: o
    // pedido em aberto é ESTADO ("esta permuta espera alguém"), e é isso que a
    // fila do admin lista. `undefined` quando a resposta não os carrega — o app
    // distingue "não veio" de "não tem", que seriam a mesma coisa com `[]`.
    productRequests: barter.productRequests?.map((request) =>
      toBarterProductRequestJson(request, lens),
    ),
    // COM QUEM ela está parada e QUAL é o próximo ato, resolvidos pela máquina de
    // estados do servidor. Vão no JSON para o app não ter uma segunda cópia do
    // fluxo em Dart: uma etapa nova aparece nas telas já instaladas em vez de
    // exigir versão nova. Null nos dois fins de linha (negada, faturada).
    waitingFor: BARTER_HOLDER[barter.status as BarterStatus] ?? null,
    nextAction: nextActionOf(barter.status) ?? null,
    statusLabel: BARTER_STATUS_LABELS[barter.status as BarterStatus] ?? barter.status,
    createdAt: barter.createdAt,
    items: barter.items?.map((item) => toBarterItemJson(item, lens)),
    // A LINHA DO TEMPO só vem no detalhe (o service a inclui lá). `undefined` na
    // listagem some do JSON, e o app distingue "não veio nesta resposta" de
    // "esta permuta não tem eventos" — que seriam a mesma coisa com `[]`.
    events: barter.events?.map(toBarterEventJson),
    // O ANDAMENTO acompanha a linha do tempo: as duas respondem à mesma pergunta
    // e vão pela mesma porta (o detalhe), então a mesma regra de presença vale
    // para as duas — a listagem mostra estado, não trajetória.
    //
    // `events` continua no contrato ao lado dele, e não foi absorvido: ele é o
    // fato gravado, na ordem em que aconteceu, e é o que o comprovante e a
    // auditoria do documento leem. `steps` é a LEITURA dele contra a esteira.
    steps: barter.events ? toBarterProgressJson(barter, barter.events) : undefined,
  };
}

/**
 * A CREDORA — o cadastro que dá o timbre aos documentos emitidos.
 *
 * `forum` sai RESOLVIDO (o eleito, ou a comarca da sede) pelo mesmo motivo de
 * `statusLabel`: o cliente não deveria precisar conhecer a regra do vazio para
 * saber qual foro vai sair impresso. O campo cru continua no formulário, que é
 * onde a distinção importa.
 */
export function toCreditorJson(creditor: Creditor) {
  return {
    name: creditor.name,
    cnpj: creditor.cnpj,
    address: creditor.address,
    addressNumber: creditor.addressNumber,
    city: creditor.city,
    // O que foi ESCOLHIDO (vazio = "a comarca da sede") e o que VALE.
    forum: creditor.forum,
    effectiveForum: forumOf(creditor),
    // A MARGEM DE SEGURANÇA DO PENHOR. Não entra em `gaps`: zero é uma escolha
    // ("não exijo folga"), e não um cadastro pela metade.
    pledgeMarginPercent: creditor.pledgeMarginPercent,
    updatedBy: creditor.updatedBy,
    updatedAt: creditor.updatedAt,
    gaps: creditorGaps(creditor),
  };
}

/**
 * A MESA DA CÉDULA — o contrato da tela de quem preenche e de quem emite.
 *
 * Ela sai em quatro blocos, e a divisão é a informação principal desta resposta:
 * quem preenche o quê. `known` é o que a permuta já respondeu e ninguém digita;
 * `creditor` é configuração da instalação; `cpr` é o rascunho do consultor; e
 * `gaps` é o que falta para o documento poder ser gerado.
 *
 * AS LISTAS DE PENDÊNCIA SAEM SEPARADAS porque quem resolve cada uma é outra
 * pessoa: `consultantGaps` é do consultor, ali mesmo; `creditorGaps` é de quem
 * administra o servidor; e `gaps` é a soma de tudo, que é o que o emissor lê
 * antes de emitir. Uma lista só mandaria o consultor procurar um campo de CNPJ
 * que não existe no formulário dele.
 *
 * `suggestion` vem vazio quando já existe rascunho — ver `cprFor`.
 */
export function toCprJson(desk: {
  cpr:
    | (BarterCpr & {
        areas: (CprArea & { owners: CprAreaOwner[] })[];
        guarantors: CprGuarantor[];
        scrFile?: BarterFileMeta | null;
        signedFile?: BarterFileMeta | null;
        registryFile?: BarterFileMeta | null;
      })
    | null;
  known: unknown;
  creditor: Creditor;
  gaps: string[];
  consultantGaps: string[];
  pledge: unknown;
  pledgeWarnings: string[];
  suggestion: unknown;
}) {
  const creditor = toCreditorJson(desk.creditor);
  return {
    cpr: desk.cpr ? toCprDraftJson(desk.cpr) : null,
    known: desk.known,
    creditor,
    creditorGaps: creditor.gaps,
    gaps: desk.gaps,
    // O QUE TRAVA O ENCAMINHAMENTO, separado do resto pelo mesmo motivo de
    // `creditorGaps`: é o recorte de um posto só. A tela do detalhe avisa o
    // consultor com esta lista antes de ele tentar encaminhar — mostrar `gaps`
    // ali mandaria ele procurar o número da CPR, que é do emissor, e a nota
    // fiscal, que é do faturista, num formulário onde nenhum dos dois existe.
    consultantGaps: desk.consultantGaps,
    // O PLACAR DO PENHOR — exigido, penhorado, faltando. Ele acompanha a lista de
    // pendências sem se confundir com ela: a lacuna some quando a área fecha, e
    // este bloco continua dizendo por quanto ela fechou, que é o que a tela
    // mostra no cabeçalho das lavouras enquanto alguém acrescenta matrícula.
    pledge: desk.pledge,
    // OS AVISOS, fora de `gaps` e fora de `consultantGaps`: eles não travam ato
    // nenhum (ver `pledgeWarningsFor`), e o dia em que uma suspeita entrar na
    // lista que o `forward` lê é o dia em que uma permuta boa é recusada por ela.
    pledgeWarnings: desk.pledgeWarnings,
    // `complete` é derivado de `gaps` e vai junto porque é a pergunta que a
    // LISTA faz (um selo "CPR pronta" no cartão), enquanto a lista é a pergunta
    // que o FORMULÁRIO faz. Calculá-lo no cliente seria a mesma regra escrita
    // duas vezes para dois lugares da mesma tela.
    complete: desk.gaps.length === 0 && creditor.gaps.length === 0,
    suggestion: desk.suggestion,
  };
}

/** O rascunho gravado, com as lavouras na ordem em que saem no documento. */
function toCprDraftJson(
  cpr: BarterCpr & {
    areas: (CprArea & { owners: CprAreaOwner[] })[];
    guarantors: CprGuarantor[];
    scrFile?: BarterFileMeta | null;
    signedFile?: BarterFileMeta | null;
    registryFile?: BarterFileMeta | null;
  },
) {
  return {
    number: cpr.number,
    issuedAt: cpr.issuedAt,
    dueDate: cpr.dueDate,
    emitterNationality: cpr.emitterNationality,
    emitterMaritalStatus: cpr.emitterMaritalStatus,
    emitterProfession: cpr.emitterProfession,
    emitterRg: cpr.emitterRg,
    emitterAddress: cpr.emitterAddress,
    emitterAddressNumber: cpr.emitterAddressNumber,
    emitterCity: cpr.emitterCity,
    emitterCoopId: cpr.emitterCoopId,
    // O que a PROPOSTA pede e a cédula não imprime — coletado, não impresso.
    emitterCnh: cpr.emitterCnh,
    emitterFatherName: cpr.emitterFatherName,
    emitterMotherName: cpr.emitterMotherName,
    emitterEmail: cpr.emitterEmail,
    // O local da entrega SAI (cláusula V, "d"), e por isso é cobrado em `gaps`.
    deliveryPlace: cpr.deliveryPlace,
    mortgages: cpr.mortgages,
    spouseName: cpr.spouseName,
    spouseNationality: cpr.spouseNationality,
    spouseProfession: cpr.spouseProfession,
    spouseDocument: cpr.spouseDocument,
    spouseRg: cpr.spouseRg,
    sackWeightKg: cpr.sackWeightKg,
    cultivar: cpr.cultivar,
    maxMoisture: cpr.maxMoisture,
    maxImpurities: cpr.maxImpurities,
    oilContent: cpr.oilContent,
    // O SCR do produtor: o anexo (sem os bytes) e a data da consulta. O número
    // da nota e o da duplicata NÃO estão mais aqui — eles são do faturamento, e
    // saem em `known.invoices`.
    scrFile: cpr.scrFile ? toBarterFileJson(cpr.scrFile) : null,
    scrConsultedAt: cpr.scrConsultedAt,
    // OS DOIS DOCUMENTOS QUE VOLTAM DE FORA: a cédula assinada e a via carimbada
    // pelo registro. Saem aqui, ao lado do SCR, porque são anexos da CÉDULA —
    // as DATAS dos dois atos ficam na permuta (`cprSignedAt`,
    // `cprRegisteredAt`), que é onde o andamento mora.
    signedFile: cpr.signedFile ? toBarterFileJson(cpr.signedFile) : null,
    registryFile: cpr.registryFile ? toBarterFileJson(cpr.registryFile) : null,
    insurancePolicy: cpr.insurancePolicy,
    // Quem mexeu por último e quando. É o par que uma cédula editável precisa
    // mostrar: dois faturistas dividem a fila, e "isto aqui está como eu deixei?"
    // é a primeira pergunta de quem reabre um rascunho.
    filledBy: cpr.filledBy,
    updatedAt: cpr.updatedAt,
    areas: cpr.areas.map((area) => ({
      locality: area.locality,
      city: area.city,
      areaHa: area.areaHa,
      withinLargerArea: area.withinLargerArea,
      registryNumber: area.registryNumber,
      registryBook: area.registryBook,
      registryDistrict: area.registryDistrict,
      owners: area.owners.map((owner) => ({ name: owner.name, document: owner.document })),
    })),
    // Os AVALISTAS vão inteiros. Eles não saem no documento por enquanto (o
    // modelo não tem cláusula de aval), mas a tela os edita, e o que ela edita
    // ela precisa receber de volta.
    guarantors: cpr.guarantors.map((guarantor) => ({
      name: guarantor.name,
      document: guarantor.document,
      rg: guarantor.rg,
      cnh: guarantor.cnh,
      nationality: guarantor.nationality,
      profession: guarantor.profession,
      maritalStatus: guarantor.maritalStatus,
      fatherName: guarantor.fatherName,
      motherName: guarantor.motherName,
      email: guarantor.email,
      address: guarantor.address,
      addressNumber: guarantor.addressNumber,
      city: guarantor.city,
      spouseName: guarantor.spouseName,
      spouseDocument: guarantor.spouseDocument,
      spouseRg: guarantor.spouseRg,
      spouseNationality: guarantor.spouseNationality,
      spouseProfession: guarantor.spouseProfession,
    })),
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
