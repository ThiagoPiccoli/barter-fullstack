import {
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import type {
  Barter,
  BarterCpr,
  BarterCreditFile,
  BarterInvoice,
  Creditor,
  BarterEvent,
  BarterItem,
  BarterProductRequest,
  CprArea,
  CprAreaOwner,
  CprGuarantor,
  Prisma,
  User,
  VersionGrain,
} from '@prisma/client';
import { AUDIT_ACTION, AuditService } from '../audit/audit.service';
import { PrismaService } from '../prisma/prisma.service';
import {
  AREA_EPSILON,
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
  BARTER_STATUS_LABELS,
  BARTER_STEPS,
  lineFrom,
  outcomeLabelOf,
  refusalFor,
  requirementsOf,
  stageOf,
  type BarterAction,
  type BarterStatus,
  type ReviewRequirement,
} from './barter-workflow';
import { taxRateOf, type TaxRegime } from './tax-regime';
import {
  CHANGE_REQUEST_ACTION,
  CHANGE_REQUEST_STATUS,
  CLEARED_BY_CHANGE,
  RESOLVED_REQUEST,
  changeDecisionRefusal,
  changeRequestRefusal,
  cultureRefusal,
  itemPriceRefusal,
  priceChangeRefusal,
  type BarterCulture,
  type ChangeRequestAction,
} from './change-request';
import {
  PRODUCT_REQUEST_ACTION,
  PRODUCT_REQUEST_STATUS,
  offBarterCost,
  productDecisionRefusal,
  productRequestRefusal,
  type GrantedRequest,
  type ProductRequestAction,
} from './product-request';
import {
  EMPTY_CPR,
  consultantCprGaps,
  cprGaps,
  knownFrom,
  pledgeReadingOf,
  suggestFrom,
  type CprContext,
  type CprKnown,
  type CprPledge,
  type CprPledgeReading,
} from './cpr';
import {
  CREDIT_FILE_KIND,
  CREDIT_FILE_LABELS,
  creditFileRefusal,
  type CreditFileKind,
} from './credit-file';
import { creditorGaps } from '../common/creditor';
import { Paginated, windowOf } from '../common/pagination';
import { CAPABILITY, can } from '../common/policy';
import { ROLE } from '../common/roles';
import { CreditorService } from '../creditor/creditor.service';
import { InsuranceService } from '../insurance/insurance.service';
import {
  INSURANCE_UNIT,
  MISSING_CITY_REFUSAL,
  insuranceCostFor,
  insuranceItemNameOf,
  missingRateRefusal,
} from '../insurance/insurance-rate';
import { SeasonsService, type VersionWithPrices } from '../seasons/seasons.service';
import { countsAsRealized } from '../seasons/version-progress';
import {
  AttachCreditFileDto,
  AttachInvoiceDto,
  BarterInputDto,
  BarterOpinionDto,
  ChangeBarterPricesDto,
  CreateBarterDto,
  DecideBarterChangeDto,
  DecideBarterProductDto,
  ForwardBarterDto,
  InvoiceBarterDto,
  ListBartersQuery,
  MIN_OPINION_LENGTH,
  ReplaceBarterInputsDto,
  RequestBarterChangeDto,
  RequestBarterProductDto,
  ReviewBarterDto,
  SaveBarterNoteDto,
} from './dto/barter.dto';
import { IssueCprDto, RegisterCprDto, SaveCprDto, SignCprDto } from './dto/cpr.dto';

/**
 * O ARQUIVO SEM OS BYTES — nome, tipo, tamanho e quem anexou.
 *
 * É o que toda leitura que não é download carrega. O `content` é `Bytes` e viria
 * junto em qualquer `include` que não o excluísse de propósito: a listagem de
 * permutas puxaria os PDFs de todas as notas de todas elas para desenhar uma
 * tabela. Escrito uma vez aqui porque é lido de três lugares (a listagem, o
 * detalhe e a mesa da cédula), e uma cópia que esquecesse de tirar o conteúdo
 * não daria erro — daria uma resposta de dez megabytes.
 */
const FILE_META = {
  id: true,
  fileName: true,
  contentType: true,
  size: true,
  uploadedBy: true,
  uploadedAt: true,
} as const satisfies Prisma.BarterFileSelect;

/** O anexo como as telas o leem: tudo menos os bytes. */
export type FileMeta = Prisma.BarterFileGetPayload<{ select: typeof FILE_META }>;

/** Uma nota fiscal com o anexo dela (sem o conteúdo). */
export type InvoiceWithFile = BarterInvoice & { file: FileMeta | null };

/** Uma peça do dossiê do comitê com o anexo dela (sem o conteúdo). */
export type CreditFileWithFile = BarterCreditFile & { file: FileMeta | null };

/**
 * QUANTO pode pesar um anexo. Dez megabytes cobre com folga um DANFE em PDF, o
 * XML da nota e um SCR de várias páginas — e recusa, antes de o arquivo subir
 * inteiro, a foto de 40 MB tirada do celular contra a tela do computador, que é
 * o caso real que enche um banco de dados.
 *
 * O limite mora na REQUISIÇÃO (é o multer quem o aplica) e não numa coluna: o
 * custo que ele controla é o de receber, não o de guardar.
 */
export const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024;

/**
 * O QUE SE ACEITA como anexo — os formatos em que nota fiscal e SCR de fato
 * chegam.
 *
 * É uma LISTA DE PERMITIDOS, e não uma de proibidos, pelo motivo de sempre: o
 * formato que ninguém previu entra por omissão na segunda. O XML está aqui
 * porque a nota fiscal eletrônica É o XML — o PDF é a representação dela.
 */
export const ALLOWED_ATTACHMENT_TYPES: readonly string[] = [
  'application/pdf',
  'application/xml',
  'text/xml',
  'image/png',
  'image/jpeg',
];

/**
 * A EXTENSÃO como segunda opinião, quando o tipo declarado não diz nada.
 *
 * O `Content-Type` de um multipart é dito por quem envia, e quem envia às vezes
 * não sabe: o Chrome manda `application/octet-stream` para todo arquivo cujo
 * tipo o sistema não resolveu — inclusive um PDF perfeitamente comum, escolhido
 * pelo seletor de arquivos. Recusá-lo pelo cabeçalho seria recusar o documento
 * certo por uma informação que nunca foi confiável.
 *
 * Então a conferência passa a ser: o tipo declarado vale se for reconhecido; se
 * for GENÉRICO, vale a extensão do nome. O que continua não passando é o
 * arquivo que erra nos DOIS — o `.exe` arrastado por engano.
 *
 * Nada disto é trava de segurança, e vale repetir: o conteúdo nunca é executado
 * nem interpretado por este servidor, e sai como `attachment`. O que a lista
 * evita é o engano honesto.
 */
const EXTENSION_TYPES: Record<string, string> = {
  pdf: 'application/pdf',
  xml: 'application/xml',
  png: 'image/png',
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
};

/**
 * Os tipos que significam "não sei": é com eles que o navegador preenche o
 * cabeçalho quando o sistema operacional não resolveu a extensão.
 */
const UNKNOWN_TYPES: readonly string[] = ['', 'application/octet-stream', 'binary/octet-stream'];

/**
 * O TIPO REAL do anexo — o declarado, ou o que a extensão diz quando ele não
 * diz nada. `null` quando nem um nem outro é aceitável.
 */
export function attachmentTypeOf(fileName: string, declared: string): string | null {
  const type = declared.trim().toLowerCase();
  if (ALLOWED_ATTACHMENT_TYPES.includes(type)) return type;
  if (!UNKNOWN_TYPES.includes(type)) return null;

  const extension = fileName.split('.').pop()?.toLowerCase() ?? '';
  return EXTENSION_TYPES[extension] ?? null;
}

/**
 * O ARQUIVO COMO ELE CHEGA da requisição — o pedaço de `Express.Multer.File` de
 * que este service precisa.
 *
 * É um tipo próprio, e não `Express.Multer.File`, para o domínio não depender do
 * transporte: um anexo que um dia venha de outro lugar (um e-mail, uma
 * integração) continua entrando por aqui sem inventar um objeto de multer só
 * para atravessar a porta.
 */
export interface UploadedAttachment {
  originalname: string;
  mimetype: string;
  size: number;
  buffer: Buffer;
}

/** O arquivo guardado, COM os bytes — o que um download devolve. */
export interface StoredFile {
  fileName: string;
  contentType: string;
  size: number;
  content: Buffer | Uint8Array;
}

/**
 * A CULTURA da permuta, do ponto de vista da CÉDULA: o nome da gestão, o grão
 * que a paga e o vencimento da entrega daquele grão.
 *
 * Os três viajam juntos porque a cédula os usa juntos — o vencimento é o dado, e
 * os dois nomes são o endereço da pendência quando ele falta ("defina-o na
 * cultura soja, no lançamento do Barter").
 */
type CprCulture = {
  seasonName: string;
  grainName: string;
  cprDueDate: Date | null;
};

type BarterWithItems = Barter & {
  items: BarterItem[];
  productRequests: BarterProductRequest[];
  invoices: InvoiceWithFile[];
};

/**
 * A permuta com a LINHA DO TEMPO e o DOSSIÊ junto — a forma do detalhe.
 *
 * O dossiê do comitê entra aqui, e não no `include` da listagem, pelo mesmo
 * motivo dos eventos: ele é trajetória da análise, não estado da permuta — e
 * carregar os anexos de cinquenta permutas para desenhar cinquenta linhas de
 * tabela é trabalho jogado fora. Quem o serializa só o entrega a quem pode
 * abri-lo (ver `bartersCreditRead`).
 */
type BarterDetail = BarterWithItems & {
  events: BarterEvent[];
  creditFiles: CreditFileWithFile[];
};

/**
 * O `include` da LISTAGEM: os itens e os pedidos de fora do Barter.
 *
 * Os pedidos vão junto na lista, e não só no detalhe como a linha do tempo,
 * porque eles são ESTADO e não trajetória: uma permuta com pedido em aberto
 * espera alguém, e a fila do admin é uma lista — descobrir isso abrindo permuta
 * por permuta é a tela que este pedido existe para não precisar.
 */
const BARTER_INCLUDE = {
  items: true,
  productRequests: { orderBy: { id: 'asc' } },
  // AS NOTAS do faturamento vão junto pelo mesmo motivo dos pedidos: elas são
  // ESTADO. "Esta permuta já tem nota?" é o que a fila do faturista pergunta, e
  // o que a cédula precisa saber para poder ser emitida.
  //
  // O ARQUIVO vem por `select`, e sem o `content`: os bytes do PDF não podem
  // viajar numa listagem de cinquenta permutas para desenhar cinquenta linhas de
  // tabela. Quem quer o arquivo pede o arquivo (ver `invoiceFile`).
  invoices: {
    orderBy: { id: 'asc' },
    include: { file: { select: FILE_META } },
  },
} as const satisfies Prisma.BarterInclude;

/**
 * O `include` do DETALHE — o da listagem mais a linha do tempo.
 *
 * Ele é a forma de toda resposta que não é lista: o detalhe e o resultado de
 * cada ato. Escrito uma vez pelo motivo de sempre — enquanto foram seis cópias,
 * uma inclusão nova entrava em cinco.
 */
const BARTER_DETAIL_INCLUDE = {
  ...BARTER_INCLUDE,
  events: { orderBy: [{ at: 'asc' }, { id: 'asc' }] },
  // O DOSSIÊ DO COMITÊ, sem os bytes — pelo mesmo motivo das notas: a tela lista
  // os documentos, e quem quer o arquivo pede o arquivo (ver `creditFile`).
  creditFiles: {
    orderBy: { id: 'asc' },
    include: { file: { select: FILE_META } },
  },
} as const satisfies Prisma.BarterInclude;

/** A cédula com as lavouras, os donos delas e os anexos. */
type CprWithAreas = BarterCpr & {
  areas: (CprArea & { owners: CprAreaOwner[] })[];
  guarantors: CprGuarantor[];
  scrFile: FileMeta | null;
  signedFile: FileMeta | null;
  registryFile: FileMeta | null;
};

/** O `include` da cédula, escrito uma vez: leitura e sugestão leem o mesmo. */
const CPR_INCLUDE = {
  areas: {
    orderBy: { position: 'asc' },
    include: { owners: { orderBy: { position: 'asc' } } },
  },
  guarantors: { orderBy: { position: 'asc' } },
  // OS ANEXOS sem os bytes, pelo mesmo motivo das notas: a mesa da cédula é uma
  // tela de formulário, e não o download do anexo.
  scrFile: { select: FILE_META },
  signedFile: { select: FILE_META },
  registryFile: { select: FILE_META },
} as const;

/**
 * OS TRÊS ANEXOS DA CÉDULA, pela coluna que guarda cada um.
 *
 * Eles entram em momentos diferentes e por mãos diferentes — o SCR antes da
 * emissão, a cédula assinada no ato de assinar, a via do cartório no registro ou
 * depois dele —, mas a mecânica de guardar é a mesma. Ver `attachToCpr`.
 */
type CprAttachmentColumn = 'scrFileId' | 'signedFileId' | 'registryFileId';

/** Como cada anexo é chamado numa frase de recusa, em pt-BR. */
const CPR_ATTACHMENT_LABEL: Record<CprAttachmentColumn, string> = {
  scrFileId: 'o SCR do produtor anexado',
  signedFileId: 'a cédula assinada anexada',
  registryFileId: 'o comprovante do registro anexado',
};

/**
 * A MESA DA CÉDULA: o rascunho, o que a permuta já responde, quem é a credora e
 * o que ainda falta. É o que a tela precisa para desenhar o formulário inteiro
 * numa requisição só.
 *
 * ELA SERVE A TRÊS PESSOAS, e é por isso que `gaps` continua sendo uma lista de
 * frases e não um mapa de campos: o consultor a lê para saber o que preencher, o
 * emissor para saber se dá para emitir, e o admin para saber a quem cobrar.
 */
interface CprDesk {
  cpr: CprWithAreas | null;
  known: CprKnown;
  creditor: Creditor;
  gaps: string[];
  /**
   * O RECORTE DO CONSULTOR — o que trava o encaminhamento ao gerente.
   *
   * Sai ao lado de `gaps` (que é a lista inteira, de todos os postos) porque
   * responde outra pergunta: `gaps` é "falta o que para o documento sair", e
   * esta é "falta o que para esta permuta andar". A tela do detalhe mostra o
   * aviso com ela, e o portão do `forward` recusa com ela — a mesma função nos
   * dois lugares, senão o aviso diz uma coisa e a recusa diz outra.
   */
  consultantGaps: string[];
  /**
   * O PENHOR MEDIDO: quanto de área a permuta exige, quanto as lavouras somam e
   * quanto falta.
   *
   * Ele sai ao lado das pendências, e não dentro delas, porque responde a outra
   * pergunta. `consultantGaps` diz O QUE FAZER ("faltam 12,40 ha"); isto é o
   * PLACAR que a tela desenha enquanto a pessoa acrescenta matrículas, e que
   * continua útil depois de a exigência ser cumprida — a lacuna some quando fecha,
   * o placar continua mostrando por quanto fechou.
   */
  pledge: CprPledgeReading;
  /**
   * O QUE MERECE UMA CONFERIDA, sem travar nada — ver `pledgeWarningsFor`.
   *
   * Lista separada de `gaps` de propósito: o portão do encaminhamento lê `gaps`,
   * e uma suspeita não pode recusar ato nenhum.
   */
  pledgeWarnings: string[];
  suggestion: ReturnType<typeof suggestFrom>;
}

/** Quanto de um texto longo cabe numa linha da trilha sem afogá-la. */
const AUDIT_DETAIL_LIMIT = 180;

/**
 * AS SACAS que a permuta deve — a quantidade da linha de grão.
 *
 * Função, e não `items.find(...)?.quantity ?? 0` espalhado: ela é lida pelo
 * penhor, pela cédula e pelo comprovante, e `0` para a permuta sem linha de grão
 * (as anteriores ao item de pagamento) é uma decisão, não um acidente — ver
 * `repriceGrain`, que sai intacto pelo mesmo motivo.
 */
function sacksOf(items: { kind: string; quantity: number }[]): number {
  return items.find((item) => item.kind === 'grain')?.quantity ?? 0;
}

/**
 * A MATRÍCULA reduzida ao que o cartório reconhece: só os dígitos.
 *
 * É a mesma ideia de `Producer.documentDigits`, e pela mesma razão — comparar o
 * texto cru deixaria "12.345" e "12345" passarem como imóveis diferentes, que é
 * exatamente o caso que o aviso de penhor em dobro existe para encontrar. Aqui a
 * normalização NÃO vira coluna: ela serve a um aviso, não a uma unicidade, e uma
 * coluna pediria migração de dados para salvar uma comparação que roda ao abrir
 * uma tela.
 */
function registryKeyOf(registryNumber: string): string {
  return registryNumber.replace(/\D/g, '');
}

/**
 * O ITEM que um pedido atendido vira dentro da permuta.
 *
 * Em um lugar só porque ele nasce em DOIS momentos: quando o admin atende o
 * pedido (`decideProduct`) e de novo a cada remontagem do rascunho
 * (`replaceInputs`), que apaga os itens e recria a lista inteira. Os dois
 * precisam produzir o mesmo item — inclusive a marca de fora do Barter, que é
 * o que explica, no comprovante, um valor que não está em tabela nenhuma.
 *
 * `productId` null e `offBarter` true: ver o campo no schema.
 */
function offBarterItemOf(
  request: GrantedRequest,
): Prisma.BarterItemUncheckedCreateWithoutBarterInput {
  return {
    productId: null,
    kind: 'input',
    productName: request.productName,
    productSku: request.sku,
    unit: request.unit,
    quantity: request.quantity,
    unitValue: request.unitValue ?? 0,
    offBarter: true,
    requestId: request.id,
  };
}

/**
 * O TEXTO DA DECISÃO com as exigências por escrito no fim.
 *
 * Elas entram no EVENTO — não nas colunas, que já as guardam — porque a linha
 * do tempo é o que sobrevive a uma alteração: o aceite de um pedido devolve a
 * permuta a rascunho e apaga a decisão atual, exigências inclusive (ver
 * `CLEARED_BY_CHANGE`). Sem isto, "o que o comitê exigiu da primeira vez?"
 * deixaria de ter resposta assim que a permuta fosse decidida de novo.
 *
 * Por extenso, e não como três letras: quem lê a linha do tempo é gente, e o
 * texto precisa continuar legível daqui a dois anos, num app que talvez já não
 * desenhe caixa nenhuma.
 */
function noteWithRequirements(
  note: string | null,
  requirements: Partial<Record<ReviewRequirement, boolean>>,
): string | null {
  const required = requirementsOf(requirements);
  if (required.length === 0) return note;

  const line = `Exigências: ${required.join(', ')}.`;
  return note ? `${note}\n${line}` : line;
}

/**
 * A COTAÇÃO DO SEGURO desta permuta: a praça e a taxa dela.
 *
 * Tipo próprio, e não o registro do cadastro (`InsuranceRate`), porque o que a
 * permuta usa é só isto — e porque a permuta CONGELA os dois valores. Passar o
 * registro inteiro adiante convidaria alguém a ler dele, um dia, um campo que
 * muda depois (o `updatedAt`, a observação do admin) dentro de uma conta que
 * precisa ser a do dia do registro.
 */
interface InsuranceQuote {
  city: string;
  ratePerHa: number;
}

/**
 * A COTAÇÃO CONGELADA numa permuta já registrada — `null` quando ela não tem
 * seguro.
 *
 * É por aqui que a remontagem do rascunho recria a linha com a taxa do DIA DO
 * REGISTRO (ver `replaceInputs`). A pergunta é feita à taxa, e não ao município:
 * `insuranceCity` pode estar preenchido num registro cuja base foi corrigida
 * depois, e é o número que paga a apólice.
 */
function insuranceOf(barter: Barter): InsuranceQuote | null {
  return barter.insuranceRatePerHa > 0
    ? { city: barter.insuranceCity, ratePerHa: barter.insuranceRatePerHa }
    : null;
}

/**
 * A LINHA DO SEGURO dentro da permuta.
 *
 * Em um lugar só porque ela nasce em DOIS momentos, como o item de fora do
 * Barter: no registro e de novo a cada remontagem do rascunho
 * (`replaceInputs`), que apaga os itens e recria a lista inteira.
 *
 * A CONTA FICA LEGÍVEL NA PRÓPRIA LINHA: `quantity` é a área cultivável (ha) e
 * `unitValue` é a taxa do município. É o que permite ao produtor conferir o
 * valor lendo o comprovante — 1.200 ha × R$ 85,00 —, em vez de receber um
 * número fechado cuja origem está em outro lugar.
 *
 * `kind: 'input'` com `insurance: true`: ver o campo no schema. O seguro forma
 * custo como tudo o mais que a empresa adianta, e é a marca — não o `kind` —
 * que diz que esta linha não se separa em balcão nenhum.
 */
function insuranceItemOf(
  quote: InsuranceQuote,
  areaHa: number,
): Prisma.BarterItemUncheckedCreateWithoutBarterInput {
  return {
    productId: null,
    kind: 'input',
    productName: insuranceItemNameOf(quote.city),
    unit: INSURANCE_UNIT,
    quantity: areaHa,
    unitValue: quote.ratePerHa,
    insurance: true,
  };
}

/**
 * Um valor em R$ e uma quantidade como a LINHA DO TEMPO os escreve.
 *
 * Em pt-BR, e não em `toFixed`, porque estes dois textos são lidos pelo
 * gerente, pelo comitê e pelo consultor dentro do registro da permuta — ao
 * contrário dos detalhes da trilha de auditoria, que são resumo técnico. "R$
 * 1.200,00" e "R$ 1200.00" dizem a mesma coisa; só uma delas é a língua de quem
 * lê.
 */
const money = (value: number): string =>
  `R$ ${value.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

const quantityText = (value: number): string => value.toLocaleString('pt-BR');

const summarize = (text: string): string =>
  text.length <= AUDIT_DETAIL_LIMIT ? text : `${text.slice(0, AUDIT_DETAIL_LIMIT)}…`;

/**
 * Regras de negócio da permuta. O servidor é a autoridade: preços saem do
 * banco (nunca do cliente), mínimos por hectare e por classe travam a
 * criação, e as sacas do grão são calculadas aqui.
 */
@Injectable()
export class BartersService {
  private readonly logger = new Logger('Barters');

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly seasons: SeasonsService,
    private readonly creditor: CreditorService,
    private readonly insurance: InsuranceService,
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
   * - **o que chegou à emissão** (emissor): um degrau adiante do anterior — as
   *   faturadas e o que já andou na cédula. Ver `bartersReadIssuance`;
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
      return {
        OR: [
          { status: { not: BARTER_STATUS.draft } },
          { consultantId: user.id },
          // O RASCUNHO QUE PEDIU ALGUMA COISA — a exceção da exceção, e só para
          // quem tem o pedido na mesa.
          //
          // Um rascunho não é fila de ninguém, MENOS quando ele próprio bateu na
          // porta: o consultor está montando a permuta, falta um item que a
          // tabela não tem, e quem pode incluí-lo é o admin (ver
          // `product-request.ts`). Sem isto o pedido nasceria invisível para o
          // único que pode atendê-lo — e o consultor ficaria esperando resposta
          // de alguém que nunca viu a pergunta.
          //
          // Qualquer pedido, e não só o em aberto: a permuta continua visível
          // DEPOIS de decidida, porque foi este admin que escreveu o valor de um
          // item dela. Limitado ao `open`, ele perderia de vista, no instante
          // seguinte ao clique, a permuta que acabou de precificar.
          //
          // O comitê NÃO entra por aqui: ele também tem `bartersReadAll`, e o
          // rascunho continua sendo o que sempre foi para ele — um negócio que
          // ainda não foi proposto.
          ...(can(user, CAPABILITY.bartersProductReview)
            ? [{ productRequests: { some: {} } }]
            : []),
        ],
      };
    }
    if (can(user, CAPABILITY.bartersReadTeam)) return { managerId: user.id };
    if (can(user, CAPABILITY.bartersReadInvoicing)) {
      return { status: { in: lineFrom(BARTER_ACTION.invoice) } };
    }
    if (can(user, CAPABILITY.bartersReadIssuance)) {
      return { status: { in: lineFrom(BARTER_ACTION.cprIssue) } };
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
        include: BARTER_INCLUDE,
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
      include: BARTER_DETAIL_INCLUDE,
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

    // 1.5. A CULTURA escolhida pelo consultor, entre as que este lançamento
    //      aceita. É a primeira decisão da permuta: ela define a cotação que
    //      converte o custo em sacas, a produtividade que dimensiona o penhor e
    //      o vencimento da cédula. A recusa nomeia o que ESTÁ aberto, porque é
    //      isso que o consultor precisa saber para escolher de novo.
    const grain = version.grains.find((row) => row.grainId === dto.grainId);
    if (!grain) {
      const open = version.grains.map((row) => row.grainName).join(' e ');
      throw new UnprocessableEntityException(
        `O Barter ${version.code} não aceita essa cultura. Ele paga em ${open || 'nenhuma cultura'}`,
      );
    }
    if (grain.price <= 0) {
      throw new UnprocessableEntityException(
        `O Barter ${version.code} está sem valor para a saca de ${grain.grainName}`,
      );
    }
    // E SEM PRODUTIVIDADE ESTIMADA TAMBÉM NÃO SE PERMUTA — o portão gêmeo do de
    // cima, e pelo mesmo motivo.
    //
    // A cotação da saca é o que converte custo em dívida; a produtividade é o que
    // converte a dívida em ÁREA DE GARANTIA. Faltando ela, a permuta entraria na
    // esteira com um penhor que ninguém sabe dimensionar — e a descoberta
    // aconteceria lá na frente, com o insumo já retirado, que é exatamente o custo
    // que o dimensionamento existe para evitar.
    //
    // A recusa é AQUI, e não no encaminhamento, porque aqui ela é grátis: a
    // permuta ainda não existe, ninguém digitou cédula nenhuma, e quem resolve é
    // o admin em um campo só. É também por causa dela que `pledgeYield` 0 pode
    // significar "permuta antiga" sem ambiguidade — ver o campo no schema.
    if (grain.estimatedYield <= 0) {
      throw new UnprocessableEntityException(
        `O Barter ${version.code} está sem produtividade estimada de ${grain.grainName} — ` +
          `sem ela não há como dimensionar a área do penhor. Peça ao administrador para informá-la no lançamento`,
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

    // 3.5. O SEGURO, quando o Barter desta versão leva seguro: a taxa da praça
    //      do produtor, cotada agora e congelada no registro. A recusa por praça
    //      sem taxa acontece AQUI, pelo mesmo motivo da recusa por versão sem
    //      produtividade — aqui ela é grátis.
    const insurance = await this.insuranceFor(version, producer);

    // 4, 5 e 6 — a precificação e as travas — em um lugar só, porque a
    // ALTERAÇÃO de um rascunho passa exatamente pelas mesmas (ver
    // `replaceInputs`): mudar um insumo é refazer a permuta inteira contra as
    // mesmas regras, e duas cópias delas divergiriam no primeiro ajuste.
    const items = await this.pricedItemsFor(version, grain, producer, dto.inputs, [], insurance);

    // A FORMA de recolhimento: a do CADASTRO do produtor, que é onde a opção
    // formal dele mora (ver `Producer.taxRegime`). O corpo ainda pode dizer
    // outra — o consultor corrige na hora quando o cadastro está atrasado —, e
    // a ausência não é mais um chute: é o que está registrado sobre ele.
    const taxRegime = dto.taxRegime ?? (producer.taxRegime as TaxRegime);

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
      // O PENHOR congelado: a produtividade desta versão e a margem da credora
      // HOJE. As duas mudam — a próxima versão revê a estimativa, a diretoria
      // revê o apetite de risco —, e lidas na hora de conferir fariam esta
      // permuta passar a exigir mais área do que as lavouras que o consultor já
      // anotou, sem que nada nela tivesse mudado. Mesmo argumento de `taxRate`.
      pledgeYield: grain.estimatedYield,
      pledgeMarginPercent: (await this.creditor.get()).pledgeMarginPercent,
      // O SEGURO congelado: a praça que o precificou e a taxa dela HOJE. Vazio
      // e zero quando o Barter não leva seguro — ver `Barter.insuranceCity`.
      insuranceCity: insurance?.city ?? '',
      insuranceRatePerHa: insurance?.ratePerHa ?? 0,
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
   * O SEGURO DESTA PERMUTA — a praça do produtor e a taxa dela, ou `null`
   * quando o Barter não leva seguro.
   *
   * Quem decide se leva é o LANÇAMENTO (`BarterVersion.insuranceRequired`), e
   * não o consultor nem o produtor: contratar seguro é decisão comercial da
   * safra, e deixá-la permuta a permuta faria o mesmo Barter ser vendido de dois
   * jeitos na mesma praça, no mesmo dia, conforme quem atendeu.
   *
   * AS DUAS RECUSAS são o ponto deste método, e elas acontecem no REGISTRO de
   * propósito — o lugar mais barato para elas: a permuta ainda não existe,
   * ninguém retirou nada, e quem resolve é o admin num campo de cadastro. A
   * alternativa seria deixar a permuta nascer sem a linha do seguro, e aí o que
   * se descobre semanas depois é uma permuta sem seguro dentro de uma safra que
   * tem seguro — com o insumo já na fazenda.
   *
   * Elas dizem coisas DIFERENTES porque mandam fazer coisas diferentes: falta a
   * praça na base de seguros, ou falta o município no cadastro do produtor. Ver
   * `insurance-rate.ts`, onde as duas frases moram.
   */
  private async insuranceFor(
    version: VersionWithPrices,
    producer: { city: string | null; areaHa: number },
  ): Promise<InsuranceQuote | null> {
    if (!version.insuranceRequired) return null;

    const city = producer.city?.trim() ?? '';
    if (!city) {
      throw new UnprocessableEntityException(MISSING_CITY_REFUSAL);
    }

    const rate = await this.insurance.rateFor(city);
    if (!rate) {
      throw new UnprocessableEntityException(missingRateRefusal(city));
    }

    // A PRAÇA GRAVADA é a do CADASTRO DA BASE, e não a do produtor: as duas são
    // o mesmo lugar (é o que a chave canônica garante), e a da base é a grafia
    // que o admin escolheu. É ela que sai na linha do comprovante, e ler
    // "Seguro agrícola — maringa / pr" num documento seria expor ao produtor a
    // digitação de outra pessoa.
    return { city: rate.city, ratePerHa: rate.valuePerHa };
  }

  /**
   * OS ITENS DA PERMUTA, precificados pela versão e conferidos contra as regras
   * de mínimo — a linha do grão inclusa, que é o pagamento.
   *
   * É a parte do registro que a ALTERAÇÃO refaz por inteiro, e por isso ela mora
   * aqui e não dentro de `create`: trocar um insumo de um rascunho não é uma
   * edição pontual, é a permuta sendo remontada e submetida às mesmas travas —
   * a exigência por hectare, o mínimo de cada classe e a conversão em sacas.
   * Enquanto isto foi corpo de `create`, o único jeito de alterar uma permuta
   * seria uma segunda cópia das regras, e a primeira divergência entre as duas
   * seria uma permuta gravada fora do que o Barter exige.
   *
   * A VERSÃO é parâmetro, e não lida daqui de dentro, porque quem a escolhe é
   * quem chama: o registro usa a VIGENTE (é ela que diz por quanto se permuta
   * hoje); a alteração usa a DA PERMUTA (o acordo foi fechado nela, e a gestão
   * seguinte não reescreve o que já foi combinado).
   *
   * A CULTURA é parâmetro pelo mesmo motivo, e com uma diferença que importa: no
   * registro ela é a que o consultor ESCOLHEU; na alteração ela é a que a
   * permuta JÁ TEM — lida da linha do grão, com a cotação congelada lá. Trocar a
   * cultura de um rascunho é, por isso, refazer a linha do grão, e não editar um
   * campo: ver `setCulture`.
   *
   * OS ITENS DE FORA DO BARTER entram por `granted`, e entram por um caminho
   * separado de propósito (ver `product-request.ts`): eles somam CUSTO — foram
   * retirados, e as sacas os pagam — e não passam por régua nenhuma. Não têm
   * classe, então nunca somariam no numerador de uma pasta; contá-los no
   * denominador faria um pedido atendido derrubar, na remontagem, uma permuta
   * que cumpria os mínimos antes dele.
   *
   * O SEGURO entra por `insurance`, e pela mesma porta separada e pelo mesmo
   * motivo: ele soma custo (a empresa adianta a apólice, e as sacas a pagam) e
   * não é insumo de classe nenhuma. Fosse ele contado no total que mede as
   * pastas, ligar o seguro no lançamento derrubaria, de uma vez, todas as
   * permutas da praça que cumpriam os mínimos no dia anterior — sem que nenhum
   * consultor tivesse mudado um item sequer.
   */
  private async pricedItemsFor(
    version: VersionWithPrices,
    grain: VersionGrain,
    producer: { areaHa: number },
    inputs: BarterInputDto[],
    granted: GrantedRequest[] = [],
    insurance: InsuranceQuote | null = null,
  ): Promise<Prisma.BarterItemUncheckedCreateWithoutBarterInput[]> {
    // Consolida quantidades por produto (payload pode repetir ids) e as leva à
    // precisão em que serão GRAVADAS. Arredondar aqui, e não só no app, é o que
    // faz o item registrado ser o mesmo número que o comprovante imprime: o app
    // já mandava 2 casas, mas quem manda é este lado, e ele aceitava qualquer
    // precisão de quem chamasse a API direto.
    const quantities = new Map<number, number>();
    for (const item of inputs) {
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

    // 6. Converte o custo em sacas do grão da safra — o coração do escambo. O
    //    que veio de fora do Barter e o SEGURO entram AQUI, e só aqui: os dois
    //    são custo adiantado como qualquer outro, e as sacas pagam a permuta
    //    inteira.
    const insuranceCost = insurance ? insuranceCostFor(producer.areaHa, insurance.ratePerHa) : 0;
    const sacks = sacksToCover(totalCost + offBarterCost(granted) + insuranceCost, grain.price);

    return [
      {
        productId: grain.grainId,
        kind: 'grain',
        productName: grain.grainName,
        // O grão não leva código: quem o identifica é a cultura do lançamento, e
        // o item existe para dizer quantas sacas pagam a permuta — não para ser
        // separado no balcão, que é a pergunta a que o código do insumo responde.
        unit: grain.grainUnit,
        quantity: sacks,
        unitValue: grain.price,
      },
      ...products.map((product) => ({
        productId: product.id,
        kind: 'input',
        productName: product.name,
        // O CÓDIGO congelado junto com o nome: é por ele que o insumo é
        // separado, conferido e faturado, e o cadastro pode ser recodificado
        // (ou o produto excluído) depois. Ver `BarterItem.productSku`.
        productSku: product.sku,
        unit: product.unit,
        quantity: quantities.get(product.id)!,
        unitValue: valueOf.get(product.id)!.price,
      })),
      ...granted.map(offBarterItemOf),
      // A LINHA DO SEGURO, quando há. Ela vem por último de propósito: é a
      // última coisa que o produtor lê no comprovante antes do total, e é lá
      // que ela pertence — não é insumo que ele retira do balcão.
      //
      // Ela só existe com custo maior que zero: área zerada não gera linha
      // (ver `insuranceCostFor`), e uma linha de R$ 0,00 no comprovante seria o
      // documento afirmando um seguro que não foi contratado.
      ...(insurance && insuranceCost > 0 ? [insuranceItemOf(insurance, producer.areaHa)] : []),
    ];
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
    // Os atos do DESVIO e os do PEDIDO DE FORA DO BARTER entram aqui junto com
    // os da esteira, e é a linha do tempo que os une: ela conta o que aconteceu
    // com esta permuta, e um pedido de alteração aconteceu tanto quanto um
    // parecer. Ver `change-request.ts` e `product-request.ts`.
    action: BarterAction | ChangeRequestAction | ProductRequestAction,
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
        include: BARTER_DETAIL_INCLUDE,
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

    // A CÉDULA PREENCHIDA é o segundo portão do encaminhamento, e ele é novo.
    //
    // Ela é coletada AGORA, com o produtor ainda por perto, e não semanas
    // depois — quando o emissor tenta gerar o título e descobre que falta a
    // matrícula de uma lavoura que ninguém anotou, com a permuta já faturada e
    // o insumo já retirado. O custo de voltar atrás cresce a cada posto da
    // esteira, e o encaminhamento é o último momento em que ele é zero.
    //
    // SÓ AS PENDÊNCIAS DELE são cobradas (ver `consultantCprGaps`): a nota
    // fiscal não existe antes do faturamento, o vencimento é da safra e o número
    // da cédula é do emissor. Exigi-los aqui travaria a esteira num impossível.
    await this.requireCprFilledBy(consultant, barter);

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
        'Você está sem gerente designado. Fale com o administrador antes de encaminhar permutas',
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
   * A CÉDULA JÁ TEM O QUE É DO CONSULTOR? — ou o erro que lista o que falta.
   *
   * A mensagem nomeia as primeiras pendências e conta o resto, em vez de
   * despejar as vinte de uma cédula em branco: quem lê isto num alerta precisa
   * saber O QUE fazer, e uma parede de texto vira "deu erro". A lista inteira
   * está na tela da cédula, que é onde ela se resolve — e é para lá que a frase
   * manda ir.
   */
  private async requireCprFilledBy(consultant: User, barter: Barter): Promise<void> {
    const cpr = await this.loadCpr(barter.id);
    // AS SACAS SÃO LIDAS AGORA, e não do que veio com a permuta: este portão
    // confere a garantia contra a dívida que a permuta tem NESTE INSTANTE. Entre
    // o registro e o encaminhamento ela pode ter engordado — um produto de fora
    // do Barter deferido soma custo e a linha do grão é recalculada —, e conferir
    // contra o número antigo aprovaria um penhor que já não cobre.
    const grain = await this.prisma.barterItem.findFirst({
      where: { barterId: barter.id, kind: 'grain' },
      select: { quantity: true },
    });
    const missing = consultantCprGaps(
      cpr ?? EMPTY_CPR,
      cpr?.areas ?? [],
      this.pledgeOf(barter, grain?.quantity ?? 0),
    );
    if (missing.length === 0) return;

    const MOSTRADAS = 4;
    const primeiras = missing.slice(0, MOSTRADAS).join(', ');
    const resto = missing.length - MOSTRADAS;
    throw new UnprocessableEntityException(
      `Preencha a cédula (CPR) desta permuta antes de encaminhá-la ao gerente — ` +
        `falta ${primeiras}${resto > 0 ? ` e mais ${resto} campo(s)` : ''}.`,
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
   * Essa corrida é REAL, e não teórica: sob `READ COMMITTED` — o isolamento
   * padrão do Postgres —, duas transações simultâneas leem o mesmo máximo e
   * escolhem o mesmo número, e com mais de uma instância da API isso deixa de
   * depender de sorte.
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
            include: BARTER_DETAIL_INCLUDE,
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
    // AS EXIGÊNCIAS só sobrevivem na APROVAÇÃO, e são zeradas na negativa: pedir
    // avalista de uma permuta negada é pedir garantia para um negócio que não
    // vai acontecer, e a exigência ficaria pendurada na tela de quem levou a
    // negativa ao produtor. Não é conferência do DTO porque não é erro de quem
    // chama — é o desfecho que decide o que a decisão carrega.
    const requirements = {
      requiresGuarantor: dto.status !== BARTER_STATUS.denied && dto.requiresGuarantor === true,
      requiresCollateral: dto.status !== BARTER_STATUS.denied && dto.requiresCollateral === true,
      requiresInsurance: dto.status !== BARTER_STATUS.denied && dto.requiresInsurance === true,
    };
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
        ...requirements,
      },
      // AS EXIGÊNCIAS ENTRAM NO EVENTO junto com o texto, e não só nas colunas
      // da permuta: a linha do tempo é o que sobrevive a uma alteração (ver
      // `CLEARED_BY_CHANGE`, que apaga a decisão atual quando a permuta volta a
      // rascunho). Sem elas ali, "o que o comitê exigiu da primeira vez?" não
      // teria onde ser respondido depois de a permuta ser decidida de novo.
      noteWithRequirements(note, requirements),
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
        reviewed.reviewNote ? `: ${summarize(reviewed.reviewNote)}` : ''
      }`,
    });

    await this.closeBarterIfGoalReached(committee, reviewed);
    return reviewed;
  }

  /**
   * A APROVAÇÃO PODE ENCERRAR O BARTER — quando a versão pediu isso ao ser
   * publicada (`closeOnGoal`) e esta permuta cruzou a meta.
   *
   * Fica aqui, e não numa rotina de madrugada, porque a aprovação é o único ato
   * que faz o realizado crescer (ver `COUNTS_AS_REALIZED` em
   * version-progress.ts): amarrar o fechamento a ela é o que dá ao Barter fechado
   * uma hora e um ato humano por trás, em vez de um relógio.
   *
   * NÃO derruba a aprovação se falhar, e por isso é uma chamada separada — a
   * mesma escolha da trilha de auditoria (ver `AuditService.record`), e pelo
   * mesmo raciocínio: a decisão do comitê já aconteceu e é o que a permuta
   * precisa. Falhando o fechamento, o Barter continua aberto com a meta batida —
   * que é exatamente o estado do modo manual, com o alerta aceso no painel do
   * admin. O erro vai para o log, e o admin encerra com um toque.
   */
  private async closeBarterIfGoalReached(committee: User, barter: Barter): Promise<void> {
    // Negada não somou nada, e sem soma nova nenhuma meta pode ter acabado de
    // ser batida. A pergunta é feita à mesma lista que a conta usa.
    if (!countsAsRealized(barter.status)) return;
    // Permuta sem versão é registro histórico cuja gestão foi removida do banco
    // (o `versionCode` desnormalizado é o que sobra dela). Não há Barter aberto
    // do outro lado para encerrar.
    if (barter.versionId === null) return;

    try {
      const closed = await this.seasons.closeIfGoalReached(committee, barter.versionId);
      if (closed) {
        this.logger.log(`Barter ${closed.version.code} encerrado — ${closed.reason}`);
      }
    } catch (error) {
      this.logger.error(
        `Falha ao encerrar o Barter da permuta ${barter.code} depois da aprovação`,
        error instanceof Error ? error.stack : undefined,
      );
    }
  }

  /**
   * O FATURAMENTO — o posto mais simples do fluxo, e o que produz as notas.
   *
   * O faturista não avalia nem devolve: ele recebe o que as etapas anteriores
   * produziram (o pedido, o parecer, a decisão — tudo na linha do tempo da
   * permuta) e fatura o que foi APROVADO. Por isso não há aqui nenhuma decisão a
   * tomar, e por isso o único portão é o estado: negada não fatura, e sem
   * decisão do comitê também não.
   *
   * O SEGUNDO PORTÃO é a NOTA, e ele é novo: não se fatura sem ao menos uma nota
   * anexada. A trava parece burocrática e não é — a CPR que vem em seguida cita
   * a nota como ORIGEM DA DÍVIDA (cláusula VII), e uma permuta "faturada" sem
   * nota nenhuma é um faturamento que não aconteceu no mundo, ou que aconteceu e
   * não deixou prova. As duas coisas param a emissão do título alguns dias
   * depois, e aí já é o emissor quem descobre — longe de quem pode resolver.
   *
   * O que ela NÃO faz é travar a correção: notas continuam podendo ser anexadas
   * e removidas DEPOIS do faturamento (ver `attachInvoice`), porque nota
   * cancelada e reemitida é rotina.
   *
   * `invoiced` não é mais fim de linha — o que vem depois é a emissão da cédula,
   * com o emissor. Mas continua não existindo "desfaturar": corrigir faturamento
   * é ato do sistema de nota fiscal, não deste; um botão aqui apagaria o rastro
   * do que já saiu para fora.
   */
  async invoice(biller: User, code: string, dto: InvoiceBarterDto): Promise<BarterDetail> {
    const barter = await this.requireBarter(biller, code, BARTER_ACTION.invoice);

    const invoices = await this.prisma.barterInvoice.count({ where: { barterId: barter.id } });
    if (invoices === 0) {
      throw new UnprocessableEntityException(
        'Anexe ao menos uma nota fiscal antes de faturar — é ela que a cédula cita como origem da dívida',
      );
    }

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
      detail: `faturada com ${invoices} nota(s)${
        invoiced.invoiceNote ? ` — ${summarize(invoiced.invoiceNote)}` : ''
      }`,
    });
    return invoiced;
  }

  /* ── AS NOTAS DO FATURAMENTO ──────────────────────────────────────────── */

  /**
   * ANEXA UMA NOTA FISCAL à permuta — o número, o que ele tem ao lado, e o
   * arquivo.
   *
   * SÃO VÁRIAS, e é o ponto: o produtor retira os insumos em mais de um
   * carregamento, cada retirada sai com a sua nota, e a nota cancelada é
   * reemitida. Enquanto o número foi um campo de texto dentro da cédula, a
   * segunda nota não tinha onde entrar — e a cédula citava uma como origem de
   * uma dívida formada por três.
   *
   * ANTES E DEPOIS do faturamento, de propósito. Antes porque a nota costuma
   * sair primeiro e o faturamento é o carimbo que vem depois dela (`invoice` até
   * exige que haja uma); depois porque nota cancelada e reemitida é rotina, e um
   * sistema que só aceitasse anexo antes do ato empurraria a correção para fora
   * dele. O portão é o ESCOPO: a permuta precisa estar no trecho do faturista.
   *
   * O ARQUIVO E A LINHA nascem na MESMA transação: um anexo gravado sem a nota
   * seria lixo sem dono, e uma nota gravada sem o anexo é justamente o registro
   * sem prova que este modelo existe para não haver.
   */
  async attachInvoice(
    biller: User,
    code: string,
    dto: AttachInvoiceDto,
    file: UploadedAttachment,
  ): Promise<BarterDetail> {
    const barter = await this.visibleBarter(biller, code);
    const contentType = this.requireAttachable(file);

    const number = dto.number.trim();
    await this.prisma.$transaction(async (tx) => {
      const stored = await tx.barterFile.create({
        data: this.fileDataOf(biller, file, contentType),
      });
      await tx.barterInvoice.create({
        data: {
          barterId: barter.id,
          number,
          series: dto.series?.trim() ?? '',
          duplicateNumber: dto.duplicateNumber?.trim() ?? '',
          issuedAt: dto.issuedAt ? new Date(dto.issuedAt) : null,
          value: dto.value ?? 0,
          note: dto.note?.trim() ? dto.note.trim() : null,
          attachedBy: biller.fullName,
          attachedById: biller.id,
          fileId: stored.id,
        },
      });
    });

    await this.audit.record({
      actor: biller,
      action: AUDIT_ACTION.barterInvoiceAttached,
      targetType: 'barter',
      targetId: barter.id,
      targetLabel: barter.code,
      detail: `nota fiscal ${number}${dto.series?.trim() ? `/${dto.series.trim()}` : ''} anexada (${file.originalname})`,
    });
    return this.findFor(biller, code);
  }

  /**
   * REMOVE uma nota anexada — a que foi cancelada, ou a que subiu trocada.
   *
   * Existe porque o erro de anexo é o erro mais comum de todos, e o caminho
   * alternativo seria pedir ao admin que apagasse a linha no banco. O arquivo vai
   * junto (`Cascade` na coluna): ele não tem outra razão de existir.
   *
   * O que ela NÃO faz é desfaturar. Removida a última nota, a permuta continua
   * faturada — e a cédula volta a ter a pendência da origem da dívida, que é a
   * leitura certa: o ato aconteceu, e a prova dele está faltando.
   */
  async removeInvoice(biller: User, code: string, invoiceId: number): Promise<BarterDetail> {
    const barter = await this.visibleBarter(biller, code);

    // Pelo ID DENTRO da permuta: um id de nota de outra permuta não encontra
    // nada por aqui, e a mensagem é a de quem digitou um número que não existe.
    const invoice = await this.prisma.barterInvoice.findFirst({
      where: { id: invoiceId, barterId: barter.id },
    });
    if (!invoice) throw new NotFoundException('Esta permuta não tem a nota que você quer remover');

    await this.prisma.$transaction(async (tx) => {
      await tx.barterInvoice.delete({ where: { id: invoice.id } });
      // O arquivo é apagado DEPOIS da linha e não pelo `Cascade` do banco: o
      // `onDelete: Cascade` mora do lado da nota (apagar o arquivo apaga a nota),
      // e não o contrário. Aqui a ordem é a que o domínio quer.
      if (invoice.fileId !== null) {
        await tx.barterFile.delete({ where: { id: invoice.fileId } });
      }
    });

    await this.audit.record({
      actor: biller,
      action: AUDIT_ACTION.barterInvoiceRemoved,
      targetType: 'barter',
      targetId: barter.id,
      targetLabel: barter.code,
      detail: `nota fiscal ${invoice.number} removida`,
    });
    return this.findFor(biller, code);
  }

  /**
   * O ARQUIVO de uma nota, com os bytes — a única leitura que os carrega.
   *
   * O escopo é o da PERMUTA (`findFor`), e não uma capacidade nova: quem alcança
   * a permuta alcança os documentos dela. É a mesma porta do detalhe, e é o que
   * permite ao emissor conferir a nota que a cédula cita sem que ninguém precise
   * lhe mandar o PDF por e-mail.
   */
  async invoiceFile(viewer: User, code: string, invoiceId: number): Promise<StoredFile> {
    const barter = await this.findFor(viewer, code);
    const invoice = await this.prisma.barterInvoice.findFirst({
      where: { id: invoiceId, barterId: barter.id },
      include: { file: true },
    });
    if (!invoice?.file) {
      throw new NotFoundException('Esta nota não tem arquivo anexado');
    }
    return invoice.file;
  }

  /* ── O DOSSIÊ DO COMITÊ: o que fundamenta a decisão de crédito ────────── */

  /**
   * ANEXA UMA PEÇA DA ANÁLISE DE CRÉDITO — a consulta ao Serasa, o extrato do
   * endividamento do produtor dentro da cooperativa, a certidão que a reunião
   * pediu.
   *
   * Quem anexa é o COMITÊ (`barters.creditAttach`), e a janela vai até a decisão
   * (ver `creditFileRefusal`): o dossiê existe para DECIDIR, e juntar uma
   * consulta a uma permuta já aprovada seria acrescentar fundamento a uma
   * decisão tomada — um documento que parece ter sido lido e não foi.
   *
   * O ARQUIVO E A LINHA nascem na MESMA transação, como na nota fiscal: um anexo
   * sem dono é lixo, e uma peça sem documento é o e-mail de volta.
   */
  async attachCreditFile(
    committee: User,
    code: string,
    dto: AttachCreditFileDto,
    file: UploadedAttachment,
  ): Promise<BarterDetail> {
    const barter = await this.visibleBarter(committee, code);

    const refusal = creditFileRefusal(barter);
    if (refusal) throw new UnprocessableEntityException(refusal);

    const contentType = this.requireAttachable(file);
    const kind = dto.kind ?? CREDIT_FILE_KIND.other;

    await this.prisma.$transaction(async (tx) => {
      const stored = await tx.barterFile.create({
        data: this.fileDataOf(committee, file, contentType),
      });
      await tx.barterCreditFile.create({
        data: {
          barterId: barter.id,
          kind,
          note: dto.note?.trim() ? dto.note.trim() : null,
          attachedBy: committee.fullName,
          attachedById: committee.id,
          fileId: stored.id,
        },
      });
    });

    await this.audit.record({
      actor: committee,
      action: AUDIT_ACTION.barterCreditFileAttached,
      targetType: 'barter',
      targetId: barter.id,
      targetLabel: barter.code,
      detail: `${CREDIT_FILE_LABELS[kind]} anexada ao dossiê (${file.originalname})`,
    });
    return this.findFor(committee, code);
  }

  /**
   * REMOVE uma peça do dossiê — a que subiu trocada, ou a que foi substituída
   * por uma consulta mais nova.
   *
   * A MESMA JANELA de anexar, e é o ponto: o que fundamentou uma decisão já
   * tomada não se apaga. Enquanto a permuta espera decisão, o dossiê é rascunho
   * de trabalho da reunião; depois dela, é prova — e a trilha guarda as duas
   * pontas justamente porque é sobre uma decisão questionada que alguém vai
   * procurar o documento que sumiu.
   *
   * O arquivo vai junto (`Cascade` do lado da peça, aplicado aqui na ordem que o
   * domínio quer, como na nota).
   */
  async removeCreditFile(
    committee: User,
    code: string,
    creditFileId: number,
  ): Promise<BarterDetail> {
    const barter = await this.visibleBarter(committee, code);

    const refusal = creditFileRefusal(barter);
    if (refusal) throw new UnprocessableEntityException(refusal);

    const credit = await this.prisma.barterCreditFile.findFirst({
      where: { id: creditFileId, barterId: barter.id },
    });
    if (!credit) {
      throw new NotFoundException('Esta permuta não tem a peça que você quer remover');
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.barterCreditFile.delete({ where: { id: credit.id } });
      await tx.barterFile.delete({ where: { id: credit.fileId } });
    });

    await this.audit.record({
      actor: committee,
      action: AUDIT_ACTION.barterCreditFileRemoved,
      targetType: 'barter',
      targetId: barter.id,
      targetLabel: barter.code,
      detail: `${CREDIT_FILE_LABELS[credit.kind as CreditFileKind] ?? credit.kind} removida do dossiê`,
    });
    return this.findFor(committee, code);
  }

  /**
   * O ARQUIVO de uma peça do dossiê, com os bytes.
   *
   * DUAS PORTAS são conferidas aqui, e não uma: o ESCOPO da permuta (`findFor`,
   * como em toda leitura) e a CAPACIDADE de ler o dossiê. A segunda é o que
   * torna esta leitura diferente da do anexo da nota — quem alcança a permuta
   * alcança os documentos dela, menos estes. Ver `bartersCreditRead`.
   *
   * A capacidade também é exigida na porta da rota; repeti-la aqui é a mesma
   * escolha de `create` conferir o papel do consultor: uma invariante do
   * domínio não pode depender de alguém ter lembrado de pôr o decorator.
   */
  async creditFile(viewer: User, code: string, creditFileId: number): Promise<StoredFile> {
    if (!can(viewer, CAPABILITY.bartersCreditRead)) {
      throw new ForbiddenException(
        'O dossiê da análise de crédito é do comitê — ele não acompanha a permuta',
      );
    }

    const barter = await this.findFor(viewer, code);
    const credit = await this.prisma.barterCreditFile.findFirst({
      where: { id: creditFileId, barterId: barter.id },
      include: { file: true },
    });
    if (!credit?.file) {
      throw new NotFoundException('Esta peça não tem arquivo anexado');
    }
    return credit.file;
  }

  /* ── O DESVIO: o pedido de alteração e o caminho de volta ─────────────── */

  /**
   * O PEDIDO DE ALTERAÇÃO do consultor — o único caminho de volta da esteira.
   *
   * Ele não move a permuta: ela continua exatamente onde estava, na fila de quem
   * estava, e o gerente que ia dar o parecer continua podendo dar. O que o
   * pedido faz é PENDURAR uma bandeira nela e pôr uma linha na mesa do admin —
   * porque devolver a permuta na hora do pedido tiraria da mesa de terceiros um
   * trabalho que talvez nem precise ser desfeito (o admin pode recusar), e
   * ninguém saberia por que a permuta sumiu da fila.
   *
   * Quem pede é o consultor QUE REGISTROU. O escopo dele já é "as minhas", então
   * a conferência abaixo só morde quando alguém com esta capacidade enxergar
   * mais do que a própria carteira — que é o dia em que o gerente puder pedir
   * pelo time. Melhor a regra estar escrita antes desse dia.
   */
  async requestChange(
    consultant: User,
    code: string,
    dto: RequestBarterChangeDto,
  ): Promise<BarterDetail> {
    const barter = await this.visibleBarter(consultant, code);
    if (barter.consultantId !== consultant.id) {
      throw new ForbiddenException('Só quem registrou a permuta pode pedir a alteração dela');
    }

    const refusal = changeRequestRefusal(barter);
    if (refusal) throw new UnprocessableEntityException(refusal);

    // A CULTURA: a alteração atravessa versões, e não atravessa culturas. Ela é
    // conferida já no PEDIDO, e não só na remontagem, para o consultor não
    // esperar a resposta do admin por um caminho que termina fechado.
    await this.requireSameCulture(barter);

    const note = dto.note.trim();
    const requested = await this.applyChange(
      barter,
      CHANGE_REQUEST_ACTION.changeRequested,
      consultant,
      barter.status as BarterStatus,
      {
        changeRequestStatus: CHANGE_REQUEST_STATUS.open,
        changeRequestNote: note,
        changeRequestBy: consultant.fullName,
        changeRequestById: consultant.id,
        changeRequestAt: new Date(),
        // DE ONDE o pedido foi feito. Não é o estado para onde voltar (a recusa
        // não mexe no status): é o que a linha do tempo precisa para dizer "ele
        // pediu quando ela já estava aprovada", que é o que muda a leitura do
        // admin — desfazer um parecer custa menos do que desfazer uma decisão.
        changeRequestFrom: barter.status,
        // A recusa ANTERIOR sai de cena junto: o pedido novo é outro assunto, e
        // deixar a resposta do pedido passado ao lado dele faria a tela mostrar
        // um "recusado" sobre um pedido que ainda não foi lido.
        changeRequestReply: null,
      },
      note,
    );

    await this.audit.record({
      actor: consultant,
      action: AUDIT_ACTION.barterChangeRequested,
      targetType: 'barter',
      targetId: requested.id,
      targetLabel: requested.code,
      detail: `alteração pedida com a permuta em "${
        BARTER_STATUS_LABELS[barter.status as BarterStatus] ?? barter.status
      }": ${summarize(note)}`,
    });
    return requested;
  }

  /**
   * A DECISÃO DO ADMIN sobre o pedido: liberar a permuta ou recusar o pedido.
   *
   * LIBERAR devolve a permuta a `draft` e apaga o que as etapas cumpridas
   * escreveram nela (ver `CLEARED_BY_CHANGE`) — o parecer e a decisão falavam de
   * uma permuta que está prestes a mudar. A história não se perde: os eventos
   * continuam lá, e é por isso que apagar o estado atual é seguro.
   *
   * RECUSAR não mexe em nada além do próprio pedido: a permuta segue onde
   * estava, com o motivo da recusa visível para quem pediu. Não é preciso
   * "restaurar" estado nenhum justamente porque o pedido nunca o tirou dela.
   *
   * O admin decide o PROCESSO, e não o negócio — ver `bartersChangeReview`. Ele
   * continua sem poder aprovar ou negar permuta.
   */
  async decideChange(admin: User, code: string, dto: DecideBarterChangeDto): Promise<BarterDetail> {
    const barter = await this.visibleBarter(admin, code);

    const refusal = changeDecisionRefusal(barter);
    if (refusal) throw new UnprocessableEntityException(refusal);

    const note = dto.note?.trim() ? dto.note.trim() : null;
    const decided = dto.accept
      ? await this.applyChange(
          barter,
          CHANGE_REQUEST_ACTION.changeAccepted,
          admin,
          BARTER_STATUS.draft,
          {
            ...CLEARED_BY_CHANGE,
            // O pedido ATENDIDO some por inteiro: quem conta essa história a
            // partir de agora é o `status` da permuta, que voltou a ser
            // rascunho, e o evento gravado aqui. Um pedido "aceito" pendurado
            // seria um segundo lugar dizendo a mesma coisa. Ver
            // `RESOLVED_REQUEST` — a outra saída que atende usa o mesmo zerar.
            ...RESOLVED_REQUEST,
          },
          note,
        )
      : await this.applyChange(
          barter,
          CHANGE_REQUEST_ACTION.changeDenied,
          admin,
          barter.status as BarterStatus,
          {
            changeRequestStatus: CHANGE_REQUEST_STATUS.denied,
            changeRequestReply: note,
          },
          note,
        );

    await this.audit.record({
      actor: admin,
      action: AUDIT_ACTION.barterChangeDecided,
      targetType: 'barter',
      targetId: decided.id,
      targetLabel: decided.code,
      detail: dto.accept
        ? `alteração liberada — a permuta de ${decided.consultantName} voltou a rascunho${
            note ? `: ${summarize(note)}` : ''
          }`
        : `alteração recusada${note ? `: ${summarize(note)}` : ''}`,
    });
    return decided;
  }

  /**
   * A TERCEIRA SAÍDA DO PEDIDO: o admin ATENDE mexendo no valor, e a permuta
   * não sai do lugar.
   *
   * A maior parte dos pedidos que chegam é de um número — o valor de um insumo
   * saiu diferente do que foi combinado com o produtor. Devolver a permuta ao
   * rascunho por causa disso joga fora dois pareceres e uma decisão para
   * corrigir o que o admin já tem na mão. Aqui ele corrige, o servidor
   * recalcula as sacas, e a permuta continua com quem estava. Ver
   * `priceChangeRefusal` em `change-request.ts`, onde a regra mora.
   *
   * Três coisas acontecem na MESMA transação, e as três precisam andar juntas:
   * os valores mudam, a linha do grão é recalculada a partir deles e o pedido
   * se fecha. Uma permuta gravada com o valor novo e as sacas velhas é uma
   * permuta que promete ao produtor uma entrega que não paga o que ele retirou.
   */
  async changePrices(admin: User, code: string, dto: ChangeBarterPricesDto): Promise<BarterDetail> {
    const barter = await this.visibleBarter(admin, code);

    const refusal = priceChangeRefusal(barter);
    if (refusal) throw new UnprocessableEntityException(refusal);

    const items = await this.prisma.barterItem.findMany({ where: { barterId: barter.id } });
    const byId = new Map(items.map((item) => [item.id, item]));

    // O payload é consolidado por item (último vence), como as quantidades no
    // registro: dois valores para a mesma linha não são um erro que valha uma
    // recusa — é a tela mandando o que o admin digitou por último.
    const wanted = new Map(dto.prices.map((price) => [price.itemId, price.unitValue]));

    const changes: { item: BarterItem; unitValue: number }[] = [];
    for (const [itemId, unitValue] of wanted) {
      const item = byId.get(itemId);
      // Item de outra permuta, ou de uma lista que mudou enquanto a tela estava
      // aberta (o consultor remontou o rascunho). A frase manda reabrir, que é
      // o que resolve — e não acusa quem digitou.
      if (!item) {
        throw new UnprocessableEntityException(
          'Esta permuta não tem mais o item que você está alterando. Abra-a de novo para ver como ela está',
        );
      }
      const itemRefusal = itemPriceRefusal(item);
      if (itemRefusal) throw new UnprocessableEntityException(itemRefusal);

      // O que não muda não vira alteração: um valor reenviado igual ao gravado
      // é a tela devolvendo o formulário inteiro, e gravá-lo produziria um
      // evento dizendo "de R$ 120,00 para R$ 120,00".
      if (Math.abs(unitValue - item.unitValue) >= MONEY_EPSILON) {
        changes.push({ item, unitValue });
      }
    }
    if (changes.length === 0) {
      throw new UnprocessableEntityException(
        'Os valores enviados são os que esta permuta já tem — nada mudou',
      );
    }

    const note = dto.note?.trim() ? dto.note.trim() : null;
    // O QUE MUDOU, escrito por extenso na linha do tempo. É a peça que o
    // gerente e o comitê vão ler para saber que a permuta que eles analisaram
    // não é mais a mesma — e "valores alterados" sozinho os obrigaria a
    // comparar de cabeça com o que leram ontem.
    const summary = changes
      .map(
        (change) =>
          `${change.item.productName}: ${money(change.item.unitValue)} → ${money(change.unitValue)}`,
      )
      .join('; ');

    try {
      await this.prisma.$transaction(async (tx) => {
        for (const change of changes) {
          await tx.barterItem.update({
            where: { id: change.item.id },
            data: {
              unitValue: change.unitValue,
              // De onde o valor saiu, guardado na PRIMEIRA sobrescrita: uma
              // segunda correção do mesmo item continua tendo partido da
              // tabela, e é a tabela que a tela mostra ao lado do valor de
              // hoje. Ver `listValue` no schema.
              listValue: change.item.listValue ?? change.item.unitValue,
            },
          });
        }

        await this.repriceGrain(tx, barter.id);

        // O `changeRequestStatus` no `where` é a mesma trava de `applyChange`:
        // entre a leitura e a gravação cabe o outro admin decidindo o mesmo
        // pedido, e sem ela os dois atenderiam o mesmo pedido de dois jeitos.
        await tx.barter.update({
          where: {
            id: barter.id,
            status: barter.status,
            changeRequestStatus: CHANGE_REQUEST_STATUS.open,
          },
          data: {
            ...RESOLVED_REQUEST,
            events: {
              create: [
                this.eventOf(
                  admin,
                  CHANGE_REQUEST_ACTION.changeApplied,
                  barter.status as BarterStatus,
                  barter.status as BarterStatus,
                  note ? `${summary} — ${note}` : summary,
                ),
              ],
            },
          },
        });
      });
    } catch (error) {
      if ((error as { code?: string })?.code === 'P2025') {
        throw new UnprocessableEntityException(
          'Esta permuta mudou enquanto você alterava os valores. Abra de novo para ver como ela está',
        );
      }
      throw error;
    }

    await this.audit.record({
      actor: admin,
      action: AUDIT_ACTION.barterPricesChanged,
      targetType: 'barter',
      targetId: barter.id,
      targetLabel: barter.code,
      detail: `valor alterado no pedido de ${barter.changeRequestBy ?? barter.consultantName}: ${summarize(summary)}`,
    });

    return this.findFor(admin, code);
  }

  /* ── O PEDIDO DE FORA DO BARTER ────────────────────────────────────────── */

  /**
   * O PEDIDO DE PRODUTO do consultor: falta um item que a tabela da versão não
   * tem, e é o admin quem pode pô-lo na permuta com um valor.
   *
   * Ele NÃO move a permuta e não a tira da fila de ninguém — como o pedido de
   * alteração, ele pendura uma linha na mesa do admin. Diferente dele, vale
   * também no RASCUNHO: é ali que o consultor está montando a permuta e topa
   * com o que falta, e o item que ele quer não existe em lista nenhuma para ele
   * mesmo acrescentar. Ver `product-request.ts`.
   */
  async requestProduct(
    consultant: User,
    code: string,
    dto: RequestBarterProductDto,
  ): Promise<BarterDetail> {
    const barter = await this.visibleBarter(consultant, code);
    // A mesma regra do pedido de alteração, e pelo mesmo motivo: a permuta é de
    // quem a registrou, e quem falou com o produtor é quem sabe o que falta.
    if (barter.consultantId !== consultant.id) {
      throw new ForbiddenException('Só quem registrou a permuta pode pedir um produto para ela');
    }

    const refusal = productRequestRefusal(barter);
    if (refusal) throw new UnprocessableEntityException(refusal);

    const productName = dto.productName.trim();
    const unit = dto.unit.trim();
    const quantity = roundQuantity(dto.quantity);
    const note = dto.note?.trim() ? dto.note.trim() : null;
    const asked = `${productName} — ${quantityText(quantity)} ${unit}`;

    try {
      await this.prisma.barter.update({
        // O `status` no `where` pelo motivo de sempre: entre a conferência e a
        // gravação cabe o encaminhamento (ou a decisão do comitê) vindo de
        // outra tela, e um pedido gravado depois dele entraria numa permuta que
        // já não pode recebê-lo.
        where: { id: barter.id, status: barter.status },
        data: {
          productRequests: {
            create: {
              productName,
              unit,
              quantity,
              note,
              requestedBy: consultant.fullName,
              requestedById: consultant.id,
            },
          },
          // O evento na MESMA transação do pedido, como toda mudança de estado
          // desta permuta: sem o evento não há pedido. Ele não muda o `status`
          // — o ato aconteceu com a permuta onde ela estava, e é isso que
          // `fromStatus` igual a `toStatus` diz.
          events: {
            create: [
              this.eventOf(
                consultant,
                PRODUCT_REQUEST_ACTION.productRequested,
                barter.status as BarterStatus,
                barter.status as BarterStatus,
                note ? `${asked}: ${note}` : asked,
              ),
            ],
          },
        },
      });
    } catch (error) {
      if ((error as { code?: string })?.code === 'P2025') {
        throw new UnprocessableEntityException(
          'Esta permuta mudou enquanto você escrevia o pedido. Abra de novo para ver como ela está',
        );
      }
      throw error;
    }

    await this.audit.record({
      actor: consultant,
      action: AUDIT_ACTION.barterProductRequested,
      targetType: 'barter',
      targetId: barter.id,
      targetLabel: barter.code,
      detail: `produto de fora do Barter pedido: ${summarize(asked)}`,
    });

    return this.findFor(consultant, code);
  }

  /**
   * A DECISÃO DO ADMIN sobre o pedido de produto: incluir com o valor acertado,
   * ou recusar com o motivo.
   *
   * INCLUIR põe o item na permuta onde ela está e recalcula as sacas — o item
   * é custo retirado como qualquer outro. Ele entra marcado (`offBarter`), sem
   * produto no catálogo e com o valor que o admin escreveu: é o único valor
   * deste sistema que não sai de uma tabela publicada, e é por isso que o
   * pedido atendido continua existindo ao lado dele, dizendo de onde veio.
   *
   * RECUSAR não mexe na permuta. E continua valendo depois de o comitê decidir,
   * ao contrário de incluir: limpar a mesa de um pedido que ficou para trás não
   * altera permuta nenhuma, e deixá-lo pendurado para sempre seria uma fila que
   * não anda.
   */
  async decideProduct(
    admin: User,
    code: string,
    requestId: number,
    dto: DecideBarterProductDto,
  ): Promise<BarterDetail> {
    const barter = await this.visibleBarter(admin, code);

    const request = await this.prisma.barterProductRequest.findFirst({
      where: { id: requestId, barterId: barter.id },
    });
    // O pedido é lido DENTRO da permuta (`barterId`): um id de pedido de outra
    // permuta não é "não encontrado por engano" — é a única maneira de alguém
    // atender, pela porta de uma permuta que enxerga, o pedido de outra.
    if (!request) throw new NotFoundException('Registro não encontrado.');

    const decided = productDecisionRefusal(request);
    if (decided) throw new UnprocessableEntityException(decided);

    const note = dto.note?.trim() ? dto.note.trim() : null;

    if (!dto.accept) {
      await this.prisma.$transaction([
        this.prisma.barterProductRequest.update({
          where: { id: request.id, status: PRODUCT_REQUEST_STATUS.open },
          data: {
            status: PRODUCT_REQUEST_STATUS.denied,
            decidedBy: admin.fullName,
            decidedById: admin.id,
            decidedAt: new Date(),
            reply: note,
          },
        }),
        this.prisma.barter.update({
          where: { id: barter.id },
          data: {
            events: {
              create: [
                this.eventOf(
                  admin,
                  PRODUCT_REQUEST_ACTION.productDenied,
                  barter.status as BarterStatus,
                  barter.status as BarterStatus,
                  note ? `${request.productName}: ${note}` : request.productName,
                ),
              ],
            },
          },
        }),
      ]);
    } else {
      // A JANELA vale para o atendimento, e não só para o pedido: entre um e
      // outro o comitê pode ter decidido a permuta, e incluir um insumo nela
      // depois disso alteraria o que foi aprovado sem passar por quem aprovou.
      // A recusa não passa por aqui de propósito — ver o comentário do método.
      const refusal = productRequestRefusal(barter);
      if (refusal) throw new UnprocessableEntityException(refusal);

      // O que o ADMIN escreveu vence o que o consultor pediu: a descrição do
      // fornecedor é outra, a embalagem é em 20 l e não em litro, e é o item
      // dele que vai ser separado no balcão. Ausente, vale o do pedido.
      const granted: GrantedRequest = {
        id: request.id,
        productName: dto.productName?.trim() || request.productName,
        unit: dto.unit?.trim() || request.unit,
        quantity: roundQuantity(dto.quantity ?? request.quantity),
        sku: dto.sku?.trim() || request.sku,
        unitValue: dto.unitValue!,
      };
      const included =
        `${granted.productName} — ${quantityText(granted.quantity)} ${granted.unit} ` +
        `a ${money(granted.unitValue!)}`;

      try {
        await this.prisma.$transaction(async (tx) => {
          await tx.barterProductRequest.update({
            // `status` no `where`: dois admins na mesma tela atenderiam o mesmo
            // pedido duas vezes, e a permuta ficaria com o item em dobro.
            where: { id: request.id, status: PRODUCT_REQUEST_STATUS.open },
            data: {
              status: PRODUCT_REQUEST_STATUS.added,
              productName: granted.productName,
              unit: granted.unit,
              quantity: granted.quantity,
              sku: granted.sku,
              unitValue: granted.unitValue,
              decidedBy: admin.fullName,
              decidedById: admin.id,
              decidedAt: new Date(),
              reply: note,
            },
          });

          await tx.barterItem.create({
            data: { ...offBarterItemOf(granted), barterId: barter.id },
          });

          // As SACAS mudam junto, na mesma transação: o item é custo retirado, e
          // uma permuta com o insumo dentro e as sacas de antes promete ao
          // produtor uma entrega que não paga o que ele levou.
          await this.repriceGrain(tx, barter.id);

          await tx.barter.update({
            where: { id: barter.id, status: barter.status },
            data: {
              events: {
                create: [
                  this.eventOf(
                    admin,
                    PRODUCT_REQUEST_ACTION.productAdded,
                    barter.status as BarterStatus,
                    barter.status as BarterStatus,
                    note ? `${included} — ${note}` : included,
                  ),
                ],
              },
            },
          });
        });
      } catch (error) {
        if ((error as { code?: string })?.code === 'P2025') {
          throw new UnprocessableEntityException(
            'Este pedido mudou enquanto você o atendia. Abra a permuta de novo para ver como ela está',
          );
        }
        throw error;
      }
    }

    await this.audit.record({
      actor: admin,
      action: AUDIT_ACTION.barterProductDecided,
      targetType: 'barter',
      targetId: barter.id,
      targetLabel: barter.code,
      detail: dto.accept
        ? `produto de fora do Barter incluído: ${summarize(
            `${dto.productName?.trim() || request.productName} a ${money(dto.unitValue!)}`,
          )}`
        : `produto de fora do Barter recusado: ${summarize(
            `${request.productName}${note ? ` — ${note}` : ''}`,
          )}`,
    });

    return this.findFor(admin, code);
  }

  /**
   * OS PEDIDOS ATENDIDOS desta permuta, do tamanho que o item precisa deles.
   *
   * É daqui que a remontagem do rascunho tira de volta os itens de fora do
   * Barter: eles não vêm no payload do consultor (não têm produto no catálogo
   * para ele apontar) e sumiriam no primeiro `PUT /inputs`.
   */
  private async grantedRequestsOf(barterId: number): Promise<GrantedRequest[]> {
    return this.prisma.barterProductRequest.findMany({
      where: { barterId, status: PRODUCT_REQUEST_STATUS.added },
      select: {
        id: true,
        productName: true,
        unit: true,
        quantity: true,
        sku: true,
        unitValue: true,
      },
      orderBy: { id: 'asc' },
    });
  }

  /**
   * RECALCULA A LINHA DO GRÃO a partir do custo dos insumos que a permuta tem
   * AGORA — o mesmo cálculo do registro, feito sobre o que está gravado.
   *
   * A cotação é a da PRÓPRIA permuta (o `unitValue` do item de grão, congelado
   * no registro), e não a da versão vigente: o que muda aqui é o custo, nunca o
   * preço da saca. Ler a cotação de hoje faria uma correção de R$ 10 num insumo
   * reprecificar a permuta inteira pela tabela nova.
   *
   * Permuta sem linha de grão — as anteriores ao item de pagamento — sai
   * intacta: não há cotação pela qual converter, e inventar uma seria afirmar
   * uma entrega que ninguém acordou.
   */
  private async repriceGrain(tx: Prisma.TransactionClient, barterId: number): Promise<void> {
    const items = await tx.barterItem.findMany({ where: { barterId } });
    const grain = items.find((item) => item.kind === 'grain');
    if (!grain || grain.unitValue <= 0) return;

    const cost = items
      .filter((item) => item.kind === 'input')
      .reduce((sum, item) => sum + item.quantity * item.unitValue, 0);

    await tx.barterItem.update({
      where: { id: grain.id },
      data: { quantity: sacksToCover(cost, grain.unitValue) },
    });
  }

  /**
   * A REESCRITA DOS INSUMOS de um rascunho — o que o pedido de alteração existe
   * para permitir, e o que o consultor faz antes do primeiro encaminhamento.
   *
   * Só o RASCUNHO, e é `refusalFor(forward)` quem diz isso: a mesma porta do
   * parecer salvo (`saveNote`), com a mesma frase para quem chega tarde. Uma
   * permuta na mesa de outra pessoa não se edita por baixo dela — é para isso
   * que existe o pedido.
   *
   * A permuta é remontada por inteiro contra as mesmas regras do registro
   * (`pricedItemsFor`), com duas escolhas que merecem nome:
   *
   * - a VERSÃO é a DA PERMUTA, e não a vigente. O acordo foi fechado naquela
   *   tabela, e a gestão seguinte não reescreve preço combinado — é o mesmo
   *   motivo de o item guardar o preço em vez de lê-lo;
   * - a ÁREA é a CONGELADA no registro (`producerAreaHa`), e não a do cadastro
   *   de hoje. Ela é o denominador dos mínimos por hectare e do investimento, e
   *   trocá-la aqui faria a alteração de um insumo mudar em silêncio a régua
   *   pela qual a permuta inteira é medida.
   *
   * Sem evento na linha do tempo, como em `saveNote` e pelo mesmo motivo: o
   * rascunho é a bancada do consultor, e o ato que o processo registra é o
   * ENCAMINHAMENTO — que vem logo depois e leva o parecer junto.
   */
  async replaceInputs(
    consultant: User,
    code: string,
    dto: ReplaceBarterInputsDto,
  ): Promise<BarterDetail> {
    const barter = await this.requireBarter(consultant, code, BARTER_ACTION.forward);

    const { version, grain } = await this.requireSameCulture(barter);

    // OS ITENS DE FORA DO BARTER voltam para a lista, porque eles não estão na
    // lista que o consultor manda: ele escolhe do catálogo, e um item que não é
    // do catálogo não tem `productId` para ele apontar. Quem os guarda é o
    // pedido atendido (ver `PRODUCT_REQUEST_STATUS.added`) — sem isto, a
    // primeira correção de quantidade apagaria da permuta o item que o admin
    // acabou de incluir, sem ninguém ter pedido isso.
    const granted = await this.grantedRequestsOf(barter.id);

    // O SEGURO volta pela mesma razão dos itens de fora do Barter — ele não
    // está na lista que o consultor manda, e sumiria na primeira correção de
    // quantidade —, mas ele volta do lugar oposto: da PRÓPRIA PERMUTA, e não do
    // cadastro. A taxa foi congelada no registro (ver `Barter.insuranceCity`), e
    // relê-la da base faria uma correção de quantidade reprecificar o seguro
    // pela cotação de hoje, num rascunho que o produtor já viu.
    const items = await this.pricedItemsFor(
      version,
      grain,
      { areaHa: barter.producerAreaHa },
      dto.inputs,
      granted,
      insuranceOf(barter),
    );

    // Os itens antigos SAEM e os novos entram, na mesma transação: a permuta é
    // um conjunto, e um instante em que ela esteja sem insumos (ou com os dois
    // conjuntos somados) é um instante em que qualquer leitura dela mente.
    //
    // O `status` no `where` do update é a mesma trava de `applyStep`: entre a
    // conferência e a gravação cabe o encaminhamento vindo de outro aparelho do
    // mesmo consultor, e sem ele os itens seriam trocados DEPOIS de a permuta
    // já estar na mesa do gerente.
    try {
      await this.prisma.$transaction([
        this.prisma.barterItem.deleteMany({ where: { barterId: barter.id } }),
        this.prisma.barter.update({
          where: { id: barter.id, status: BARTER_STATUS.draft },
          data: { items: { create: items } },
        }),
      ]);
    } catch (error) {
      if ((error as { code?: string })?.code === 'P2025') {
        throw new UnprocessableEntityException(BARTER_STEPS[BARTER_ACTION.forward].done);
      }
      throw error;
    }

    return this.findFor(consultant, code);
  }

  /**
   * TROCA A CULTURA de um rascunho — a permuta passa a ser paga em outro grão.
   *
   * Ela existe porque a cultura é a PRIMEIRA decisão da permuta e nem sempre é a
   * primeira a ficar pronta: o consultor monta os insumos com o produtor, e o
   * produtor decide na conversa que aquele talhão vai de milho, e não de soja.
   * Sem esta porta, a saída seria apagar o rascunho e digitar tudo de novo.
   *
   * SÓ O RASCUNHO, e é `refusalFor(forward)` quem diz isso — a mesma porta de
   * `replaceInputs` e `saveNote`, com a mesma frase para quem chega tarde.
   * Depois do encaminhamento a permuta está na mesa de alguém, e trocar a
   * cultura por baixo mudaria o negócio que aquela pessoa está analisando: o
   * caminho de lá é o pedido de alteração.
   *
   * O QUE MUDA: as sacas (a cotação da cultura nova converte o mesmo custo) e a
   * produtividade com que o penhor é dimensionado. O QUE NÃO MUDA: os insumos, o
   * custo em R$, o seguro e os itens de fora do Barter — trocar de cultura não é
   * refazer a permuta, é trocar a moeda com que ela é paga.
   *
   * A permuta é REMONTADA por inteiro (`pricedItemsFor`) em vez de ter a linha do
   * grão reescrita: é o mesmo caminho da alteração de insumos, e é ele que
   * garante que as regras de mínimo continuem valendo depois da troca.
   */
  async setCulture(consultant: User, code: string, grainId: number): Promise<BarterDetail> {
    const barter = await this.requireBarter(consultant, code, BARTER_ACTION.forward);
    const { version } = await this.requireSameCulture(barter);

    // A CULTURA NOVA precisa estar nas duas pontas: na versão DA PERMUTA (é ela
    // que precifica, e foi nela que o acordo foi fechado) e no Barter ABERTO
    // hoje (trocar para uma cultura que a praça não vende mais seria registrar
    // um negócio que não existe). A conferência da segunda é a mesma de
    // `requireSameCulture`, feita antes da troca em vez de depois dela.
    const grain = version.grains.find((row) => row.grainId === grainId);
    if (!grain) {
      const offered = version.grains.map((row) => row.grainName).join(' e ');
      throw new UnprocessableEntityException(
        `O Barter ${version.code} não aceita essa cultura. Ele paga em ${offered}`,
      );
    }
    const open = await this.seasons.requireOpenVersion();
    const refusal = cultureRefusal({ grainId, grainName: grain.grainName }, open);
    if (refusal) throw new UnprocessableEntityException(refusal);

    if (grain.estimatedYield <= 0) {
      throw new UnprocessableEntityException(
        `O Barter ${version.code} está sem produtividade estimada de ${grain.grainName} — ` +
          `sem ela não há como dimensionar a área do penhor. Peça ao administrador para informá-la no lançamento`,
      );
    }

    // OS INSUMOS ATUAIS, relidos da própria permuta: a troca não pede a lista de
    // novo ao app. O que entra em `inputs` é só o insumo de catálogo — o que veio
    // de fora do Barter e o seguro voltam pelos caminhos próprios deles, como em
    // `replaceInputs`.
    const current = await this.prisma.barterItem.findMany({ where: { barterId: barter.id } });
    const inputs = current
      .filter((item) => item.kind === 'input' && !item.offBarter && !item.insurance)
      .map((item) => ({ productId: item.productId!, quantity: item.quantity }));

    const items = await this.pricedItemsFor(
      version,
      grain,
      { areaHa: barter.producerAreaHa },
      inputs,
      await this.grantedRequestsOf(barter.id),
      insuranceOf(barter),
    );

    try {
      await this.prisma.$transaction([
        this.prisma.barterItem.deleteMany({ where: { barterId: barter.id } }),
        this.prisma.barter.update({
          where: { id: barter.id, status: BARTER_STATUS.draft },
          data: {
            items: { create: items },
            // A PRODUTIVIDADE congelada troca junto: ela é da cultura, e deixá-la
            // como estava dimensionaria o penhor do milho pela estimativa da
            // soja — um erro que só apareceria na hora de conferir as matrículas.
            pledgeYield: grain.estimatedYield,
          },
        }),
      ]);
    } catch (error) {
      if ((error as { code?: string })?.code === 'P2025') {
        throw new UnprocessableEntityException(BARTER_STEPS[BARTER_ACTION.forward].done);
      }
      throw error;
    }

    return this.findFor(consultant, code);
  }

  /**
   * A TABELA COM QUE ESTA PERMUTA FOI FECHADA — a gestão dela, com os valores.
   *
   * Ela existe porque a REMONTAGEM acontece sobre a tabela da permuta, e não
   * sobre a vigente (ver `cultureRefusal`): sem esta rota, a tela do consultor
   * montaria os insumos lendo os preços de hoje enquanto o servidor gravaria os
   * daquela gestão, e o total em sacas que ele mostrasse ao produtor não seria o
   * que ficaria registrado.
   *
   * O escopo é o da PERMUTA (`findFor`), e não o do lançamento: quem alcança a
   * permuta alcança a tabela com que ela foi feita. O detalhe da versão em si
   * (`GET /barter-versions/:code`, com metas e realizado) continua sendo do
   * admin — aqui não vai meta nenhuma, só o que precifica esta permuta.
   */
  async versionOf(viewer: User, code: string): Promise<VersionWithPrices> {
    const barter = await this.findFor(viewer, code);
    if (!barter.versionCode) {
      throw new UnprocessableEntityException(
        'Esta permuta é anterior ao lançamento por versões e não tem tabela própria',
      );
    }
    return this.seasons.findVersion(barter.versionCode);
  }

  /**
   * A CULTURA DESTA PERMUTA — o grão que a paga, lido da LINHA DE PAGAMENTO.
   *
   * A permuta não tem campo de cultura, e isso é deliberado (ver `Barter` no
   * schema): a linha de `kind: "grain"` já guarda o produto, o nome e a cotação
   * congelados no registro. Ela é a resposta, e ter uma coluna ao lado seria um
   * segundo lugar dizendo o mesmo.
   *
   * `null` nas permutas anteriores ao item de pagamento — elas não dizem em que
   * são pagas, e é quem chama que decide o que fazer com isso.
   */
  private async cultureOf(barter: Barter): Promise<BarterCulture | null> {
    const item = await this.prisma.barterItem.findFirst({
      where: { barterId: barter.id, kind: 'grain' },
      select: { productId: true, productName: true },
    });
    if (!item) return null;
    return { grainId: item.productId, grainName: item.productName };
  }

  /**
   * A GESTÃO EM QUE A PERMUTA FOI FECHADA, conferida contra a que está aberta
   * hoje: a aberta precisa AINDA ACEITAR a cultura desta permuta.
   *
   * Devolve a versão da permuta e a cultura dela DENTRO dessa versão — a versão
   * reprecifica a remontagem (foi nela que o acordo foi fechado) e a cultura diz
   * por qual cotação o custo vira sacas. Ver `cultureRefusal` em
   * `change-request.ts`, onde a regra mora e está explicada.
   */
  private async requireSameCulture(
    barter: Barter,
  ): Promise<{ version: VersionWithPrices; grain: VersionGrain }> {
    if (!barter.versionCode) {
      throw new UnprocessableEntityException(
        'Esta permuta é anterior ao lançamento por versões e não pode ser alterada',
      );
    }
    const culture = await this.cultureOf(barter);
    if (!culture) {
      throw new UnprocessableEntityException(
        'Esta permuta é anterior à linha de pagamento e não pode ser alterada',
      );
    }

    const version = await this.seasons.findVersion(barter.versionCode);
    // `requireOpenVersion` é quem recusa quando não há Barter aberto, com a
    // frase do lançamento: sem gestão aberta não há com o que comparar, e
    // remontar uma permuta fora de qualquer gestão aberta não é alteração, é
    // reabrir a praça por conta própria.
    const open = await this.seasons.requireOpenVersion();

    const refusal = cultureRefusal(culture, open);
    if (refusal) throw new UnprocessableEntityException(refusal);

    // A CULTURA DENTRO DA VERSÃO DA PERMUTA. Ela existe por construção — a
    // permuta nasceu de uma das culturas daquela versão, e culturas não somem de
    // uma versão publicada —, e a recusa aqui é a rede contra o banco mexido à
    // mão, não um caminho que a operação alcance.
    const grain =
      version.grains.find((row) => row.grainId === culture.grainId) ??
      version.grains.find(
        (row) => row.grainName.trim().toLowerCase() === culture.grainName.trim().toLowerCase(),
      );
    if (!grain) {
      throw new UnprocessableEntityException(
        `O Barter ${version.code} não tem mais a cultura ${culture.grainName} desta permuta`,
      );
    }

    return { version, grain };
  }

  /**
   * UM PASSO DO DESVIO: grava o pedido (ou a decisão sobre ele) e o evento
   * juntos, como `applyStep` faz com a esteira.
   *
   * Separado dele por uma diferença que não é de forma: aqui o `to` PODE SER O
   * MESMO estado de onde a permuta está — o pedido e a recusa não a movem. O
   * `where` continua com o status de origem pelo motivo de sempre (dois admins
   * decidindo o mesmo pedido), e a mensagem de quem perde a corrida é a do
   * pedido, não a de uma etapa da esteira: ele já foi decidido por outro.
   */
  private async applyChange(
    barter: Barter,
    action: ChangeRequestAction,
    actor: User,
    to: BarterStatus,
    fields: Prisma.BarterUncheckedUpdateInput,
    note?: string | null,
  ): Promise<BarterDetail> {
    try {
      return await this.prisma.barter.update({
        where: {
          id: barter.id,
          status: barter.status,
          changeRequestStatus: barter.changeRequestStatus,
        },
        data: {
          ...fields,
          status: to,
          events: {
            create: [this.eventOf(actor, action, barter.status as BarterStatus, to, note)],
          },
        },
        include: BARTER_DETAIL_INCLUDE,
      });
    } catch (error) {
      if ((error as { code?: string })?.code === 'P2025') {
        throw new UnprocessableEntityException(
          'Esta permuta mudou enquanto você decidia. Abra de novo para ver como ela está',
        );
      }
      throw error;
    }
  }

  /* ── A CÉDULA: o preenchimento do consultor e a emissão do emissor ────── */

  /**
   * A MESA DA CÉDULA — tudo o que a tela precisa, de uma vez: o rascunho
   * gravado, o que a permuta já responde, quem é a credora, a sugestão de
   * preenchimento e o que ainda falta.
   *
   * Numa requisição só, e de propósito: o formulário da CPR mistura as três
   * fontes do documento (ver cpr.ts), e montá-lo com uma chamada por fonte
   * deixaria a tela desenhar campos vazios enquanto a sugestão não chega — que é
   * exatamente o instante em que alguém começa a digitar o que já existia.
   *
   * QUEM CHEGA AQUI são três papéis com perguntas diferentes, e a mesma resposta
   * serve aos três: o CONSULTOR (preenche), o EMISSOR (confere e emite) e o
   * ADMIN (lê a segunda via). O escopo de cada um é o da PERMUTA — uma permuta
   * que não abre pelo código não abre a cédula —, e é `scopeFor` quem o
   * responde. Duas regras de escopo para a mesma pergunta é uma a mais do que se
   * mantém em dia.
   *
   * O CONSULTOR PREENCHE DESDE O RASCUNHO, e isso é deliberado: a qualificação
   * do produtor e as matrículas das lavouras são o que ele traz da visita, e a
   * permuta demora semanas para chegar ao faturamento. Coletar depois é coletar
   * por telefone.
   */
  async cprFor(viewer: User, code: string): Promise<CprDesk> {
    const barter = await this.findFor(viewer, code);
    const cpr = await this.loadCpr(barter.id);

    const producer = barter.producerId
      ? await this.prisma.producer.findUnique({ where: { id: barter.producerId } })
      : null;

    const culture = await this.cprCultureOf(barter);
    const context = this.cprContextOf(barter, culture);

    return {
      cpr,
      known: this.knownOf(
        barter,
        producer?.document ?? '',
        cpr?.sackWeightKg ?? EMPTY_CPR.sackWeightKg,
        culture,
      ),
      // A credora vem do CADASTRO (ver creditor/), e é o serializer quem calcula
      // as pendências dela — assim a mesa da cédula e a tela de cadastro dizem
      // exatamente a mesma coisa sobre o que falta.
      creditor: await this.creditor.get(),
      gaps: cprGaps(cpr ?? EMPTY_CPR, cpr?.areas ?? [], context),
      consultantGaps: consultantCprGaps(cpr ?? EMPTY_CPR, cpr?.areas ?? [], context.pledge),
      // O PENHOR MEDIDO, ao lado da lista de pendências: a lista diz que falta
      // área, este bloco diz quanta e contra o quê. É o que o formulário desenha
      // no cabeçalho das lavouras enquanto o consultor acrescenta matrículas.
      pledge: pledgeReadingOf(context.pledge, cpr?.areas ?? []),
      // OS AVISOS, que não são pendências (ver `pledgeWarningsFor`): eles não
      // travam nada, e por isso ficam fora de `gaps` — misturá-los faria a lista
      // que o portão do encaminhamento lê recusar uma permuta por uma suspeita.
      pledgeWarnings: await this.pledgeWarningsFor(barter, cpr?.areas ?? []),
      // A sugestão só faz sentido enquanto NÃO há rascunho: depois que o
      // consultor escreveu, o que está na tela é dele, e oferecer por cima o
      // texto de uma cédula antiga é a maneira mais fácil de sobrescrever uma
      // correção que alguém acabou de fazer.
      suggestion: cpr ? {} : suggestFrom(producer, await this.previousCpr(barter.producerId)),
    };
  }

  /**
   * O QUE CHEIRA MAL NO PENHOR, sem travar nada — os dois jeitos conhecidos de a
   * área fechar na conta e não fechar no mundo.
   *
   * São AVISOS e não pendências, e a diferença é de autoridade. `cprGaps`
   * responde "dá para emitir?", e a resposta dela recusa atos: tudo o que entra
   * lá precisa ser verdade sem exceção. Estes dois não são — há arrendamento
   * legítimo que a área cultivável do cadastro não reflete, e há matrícula grande
   * cuja lavoura foi repartida de boa-fé entre duas permutas. Travar por eles
   * recusaria operação boa; calar sobre eles é deixar passar a operação que a
   * feature existe para pegar. O meio-termo é dizer, e deixar a decisão com quem
   * tem o contexto.
   *
   * 1. A MESMA MATRÍCULA GARANTINDO DUAS PERMUTAS. É o furo mais caro do penhor:
   *    os mesmos 100 ha fechando a área de dois barters valem 100 ha e garantem
   *    200. Acontece sem má-fé — o mesmo produtor emite duas cédulas na safra, ou
   *    dois arrendatários apontam para a fazenda do mesmo dono — e é invisível
   *    para quem olha uma cédula por vez, que é como todo mundo olha.
   *
   * 2. A SOMA PASSANDO DA ÁREA CULTIVÁVEL DO PRODUTOR. A área da lavoura é
   *    digitada à mão e virou um portão: quem precisa de 40 ha e tem 30 anotados
   *    tem agora um motivo para escrever 40. O cadastro (`producerAreaHa`,
   *    congelado no registro) é a única segunda fonte que existe sobre quanta
   *    terra esse produtor tem.
   *
   * A busca da matrícula ignora as permutas NEGADAS e os rascunhos dos outros —
   * as primeiras não garantem nada e os segundos ainda não estão na mesa de
   * ninguém —, e compara pelo número normalizado: "12.345" e "12345" são a mesma
   * matrícula, e o cartório não tem opinião sobre a pontuação de quem digita.
   */
  private async pledgeWarningsFor(
    barter: Barter,
    areas: { areaHa: number; registryNumber: string }[],
  ): Promise<string[]> {
    const warnings: string[] = [];

    const registries = new Map(
      areas
        .map((area) => [registryKeyOf(area.registryNumber), area.registryNumber] as const)
        .filter(([key]) => key.length > 0),
    );
    if (registries.size > 0) {
      const elsewhere = await this.prisma.cprArea.findMany({
        where: {
          cpr: {
            barter: {
              id: { not: barter.id },
              versionCode: barter.versionCode,
              status: { notIn: [BARTER_STATUS.denied, BARTER_STATUS.draft] },
            },
          },
        },
        select: { registryNumber: true, cpr: { select: { barter: { select: { code: true } } } } },
      });

      const shared = new Map<string, Set<string>>();
      for (const row of elsewhere) {
        const key = registryKeyOf(row.registryNumber);
        if (!registries.has(key)) continue;
        const codes = shared.get(key) ?? new Set<string>();
        codes.add(row.cpr.barter.code);
        shared.set(key, codes);
      }
      for (const [key, codes] of shared) {
        warnings.push(
          `a matrícula ${registries.get(key)} também está em penhor na(s) permuta(s) ` +
            `${[...codes].sort().join(', ')} desta mesma gestão — confira se a lavoura não está ` +
            `sendo dada em garantia duas vezes`,
        );
      }
    }

    const pledged =
      Math.round(areas.reduce((total, area) => total + (area.areaHa || 0), 0) * 100) / 100;
    if (barter.producerAreaHa > 0 && pledged > barter.producerAreaHa + AREA_EPSILON) {
      warnings.push(
        `as lavouras somam ${pledged.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ha, ` +
          `acima dos ${barter.producerAreaHa.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ha ` +
          `de área cultivável registrados para o produtor — confira as áreas ou o cadastro`,
      );
    }

    return warnings;
  }

  /**
   * A SAFRA em que a permuta foi fechada — quem sabe o VENCIMENTO da cédula.
   *
   * Ela é lida pela versão (`versionCode`), e não pela safra aberta hoje, pelo
   * mesmo motivo de tudo o mais nesta permuta: o acordo foi fechado naquela
   * gestão, e a safra seguinte não reescreve o vencimento do que já foi
   * combinado.
   *
   * `null` nas permutas anteriores ao lançamento por versões e nas cujas gestões
   * sumiram do banco. Não é erro: `cprGaps` cobra o vencimento, e a frase manda
   * acertá-lo no lançamento — que é onde ele se resolve.
   */
  private async cprCultureOf(barter: Barter): Promise<CprCulture | null> {
    if (!barter.versionCode) return null;
    const version = await this.prisma.barterVersion.findUnique({
      where: { code: barter.versionCode },
      include: { season: true, grains: true },
    });
    if (!version) return null;

    const culture = await this.cultureOf(barter);
    const grain =
      version.grains.find((row) => row.grainId === culture?.grainId) ??
      version.grains.find(
        (row) => row.grainName.trim().toLowerCase() === culture?.grainName.trim().toLowerCase(),
      );

    return {
      seasonName: version.season.name,
      grainName: grain?.grainName ?? culture?.grainName ?? '',
      // O VENCIMENTO da CULTURA desta permuta. Ele era da safra, quando a safra
      // era a cultura; hoje a mesma gestão tem soja vencendo em abril e milho em
      // agosto, e é a linha do grão da permuta que diz qual das duas vale aqui.
      cprDueDate: grain?.cprDueDate ?? null,
    };
  }

  /**
   * O contexto que `cprGaps` precisa: as notas do faturamento, a safra e o
   * dimensionamento do penhor.
   */
  private cprContextOf(barter: BarterWithItems, culture: CprCulture | null): CprContext {
    return {
      invoices: barter.invoices.map((invoice) => ({
        number: invoice.number,
        fileId: invoice.fileId,
      })),
      seasonName: culture?.seasonName ?? '',
      // A CULTURA entra no contexto por causa de UMA frase: a do vencimento que
      // falta. Com duas culturas no mesmo Barter, "defina-o na safra" não diz em
      // qual delas — e quem lê a pendência é quem vai resolvê-la.
      grainName: culture?.grainName ?? '',
      pledge: this.pledgeOf(barter, sacksOf(barter.items)),
    };
  }

  /**
   * O PENHOR DESTA PERMUTA — as duas taxas congeladas, com as sacas de agora.
   *
   * As sacas entram por fora, e não são lidas aqui, porque quem as tem à mão
   * muda: a mesa da cédula já carrega os itens, o portão do encaminhamento não.
   * Elas também são a única das três parcelas que MUDA depois do registro —
   * deferir um produto de fora do Barter recalcula a linha do grão (ver
   * `repriceGrain`) —, e é por isso que a área exigida se recalcula a cada
   * leitura em vez de ficar gravada.
   */
  private pledgeOf(barter: Barter, sacks: number): CprPledge {
    return {
      sacks,
      yieldPerHa: barter.pledgeYield,
      marginPercent: barter.pledgeMarginPercent,
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
   *
   * DEPOIS DE EMITIDA, NÃO SE ESCREVE MAIS. Até a emissão a cédula é rascunho e
   * se corrige à vontade; do ato do emissor em diante ela é um documento que
   * existe no mundo, que alguém conferiu e assinou embaixo. Reescrevê-la por
   * baixo faria a segunda via sair diferente da primeira — e é a primeira que
   * está com o produtor.
   */
  async saveCpr(consultant: User, code: string, dto: SaveCprDto): Promise<CprDesk> {
    const barter = await this.findFor(consultant, code);
    this.requireCprWritable(barter);

    const { areas, guarantors, issuedAt, scrConsultedAt, ...fields } = dto;

    // Datas chegam como texto ISO (é o que o DTO valida) e viram Date aqui. A
    // ausência do campo mantém o que está gravado — apagar uma data já escrita
    // não é operação que um formulário de rascunho precise oferecer, e a maneira
    // de corrigi-la é escrever a certa por cima.
    //
    // O VENCIMENTO não vem do corpo: ele é da CULTURA desta permuta, e o
    // servidor o copia de lá. É a diferença entre um dado que a pessoa informa e
    // um que ela herda — e era justamente essa confusão que fazia duas cédulas
    // da mesma safra saírem com vencimentos diferentes. Com duas culturas no
    // mesmo Barter a herança continua valendo, só que a fonte é mais precisa: o
    // vencimento da soja não é o do milho.
    const culture = await this.cprCultureOf(barter);
    const dates = {
      ...(issuedAt ? { issuedAt: new Date(issuedAt) } : {}),
      ...(scrConsultedAt ? { scrConsultedAt: new Date(scrConsultedAt) } : {}),
      dueDate: culture?.cprDueDate ?? null,
    };

    const written = {
      ...fields,
      ...dates,
      filledBy: consultant.fullName,
      filledById: consultant.id,
    };

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

    const desk = await this.cprFor(consultant, code);
    await this.audit.record({
      actor: consultant,
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
        `CPR ${desk.cpr?.number || 'sem número'}: ` +
        (desk.gaps.length === 0 ? 'completa' : `faltam ${desk.gaps.length} campo(s)`),
    });
    return desk;
  }

  /**
   * A CÉDULA AINDA ACEITA ESCRITA? — ou seja, ela ainda não foi emitida.
   *
   * A pergunta é sobre o ESTADO DA PERMUTA, e não sobre um campo da cédula: quem
   * guarda "esta cédula já saiu" é a esteira (`cprIssued` para a frente), e um
   * segundo lugar dizendo a mesma coisa é um lugar a mais para divergir.
   *
   * A frase vem da máquina de estados pelo mesmo motivo de todas as outras: no
   * dia em que houver uma etapa a mais entre a emissão e a assinatura, ela
   * aparece escrita certa nas telas já instaladas.
   */
  private requireCprWritable(barter: Barter): void {
    if (stageOf(barter.status) >= stageOf(BARTER_STATUS.cprIssued)) {
      throw new UnprocessableEntityException(
        `${BARTER_STEPS[BARTER_ACTION.cprIssue].done} — o documento não se reescreve depois de emitido`,
      );
    }
  }

  /**
   * ANEXA O SCR do produtor à cédula — o relatório do Banco Central que diz
   * quanto ele já deve, e a quem.
   *
   * Rota PRÓPRIA, e não um campo do formulário, porque um anexo de megabytes
   * dentro do JSON faria cada salvamento de rascunho reenviá-lo. E porque ele é
   * um ato à parte na prática: a consulta ao SCR é feita, o PDF é baixado, e
   * então ele é juntado à cédula.
   *
   * `upsert` na cédula: anexar o SCR pode ser a PRIMEIRA coisa que alguém faz
   * nesta permuta, e exigir que o formulário tenha sido salvo antes trocaria a
   * ordem do trabalho por uma ordem do banco de dados.
   *
   * O SCR ANTERIOR é apagado quando um novo chega: ele é uma fotografia, e duas
   * fotografias com datas diferentes penduradas na mesma cédula fariam alguém
   * conferir a errada.
   *
   * DOIS POSTOS anexam — o consultor, que consulta o SCR, e o EMISSOR, que fica
   * travado por ele na hora de emitir (ver a rota). O parâmetro se chama `actor`
   * por isso: quem assina `filledBy` aqui é quem anexou, e nem sempre é o
   * consultor.
   */
  async saveScr(actor: User, code: string, file: UploadedAttachment): Promise<CprDesk> {
    const barter = await this.findFor(actor, code);
    this.requireCprWritable(barter);

    // `claimsFilling` porque anexar o SCR É preencher a cédula: ele é exigência
    // dela (ver `cprGaps`), e quem o junta responde por ele.
    await this.attachToCpr(actor, barter, file, 'scrFileId', { claimsFilling: true });

    await this.audit.record({
      actor,
      action: AUDIT_ACTION.barterCprSaved,
      targetType: 'barter',
      targetId: barter.id,
      targetLabel: barter.code,
      detail: `SCR do produtor anexado à CPR (${file.originalname})`,
    });
    return this.cprFor(actor, code);
  }

  /**
   * O ARQUIVO DO SCR, com os bytes. Mesma porta do anexo da nota: quem alcança a
   * permuta alcança os documentos dela — é assim que o emissor confere o SCR na
   * hora de emitir, sem pedir o PDF a ninguém.
   */
  scrFile(viewer: User, code: string): Promise<StoredFile> {
    return this.cprFileOf(viewer, code, 'scrFileId');
  }

  /**
   * A EMISSÃO DA CÉDULA — o primeiro ato do emissor, e a CONFERÊNCIA do fluxo.
   *
   * É aqui que tudo o que os outros postos escreveram é lido contra o que o
   * documento exige, e a cédula com lacuna NÃO SAI. A recusa não é um estado —
   * o emissor não devolve a permuta a ninguém — e sim um 422 com a lista por
   * extenso do que falta, cada item dizendo com quem ele se resolve (ver
   * `cprGaps`): o RG é com o consultor, a nota é com o faturista, o vencimento é
   * com quem cadastra a safra.
   *
   * A CREDORA entra na mesma conferência, e o motivo é o de sempre: um título
   * sem a qualificação de quem cobra não é título. As duas listas continuam
   * SEPARADAS na resposta, porque quem resolve cada uma é outra pessoa.
   */
  async issueCpr(emitter: User, code: string, dto: IssueCprDto): Promise<BarterDetail> {
    const barter = await this.requireBarter(emitter, code, BARTER_ACTION.cprIssue);

    // O NÚMERO, quando ele vem no ato. É a única escrita do emissor na cédula, e
    // ela acontece ANTES da conferência de propósito: o número que ele acabou de
    // informar precisa contar como preenchido, senão a emissão recusaria por
    // uma pendência que o próprio pedido resolve.
    const number = dto.number?.trim();
    if (number) {
      await this.prisma.barterCpr.upsert({
        where: { barterId: barter.id },
        create: { barterId: barter.id, number, filledBy: emitter.fullName, filledById: emitter.id },
        update: { number },
      });
    }

    const desk = await this.cprFor(emitter, code);
    const missingCreditor = creditorGaps(desk.creditor);
    if (desk.gaps.length > 0 || missingCreditor.length > 0) {
      throw new UnprocessableEntityException(
        `A cédula não pode ser emitida — ${[
          ...(desk.gaps.length > 0 ? [`falta na cédula: ${desk.gaps.join(', ')}`] : []),
          ...(missingCreditor.length > 0
            ? [`falta na credora: ${missingCreditor.join(', ')}`]
            : []),
        ].join('; ')}`,
      );
    }

    const note = dto.note?.trim() ? dto.note.trim() : null;
    const issued = await this.applyStep(
      barter,
      BARTER_ACTION.cprIssue,
      emitter,
      BARTER_STATUS.cprIssued,
      {
        cprEmittedBy: emitter.fullName,
        cprEmittedById: emitter.id,
        cprEmittedAt: new Date(),
        cprEmissionNote: note,
      },
      note,
    );

    await this.audit.record({
      actor: emitter,
      action: AUDIT_ACTION.barterCprIssued,
      targetType: 'barter',
      targetId: issued.id,
      targetLabel: issued.code,
      detail: `CPR ${desk.cpr?.number || 'sem número'} emitida${note ? `: ${summarize(note)}` : ''}`,
    });
    return issued;
  }

  /**
   * A COLETA DE ASSINATURAS concluída.
   *
   * O ato é o REGISTRO de um fato que aconteceu fora do sistema — o produtor
   * assinou —, e por isso a data é informável: a assinatura é na fazenda, e o
   * lançamento é no escritório, às vezes na segunda-feira seguinte. Ausente, ela
   * vale hoje, que é o caso comum.
   *
   * O sistema não valida a assinatura e não a interpreta: ele guarda o PAPEL
   * ASSINADO, quem o lançou e quando. Uma cédula assinada continua sendo um
   * papel assinado, e é ele que vale.
   *
   * O ARQUIVO É OBRIGATÓRIO, e é a razão de esta rota ter virado `multipart`.
   * "Assinada" sem o papel assinado era um estado afirmando um fato que o
   * sistema não tinha como mostrar: a segunda via saía em branco, diferente da
   * que está na mão do produtor, e o documento com as assinaturas morava no
   * e-mail de alguém. O emissor lança este ato com o papel na mesa — é dele que
   * o lançamento nasce.
   */
  async signCpr(
    emitter: User,
    code: string,
    dto: SignCprDto,
    file: UploadedAttachment,
  ): Promise<BarterDetail> {
    const barter = await this.requireBarter(emitter, code, BARTER_ACTION.cprSign);

    // O ANEXO VAI ANTES DO PASSO, e a ordem é deliberada: se o passo recusar
    // (outro aparelho assinou primeiro), o que fica gravado é a cédula assinada
    // anexada — que é verdade. Na ordem inversa, a falha do anexo deixaria a
    // permuta "assinada" sem o papel, que é exatamente o estado que esta
    // mudança existe para não existir mais.
    await this.attachToCpr(emitter, barter, file, 'signedFileId', { claimsFilling: false });

    const note = dto.note?.trim() ? dto.note.trim() : null;
    const signed = await this.applyStep(
      barter,
      BARTER_ACTION.cprSign,
      emitter,
      BARTER_STATUS.cprSigned,
      {
        cprSignedAt: dto.signedAt ? new Date(dto.signedAt) : new Date(),
        cprSignatureNote: note,
      },
      note,
    );

    await this.audit.record({
      actor: emitter,
      action: AUDIT_ACTION.barterCprSigned,
      targetType: 'barter',
      targetId: signed.id,
      targetLabel: signed.code,
      detail: `assinaturas colhidas (${file.originalname})${note ? `: ${summarize(note)}` : ''}`,
    });
    return signed;
  }

  /**
   * O REGISTRO do título — o fim da linha.
   *
   * O NÚMERO é obrigatório (ver `RegisterCprDto`), e é a única obrigatoriedade
   * do trecho do emissor: é ele que transforma "levamos ao cartório" em "está
   * registrada". Sem ele, alguém teria de refazer a busca no cartório para
   * descobrir se o registro existe — que é exatamente o trabalho que este campo
   * evita para sempre.
   *
   * A VIA CARIMBADA é anexo OPCIONAL, e a diferença para a assinatura é a
   * natureza do que se lança: lá o papel assinado É o fato, aqui o fato é o
   * número do registro, que o campo obrigatório já afirma. Cartório que demora
   * semanas para devolver a via não pode travar o fim da linha — e quando ela
   * chegar, este ato já terá acontecido. Por isso ela também entra por
   * `PUT /cpr/registry-file`, depois.
   *
   * Depois daqui não há próximo ato. O que vem é a colheita, e ela não é deste
   * sistema.
   */
  async registerCpr(
    emitter: User,
    code: string,
    dto: RegisterCprDto,
    file?: UploadedAttachment,
  ): Promise<BarterDetail> {
    const barter = await this.requireBarter(emitter, code, BARTER_ACTION.cprRegister);

    if (file) {
      await this.attachToCpr(emitter, barter, file, 'registryFileId', { claimsFilling: false });
    }

    const registryNumber = dto.registryNumber.trim();
    const place = dto.registryPlace?.trim() ? dto.registryPlace.trim() : null;
    const note = dto.note?.trim() ? dto.note.trim() : null;

    // O TEXTO DO EVENTO é o registro por extenso, e não a observação: a linha do
    // tempo é lida por quem quer saber sob que número a cédula foi registrada, e
    // ele estaria só num campo do cadastro se a observação fosse o que vai ali.
    const timeline = [
      `Registro ${registryNumber}`,
      ...(place ? [place] : []),
      ...(note ? [note] : []),
    ].join(' — ');

    const registered = await this.applyStep(
      barter,
      BARTER_ACTION.cprRegister,
      emitter,
      BARTER_STATUS.cprRegistered,
      {
        cprRegisteredAt: dto.registeredAt ? new Date(dto.registeredAt) : new Date(),
        cprRegistryNumber: registryNumber,
        cprRegistryPlace: place,
      },
      timeline,
    );

    await this.audit.record({
      actor: emitter,
      action: AUDIT_ACTION.barterCprRegistered,
      targetType: 'barter',
      targetId: registered.id,
      targetLabel: registered.code,
      detail: `CPR registrada sob ${registryNumber}${place ? ` em ${place}` : ''}`,
    });
    return registered;
  }

  /* ── OS ANEXOS: o que vale como arquivo, e como ele é gravado ─────────── */

  /**
   * GRAVA UM ANEXO DA CÉDULA, trocando o que estava na mesma coluna.
   *
   * Os três anexos dela têm a mesma mecânica e donos diferentes: o SCR (a
   * fotografia do endividamento), a cédula ASSINADA e a via carimbada pelo
   * REGISTRO. Um método para os três porque a diferença entre eles não está em
   * como se guarda um arquivo — está em QUANDO cada um pode entrar, e isso é
   * decidido por quem chama.
   *
   * SEMPRE SUBSTITUI: cada coluna guarda UM documento, e dois arquivos
   * pendurados na mesma cédula fariam alguém conferir o errado. O antigo sai
   * DEPOIS de o novo estar no lugar — um instante em que a cédula esteja sem
   * anexo nenhum é um instante em que ela parece pendente.
   *
   * `upsert` porque anexar pode ser a PRIMEIRA coisa que acontece nesta permuta
   * (é o caso do SCR), e exigir que o formulário tenha sido salvo antes trocaria
   * a ordem do trabalho por uma ordem do banco de dados.
   *
   * `claimsFilling` diz se quem anexa assume o `filledBy` da cédula. O SCR sim —
   * ele é exigência do documento, e quem o junta responde por ele. A cédula
   * assinada e o comprovante do registro NÃO: o emissor não preenche a cédula,
   * ele junta o papel que voltou, e carimbá-lo como "último a preencher"
   * apagaria da tela o nome de quem de fato a escreveu.
   */
  private async attachToCpr(
    actor: User,
    barter: Barter,
    file: UploadedAttachment,
    column: CprAttachmentColumn,
    { claimsFilling }: { claimsFilling: boolean },
  ): Promise<void> {
    const contentType = this.requireAttachable(file);

    await this.prisma.$transaction(async (tx) => {
      const existing = await tx.barterCpr.findUnique({
        where: { barterId: barter.id },
        select: { id: true, scrFileId: true, signedFileId: true, registryFileId: true },
      });

      const stored = await tx.barterFile.create({
        data: this.fileDataOf(actor, file, contentType),
      });

      // O vínculo é escrito por extenso, e não por chave calculada: o Prisma
      // confere os campos do `data` em tempo de compilação, e uma coluna
      // montada em string passaria batido até a primeira gravação em produção.
      const link =
        column === 'scrFileId'
          ? { scrFileId: stored.id }
          : column === 'signedFileId'
            ? { signedFileId: stored.id }
            : { registryFileId: stored.id };

      if (!existing) {
        await tx.barterCpr.create({
          data: { barterId: barter.id, filledBy: actor.fullName, filledById: actor.id, ...link },
        });
        return;
      }

      await tx.barterCpr.update({
        where: { id: existing.id },
        data: {
          ...link,
          ...(claimsFilling ? { filledBy: actor.fullName, filledById: actor.id } : {}),
        },
      });

      const previous = existing[column];
      if (previous !== null) {
        await tx.barterFile.delete({ where: { id: previous } });
      }
    });
  }

  /**
   * O ARQUIVO de um anexo da cédula, com os bytes.
   *
   * Um método para os três pelo mesmo motivo de `attachToCpr`, e com a mesma
   * porta de escopo do anexo da nota: quem alcança a permuta alcança os
   * documentos dela. A recusa diz QUAL anexo falta — "não encontrado" numa tela
   * com três botões de download não diz nada a quem clicou.
   */
  private async cprFileOf(
    viewer: User,
    code: string,
    which: CprAttachmentColumn,
  ): Promise<StoredFile> {
    const barter = await this.findFor(viewer, code);
    const cpr = await this.prisma.barterCpr.findUnique({
      where: { barterId: barter.id },
      include: { scrFile: true, signedFile: true, registryFile: true },
    });

    const found =
      which === 'scrFileId'
        ? cpr?.scrFile
        : which === 'signedFileId'
          ? cpr?.signedFile
          : cpr?.registryFile;
    if (!found) {
      throw new NotFoundException(`Esta cédula ainda não tem ${CPR_ATTACHMENT_LABEL[which]}`);
    }
    return found;
  }

  /** A CÉDULA ASSINADA — o papel que voltou com as assinaturas. */
  signedCprFile(viewer: User, code: string): Promise<StoredFile> {
    return this.cprFileOf(viewer, code, 'signedFileId');
  }

  /** A VIA CARIMBADA pelo registro. */
  cprRegistryFile(viewer: User, code: string): Promise<StoredFile> {
    return this.cprFileOf(viewer, code, 'registryFileId');
  }

  /**
   * A VIA CARIMBADA lançada DEPOIS do registro.
   *
   * Existe porque o cartório devolve quando devolve: o ato do registro acontece
   * com o número em mãos, e a via carimbada chega semanas depois. Sem esta rota,
   * o único jeito de juntá-la seria refazer um ato que não se refaz.
   */
  async saveCprRegistryFile(
    emitter: User,
    code: string,
    file: UploadedAttachment,
  ): Promise<CprDesk> {
    const barter = await this.findFor(emitter, code);
    if (!barter.cprRegisteredAt) {
      throw new UnprocessableEntityException(
        'O comprovante do registro só entra depois de a cédula ser registrada',
      );
    }

    await this.attachToCpr(emitter, barter, file, 'registryFileId', { claimsFilling: false });

    await this.audit.record({
      actor: emitter,
      action: AUDIT_ACTION.barterCprRegistered,
      targetType: 'barter',
      targetId: barter.id,
      targetLabel: barter.code,
      detail: `comprovante do registro anexado (${file.originalname})`,
    });
    return this.cprFor(emitter, code);
  }

  /**
   * ESTE ARQUIVO PODE SER ANEXADO? — tipo e tamanho, nesta ordem.
   *
   * O TAMANHO é conferido aqui além do multer porque as duas travas respondem a
   * coisas diferentes: o multer corta a requisição (e devolve um erro de
   * transporte, sem língua nenhuma), e esta diz à pessoa, em pt-BR, qual é o
   * limite e quanto o arquivo dela tem. Uma sem a outra é ou uma recusa que
   * ninguém entende, ou um upload de 40 MB recebido inteiro para ser recusado no
   * fim.
   *
   * O TIPO vem do que o cliente declara, com a EXTENSÃO como segunda opinião
   * quando ele não declara nada de útil (ver `attachmentTypeOf`). Não é trava de
   * segurança — o conteúdo nunca é executado nem interpretado por este servidor,
   * e sai como `attachment` —, é o que impede o engano honesto: a foto no lugar
   * do PDF, o executável arrastado sem querer.
   *
   * Devolve o tipo RESOLVIDO, e é ele que vai para o banco: gravar
   * `application/octet-stream` faria o download do PDF chegar como um arquivo
   * que o navegador não sabe abrir, meses depois, sem ninguém entender por quê.
   */
  private requireAttachable(file: UploadedAttachment): string {
    const type = attachmentTypeOf(file.originalname, file.mimetype);
    if (type === null) {
      throw new UnprocessableEntityException(
        `Anexe um PDF, XML ou imagem — "${file.originalname}" veio como ${
          file.mimetype || 'tipo desconhecido'
        }`,
      );
    }
    if (file.size > MAX_ATTACHMENT_BYTES) {
      const mb = (bytes: number) => (bytes / 1024 / 1024).toFixed(1).replace('.', ',');
      throw new UnprocessableEntityException(
        `O anexo passa do limite: ${mb(file.size)} MB, e o máximo é ${mb(MAX_ATTACHMENT_BYTES)} MB`,
      );
    }
    if (file.size === 0) {
      throw new UnprocessableEntityException(`O arquivo "${file.originalname}" está vazio`);
    }
    return type;
  }

  /**
   * A linha de `BarterFile` a partir do arquivo recebido.
   *
   * O `Buffer` do multer vira `Uint8Array` na cópia: os dois são a mesma coisa em
   * memória, mas o `Buffer` do Node pode estar apoiado num `SharedArrayBuffer`, e
   * o cliente do Prisma pede um `ArrayBuffer`. A cópia resolve isso sem
   * asserção de tipo — que aqui esconderia a diferença em vez de desfazê-la.
   */
  private fileDataOf(
    actor: User,
    file: UploadedAttachment,
    contentType: string,
  ): Prisma.BarterFileCreateWithoutInvoiceInput {
    return {
      fileName: file.originalname,
      contentType,
      size: file.size,
      content: Uint8Array.from(file.buffer),
      uploadedBy: actor.fullName,
      uploadedById: actor.id,
    };
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

  /**
   * O que a cédula tira do registro — o item de grão carrega os números, a
   * CULTURA do lançamento carrega o vencimento e o faturamento carrega as notas.
   *
   * As três fontes entram aqui porque todas as três são LEITURA para quem
   * preenche a cédula: nenhuma delas é digitada no formulário, e cada uma tem
   * outro dono.
   */
  private knownOf(
    barter: BarterWithItems,
    document: string,
    sackWeightKg: number,
    culture: CprCulture | null,
  ): CprKnown {
    return knownFrom(
      barter,
      barter.items.find((item) => item.kind === 'grain'),
      document,
      sackWeightKg,
      { name: culture?.seasonName ?? '', cprDueDate: culture?.cprDueDate ?? null },
      barter.invoices.map((invoice) => ({
        number: invoice.number,
        series: invoice.series,
        duplicateNumber: invoice.duplicateNumber,
      })),
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
    const barter = await this.visibleBarter(actor, code);

    const refusal = refusalFor(action, barter);
    if (refusal) throw new UnprocessableEntityException(refusal);

    return barter;
  }

  /**
   * As DUAS PRIMEIRAS perguntas de [requireBarter], sem a terceira: a permuta
   * existe e o autor a enxerga.
   *
   * Ela é separada porque o DESVIO não passa pela esteira: "posso pedir
   * alteração?" e "posso decidir este pedido?" não são perguntas sobre o ponto
   * da linha em que a permuta está, e são respondidas por `change-request.ts`.
   * O que não muda é a ordem — existe, enxerga, só então a regra do ato —, que
   * é o que impede a mensagem da regra de contar o que o escopo esconde.
   */
  private async visibleBarter(actor: User, code: string): Promise<Barter> {
    const barter = await this.prisma.barter.findUnique({ where: { code } });
    if (!barter) throw new NotFoundException('Registro não encontrado.');

    const visible = await this.prisma.barter.count({
      where: { code, ...this.scopeFor(actor) },
    });
    if (visible === 0) throw new ForbiddenException(this.noAccessFor(actor));

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
