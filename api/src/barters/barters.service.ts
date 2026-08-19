import {
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import type { Barter, BarterEvent, BarterItem, Prisma, User } from '@prisma/client';
import { AUDIT_ACTION, AuditService } from '../audit/audit.service';
import { PrismaService } from '../prisma/prisma.service';
import {
  MONEY_EPSILON,
  classRequired,
  classSpend,
  inputCost,
  minQuantityFor,
  roundQuantity,
  sacksToCover,
  type PricedInput,
} from './barter-math';
import {
  BARTER_ACTION,
  BARTER_STATUS,
  BARTER_STEPS,
  refusalFor,
  type BarterAction,
  type BarterStatus,
} from './barter-workflow';
import { TAX_REGIME, taxRateOf } from './tax-regime';
import { Paginated, windowOf } from '../common/pagination';
import { CAPABILITY, can } from '../common/policy';
import { ROLE } from '../common/roles';
import { SeasonsService } from '../seasons/seasons.service';
import {
  BarterOpinionDto,
  CreateBarterDto,
  InvoiceBarterDto,
  ListBartersQuery,
  ReviewBarterDto,
} from './dto/barter.dto';

type BarterWithItems = Barter & { items: BarterItem[] };

/** A permuta com a LINHA DO TEMPO junto — a forma do detalhe. */
type BarterDetail = BarterWithItems & { events: BarterEvent[] };

/** Quanto de um texto longo cabe numa linha da trilha sem afogá-la. */
const AUDIT_DETAIL_LIMIT = 180;

const summarize = (text: string): string =>
  text.length <= AUDIT_DETAIL_LIMIT ? text : `${text.slice(0, AUDIT_DETAIL_LIMIT)}…`;

/**
 * Regras de negócio da permuta. O servidor é a autoridade: preços saem do
 * banco (nunca do cliente), mínimos por hectare e por classe travam a
 * criação, e as sacas do grão são calculadas aqui.
 */
@Injectable()
export class BartersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly seasons: SeasonsService,
  ) {}

  /**
   * O RECORTE de quem enxerga o quê — a regra de acesso central do domínio, em
   * um lugar só. Três escopos, e cada um responde a uma pergunta diferente:
   *
   * - **tudo** (admin, comitê, faturista): acompanham a operação inteira;
   * - **o time** (gerente): as permutas endereçadas a ele. Ele não é auditor —
   *   responde por um time, e a permuta de outro time não é assunto dele;
   * - **as próprias** (consultor): as que ele registrou.
   *
   * A ordem das perguntas importa: `readAll` vence `readTeam`, de modo que um
   * papel que ganhe as duas continue enxergando tudo em vez de ficar preso ao
   * recorte mais estreito.
   */
  private scopeFor(user: User): Prisma.BarterWhereInput {
    if (can(user, CAPABILITY.bartersReadAll)) return {};
    if (can(user, CAPABILITY.bartersReadTeam)) return { managerId: user.id };
    return { consultantId: user.id };
  }

  /**
   * Permutas visíveis para o usuário, dentro do escopo dele (ver `scopeFor`).
   *
   * O `id` desempata a ordenação por data. Sem ele, permutas criadas no mesmo
   * instante sairiam em ordem arbitrária a cada consulta e a paginação
   * repetiria umas e pularia outras entre uma página e a seguinte.
   */
  async listFor(user: User, query: ListBartersQuery): Promise<Paginated<BarterWithItems>> {
    const { take, skip } = windowOf(query);
    const where = {
      ...this.scopeFor(user),
      ...(query.status ? { status: query.status } : {}),
      ...(query.unitId ? { unitId: query.unitId } : {}),
      ...(query.managerId ? { managerId: query.managerId } : {}),
    };

    const [items, total] = await this.prisma.$transaction([
      this.prisma.barter.findMany({
        where,
        include: { items: true },
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        take,
        skip,
      }),
      this.prisma.barter.count({ where }),
    ]);

    return new Paginated(items, total, take, skip);
  }

  /**
   * Uma permuta pelo código público, respeitando o escopo do usuário.
   *
   * O escopo é o MESMO da listagem, e por isso vem do mesmo lugar: uma permuta
   * que não aparece na lista de alguém também não pode abrir pelo código. Foi
   * exatamente essa a fresta que o `scopeFor` fecha — a listagem filtrava, o
   * detalhe conferia por conta própria, e as duas regras podiam divergir.
   */
  async findFor(user: User, code: string): Promise<BarterDetail> {
    const barter = await this.prisma.barter.findFirst({
      where: { code, ...this.scopeFor(user) },
      // O DETALHE leva a linha do tempo; a LISTAGEM não. É o mesmo motivo de a
      // listagem não trazer o histórico de preço do produto: uma tela de lista
      // mostra estado, não trajetória, e cobrar do banco os eventos de cinquenta
      // permutas para desenhar cinquenta linhas de tabela é trabalho jogado fora.
      //
      // Quem precisa da trajetória inteira é quem abre a permuta — em especial o
      // faturista, que fatura lendo o que as etapas anteriores produziram.
      include: { items: true, events: { orderBy: [{ at: 'asc' }, { id: 'asc' }] } },
    });
    if (barter) return barter;

    // Distingue "não existe" de "não é sua": a segunda é informação útil para
    // quem digitou um código legítimo, e a permuta em si continua invisível.
    const exists = await this.prisma.barter.count({ where: { code } });
    if (exists === 0) throw new NotFoundException('Registro não encontrado.');
    throw new ForbiddenException('Você não tem acesso a esta permuta');
  }

  /**
   * Registra uma permuta para um produtor da carteira do consultor. Fluxo:
   * 1. precisa haver um Barter (versão) aberto — é ele quem diz por quanto se
   *    permuta hoje, e qual é o grão de pagamento;
   * 2. produtor precisa pertencer à carteira de quem registra;
   * 3. a UNIDADE de retirada precisa existir — mas é só logística: ela não
   *    escolhe quem analisa a permuta, e pode ser qualquer uma da lista;
   * 4. todo insumo com exigência por hectare é obrigatório, no mínimo
   *    `taxa × área` (o app pré-preenche, o servidor confere);
   * 5. as regras de mínimo das classes precisam estar satisfeitas;
   * 6. o custo é precificado com a TABELA DA VERSÃO e convertido em sacas do
   *    grão da safra — o item de grão é criado pelo servidor.
   *
   * O consultor não escolhe mais o grão: ele é da safra. E os preços não vêm
   * mais do catálogo — vêm da versão, que é o acordo publicado. Um insumo fora
   * da tabela da versão simplesmente não é permutável naquela gestão.
   *
   * A permuta nasce em `sentToManager`, e não em `pending`: ela é ENDEREÇADA ao
   * gerente do consultor, que precisa dar o parecer técnico antes de a
   * negociação seguir para a revisão.
   */
  async create(consultant: User, dto: CreateBarterDto): Promise<BarterDetail> {
    // A rota já exige a capacidade `barters.register`; aqui a regra é repetida
    // como invariante do DOMÍNIO, e na forma de LISTA DE PERMITIDOS. Enquanto
    // isto perguntava "é admin?", cada papel novo entrava por omissão — gerente,
    // comitê e faturista registrariam permuta sem ninguém ter decidido isso.
    if (consultant.role !== ROLE.consultant) {
      throw new ForbiddenException('Permutas são registradas pelo consultor da carteira');
    }

    // O DESTINATÁRIO. O cadastro do consultor exige um gerente, então isto só
    // acontece quando o gerente dele foi excluído depois — e nesse caso a
    // permuta nasceria endereçada a ninguém: ficaria em `sentToManager` para
    // sempre, sem erro e sem a quem cobrar. Melhor recusar aqui.
    if (consultant.managerId === null) {
      throw new UnprocessableEntityException(
        'Você está sem gerente designado — fale com o administrador antes de registrar permutas',
      );
    }
    const manager = await this.prisma.user.findUnique({ where: { id: consultant.managerId } });
    if (!manager) {
      throw new UnprocessableEntityException(
        'Você está sem gerente designado — fale com o administrador antes de registrar permutas',
      );
    }

    // 1. O Barter vigente é o primeiro portão: sem lançamento aberto não existe
    //    tabela de valores, e uma permuta sem tabela seria um acordo sem preço.
    const version = await this.seasons.requireOpenVersion();
    if (version.grainPrice <= 0) {
      throw new UnprocessableEntityException(
        `O Barter ${version.code} está sem valor para a saca de ${version.season.grainName}`,
      );
    }

    // 2. O produtor precisa estar na carteira de QUEM REGISTRA. A carteira é
    //    compartilhável (o mesmo produtor é atendido por vários consultores,
    //    ver ProducerConsultant), então a pergunta é de pertencimento à lista —
    //    e não mais igualdade com um dono único. A permuta continua sendo de um
    //    consultor só: o que a registrou.
    const producer = await this.prisma.producer.findUnique({
      where: { id: dto.producerId },
      include: {
        consultants: { where: { consultantId: consultant.id }, select: { consultantId: true } },
      },
    });
    if (!producer) {
      throw new UnprocessableEntityException('Produtor não encontrado');
    }
    if (producer.consultants.length === 0) {
      throw new ForbiddenException('Este produtor não pertence à sua carteira');
    }

    // 3. A unidade de retirada é LOGÍSTICA: onde o produtor vai buscar. Ela não
    //    escolhe quem analisa a permuta nem participa de regra nenhuma, então a
    //    única conferência é que ela exista — qualquer praça serve.
    const unit = await this.prisma.unit.findUnique({ where: { id: dto.unitId } });
    if (!unit) {
      throw new UnprocessableEntityException('Escolha uma unidade de retirada válida');
    }

    // Consolida quantidades por produto (payload pode repetir ids) e as leva à
    // precisão em que serão GRAVADAS. Arredondar aqui, e não só no app, é o que
    // faz o item registrado ser o mesmo número que o comprovante imprime: o app
    // já mandava 2 casas, mas quem manda é este lado, e ele aceitava qualquer
    // precisão de quem chamasse a API direto.
    const quantities = new Map<number, number>();
    for (const item of dto.inputs) {
      quantities.set(item.productId, (quantities.get(item.productId) ?? 0) + item.quantity);
    }
    for (const [productId, quantity] of quantities) {
      quantities.set(productId, roundQuantity(quantity));
    }

    const products = await this.prisma.product.findMany({
      where: { id: { in: [...quantities.keys()] }, type: 'input' },
    });
    if (products.length !== quantities.size) {
      throw new UnprocessableEntityException('A permuta contém insumos inexistentes');
    }

    // Os valores saem da versão, nunca do catálogo. Insumo que o admin não
    // lançou nesta versão não tem preço acordado — e um preço "de reserva"
    // vindo do cadastro é justamente o tipo de valor que ninguém combinou.
    const valueOf = new Map(version.prices.map((row) => [row.productId, row]));
    const missing = products.filter((product) => !valueOf.has(product.id));
    if (missing.length > 0) {
      throw new UnprocessableEntityException(
        `Fora do Barter ${version.code}: ${missing.map((product) => product.name).join(', ')}`,
      );
    }

    const pricedInputs: PricedInput[] = products.map((product) => ({
      productId: product.id,
      quantity: quantities.get(product.id)!,
      unitPrice: valueOf.get(product.id)!.price,
      classId: product.classId,
    }));

    if (pricedInputs.some((item) => item.quantity <= 0)) {
      throw new UnprocessableEntityException('Quantidades de insumo devem ser maiores que zero');
    }

    // 4. Insumos com exigência por hectare são obrigatórios para a área do
    //    produtor — mas só os que ESTÃO na versão: exigir o que o Barter não
    //    lançou travaria toda permuta da gestão.
    const requiredProducts = (
      await this.prisma.product.findMany({
        where: { type: 'input', requiredPerHa: { gt: 0 } },
      })
    ).filter((product) => valueOf.has(product.id));
    for (const product of requiredProducts) {
      const min = minQuantityFor(product.requiredPerHa, producer.areaHa);
      const chosen = quantities.get(product.id) ?? 0;
      if (chosen + 0.005 < min) {
        throw new UnprocessableEntityException(
          `${product.name} exige no mínimo ${min} ${product.unit} para ${producer.areaHa} ha`,
        );
      }
    }

    // 5. Regras de mínimo por CLASSE travam o envio.
    const totalCost = inputCost(pricedInputs);
    if (totalCost <= 0) {
      throw new UnprocessableEntityException('Escolha ao menos um insumo para retirar');
    }

    const ruledClasses = (
      await this.prisma.productClass.findMany({ where: { NOT: { ruleType: 'none' } } })
    ).filter((productClass) => productClass.ruleValue > 0);
    const unmet = ruledClasses.filter((productClass) => {
      const required = classRequired(productClass, { totalCost, areaHa: producer.areaHa });
      return required > 0 && classSpend(pricedInputs, productClass.id) < required - MONEY_EPSILON;
    });
    if (unmet.length > 0) {
      throw new UnprocessableEntityException(
        `Mínimo da classe não atingido: ${unmet.map((c) => c.name).join(', ')}`,
      );
    }

    // 6. Converte o custo em sacas do grão da safra — o coração do escambo.
    const sacks = sacksToCover(totalCost, version.grainPrice);

    const items = [
      {
        productId: version.season.grainId,
        kind: 'grain',
        productName: version.season.grainName,
        unit: version.season.grainUnit,
        quantity: sacks,
        unitValue: version.grainPrice,
      },
      ...products.map((product) => ({
        productId: product.id,
        kind: 'input',
        productName: product.name,
        unit: product.unit,
        quantity: quantities.get(product.id)!,
        unitValue: valueOf.get(product.id)!.price,
      })),
    ];

    // A FORMA de recolhimento escolhida no fechamento. Ausente vale
    // `comercializacao`: é o regime de quem não fez a opção formal pela folha.
    const taxRegime = dto.taxRegime ?? TAX_REGIME.comercializacao;

    return this.createWithCode({
      versionId: version.id,
      versionCode: version.code,
      consultantId: consultant.id,
      consultantName: consultant.fullName,
      consultantBranch: consultant.branch ?? '',
      producerId: producer.id,
      producerName: producer.name,
      unitId: unit.id,
      unitName: unit.name,
      // O IMPOSTO DA ENTREGA: a forma escolhida no fechamento, e a alíquota que
      // ela produz para ESTE produtor (CPF ou CNPJ muda o percentual). A
      // alíquota é congelada aqui — a entrega é comercialização de produção
      // rural, e o que vale é a tabela do dia. Ver `tax-regime.ts`.
      taxRegime,
      taxRate: taxRateOf(taxRegime, producer.documentDigits),
      // O destinatário é gravado no ENVIO. Trocar o gerente do consultor depois
      // vale para as próximas permutas; esta continua na mesa de quem a
      // recebeu. Ver o comentário de `managerId` no schema.
      managerId: manager.id,
      managerName: manager.fullName,
      status: BARTER_STATUS.sentToManager,
      items: { create: items },
      // O PRIMEIRO EVENTO da linha do tempo nasce junto com a permuta, na mesma
      // transação — não existe permuta sem o registro de que ela foi registrada.
      events: {
        create: [
          this.eventOf(consultant, BARTER_ACTION.register, null, BARTER_STATUS.sentToManager),
        ],
      },
    });
  }

  /**
   * Uma linha da LINHA DO TEMPO, com o autor congelado em texto.
   *
   * Snapshot pelo mesmo motivo do AuditLog: o histórico precisa continuar
   * legível depois que a conta for excluída — e é justamente o registro de quem
   * decidiu que alguém vai querer ler nesse dia.
   */
  private eventOf(
    actor: User,
    action: BarterAction,
    from: BarterStatus | null,
    to: BarterStatus,
    note?: string | null,
  ): Prisma.BarterEventCreateWithoutBarterInput {
    return {
      action,
      fromStatus: from,
      toStatus: to,
      actorId: actor.id,
      actorName: actor.fullName,
      actorRole: actor.role,
      note: note ?? null,
    };
  }

  /**
   * UM PASSO da máquina de estados: grava a mudança e o evento JUNTOS.
   *
   * Os dois na mesma transação, e isso é a regra do histórico: sem o evento não
   * há mudança de estado. É o que separa esta trilha da de auditoria, que é
   * best-effort de propósito (ver AuditService.record) — ali perder uma linha
   * não pode derrubar o ato; aqui a linha É parte do ato.
   *
   * O `status` entra no `where` do update, e não só na conferência de antes: dois
   * membros do comitê decidindo a mesma permuta no mesmo segundo passariam os
   * dois pela leitura e o segundo sobrescreveria a decisão do primeiro em
   * silêncio. Com ele, o segundo não encontra a linha (P2025) e recebe a mesma
   * resposta de quem chega tarde — que é o que de fato aconteceu com ele.
   */
  private async applyStep(
    barter: Barter,
    action: BarterAction,
    actor: User,
    to: BarterStatus,
    fields: Prisma.BarterUncheckedUpdateInput,
    note?: string | null,
  ): Promise<BarterDetail> {
    try {
      return await this.prisma.barter.update({
        where: { id: barter.id, status: barter.status },
        data: {
          ...fields,
          status: to,
          events: {
            create: [this.eventOf(actor, action, barter.status as BarterStatus, to, note)],
          },
        },
        // A resposta de um ATO é do tamanho do detalhe, e leva a linha do tempo
        // com o passo que ele acabou de criar. Sem isso, a tela que agiu ficava
        // com uma permuta SEM histórico na mão — e a linha do tempo que estava
        // ali sumia no instante seguinte ao clique, até alguém reabrir o
        // registro. Quem não carrega eventos é só a LISTAGEM.
        include: { items: true, events: { orderBy: [{ at: 'asc' }, { id: 'asc' }] } },
      });
    } catch (error) {
      if ((error as { code?: string })?.code === 'P2025') {
        throw new UnprocessableEntityException(BARTER_STEPS[action].done);
      }
      throw error;
    }
  }

  /**
   * O PARECER TÉCNICO do gerente — a etapa que faz a permuta seguir.
   *
   * Três coisas são conferidas, e a ordem importa: a permuta existe, ela está
   * ESPERANDO parecer, e ela foi endereçada a quem está pedindo. A terceira é a
   * que a tabela de capacidades não alcança: `barters.opinion` diz que gerente
   * dá parecer, não que ESTE gerente dá parecer nesta permuta. Sem ela, qualquer
   * gerente opinaria sobre o time de qualquer outro.
   *
   * O parecer não decide nada: ele é gravado e a permuta passa a `pending`, que
   * é a fila de REVISÃO. Quem aprova ou nega continua sendo quem tem
   * `barters.review`, e lê este texto antes.
   */
  async giveOpinion(manager: User, code: string, dto: BarterOpinionDto): Promise<BarterDetail> {
    const barter = await this.requireBarter(code, BARTER_ACTION.opinion);

    // A política sobre o RECURSO, que a máquina de estados não alcança: ela diz
    // que a permuta está no ponto do parecer, não que este gerente é o dono
    // desta. Sem isto, qualquer gerente opinaria sobre o time de qualquer outro.
    if (barter.managerId !== manager.id) {
      throw new ForbiddenException('Esta permuta foi enviada a outro gerente');
    }

    const note = dto.note.trim();
    const reviewed = await this.applyStep(
      barter,
      BARTER_ACTION.opinion,
      manager,
      BARTER_STATUS.pending,
      {
        // O nome é regravado porque ele é a ASSINATURA do parecer, e não só o
        // rótulo do destinatário: entre o envio e o parecer, a pessoa pode ter
        // corrigido o próprio nome no cadastro.
        managerName: manager.fullName,
        managerNote: note,
        managerReviewedAt: new Date(),
      },
      note,
    );

    await this.audit.record({
      actor: manager,
      action: AUDIT_ACTION.barterOpinion,
      targetType: 'barter',
      targetId: reviewed.id,
      targetLabel: reviewed.code,
      // O parecer inteiro vive na permuta; aqui vai o começo dele, porque a
      // trilha se lê em lista e um texto de duas mil letras por linha a
      // esconderia de quem está procurando outra coisa.
      detail: `parecer sobre a permuta de ${reviewed.consultantName}: ${summarize(note)}`,
    });
    return reviewed;
  }

  /**
   * Grava a permuta reservando o próximo código público.
   *
   * O código é decidido lendo o maior já usado e somando um, e entre a leitura
   * e a gravação existe uma fresta: dois registros simultâneos podem escolher
   * o mesmo número.
   *
   * Essa corrida é REAL hoje. Enquanto o banco era SQLite, um comentário aqui
   * dizia que ela não acontecia porque as escritas eram serializadas dentro do
   * processo — e avisava que trocar para Postgres a traria de volta. A troca
   * aconteceu: sob `READ COMMITTED`, duas transações simultâneas leem o mesmo
   * máximo e escolhem o mesmo número, e com mais de uma instância da API isso
   * deixa de depender de sorte.
   *
   * Quem resolve não é o banco, é este par: o índice único em `code` transforma
   * a colisão numa falha limpa (P2002), e o laço abaixo a trata como "pegue o
   * próximo". Cinco tentativas cobrem uma concorrência muito acima da real —
   * permuta é registrada por gente, uma de cada vez.
   */
  private async createWithCode(
    data: Omit<Prisma.BarterUncheckedCreateInput, 'code'>,
  ): Promise<BarterDetail> {
    const MAX_ATTEMPTS = 5;
    for (let attempt = 1; ; attempt++) {
      try {
        return await this.prisma.$transaction(async (tx) =>
          tx.barter.create({
            data: { ...data, code: await this.nextCode(tx) },
            include: { items: true, events: { orderBy: [{ at: 'asc' }, { id: 'asc' }] } },
          }),
        );
      } catch (error) {
        if (attempt >= MAX_ATTEMPTS || !this.isDuplicateCode(error)) throw error;
      }
    }
  }

  /** Violação do índice único de `code` (P2002) — outra permuta chegou antes. */
  private isDuplicateCode(error: unknown): boolean {
    const known = error as { code?: string; meta?: { target?: unknown } };
    if (known?.code !== 'P2002') return false;
    const target = known.meta?.target;
    const fields = Array.isArray(target) ? target : [target];
    return fields.some((field) => typeof field === 'string' && field.includes('code'));
  }

  /**
   * A DECISÃO DO COMITÊ: aprova ou nega a permuta que já tem parecer, com
   * observação opcional. Grava o snapshot de quem decidiu e o momento.
   *
   * É a única etapa que decide o negócio, e ela é do comitê — o admin
   * administra o sistema (contas, catálogo, valores) e não passa por aqui. Ver
   * CAPABILITY.bartersReview.
   *
   * Só alcança quem está em `pending`, e as maneiras de não estar têm mensagens
   * diferentes de propósito: quem chega antes precisa saber com quem a permuta
   * está parada, não que "já foi decidida" — quem lê isso vai procurar uma
   * decisão que ninguém tomou. Quem escreve as mensagens é a máquina de estados.
   */
  async review(committee: User, code: string, dto: ReviewBarterDto): Promise<BarterDetail> {
    const barter = await this.requireBarter(code, BARTER_ACTION.review);

    const note = dto.note?.trim() ? dto.note.trim() : null;
    const reviewed = await this.applyStep(
      barter,
      BARTER_ACTION.review,
      committee,
      dto.status,
      {
        reviewNote: note,
        reviewedBy: committee.fullName,
        reviewedById: committee.id,
        reviewedAt: new Date(),
      },
      note,
    );

    // A permuta já guarda `reviewedBy`, e a linha do tempo dela já guarda o
    // evento. A trilha de auditoria é uma terceira coisa, e responde a outra
    // pergunta: "quem mexeu no sistema" — ela é global, cruza usuários,
    // unidades e permutas, e é onde uma investigação começa. Decidir permuta é
    // dinheiro, então continua entrando nela.
    await this.audit.record({
      actor: committee,
      action: AUDIT_ACTION.barterReviewed,
      targetType: 'barter',
      targetId: reviewed.id,
      targetLabel: reviewed.code,
      detail: `${dto.status === BARTER_STATUS.approved ? 'aprovada' : 'negada'}${
        reviewed.reviewNote ? ` — ${summarize(reviewed.reviewNote)}` : ''
      }`,
    });
    return reviewed;
  }

  /**
   * O FATURAMENTO — o último posto da linha, e o mais simples de todos.
   *
   * O faturista não avalia nem devolve: ele recebe o que as etapas anteriores
   * produziram (o pedido, o parecer, a decisão — tudo na linha do tempo da
   * permuta) e fatura o que foi APROVADO. Por isso não há aqui nenhuma decisão a
   * tomar, e por isso o único portão é o estado: negada não fatura, e sem
   * decisão do comitê também não.
   *
   * `invoiced` é fim de linha. Não existe "desfaturar" — corrigir faturamento é
   * ato do sistema de nota fiscal, não deste; um botão aqui apagaria o rastro do
   * que já saiu para fora.
   */
  async invoice(biller: User, code: string, dto: InvoiceBarterDto): Promise<BarterDetail> {
    const barter = await this.requireBarter(code, BARTER_ACTION.invoice);

    const note = dto.note?.trim() ? dto.note.trim() : null;
    const invoiced = await this.applyStep(
      barter,
      BARTER_ACTION.invoice,
      biller,
      BARTER_STATUS.invoiced,
      {
        invoiceNote: note,
        invoicedBy: biller.fullName,
        invoicedById: biller.id,
        invoicedAt: new Date(),
      },
      note,
    );

    await this.audit.record({
      actor: biller,
      action: AUDIT_ACTION.barterInvoiced,
      targetType: 'barter',
      targetId: invoiced.id,
      targetLabel: invoiced.code,
      detail: `faturada${invoiced.invoiceNote ? ` — ${summarize(invoiced.invoiceNote)}` : ''}`,
    });
    return invoiced;
  }

  /**
   * A permuta pronta para receber um ato — ou o erro que explica por que não.
   *
   * As duas perguntas que TODA etapa faz, no mesmo lugar e na mesma ordem: ela
   * existe? e ela está no ponto desta etapa? A segunda é da máquina de estados,
   * e é ela quem escreve a mensagem — inclusive a que diz com quem a permuta
   * está parada.
   *
   * Repare que a permuta é buscada SEM escopo, de propósito: quem chega aqui já
   * passou pela capacidade do passo, e as três etapas são de papéis que enxergam
   * a operação inteira (ou, no caso do gerente, cuja posse é conferida logo
   * depois). Filtrar por escopo aqui devolveria 404 para o gerente do outro time
   * em vez do 403 que ele merece — "não é sua" é informação diferente de "não
   * existe".
   */
  private async requireBarter(code: string, action: BarterAction): Promise<Barter> {
    const barter = await this.prisma.barter.findUnique({ where: { code } });
    if (!barter) throw new NotFoundException('Registro não encontrado.');

    const refusal = refusalFor(action, barter);
    if (refusal) throw new UnprocessableEntityException(refusal);

    return barter;
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
