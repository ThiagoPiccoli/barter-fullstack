import {
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import type {
  Barter,
  BarterCpr,
  Creditor,
  BarterEvent,
  BarterItem,
  CprArea,
  CprAreaOwner,
  CprGuarantor,
  Prisma,
  User,
} from '@prisma/client';
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
  lineFrom,
  outcomeLabelOf,
  refusalFor,
  type BarterAction,
  type BarterStatus,
} from './barter-workflow';
import { TAX_REGIME, taxRateOf } from './tax-regime';
import { EMPTY_CPR, cprGaps, knownFrom, suggestFrom, type CprKnown } from './cpr';
import { Paginated, windowOf } from '../common/pagination';
import { CAPABILITY, can } from '../common/policy';
import { ROLE } from '../common/roles';
import { CreditorService } from '../creditor/creditor.service';
import { SeasonsService } from '../seasons/seasons.service';
import {
  BarterOpinionDto,
  CreateBarterDto,
  ForwardBarterDto,
  InvoiceBarterDto,
  ListBartersQuery,
  MIN_OPINION_LENGTH,
  ReviewBarterDto,
  SaveBarterNoteDto,
} from './dto/barter.dto';
import { SaveCprDto } from './dto/cpr.dto';

type BarterWithItems = Barter & { items: BarterItem[] };

/** A permuta com a LINHA DO TEMPO junto — a forma do detalhe. */
type BarterDetail = BarterWithItems & { events: BarterEvent[] };

/** A cédula com as lavouras e os donos delas — a forma como ela é lida e salva. */
type CprWithAreas = BarterCpr & {
  areas: (CprArea & { owners: CprAreaOwner[] })[];
  guarantors: CprGuarantor[];
};

/** O `include` da cédula, escrito uma vez: leitura e sugestão leem o mesmo. */
const CPR_INCLUDE = {
  areas: {
    orderBy: { position: 'asc' },
    include: { owners: { orderBy: { position: 'asc' } } },
  },
  guarantors: { orderBy: { position: 'asc' } },
} as const;

/**
 * A MESA DA CÉDULA: o rascunho, o que a permuta já responde, quem é a credora e
 * o que ainda falta. É o que a tela do faturista precisa para desenhar o
 * formulário inteiro numa requisição só.
 */
