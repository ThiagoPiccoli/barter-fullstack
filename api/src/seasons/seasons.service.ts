import { Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import type { BarterVersion, Prisma, Product, Season, User, VersionPrice } from '@prisma/client';
import { AUDIT_ACTION, AuditService } from '../audit/audit.service';
import { PrismaService } from '../prisma/prisma.service';
import { normalizeName, slugify } from './product-name';
import { letterFor, seasonCode, versionCode } from './season-code';
import { goalsOf, isOpenAt, realizedFrom, type Goal, type Realized } from './version-progress';
import { parseSheet, readWorkbook, type ImportRow } from './version-import';
import {
  ImportVersionDto,
  OpenSeasonDto,
  PublishVersionDto,
  UpdateVersionPriceDto,
  VersionLimitsDto,
} from './dto/season.dto';

export type SeasonWithVersions = Season & { versions: BarterVersion[] };
export type VersionWithPrices = BarterVersion & { season: Season; prices: VersionPrice[] };
export type VersionProgress = { realized: Realized; goals: Goal[] };

/**
 * PRAZO da transação que publica uma versão — explícito porque o padrão do
 * Prisma (5 s) não era um prazo escolhido, era um prazo herdado.
 *
 * Uma planilha de 20.000 linhas estourava esses 5 s no meio da gravação e o
 * admin recebia 500 "Erro inesperado no servidor" (P2028), depois de os
 * produtos já terem sido criados fora da transação. As duas metades disso estão
 * corrigidas — a escrita virou um punhado de comandos em lote, e a criação dos
 * produtos entrou na MESMA transação —, mas o prazo continua explícito: ele é a
 * diferença entre "demorou" e "não dá para saber o que aconteceu".
 *
 * Generoso de propósito. Quem publica é o admin, uma vez por lançamento,
 * olhando a barra de progresso; o custo de esperar é dele, e é menor do que o
 * de uma publicação pela metade. `maxWait` é o tempo de pegar conexão no pool,
 * outra pergunta e outro número.
 */
const PUBLISH_TIMEOUT_MS = 60_000;
const PUBLISH_MAX_WAIT_MS = 10_000;

/** Uma linha da tabela já resolvida contra o catálogo. */
export interface ResolvedPrice {
  product: Product;
  price: number;
  /** Unidade desta versão, quando a planilha traz uma diferente do cadastro. */
  unit?: string;
}

/**
 * O LANÇAMENTO do Barter: safra, versões e a tabela de valores de cada uma.
 *
 * A regra que organiza o arquivo inteiro: **existe no máximo uma safra aberta e,
 * dentro dela, no máximo uma versão vigente**. É isso que faz a pergunta "por
 * quanto se permuta agora?" ter uma resposta só — o consultor não escolhe grão
 * nem tabela, ele registra a permuta e o servidor sabe em qual gestão ela cai.
 *
 * Publicar a versão seguinte encerra a anterior NA MESMA TRANSAÇÃO. Se as duas
 * ficassem ativas por um instante, uma permuta registrada nesse intervalo
 * poderia nascer na tabela errada — e permuta é registro histórico, não dá para
 * consertar depois sem reescrever o que foi acordado.
 */
@Injectable()
export class SeasonsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  /* ── Safra ─────────────────────────────────────────────────────────── */

  /** Todas as safras, da mais recente para a mais antiga, com suas versões. */
  async listSeasons(): Promise<SeasonWithVersions[]> {
    return this.prisma.season.findMany({
      include: { versions: { orderBy: { number: 'desc' } } },
      orderBy: [{ year: 'desc' }, { id: 'desc' }],
    });
  }

  /** A safra aberta (ou null). É a única que aceita versões novas. */
  async openSeason(): Promise<SeasonWithVersions | null> {
    return this.prisma.season.findFirst({
      where: { status: 'open' },
      include: { versions: { orderBy: { number: 'desc' } } },
    });
  }

  async findSeason(code: string): Promise<SeasonWithVersions> {
    const season = await this.prisma.season.findUnique({
      where: { code },
      include: { versions: { orderBy: { number: 'desc' } } },
    });
    if (!season) throw new NotFoundException('Registro não encontrado.');
    return season;
  }

  /**
   * Abre a safra sobre um grão. Uma de cada vez: enquanto houver safra aberta,
   * a próxima não entra — do contrário voltaria a existir a pergunta "em qual
   * delas esta permuta caiu?", que é justamente o que este desenho elimina.
   */
  async open(admin: User, dto: OpenSeasonDto): Promise<SeasonWithVersions> {
    const running = await this.openSeason();
    if (running) {
      throw new UnprocessableEntityException(
        `A safra ${running.name} ainda está aberta. Encerre-a antes de abrir outra.`,
      );
    }

    const grain = await this.prisma.product.findUnique({ where: { id: dto.grainId } });
    if (!grain || grain.type !== 'grain') {
      throw new UnprocessableEntityException('Escolha um grão válido para a safra');
    }

    const code = seasonCode(dto.letter ?? letterFor(grain.name), dto.year);
    if (await this.prisma.season.findUnique({ where: { code } })) {
      throw new UnprocessableEntityException(
        `Já existe a safra ${code}. Use outra letra para diferenciá-la.`,
      );
    }

    const season = await this.prisma.season.create({
      data: {
        code,
        name: dto.name?.trim() || `${grain.name} ${dto.year}`,
        year: dto.year,
        grainId: grain.id,
        grainName: grain.name,
        grainUnit: grain.unit,
        status: 'open',
      },
      include: { versions: true },
    });

    await this.audit.record({
      actor: admin,
      action: AUDIT_ACTION.seasonOpened,
      targetType: 'season',
      targetId: season.id,
      targetLabel: season.code,
      detail: `${season.name} — pagamento em ${season.grainName}`,
    });
    return season;
  }

  /** Encerra a safra e, junto, a versão que estiver vigente nela. */
  async close(admin: User, code: string): Promise<SeasonWithVersions> {
    const season = await this.findSeason(code);
    if (season.status !== 'open') {
      throw new UnprocessableEntityException('Esta safra já foi encerrada');
    }

    const now = new Date();
    await this.prisma.$transaction([
      this.prisma.barterVersion.updateMany({
        where: { seasonId: season.id, status: 'active' },
        data: { status: 'closed', closedAt: now, closedBy: admin.fullName, closedById: admin.id },
      }),
      this.prisma.season.update({
        where: { id: season.id },
        data: { status: 'closed', closedAt: now },
      }),
    ]);

    await this.audit.record({
      actor: admin,
      action: AUDIT_ACTION.seasonClosed,
      targetType: 'season',
      targetId: season.id,
      targetLabel: season.code,
      detail: season.name,
    });
    return this.findSeason(code);
  }

  /* ── Versão ────────────────────────────────────────────────────────── */

  /**
   * A versão vigente: a ativa da safra aberta. Devolve null quando não há
   * Barter lançado — o app usa isso para mostrar "Barter fechado" em vez de
   * uma tela de permuta que o servidor recusaria no envio.
   */
  async currentVersion(): Promise<VersionWithPrices | null> {
    const season = await this.openSeason();
    if (!season) return null;
    return this.prisma.barterVersion.findFirst({
      where: { seasonId: season.id, status: 'active' },
      include: { season: true, prices: { orderBy: { productName: 'asc' } } },
    });
  }

  /**
   * A versão que pode receber permuta AGORA, ou o erro que explica por quê não.
   * É o portão que o registro de permuta atravessa (barters.service.ts).
   */
  async requireOpenVersion(now = new Date()): Promise<VersionWithPrices> {
    const version = await this.currentVersion();
    if (!version) {
      throw new UnprocessableEntityException(
        'Não há Barter aberto no momento. Aguarde o próximo lançamento.',
      );
    }
    if (!isOpenAt(version, now)) {
      throw new UnprocessableEntityException(
        `O Barter ${version.code} está fechado para novos registros.`,
      );
    }
    return version;
  }

  async findVersion(code: string): Promise<VersionWithPrices> {
    const version = await this.prisma.barterVersion.findUnique({
      where: { code },
      include: { season: true, prices: { orderBy: { productName: 'asc' } } },
    });
    if (!version) throw new NotFoundException('Registro não encontrado.');
    return version;
  }

  /** Metas × realizado das permutas aprovadas da versão. */
  async progressOf(version: BarterVersion): Promise<VersionProgress> {
    const barters = await this.prisma.barter.findMany({
      where: { versionId: version.id },
      select: {
        status: true,
        items: { select: { kind: true, quantity: true, unitValue: true } },
      },
    });
    const realized = realizedFrom(barters);
    return { realized, goals: goalsOf(version, realized) };
  }

  /**
   * Publica a próxima versão da safra: fecha a anterior, grava a tabela nova e
   * acrescenta o ponto de cada produto na linha do tempo de preços.
   *
   * O `Product.currentPrice` continua sendo escrito porque virou o "último
   * valor publicado" — é dele que vivem o relatório do produto e o gráfico.
   * Quem precifica uma permuta, porém, é a tabela desta versão: o campo do
   * catálogo é memória, não autoridade.
   */
  async publish(
    admin: User,
    seasonCodeValue: string,
    dto: PublishVersionDto,
  ): Promise<VersionWithPrices> {
    const season = await this.findSeason(seasonCodeValue);
    this.assertPublishable(season, dto);
    const prices = await this.resolvePrices(dto.prices);
    return this.publishResolved(admin, season, prices, dto.grainPrice, dto, null);
  }

  /**
   * Publica a próxima versão a partir da PLANILHA — o caminho do admin.
   *
   * O arquivo é a tabela: o que está nele é permutável na versão nova, o que
   * não está deixa de ser. `carryOver` existe para o arquivo que traz só o que
   * mudou: ligado, os insumos ausentes seguem com o valor da versão anterior.
   */
  async import(
    admin: User,
    seasonCodeValue: string,
    file: { originalname: string; buffer: Buffer },
    dto: ImportVersionDto,
  ): Promise<VersionWithPrices> {
    const season = await this.findSeason(seasonCodeValue);

    // ANTES de tocar no catálogo. O casamento das linhas com o cadastro CRIA
    // produto e pasta (é o que torna a carga em massa útil), e isso acontece
    // fora da transação que publica a versão. Enquanto estas conferências
    // moravam só lá dentro, uma planilha boa recusada por safra encerrada ou
    // por data de encerramento no passado devolvia 422 — e deixava para trás os
    // insumos e as pastas que tinha acabado de cadastrar.
    this.assertPublishable(season, dto);

    let matrix: string[][];
    try {
      matrix = await readWorkbook(file.buffer);
    } catch (error) {
      throw new UnprocessableEntityException(
        error instanceof Error ? error.message : 'Não consegui ler o arquivo.',
      );
    }

    const { rows, errors } = parseSheet(matrix);
    if (errors.length > 0) {
      // Só as primeiras: a mensagem vai inteira para uma SnackBar do app, e
      // uma lista de quarenta linhas não seria lida por ninguém.
      const shown = errors.slice(0, 3).join(' ');
      const rest = errors.length > 3 ? ` (+${errors.length - 3} problema(s))` : '';
      throw new UnprocessableEntityException(`${shown}${rest}`);
    }

    /*
     * UMA transação para casar o arquivo com o catálogo E publicar a versão.
     *
     * Antes eram duas coisas separadas, e a costura entre elas é que era o
     * problema: `resolveImported` CRIA produto e pasta, isso acontecia fora de
     * qualquer transação, e a publicação vinha depois. Falhando a publicação —
     * por prazo estourado, por preço repetido, pelo que fosse —, os produtos
     * recém-criados ficavam no catálogo e nenhuma versão saía. O admin via
     * "Erro inesperado no servidor" e o cadastro dele tinha mudado assim mesmo,
     * sem nada dizendo o quê.
     *
     * Junto, o arquivo passa a ser tudo ou nada: ou existe a versão nova com os
     * produtos que ela precisou criar, ou o banco está como estava.
     */
    const created = await this.prisma.$transaction(
      async (tx) => {
        const prices = await this.resolveImported(tx, rows);

        if (/^true$/i.test(dto.carryOver ?? '')) {
          await this.carryOverInto(tx, season, prices);
        }

        return this.writeVersion(tx, admin, season, prices, dto.grainPrice, dto, file.originalname);
      },
      { timeout: PUBLISH_TIMEOUT_MS, maxWait: PUBLISH_MAX_WAIT_MS },
    );

    await this.recordPublication(admin, created, dto.grainPrice, file.originalname);
    return created;
  }

  /**
   * Os insumos da versão anterior que o arquivo NÃO trouxe, mantidos com o
   * valor que tinham. É o `carryOver`: o fornecedor manda só o que mudou.
   */
  private async carryOverInto(
    tx: Prisma.TransactionClient,
    season: Season,
    prices: ResolvedPrice[],
  ): Promise<void> {
    const previous = await tx.barterVersion.findFirst({
      where: { seasonId: season.id },
      orderBy: { number: 'desc' },
      include: { prices: true },
    });
    const chosen = new Set(prices.map((row) => row.product.id));
    const kept = (previous?.prices ?? []).filter(
      (row) => row.productId !== null && !chosen.has(row.productId),
    );
    if (kept.length === 0) return;

    const products = await tx.product.findMany({
      where: { id: { in: kept.map((row) => row.productId!) } },
    });
    const byId = new Map(products.map((product) => [product.id, product]));
    for (const row of kept) {
      const product = byId.get(row.productId!);
      if (product) {
        prices.push({ product, price: row.price, unit: row.unit });
      }
    }
  }

  /**
   * As condições que não dependem da tabela: a safra aceita uma versão nova, e
   * a vigência pedida faz sentido. Ficam separadas porque são conferíveis ANTES
   * de resolver as linhas contra o catálogo — e a importação precisa disso, já
   * que resolver cria produto e pasta.
   *
   * Continua sendo chamada de dentro do `publishResolved`: é lá que está o
   * portão final, e o caminho do corpo JSON não passa por outro lugar. Chamar
   * duas vezes na importação é barato e mantém a regra num arquivo só.
   */
  private assertPublishable(season: Season, limits: Pick<VersionLimitsDto, 'endsAt'>): void {
    if (season.status !== 'open') {
      throw new UnprocessableEntityException(
        'Esta safra está encerrada; abra uma nova safra para lançar um Barter.',
      );
    }
    if (limits.endsAt && new Date(limits.endsAt).getTime() <= Date.now()) {
      throw new UnprocessableEntityException('A data de encerramento precisa ser no futuro');
    }
  }

  /**
   * O caminho comum das duas formas de publicar (corpo JSON e planilha): a
   * transação que troca a gestão. Recebe as linhas JÁ resolvidas contra o
   * catálogo para que a importação possa criar produtos antes de chegar aqui.
   */
  async publishResolved(
    admin: User,
    season: Season,
    prices: ResolvedPrice[],
    grainPrice: number,
    limits: VersionLimitsDto,
    sourceFile: string | null,
  ): Promise<VersionWithPrices> {
    const created = await this.prisma.$transaction(
      (tx) => this.writeVersion(tx, admin, season, prices, grainPrice, limits, sourceFile),
      { timeout: PUBLISH_TIMEOUT_MS, maxWait: PUBLISH_MAX_WAIT_MS },
    );
    await this.recordPublication(admin, created, grainPrice, sourceFile);
    return created;
  }

  /**
   * A GRAVAÇÃO da versão, dentro de uma transação que o chamador abriu.
   *
   * Recebe `tx` em vez de abrir a própria porque a importação precisa que a
   * criação dos produtos e a publicação caibam na MESMA transação — ver o
   * comentário em `import`.
   *
   * Tudo aqui é em LOTE, e isso é o ponto do arquivo. A versão anterior gravava
   * a linha do tempo com um `tx.product.update` POR PRODUTO, em série: uma
   * tabela de 20.000 itens virava 20.000 idas e voltas ao banco dentro de uma
   * transação, o que estourava o prazo dela (P2028 aos 5 s) e devolvia 500 ao
   * admin. O trabalho é o mesmo; o número de comandos é que não podia ser
   * proporcional ao tamanho da tabela. Agora são cinco, para qualquer tamanho.
   */
  private async writeVersion(
    tx: Prisma.TransactionClient,
    admin: User,
    season: Season,
    prices: ResolvedPrice[],
    grainPrice: number,
    limits: VersionLimitsDto,
    sourceFile: string | null,
  ): Promise<VersionWithPrices> {
    this.assertPublishable(season, limits);
    if (prices.length === 0) {
      throw new UnprocessableEntityException('A tabela de valores está vazia');
    }

    const endsAt = limits.endsAt ? new Date(limits.endsAt) : null;
    const now = new Date();

    const previous = await tx.barterVersion.findFirst({
      where: { seasonId: season.id },
      orderBy: { number: 'desc' },
    });
    const number = (previous?.number ?? 0) + 1;
    const code = versionCode(season.code, number);

    // Uma vigente só: a anterior fecha no mesmo instante em que a nova nasce.
    await tx.barterVersion.updateMany({
      where: { seasonId: season.id, status: 'active' },
      data: { status: 'closed', closedAt: now, closedBy: admin.fullName, closedById: admin.id },
    });

    const version = await tx.barterVersion.create({
      data: {
        seasonId: season.id,
        number,
        code,
        status: 'active',
        grainPrice,
        startsAt: now,
        endsAt,
        targetSales: limits.targetSales ?? null,
        targetSacks: limits.targetSacks ?? null,
        targetBarters: limits.targetBarters ?? null,
        sourceFile,
        note: limits.note?.trim() || null,
      },
    });

    await tx.versionPrice.createMany({
      data: prices.map((row) => ({
        versionId: version.id,
        productId: row.product.id,
        productName: row.product.name,
        unit: row.unit ?? row.product.unit,
        price: row.price,
      })),
    });

    // Linha do tempo de preços: o produto guarda o último valor publicado e
    // ganha um ponto no histórico com o código da versão como autor — é o que
    // deixa o relatório do produto contar a história por gestão. O grão entra
    // na mesma lista: a cotação da saca também é um preço que se acompanha.
    const published: { productId: number; price: number }[] = [
      ...prices.map((row) => ({ productId: row.product.id, price: row.price })),
      ...(season.grainId ? [{ productId: season.grainId, price: grainPrice }] : []),
    ];

    await tx.priceHistoryEntry.createMany({
      data: published.map((row) => ({
        productId: row.productId,
        price: row.price,
        changedBy: `Barter ${code}`,
        changedById: admin.id,
        changedAt: now,
      })),
    });

    // O último valor publicado de cada produto, num comando só. `updateMany`
    // não serve — ele escreve o MESMO valor em todas as linhas, e aqui cada
    // produto tem o seu. O `unnest` casa os dois vetores (id, preço) e o banco
    // resolve a junção; os valores continuam sendo parâmetros, não texto
    // interpolado na consulta.
    await tx.$executeRaw`
      UPDATE "Product" AS p
         SET "currentPrice" = v.price
        FROM (
              SELECT unnest(${published.map((row) => row.productId)}::int[]) AS id,
                     unnest(${published.map((row) => row.price)}::double precision[]) AS price
             ) AS v
       WHERE p.id = v.id
    `;

    return tx.barterVersion.findUniqueOrThrow({
      where: { id: version.id },
      include: { season: true, prices: { orderBy: { productName: 'asc' } } },
    });
  }

  /** A trilha do lançamento. Fica FORA da transação: auditar não é publicar. */
  private async recordPublication(
    admin: User,
    version: VersionWithPrices,
    grainPrice: number,
    sourceFile: string | null,
  ): Promise<void> {
    await this.audit.record({
      actor: admin,
      action: AUDIT_ACTION.versionPublished,
      targetType: 'version',
      targetId: version.id,
      targetLabel: version.code,
      detail:
        `${version.prices.length} insumo(s), saca a ${grainPrice.toFixed(2)}` +
        (sourceFile ? ` — arquivo ${sourceFile}` : ''),
    });
  }

  /** Encerra a versão vigente sem encerrar a safra (o Barter para, a safra não). */
  async closeVersion(admin: User, code: string): Promise<VersionWithPrices> {
    const version = await this.findVersion(code);
    if (version.status !== 'active') {
      throw new UnprocessableEntityException('Esta versão já foi encerrada');
    }

    await this.prisma.barterVersion.update({
      where: { id: version.id },
      data: {
        status: 'closed',
        closedAt: new Date(),
        closedBy: admin.fullName,
        closedById: admin.id,
      },
    });

    await this.audit.record({
      actor: admin,
      action: AUDIT_ACTION.versionClosed,
      targetType: 'version',
      targetId: version.id,
      targetLabel: version.code,
      detail: version.season.name,
    });
    return this.findVersion(code);
  }

  /**
   * Corrige um valor DENTRO da versão vigente — a "liberdade de editar um preço
   * em específico" sem precisar republicar a planilha inteira.
   *
   * O grão entra pela mesma porta: o `productId` da safra atualiza o valor da
   * saca (`grainPrice`), que é a cotação da versão. Versão encerrada não aceita
   * correção: ela é o registro do que valeu, e as permutas fechadas nela
   * apontam para esses números.
   */
  async updatePrice(
    admin: User,
    code: string,
    productId: number,
    dto: UpdateVersionPriceDto,
  ): Promise<VersionWithPrices> {
    const version = await this.findVersion(code);
    if (version.status !== 'active') {
      throw new UnprocessableEntityException('Só a versão vigente pode ser corrigida');
    }

    const isGrain = version.season.grainId === productId;
    const row = version.prices.find((price) => price.productId === productId);
    if (!isGrain && !row) {
      throw new UnprocessableEntityException('Este produto não está na tabela desta versão');
    }

    const now = new Date();
    await this.prisma.$transaction(async (tx) => {
      if (isGrain) {
        await tx.barterVersion.update({
          where: { id: version.id },
          data: { grainPrice: dto.price },
        });
      } else {
        await tx.versionPrice.update({ where: { id: row!.id }, data: { price: dto.price } });
      }

      // O produto guarda o último valor publicado e ganha o ponto na linha do
      // tempo — é dela que vive o relatório de preço do item.
      await tx.product.update({
        where: { id: productId },
        data: {
          currentPrice: dto.price,
          priceHistory: {
            create: {
              price: dto.price,
              changedBy: `Barter ${version.code}`,
              changedById: admin.id,
              changedAt: now,
            },
          },
        },
      });
    });

    await this.audit.record({
      actor: admin,
      action: AUDIT_ACTION.versionPriceChanged,
      targetType: 'version',
      targetId: version.id,
      targetLabel: version.code,
      detail: `${row?.productName ?? version.season.grainName}: ${dto.price.toFixed(2)}`,
    });
    return this.findVersion(code);
  }

  /* ── Apoio ─────────────────────────────────────────────────────────── */

  /**
   * Casa as linhas do corpo JSON com o catálogo. Só insumos entram na tabela:
   * o grão tem o campo próprio (`grainPrice`) porque ele não é comprado, é a
   * moeda da permuta.
   */
  private async resolvePrices(
    rows: { productId: number; price: number; cost?: number }[],
  ): Promise<ResolvedPrice[]> {
    const ids = [...new Set(rows.map((row) => row.productId))];

    // O mesmo produto duas vezes na tabela é recusado AQUI, com o id na
    // mensagem. Sem esta conferência quem barrava era o índice único
    // `[versionId, productId]`, e o admin recebia "Já existe um registro com
    // estes dados." — verdade que não diz qual registro nem onde. É a mesma
    // regra que a planilha aplica por linha (ver parseSheet).
    if (ids.length !== rows.length) {
      const repeated = rows
        .map((row) => row.productId)
        .filter((id, index, all) => all.indexOf(id) !== index);
      throw new UnprocessableEntityException(
        `A tabela de valores repete o(s) produto(s): ${[...new Set(repeated)].join(', ')}`,
      );
    }

    const products = await this.prisma.product.findMany({ where: { id: { in: ids } } });
    const byId = new Map(products.map((product) => [product.id, product]));

    return rows.map((row) => {
      const product = byId.get(row.productId);
      if (!product) {
        throw new UnprocessableEntityException(`Produto ${row.productId} não existe no catálogo`);
      }
      if (product.type !== 'input') {
        throw new UnprocessableEntityException(
          `${product.name} não é um insumo — o grão da safra tem valor próprio`,
        );
      }
      return { product, price: row.price };
    });
  }

  /**
   * Casa as linhas da planilha com o catálogo — e CRIA o que não existe.
   *
   * Criar é o comportamento certo aqui: a planilha do fornecedor é a fonte do
   * que existe para permutar, e obrigar o admin a pré-cadastrar cada item novo
   * antes de subir o arquivo transformaria a carga em massa em digitação.
   *
   * A ordem de casamento importa. O `sku` vem primeiro porque é estável: nome
   * muda de grafia entre um arquivo e outro ("Ureia 45%" / "UREIA 45 %"), e
   * casar só por nome criaria um cadastro novo a cada importação — com o
   * histórico de preço partido ao meio.
   */
  private async resolveImported(
    tx: Prisma.TransactionClient,
    rows: ImportRow[],
  ): Promise<ResolvedPrice[]> {
    const [products, classes] = await Promise.all([
      tx.product.findMany({ where: { type: 'input' } }),
      tx.productClass.findMany({ orderBy: { position: 'asc' } }),
    ]);

    const bySku = new Map(
      products
        .filter((product) => product.sku)
        .map((product) => [product.sku!.toLowerCase(), product]),
    );
    const byName = new Map(products.map((product) => [normalizeName(product.name), product]));

    // A CLASSE vem do arquivo: quem define a taxonomia é a lista de preços do
    // fornecedor, não quem cadastra. O que a chave normalizada protege é o
    // outro extremo — "HERBICIDAS", "Herbicidas" e "herbicidas " são a MESMA
    // classe, e sem isso cada carga criaria uma cópia, com o mínimo de cada uma
    // medindo um conjunto diferente.
    const classByKey = new Map<string, number>();
    for (const productClass of classes) {
      classByKey.set(normalizeName(productClass.name), productClass.id);
      classByKey.set(normalizeName(productClass.slug), productClass.id);
    }
    let nextPosition = classes.reduce((max, c) => Math.max(max, c.position), 0);

    // As CLASSES primeiro, e uma a uma mesmo: são dezenas no pior caso (a
    // taxonomia de um fornecedor), e cada uma precisa do id de volta para as
    // linhas que a citam.
    const classIdFor = new Map<number, number | null>();
    for (const [index, row] of rows.entries()) {
      if (!row.productClass) {
        classIdFor.set(index, null);
        continue;
      }
      classIdFor.set(
        index,
        classByKey.get(normalizeName(row.productClass)) ??
          (await this.createClass(tx, row.productClass, ++nextPosition, classByKey)),
      );
    }

    /*
     * Os produtos NOVOS, num `createMany` só.
     *
     * Eram criados um a um, dentro do laço. Numa primeira carga isso é uma ida
     * ao banco por linha da planilha — a lista inteira do fornecedor —, e desde
     * que isto passou a rodar dentro da transação da publicação, cada uma delas
     * conta contra o prazo dela. Um comando resolve a mesma coisa.
     *
     * Dá para casar os criados de volta pelo nome normalizado porque o
     * `parseSheet` já recusou linha repetida por essa mesma chave: dentro de um
     * arquivo, um nome normalizado é um produto.
     */
    const missing = [...rows.entries()].filter(
      ([, row]) =>
        !(row.sku ? bySku.get(row.sku.toLowerCase()) : undefined) &&
        !byName.get(normalizeName(row.name)),
    );
    if (missing.length > 0) {
      await tx.product.createMany({
        data: missing.map(([index, row]) => ({
          name: row.name,
          unit: row.unit,
          type: 'input',
          currentPrice: row.price,
          requiredPerHa: row.requiredPerHa ?? 0,
          classId: classIdFor.get(index) ?? null,
          sku: row.sku,
          unitPending: row.unitPending,
        })),
      });
      const created = await tx.product.findMany({
        where: { type: 'input', name: { in: missing.map(([, row]) => row.name) } },
      });
      for (const product of created) {
        byName.set(normalizeName(product.name), product);
        if (product.sku) bySku.set(product.sku.toLowerCase(), product);
      }
    }

    const resolved: ResolvedPrice[] = [];
    for (const [index, row] of rows.entries()) {
      const classId = classIdFor.get(index) ?? null;
      let product =
        (row.sku ? bySku.get(row.sku.toLowerCase()) : undefined) ??
        byName.get(normalizeName(row.name));

      if (!product) {
        // O produto foi criado logo acima; não achá-lo aqui é defeito nosso, e
        // um 500 com rastro é melhor que uma tabela publicada pela metade.
        throw new Error(`Produto "${row.name}" (linha ${row.line}) não foi criado na importação`);
      }

      // Cadastro existente só recebe o que a planilha ACRESCENTA: o código do
      // fornecedor que faltava, a classe e a exigência por hectare. Nome e
      // unidade ficam como estão — a unidade daquela versão vai no snapshot
      // da tabela, então mudar o cadastro reescreveria as versões passadas.
      const patch: Partial<Product> = {};
      if (!product.sku && row.sku) patch.sku = row.sku;
      if (classId && product.classId !== classId) patch.classId = classId;
      // Unidade só é reescrita quando a atual é PALPITE e a planilha trouxe
      // uma de verdade. O contrário — sobrescrever o que o admin escreveu —
      // desfaria a revisão a cada carga.
      if (product.unitPending && !row.unitPending) {
        patch.unit = row.unit;
        patch.unitPending = false;
      }
      if (row.requiredPerHa !== null && row.requiredPerHa !== product.requiredPerHa) {
        patch.requiredPerHa = row.requiredPerHa;
      }
      if (Object.keys(patch).length > 0) {
        product = await tx.product.update({ where: { id: product.id }, data: patch });
        byName.set(normalizeName(product.name), product);
        if (product.sku) bySku.set(product.sku.toLowerCase(), product);
      }

      resolved.push({ product, price: row.price, unit: row.unit });
    }
    return resolved;
  }

  /**
   * Classe nova, vinda da planilha. Nasce SEM regra de mínimo: a regra é
   * decisão comercial do admin, e uma classe que chegasse travando o envio da
   * permuta seria uma decisão tomada por um arquivo.
   *
   * O nome fica como o fornecedor escreve (`FERTILIZANTES FOLIARES`); o slug é
   * a forma estável, sem acento nem espaço — é por ele que o código se refere à
   * classe se o nome de exibição mudar um dia.
   */
  private async createClass(
    tx: Prisma.TransactionClient,
    name: string,
    position: number,
    cache: Map<string, number>,
  ): Promise<number> {
    const created = await tx.productClass.create({
      data: { name: name.trim(), slug: slugify(name), position },
    });
    cache.set(normalizeName(created.name), created.id);
    cache.set(normalizeName(created.slug), created.id);
    return created.id;
  }
}
