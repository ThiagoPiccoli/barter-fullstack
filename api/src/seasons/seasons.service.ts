import { Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import type { BarterVersion, Product, Season, User, VersionPrice } from '@prisma/client';
import { AUDIT_ACTION, AuditService } from '../audit/audit.service';
import { PrismaService } from '../prisma/prisma.service';
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

/** Uma linha da tabela já resolvida contra o catálogo. */
export interface ResolvedPrice {
  product: Product;
  price: number;
  cost: number;
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
        items: { select: { kind: true, quantity: true, unitValue: true, unitCost: true } },
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

    const prices = await this.resolveImported(rows);

    if (/^true$/i.test(dto.carryOver ?? '')) {
      const previous = await this.prisma.barterVersion.findFirst({
        where: { seasonId: season.id },
        orderBy: { number: 'desc' },
        include: { prices: true },
      });
      const chosen = new Set(prices.map((row) => row.product.id));
      const kept = (previous?.prices ?? []).filter(
        (row) => row.productId !== null && !chosen.has(row.productId),
      );
      if (kept.length > 0) {
        const products = await this.prisma.product.findMany({
          where: { id: { in: kept.map((row) => row.productId!) } },
        });
        const byId = new Map(products.map((product) => [product.id, product]));
        for (const row of kept) {
          const product = byId.get(row.productId!);
          if (product) {
            prices.push({ product, price: row.price, cost: row.cost, unit: row.unit });
          }
        }
      }
    }

    return this.publishResolved(admin, season, prices, dto.grainPrice, dto, file.originalname);
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
    this.assertPublishable(season, limits);
    if (prices.length === 0) {
      throw new UnprocessableEntityException('A tabela de valores está vazia');
    }

    const endsAt = limits.endsAt ? new Date(limits.endsAt) : null;
    const now = new Date();

    const previous = await this.prisma.barterVersion.findFirst({
      where: { seasonId: season.id },
      orderBy: { number: 'desc' },
    });
    const number = (previous?.number ?? 0) + 1;
    const code = versionCode(season.code, number);

    const created = await this.prisma.$transaction(async (tx) => {
      // Uma vigente só: a anterior fecha no mesmo instante em que a nova nasce.
      await tx.barterVersion.updateMany({
        where: { seasonId: season.id, status: 'active' },
        data: {
          status: 'closed',
          closedAt: now,
          closedBy: admin.fullName,
          closedById: admin.id,
        },
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
          targetProfit: limits.targetProfit ?? null,
          targetSacks: limits.targetSacks ?? null,
          targetBarters: limits.targetBarters ?? null,
          sourceFile,
          note: limits.note?.trim() || null,
          prices: {
            create: prices.map((row) => ({
              productId: row.product.id,
              productName: row.product.name,
              unit: row.unit ?? row.product.unit,
              price: row.price,
              cost: row.cost,
            })),
          },
        },
        include: { season: true, prices: { orderBy: { productName: 'asc' } } },
      });

      // Linha do tempo de preços: o produto guarda o último valor publicado e
      // ganha um ponto no histórico com o código da versão como autor — é o que
      // deixa o relatório do produto contar a história por gestão. O grão entra
      // na mesma lista: a cotação da saca também é um preço que se acompanha.
      const published: { productId: number; price: number }[] = [
        ...prices.map((row) => ({ productId: row.product.id, price: row.price })),
        ...(season.grainId ? [{ productId: season.grainId, price: grainPrice }] : []),
      ];
      for (const row of published) {
        await tx.product.update({
          where: { id: row.productId },
          data: {
            currentPrice: row.price,
            priceHistory: {
              create: {
                price: row.price,
                changedBy: `Barter ${code}`,
                changedById: admin.id,
                changedAt: now,
              },
            },
          },
        });
      }

      return version;
    });

    await this.audit.record({
      actor: admin,
      action: AUDIT_ACTION.versionPublished,
      targetType: 'version',
      targetId: created.id,
      targetLabel: created.code,
      detail:
        `${prices.length} insumo(s), saca a ${grainPrice.toFixed(2)}` +
        (sourceFile ? ` — arquivo ${sourceFile}` : ''),
    });
    return created;
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
    if (dto.price === undefined && dto.cost === undefined) {
      throw new UnprocessableEntityException('Informe o preço e/ou o custo');
    }
    const version = await this.findVersion(code);
    if (version.status !== 'active') {
      throw new UnprocessableEntityException('Só a versão vigente pode ser corrigida');
    }

    const isGrain = version.season.grainId === productId;
    if (isGrain && dto.price === undefined) {
      throw new UnprocessableEntityException('Informe o novo valor da saca');
    }

    const now = new Date();
    await this.prisma.$transaction(async (tx) => {
      if (isGrain) {
        await tx.barterVersion.update({
          where: { id: version.id },
          data: { grainPrice: dto.price! },
        });
      } else {
        const row = version.prices.find((price) => price.productId === productId);
        if (!row) {
          throw new UnprocessableEntityException('Este produto não está na tabela desta versão');
        }
        await tx.versionPrice.update({
          where: { id: row.id },
          data: {
            ...(dto.price !== undefined ? { price: dto.price } : {}),
            ...(dto.cost !== undefined ? { cost: dto.cost } : {}),
          },
        });
      }

      if (dto.price !== undefined) {
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
      }
    });

    const updated = await this.findVersion(code);
    const label =
      version.prices.find((price) => price.productId === productId)?.productName ??
      version.season.grainName;
    await this.audit.record({
      actor: admin,
      action: AUDIT_ACTION.versionPriceChanged,
      targetType: 'version',
      targetId: version.id,
      targetLabel: version.code,
      detail:
        `${label}: ` +
        [
          dto.price !== undefined ? `preço ${dto.price.toFixed(2)}` : null,
          dto.cost !== undefined ? `custo ${dto.cost.toFixed(2)}` : null,
        ]
          .filter(Boolean)
          .join(', '),
    });
    return updated;
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
      return { product, price: row.price, cost: row.cost ?? 0 };
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
  private async resolveImported(rows: ImportRow[]): Promise<ResolvedPrice[]> {
    const [products, classes] = await Promise.all([
      this.prisma.product.findMany({ where: { type: 'input' } }),
      this.prisma.productClass.findMany({ orderBy: { position: 'asc' } }),
    ]);

    const bySku = new Map(
      products
        .filter((product) => product.sku)
        .map((product) => [product.sku!.toLowerCase(), product]),
    );
    const byName = new Map(products.map((product) => [normalizeName(product.name), product]));

    // A classe da planilha precisa ser UMA DAS QUE EXISTEM. Antes, um nome
    // desconhecido criava uma pasta nova — e era assim que "Defensivo",
    // "DEFENSIVOS" e "Defensivos Foliares" viravam três conjuntos diferentes,
    // cada um medindo um mínimo diferente. Aceita nome ou slug, com ou sem
    // acento; o que não estiver na lista é erro do arquivo.
    const classByKey = new Map<string, number>();
    for (const productClass of classes) {
      classByKey.set(normalizeName(productClass.name), productClass.id);
      classByKey.set(normalizeName(productClass.slug), productClass.id);
    }

    const resolved: ResolvedPrice[] = [];
    for (const row of rows) {
      let product =
        (row.sku ? bySku.get(row.sku.toLowerCase()) : undefined) ??
        byName.get(normalizeName(row.name));

      let classId: number | null = null;
      if (row.productClass) {
        classId = classByKey.get(normalizeName(row.productClass)) ?? null;
        if (classId === null) {
          throw new UnprocessableEntityException(
            `Linha ${row.line} (${row.name}): a classe "${row.productClass}" não existe. ` +
              `Use uma destas: ${classes.map((c) => c.name).join(', ')}.`,
          );
        }
      }

      if (!product) {
        product = await this.prisma.product.create({
          data: {
            name: row.name,
            unit: row.unit,
            type: 'input',
            currentPrice: row.price,
            requiredPerHa: row.requiredPerHa ?? 0,
            classId,
            sku: row.sku,
          },
        });
        bySku.set((row.sku ?? '').toLowerCase(), product);
        byName.set(normalizeName(product.name), product);
      } else {
        // Cadastro existente só recebe o que a planilha ACRESCENTA: o código do
        // fornecedor que faltava, a classe e a exigência por hectare. Nome e
        // unidade ficam como estão — a unidade daquela versão vai no snapshot
        // da tabela, então mudar o cadastro reescreveria as versões passadas.
        const patch: Partial<Product> = {};
        if (!product.sku && row.sku) patch.sku = row.sku;
        if (classId && product.classId !== classId) patch.classId = classId;
        if (row.requiredPerHa !== null && row.requiredPerHa !== product.requiredPerHa) {
          patch.requiredPerHa = row.requiredPerHa;
        }
        if (Object.keys(patch).length > 0) {
          product = await this.prisma.product.update({ where: { id: product.id }, data: patch });
        }
      }

      resolved.push({ product, price: row.price, cost: row.cost, unit: row.unit });
    }
    return resolved;
  }
}

/** Nome comparável: sem acento, sem caixa e sem espaço repetido. */
function normalizeName(value: string): string {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}