interface CprDesk {
  cpr: CprWithAreas | null;
  known: CprKnown;
  creditor: Creditor;
  gaps: string[];
  suggestion: ReturnType<typeof suggestFrom>;
}

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
    private readonly creditor: CreditorService,
  ) {}

  /**
   * O RECORTE de quem enxerga o quê — a regra de acesso central do domínio, em
   * um lugar só. Quatro escopos, e cada um responde a uma pergunta diferente:
   *
   * - **tudo** (admin, comitê): acompanham a operação inteira. Para o comitê
   *   isso inclui o que ainda está no gerente — é a fila que vai cair na mesa
   *   dele;
   * - **o time** (gerente): as permutas endereçadas a ele. Ele não é auditor —
   *   responde por um time, e a permuta de outro time não é assunto dele;
   * - **o que chegou ao faturamento** (faturista): o próprio trecho da linha,
   *   e nada antes dele. Ver `bartersReadInvoicing` em policy.ts;
   * - **as próprias** (consultor): as que ele registrou.
   *
   * A ordem das perguntas importa: ela vai do escopo mais largo ao mais
   * estreito, de modo que um papel que acumule duas capacidades enxergue o
   * maior dos dois alcances em vez de ficar preso ao menor.
   */
  private scopeFor(user: User): Prisma.BarterWhereInput {
    // O RASCUNHO é do dono, e essa é a única exceção ao "tudo": uma permuta que
    // o consultor ainda está montando não é fila de ninguém, e vê-la na tela do
    // comitê é pedir decisão sobre um negócio que ainda não foi proposto. Os
    // outros três escopos já a excluem por construção — o rascunho não tem
    // gerente endereçado e não chegou ao faturamento —, e o do consultor a
    // inclui porque ela é dele.
    if (can(user, CAPABILITY.bartersReadAll)) {
      return { OR: [{ status: { not: BARTER_STATUS.draft } }, { consultantId: user.id }] };
    }
    if (can(user, CAPABILITY.bartersReadTeam)) return { managerId: user.id };
    if (can(user, CAPABILITY.bartersReadInvoicing)) {
      return { status: { in: lineFrom(BARTER_ACTION.invoice) } };
    }
    return { consultantId: user.id };
  }

  /**
   * Permutas visíveis para o usuário, dentro do escopo dele (ver `scopeFor`).
   *
   * O `id` desempata a ordenação por data. Sem ele, permutas criadas no mesmo
   * instante sairiam em ordem arbitrária a cada consulta e a paginação
   * repetiria umas e pularia outras entre uma página e a seguinte.
   *
   * O ESCOPO E OS FILTROS SE SOMAM, e por isso entram num `AND` em vez de
   * serem mesclados num objeto só. Enquanto era um spread, o filtro do cliente
   * SOBRESCREVIA o recorte sempre que os dois falavam do mesmo campo — e dois
   * dos quatro escopos são exatamente um campo: o do faturista é `status` e o
   * do gerente é `managerId`. `?status=pending` apagava o recorte do faturista
   * e lhe devolvia a mesa do comitê; `?managerId=7` devolvia ao gerente o time
   * do colega, com os pareceres dentro. O filtro é RECORTE, nunca permissão —
   * ele só pode estreitar o que o escopo já permitiu.
   */
  async listFor(user: User, query: ListBartersQuery): Promise<Paginated<BarterWithItems>> {
    const { take, skip } = windowOf(query);
    const where: Prisma.BarterWhereInput = {
      AND: [
        this.scopeFor(user),
        ...(query.status ? [{ status: query.status }] : []),
        ...(query.unitId ? [{ unitId: query.unitId }] : []),
        ...(query.managerId ? [{ managerId: query.managerId }] : []),
      ],
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
   * A permuta nasce em `draft`: ela é do CONSULTOR até ele encaminhá-la. O
   * registro congela os valores da versão e as contas, mas não põe a permuta na
   * mesa de ninguém — quem faz isso é `forward`, junto com o parecer dele.
   *
   * Por isso o GERENTE não é resolvido aqui: o destinatário é gravado no envio,
   * e o envio agora é o encaminhamento. Um consultor sem gerente designado
   * registra e monta o rascunho normalmente; ele só não consegue encaminhar — e
   * a mensagem que ele lê nesse momento diz exatamente isso.
   */
  async create(consultant: User, dto: CreateBarterDto): Promise<BarterDetail> {
    // A rota já exige a capacidade `barters.register`; aqui a regra é repetida
    // como invariante do DOMÍNIO, e na forma de LISTA DE PERMITIDOS. Enquanto
    // isto perguntava "é admin?", cada papel novo entrava por omissão — gerente,
    // comitê e faturista registrariam permuta sem ninguém ter decidido isso.
    if (consultant.role !== ROLE.consultant) {
      throw new ForbiddenException('Permutas são registradas pelo consultor da carteira');
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
      // A ÁREA congelada, pelo mesmo motivo do preço do item: ela é o
      // denominador do investimento por hectare, e o produtor arrenda mais terra
      // na safra seguinte. Ver `producerAreaHa` no schema.
      producerAreaHa: producer.areaHa,
      unitId: unit.id,
      unitName: unit.name,
      // O IMPOSTO DA ENTREGA: a forma escolhida no fechamento, e a alíquota que
      // ela produz para ESTE produtor (CPF ou CNPJ muda o percentual). A
      // alíquota é congelada aqui — a entrega é comercialização de produção
      // rural, e o que vale é a tabela do dia. Ver `tax-regime.ts`.
      taxRegime,
      taxRate: taxRateOf(taxRegime, producer.documentDigits),
      // Sem `managerId`: o destinatário é gravado no ENVIO, e o envio é o
      // encaminhamento (ver `forward`). Trocar o gerente do consultor entre o
      // registro e o encaminhamento vale para esta permuta; depois dele, não.
      status: BARTER_STATUS.draft,
      // O PARECER, quando ele já vem escrito. `null` é rascunho sem parecer, que
      // é o caso normal de quem acabou de simular.
      consultantNote: dto.note?.trim() ? dto.note.trim() : null,
      items: { create: items },
      // O PRIMEIRO EVENTO da linha do tempo nasce junto com a permuta, na mesma
      // transação — não existe permuta sem o registro de que ela foi registrada.
      events: {
        create: [this.eventOf(consultant, BARTER_ACTION.register, null, BARTER_STATUS.draft)],
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
   * O PARECER DO CONSULTOR gravado no RASCUNHO, sem mover a permuta.
   *
   * É o único texto do fluxo que se reescreve, e o único ato que não passa por
   * `applyStep`: não há transição, não há evento e não há assinatura — é um
   * rascunho sendo editado pelo próprio autor. O evento vem no encaminhamento,
   * que é quando o texto deixa de ser dele e passa a ser peça do processo.
   *
   * Só o DONO edita, e só enquanto é rascunho. As duas conferências são a mesma
   * de sempre, feitas pelas mesmas portas: `requireBarter` confere o escopo (o
   * rascunho de outro consultor nem aparece) e a máquina de estados confere que
   * a permuta ainda está no ponto do encaminhamento — uma permuta já na mesa do
   * gerente recusa a edição com a frase da etapa, e não com um "não pode".
   *
   * O `status` vai no `where` do update pelo mesmo motivo de `applyStep`, e não
   * por simetria: a conferência de antes e a gravação são duas idas ao banco, e
   * entre elas cabe o encaminhamento vindo de outro aparelho do mesmo
   * consultor. Sem ele, o texto seria reescrito DEPOIS de a permuta sair da
   * mesa dele — e a permuta seguiria ao gerente com um parecer diferente do que
   * ficou congelado no evento, que é a única cópia que ninguém pode editar.
   */
  async saveNote(consultant: User, code: string, dto: SaveBarterNoteDto): Promise<BarterDetail> {
    const barter = await this.requireBarter(consultant, code, BARTER_ACTION.forward);

    const note = dto.note.trim();
    try {
      await this.prisma.barter.update({
        where: { id: barter.id, status: BARTER_STATUS.draft },
        data: { consultantNote: note.length > 0 ? note : null },
      });
    } catch (error) {
      if ((error as { code?: string })?.code === 'P2025') {
        throw new UnprocessableEntityException(BARTER_STEPS[BARTER_ACTION.forward].done);
      }
      throw error;
    }
    return this.findFor(consultant, code);
  }

  /**
   * O ENCAMINHAMENTO AO GERENTE — o ato que tira a permuta da mesa do consultor.
   *
   * Ele faz duas coisas que o registro fazia junto e agora estão separadas: grava
   * o PARECER do consultor e ENDEREÇA a permuta ao gerente dele. O destinatário
   * é lido aqui, e não no registro, porque é aqui que o envio acontece — é a
   * leitura literal de "o consultor envia para o gerente" (ver `managerId` no
   * schema).
   *
   * O parecer pode vir no corpo ou já estar salvo no rascunho; o que não pode é
   * não existir. Quem confere é este método, e não o DTO, porque o texto válido
   * é o RESULTADO dos dois — exigi-lo no corpo obrigaria a tela a reenviar o que
   * o servidor já tem.
   */
  async forward(consultant: User, code: string, dto: ForwardBarterDto): Promise<BarterDetail> {
    const barter = await this.requireBarter(consultant, code, BARTER_ACTION.forward);

    // O texto do corpo VENCE o gravado: quem escreveu agora escreveu por último.
    const note = (dto.note ?? barter.consultantNote ?? '').trim();
    if (note.length < MIN_OPINION_LENGTH) {
      throw new UnprocessableEntityException(
        `Escreva o seu parecer sobre esta negociação (mínimo de ${MIN_OPINION_LENGTH} caracteres) antes de encaminhar ao gerente`,
      );
    }

    // O DESTINATÁRIO. O cadastro do consultor exige um gerente, então isto só
    // acontece quando o gerente dele foi excluído depois — e nesse caso a
    // permuta seguiria endereçada a ninguém: ficaria em `sentToManager` para
    // sempre, sem erro e sem a quem cobrar. Melhor recusar aqui, com o rascunho
    // intacto para ser encaminhado quando o admin designar alguém.
    const manager =
      consultant.managerId === null
        ? null
        : await this.prisma.user.findUnique({ where: { id: consultant.managerId } });
    if (!manager) {
      throw new UnprocessableEntityException(
        'Você está sem gerente designado — fale com o administrador antes de encaminhar permutas',
      );
    }

    // Sem trilha de AUDITORIA, como no registro: encaminhar não decide dinheiro,
    // e a linha do tempo da permuta já guarda quem encaminhou, quando e o quê.
    // Os três atos que entram na trilha global são os que decidem — ver
    // AUDIT_ACTION.
    return this.applyStep(
      barter,
      BARTER_ACTION.forward,
      consultant,
      BARTER_STATUS.sentToManager,
      {
        consultantNote: note,
        consultantSentAt: new Date(),
        managerId: manager.id,
        managerName: manager.fullName,
      },
      note,
    );
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
    // A POSSE — "esta permuta é do time deste gerente?" — não está aqui porque
    // deixou de precisar estar: ela É o escopo de leitura do gerente
    // (`managerId`), e `requireBarter` já a confere junto com o de todo mundo.
    // Enquanto foram duas regras, a de leitura e esta, elas podiam divergir —
    // e foi assim que a mesma pergunta passou a ter dois donos no arquivo.
    const barter = await this.requireBarter(manager, code, BARTER_ACTION.opinion);

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
    const barter = await this.requireBarter(committee, code, BARTER_ACTION.review);

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
      // O DESFECHO escrito pela máquina de estados, e não por um ternário aqui:
      // a terceira saída (a ressalva) nasceu justamente onde havia um "aprovada
      // ou negada" escrito à mão, e ela teria entrado na trilha como "negada".
      detail: `${(outcomeLabelOf(BARTER_ACTION.review, dto.status) ?? dto.status).toLowerCase()}${
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
    const barter = await this.requireBarter(biller, code, BARTER_ACTION.invoice);

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
   * A MESA DA CÉDULA — tudo o que a tela do faturista precisa, de uma vez: o
   * rascunho gravado, o que a permuta já responde, quem é a credora, a sugestão
   * de preenchimento e o que ainda falta.
   *
   * Numa requisição só, e de propósito: o formulário da CPR mistura as três
   * fontes do documento (ver cpr.ts), e montá-lo com uma chamada por fonte
   * deixaria a tela desenhar campos vazios enquanto a sugestão não chega — que é
   * exatamente o instante em que alguém começa a digitar o que já existia.
   *
   * QUANDO ela pode ser preenchida: a permuta precisa estar dentro do alcance do
   * faturista, e é `scopeFor` quem responde isso (aprovada ou já faturada, via
   * `lineFrom(invoice)`). Repare que a cédula continua editável DEPOIS do
   * faturamento — não é contradição com "não existe desfaturar": a permuta está
   * fechada e continua fechada; o que se corrige aqui é um documento que ainda
   * não foi emitido. O faturamento é o ato; a cédula é papel que vem depois.
   */
  async cprFor(biller: User, code: string): Promise<CprDesk> {
    // O MESMO acesso do detalhe, e pela mesma porta: uma permuta que não abre
    // pelo código não abre a cédula. Duas regras de escopo respondendo à mesma
    // pergunta é uma a mais do que se mantém em dia — ver `requireBarter`.
    const barter = await this.findFor(biller, code);
    const cpr = await this.loadCpr(barter.id);

    const producer = barter.producerId
      ? await this.prisma.producer.findUnique({ where: { id: barter.producerId } })
      : null;

    return {
      cpr,
      known: this.knownOf(
        barter,
        producer?.document ?? '',
        cpr?.sackWeightKg ?? EMPTY_CPR.sackWeightKg,
      ),
      // A credora vem do CADASTRO (ver creditor/), e é o serializer quem calcula
      // as pendências dela — assim a mesa da cédula e a tela de cadastro dizem
      // exatamente a mesma coisa sobre o que falta.
      creditor: await this.creditor.get(),
      gaps: cprGaps(cpr ?? EMPTY_CPR, cpr?.areas ?? []),
      // A sugestão só faz sentido enquanto NÃO há rascunho: depois que o
      // faturista escreveu, o que está na tela é dele, e oferecer por cima o
      // texto de uma cédula antiga é a maneira mais fácil de sobrescrever uma
      // correção que alguém acabou de fazer.
      suggestion: cpr ? {} : suggestFrom(producer, await this.previousCpr(barter.producerId)),
    };
  }

  /**
   * GRAVA o preenchimento — inteiro ou pela metade, como ele estiver.
   *
   * É um `upsert`: a primeira gravação cria a cédula da permuta, as seguintes
   * corrigem. Campo ausente no payload fica COMO ESTAVA — o formulário salva o
   * que a pessoa mexeu, e um "salvar" que apagasse o que não foi enviado
   * transformaria cada tela parcial numa perda de dados.
   *
   * `areas` é a exceção, e é explícita: mandar a lista SUBSTITUI as lavouras.
   * Ela é uma lista editada como um todo na tela (acrescenta-se a segunda área,
   * remove-se a que estava errada), e mesclar por posição faria "apaguei a
   * primeira" virar "editei a primeira e a segunda sumiu".
   */
  async saveCpr(biller: User, code: string, dto: SaveCprDto): Promise<CprDesk> {
    const barter = await this.findFor(biller, code);
    const { areas, guarantors, issuedAt, dueDate, ...fields } = dto;

    // Datas chegam como texto ISO (é o que o DTO valida) e viram Date aqui. A
    // ausência do campo e o `null` são coisas DIFERENTES: a primeira mantém o
    // que está gravado, e a segunda... também — apagar um vencimento já escrito
    // não é operação que um formulário de rascunho precise oferecer, e a
    // maneira de corrigi-lo é escrever o certo por cima.
    const dates = {
      ...(issuedAt ? { issuedAt: new Date(issuedAt) } : {}),
      ...(dueDate ? { dueDate: new Date(dueDate) } : {}),
    };

    const written = { ...fields, ...dates, filledBy: biller.fullName, filledById: biller.id };

    await this.prisma.$transaction(async (tx) => {
      const saved = await tx.barterCpr.upsert({
        where: { barterId: barter.id },
        create: { barterId: barter.id, ...written },
        update: written,
      });

      // Os AVALISTAS seguem a mesma regra das lavouras — lista inteira
      // substitui, ausência preserva —, e pelo mesmo motivo: são editados como
      // um todo na tela e não têm identidade fora da cédula.
      if (guarantors) {
        await tx.cprGuarantor.deleteMany({ where: { cprId: saved.id } });
        for (const [position, guarantor] of guarantors.entries()) {
          await tx.cprGuarantor.create({ data: { cprId: saved.id, position, ...guarantor } });
        }
      }

      if (!areas) return;
      // Apagar e recriar, e não casar linha a linha: as lavouras não têm
      // identidade fora da cédula (ninguém aponta para uma matrícula daqui), e
      // o `Cascade` leva os proprietários junto. A alternativa — diferenciar
      // por id — pediria que a tela devolvesse ids que ela não tem motivo para
      // guardar.
      await tx.cprArea.deleteMany({ where: { cprId: saved.id } });
      for (const [position, area] of areas.entries()) {
        await tx.cprArea.create({
          data: {
            cprId: saved.id,
            position,
            locality: area.locality,
            city: area.city,
            areaHa: area.areaHa,
            withinLargerArea: area.withinLargerArea ?? false,
            registryNumber: area.registryNumber,
            registryBook: area.registryBook,
            registryDistrict: area.registryDistrict,
            owners: {
              create: (area.owners ?? []).map((owner, index) => ({
                position: index,
                name: owner.name,
                document: owner.document,
              })),
            },
          },
        });
      }
    });

    const desk = await this.cprFor(biller, code);
    await this.audit.record({
      actor: biller,
      action: AUDIT_ACTION.barterCprSaved,
      targetType: 'barter',
      targetId: barter.id,
      targetLabel: barter.code,
      // O QUE FALTA no lugar do que foi escrito: a trilha não é o backup do
      // formulário (o conteúdo está na cédula, que é lida por quem a abre), e
      // despejar aqui a qualificação civil de um produtor espalharia dado
      // pessoal por um registro que ninguém apaga. O que ela precisa dizer é
      // que a cédula foi mexida, por quem, e em que pé ela ficou.
      detail:
        `CPR ${desk.cpr?.number || 'sem número'} — ` +
        (desk.gaps.length === 0 ? 'completa' : `faltam ${desk.gaps.length} campo(s)`),
    });
    return desk;
  }

  /** A cédula da permuta com as lavouras e os donos, na ordem do documento. */
  private loadCpr(barterId: number): Promise<CprWithAreas | null> {
    return this.prisma.barterCpr.findUnique({ where: { barterId }, include: CPR_INCLUDE });
  }

  /**
   * A ÚLTIMA cédula deste produtor, de qualquer outra permuta — a fonte da
   * sugestão de preenchimento.
   *
   * Ela é buscada pelo PRODUTOR, e não pelo consultor ou pela unidade, porque o
   * que se repete é a pessoa: nacionalidade, RG, endereço, cônjuge e as
   * matrículas das lavouras são dele, e não da negociação. Ver `suggestFrom`.
   */
  private async previousCpr(producerId: number | null): Promise<CprWithAreas | null> {
    if (!producerId) return null;
    return this.prisma.barterCpr.findFirst({
      where: { barter: { producerId } },
      orderBy: { updatedAt: 'desc' },
      include: CPR_INCLUDE,
    });
  }

  /** O que a cédula tira da permuta — o item de grão é quem carrega os números. */
  private knownOf(barter: BarterWithItems, document: string, sackWeightKg: number): CprKnown {
    return knownFrom(
      barter,
      barter.items.find((item) => item.kind === 'grain'),
      document,
      sackWeightKg,
    );
  }

  /**
   * A permuta pronta para receber um ato — ou o erro que explica por que não.
   *
   * As duas perguntas que TODA etapa faz, no mesmo lugar e na mesma ordem: ela
   * existe? e ela está no ponto desta etapa? A segunda é da máquina de estados,
   * e é ela quem escreve a mensagem — inclusive a que diz com quem a permuta
   * está parada.
   *
   * A ORDEM DAS TRÊS é o que fecha o vazamento: primeiro "existe?", depois
   * "você enxerga?", só então "está no ponto?". A pergunta do meio é nova e
   * chegou com o escopo do faturista — enquanto ela não existia, a permuta era
   * buscada sem recorte e a recusa CONTAVA o que ele não podia ler: pedir o
   * faturamento de um código qualquer respondia "aguarda o parecer do gerente
   * Fulano", isto é, o estado e o nome de gente de uma etapa que não é dele. A
   * mensagem da etapa é boa; ela só não pode ser a porta dos fundos do escopo.
   *
   * Ela também absorve a posse do gerente. O escopo dele é o próprio time
   * (`managerId`), então "fora do escopo" e "endereçada a outro gerente" são a
   * mesma frase dita de dois jeitos — e é por isso que [_noAccessFor] devolve o
   * texto certo em vez de um "sem acesso" genérico: quem chega ali sabe que a
   * permuta existe e a quem cobrar.
   */
  private async requireBarter(actor: User, code: string, action: BarterAction): Promise<Barter> {
    const barter = await this.prisma.barter.findUnique({ where: { code } });
    if (!barter) throw new NotFoundException('Registro não encontrado.');

    const visible = await this.prisma.barter.count({
      where: { code, ...this.scopeFor(actor) },
    });
    if (visible === 0) throw new ForbiddenException(this.noAccessFor(actor));

    const refusal = refusalFor(action, barter);
    if (refusal) throw new UnprocessableEntityException(refusal);

    return barter;
  }

  /**
   * POR QUE esta permuta não é sua — na língua do escopo de quem perguntou.
   *
   * "Você não tem acesso" é verdade para todo mundo e não ajuda ninguém: para o
   * gerente, o que ele precisa ouvir é que a permuta tem OUTRO destinatário, e é
   * a essa frase que ele reage (ela vira "então não é comigo" em vez de "o
   * sistema está errado"). Ver `scopeFor`, de onde saem os recortes.
   */
  private noAccessFor(user: User): string {
    return can(user, CAPABILITY.bartersReadTeam)
      ? 'Esta permuta foi enviada a outro gerente'
      : 'Você não tem acesso a esta permuta';
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
