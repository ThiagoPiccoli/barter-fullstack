import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  MaxLength,
  MinLength,
  ValidateIf,
  ValidateNested,
} from 'class-validator';
import { PaginationQuery } from '../../common/pagination';
import { BARTER_STATUS, BARTER_STATUSES, type BarterStatus } from '../barter-workflow';
import { TAX_REGIMES, TAX_REGIME_MESSAGE } from '../tax-regime';
import type { TaxRegime } from '../tax-regime';

/**
 * O TAMANHO MÍNIMO de um parecer — do consultor ou do gerente, e o mesmo para os
 * dois de propósito: a exigência não é sobre quem escreve, é sobre o que um
 * parecer é. Abaixo disto o campo vira um "ok" que serve só para liberar o
 * botão, que é exatamente o que a obrigatoriedade existe para impedir.
 *
 * Ele é conferido em dois lugares e por dois motivos: aqui, no parecer do
 * gerente, porque o texto vem no corpo; e no service, no encaminhamento, porque
 * lá o texto válido pode ser o que já estava salvo no rascunho.
 */
export const MIN_OPINION_LENGTH = 10;

export class BarterInputDto {
  @IsInt()
  @IsPositive()
  productId!: number;

  @IsNumber()
  @IsPositive()
  quantity!: number;
}

/**
 * Registro de permuta. Repare que NÃO há preços no payload: o cliente escolhe
 * produtos e quantidades; quem precifica e calcula as sacas é o servidor
 * (campos extras são descartados pelo whitelist do ValidationPipe).
 *
 * Também não há `grainId`: o grão é o da safra, e a versão vigente do Barter é
 * quem diz por quanto vale a saca. Escolher grão era do tempo em que a permuta
 * carregava a própria cotação.
 */
export class CreateBarterDto {
  @IsInt()
  @IsPositive()
  producerId!: number;

  /**
   * A UNIDADE em que o produtor vai retirar os insumos.
   *
   * É escolha do consultor, e não do cadastro do produtor: o mesmo produtor
   * retira onde for conveniente na safra, e amarrar a retirada ao cadastro
   * transformaria uma decisão de logística numa edição de produtor.
   *
   * QUALQUER unidade serve, inclusive uma de outra praça. Ela é o local de
   * retirada e nada mais: não escolhe quem analisa a permuta — isso é o gerente
   * do consultor —, não participa de mínimo nem de preço.
   */
  @IsInt()
  @IsPositive()
  unitId!: number;

  /**
   * O teto não é sobre o negócio — é sobre o custo de uma requisição.
   *
   * Sem ele, o limite de 256 KB do corpo ainda deixa passar milhares de itens,
   * e cada um custa uma validação aninhada, uma entrada no `IN (...)` e uma
   * linha de permuta. A maior permuta real tem algumas dezenas de insumos, e
   * 200 é folga suficiente para nenhum consultor esbarrar nisto — quem
   * esbarrar não está registrando permuta.
   */
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(200, { message: 'Uma permuta não pode ter mais de 200 insumos' })
  @ValidateNested({ each: true })
  @Type(() => BarterInputDto)
  inputs!: BarterInputDto[];

  /**
   * COMO o Funrural desta entrega é recolhido: `comercializacao` (sobre a
   * receita da venda) ou `folha` (sobre a folha de pagamento). É a escolha do
   * fechamento — ver `tax-regime.ts`.
   *
   * Opcional, e o ausente vale `comercializacao`: é o que se aplica a quem não
   * fez a opção formal pela folha, e não um chute. Exigi-lo recusaria a permuta
   * de qualquer cliente da API que ainda não conheça o campo — inclusive as
   * versões do app já instaladas.
   */
  @IsOptional()
  @IsIn(TAX_REGIMES, { message: TAX_REGIME_MESSAGE })
  taxRegime?: TaxRegime;

  /**
   * O PARECER DO CONSULTOR, quando ele já o tem na hora de registrar.
   *
   * Opcional AQUI e obrigatório no encaminhamento (ver `ForwardBarterDto`), e a
   * diferença é o desenho todo do rascunho: montar os insumos e conhecer a
   * resposta do produtor são dois momentos, e exigir o texto no registro
   * obrigaria o consultor a inventar um parágrafo para poder salvar a permuta
   * que ele acabou de simular. Sem ele, a permuta nasce em `draft` do mesmo
   * jeito — só não anda.
   */
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  note?: string;
}

/**
 * O PARECER DO CONSULTOR gravado no rascunho, sem encaminhar nada.
 *
 * É o único texto do fluxo que se REESCREVE, e é por isso que ele tem rota
 * própria (`PUT /barters/:code/note`) em vez de caber no encaminhamento: o
 * consultor salva o que tem hoje, conversa com o produtor amanhã e completa. Os
 * outros textos do fluxo são assinaturas de etapas cumpridas e não se editam.
 *
 * Não há mínimo aqui, e há no encaminhamento: um rascunho pela metade é a razão
 * de ser deste campo. Quem confere se há parecer suficiente é o ato que faz a
 * permuta sair da mesa do consultor.
 */
export class SaveBarterNoteDto {
  @IsString()
  @MaxLength(2000)
  note!: string;
}

/**
 * O ENCAMINHAMENTO ao gerente — o ato que tira a permuta da mesa do consultor.
 *
 * O parecer é OBRIGATÓRIO, pelo mesmo motivo do parecer do gerente: sem texto,
 * o botão vira um "seguir" disfarçado, e a peça que o comitê mais precisa ler
 * (o que quem conhece o cliente tem a dizer sobre ele) volta a viver no
 * telefonema.
 *
 * O campo é opcional no PAYLOAD e obrigatório no ATO: quem já salvou o parecer
 * no rascunho encaminha sem reenviá-lo, e é o service que confere o texto
 * gravado antes de deixar a permuta andar. Exigi-lo aqui obrigaria a tela a
 * reenviar o que o servidor já tem — e a divergência entre os dois textos
 * viraria uma pergunta sem dono.
 */
export class ForwardBarterDto {
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  note?: string;
}

/**
 * A frase que o comitê lê quando decide sem escrever. Uma só para os dois
 * desfechos: as duas exigências têm o mesmo motivo, e dizê-lo de dois jeitos
 * faria parecer que são regras diferentes.
 */
const REVIEW_NOTE_MESSAGE =
  'Escreva o motivo da decisão (mínimo de 10 caracteres): a ressalva exigida, ou a razão da negativa';

/**
 * A DECISÃO DO COMITÊ. TRÊS saídas, e só elas: aprovar, aprovar COM RESSALVA ou
 * negar. Não há "devolver para o gerente" — o parecer já foi dado, e uma permuta
 * que anda para trás perde o dono da etapa.
 *
 * O TEXTO é obrigatório em duas delas, e a regra é a mesma nas duas: a decisão
 * que cria trabalho para outra pessoa precisa dizer qual. A ressalva é uma
 * exigência a cumprir (garantia real, seguro, aval) e alguém vai ter de
 * providenciá-la; a negativa é uma resposta que o consultor vai levar ao
 * produtor. Nos dois casos, "porque sim" manda a pessoa perguntar por telefone —
 * e a resposta não fica no registro.
 *
 * A aprovação limpa segue com texto OPCIONAL: ela não tem o que explicar, e
 * exigi-lo produziria quinhentos "ok" no histórico.
 */
export class ReviewBarterDto {
  @IsIn([BARTER_STATUS.approved, BARTER_STATUS.approvedWithConditions, BARTER_STATUS.denied])
  status!: Extract<BarterStatus, 'approved' | 'approvedWithConditions' | 'denied'>;

  /**
   * `ValidateIf` em vez de `IsOptional`: a obrigatoriedade depende do DESFECHO,
   * e é aqui que ela cabe — no banco, uma coluna `NOT NULL` recusaria também a
   * aprovação limpa (ver `reviewNote` no schema).
   */
  @ValidateIf((dto: ReviewBarterDto) => dto.status !== BARTER_STATUS.approved)
  @IsString({ message: REVIEW_NOTE_MESSAGE })
  @MinLength(MIN_OPINION_LENGTH, { message: REVIEW_NOTE_MESSAGE })
  // A mensagem do teto também fala do MOTIVO, e não só do tamanho: com o campo
  // ausente as três conferências falham juntas, e quem lê a recusa precisa
  // entender o que falta seja qual for a que chegar até a tela.
  @MaxLength(1000, { message: 'Escreva o motivo da decisão em até 1000 caracteres' })
  note?: string;
}

/**
 * O FATURAMENTO. Repare no que NÃO existe aqui: um `status`.
 *
 * O faturista não decide nada — ele fatura o que o comitê aprovou, e o estado da
 * permuta é quem lhe entrega o trabalho. Um campo de decisão aqui criaria uma
 * segunda aprovação depois da aprovação.
 *
 * A observação é OPCIONAL, ao contrário do parecer do gerente: o faturamento
 * normal não tem o que explicar, e exigir texto de quem só carimba produziria
 * quinhentos "ok" no histórico. Ela existe para o caso que foge (nota emitida
 * parcialmente, combinação de entrega), que é quando alguém vai querer ler.
 */
export class InvoiceBarterDto {
  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;
}

/**
 * O TAMANHO MÍNIMO de um pedido de alteração e da resposta a ele.
 *
 * O mesmo do parecer, e pela mesma razão: os dois textos existem para dizer o
 * que aconteceu a quem vai agir depois. "mudou" e "não" são botões, não
 * pedidos — e quem os recebe volta a ter de telefonar.
 */
const CHANGE_NOTE_MESSAGE = 'Explique o que precisa mudar nesta permuta (mínimo de 10 caracteres)';

/**
 * O PEDIDO DE ALTERAÇÃO feito pelo consultor — o caminho de volta da esteira
 * (ver `barters/change-request.ts`).
 *
 * O texto é OBRIGATÓRIO, e é a peça inteira do pedido: quem vai lê-lo é o admin,
 * que não estava na conversa com o produtor e não tem como adivinhar se o caso
 * é "trocar 200 kg de um insumo" ou "o produtor desistiu". A decisão dele
 * depende disso — liberar a permuta apaga o parecer do gerente e a decisão do
 * comitê.
 */
export class RequestBarterChangeDto {
  @IsString({ message: CHANGE_NOTE_MESSAGE })
  @MinLength(MIN_OPINION_LENGTH, { message: CHANGE_NOTE_MESSAGE })
  @MaxLength(2000)
  note!: string;
}

/** A frase que o admin lê quando recusa um pedido sem dizer por quê. */
const DENY_NOTE_MESSAGE = 'Escreva o motivo da recusa (mínimo de 10 caracteres)';

/**
 * A DECISÃO DO ADMIN sobre o pedido: libera ou não.
 *
 * `accept` é booleano, e não um `status` como na decisão do comitê, porque aqui
 * as saídas são mesmo duas — não há "libera com ressalva". O que muda entre
 * elas é o EFEITO: liberar devolve a permuta ao rascunho do consultor; recusar
 * deixa tudo onde está e devolve o motivo.
 *
 * O motivo é obrigatório na RECUSA e opcional na liberação, pela mesma regra da
 * decisão do comitê: a resposta que cria trabalho (ou o encerra) para outra
 * pessoa precisa dizer por quê. A liberação fala pelo próprio efeito — a
 * permuta reaparece na mão de quem pediu.
 */
export class DecideBarterChangeDto {
  @IsBoolean({ message: 'Diga se o pedido de alteração foi aceito (accept: true/false)' })
  accept!: boolean;

  @ValidateIf((dto: DecideBarterChangeDto) => !dto.accept)
  @IsString({ message: DENY_NOTE_MESSAGE })
  @MinLength(MIN_OPINION_LENGTH, { message: DENY_NOTE_MESSAGE })
  // O teto também fala do MOTIVO, e não só do tamanho: com o campo ausente as
  // três conferências falham juntas, e a que chegar até a tela precisa dizer o
  // que falta — a mesma razão da mensagem gêmea em `ReviewBarterDto`.
  @MaxLength(1000, { message: 'Escreva o motivo da recusa em até 1000 caracteres' })
  note?: string;
}

/**
 * O VALOR NOVO DE UM ITEM da permuta, escrito pelo admin ao atender o pedido do
 * consultor (ver `priceChangeRefusal` em `barters/change-request.ts`).
 *
 * O item vai por `id`, e não por `productId`: o que se está corrigindo é UMA
 * LINHA daquela permuta, e os itens de fora do Barter — que são justamente os
 * que mais mudam de valor — não têm produto nenhum no catálogo para apontar.
 */
export class BarterItemPriceDto {
  @IsInt()
  @IsPositive()
  itemId!: number;

  /**
   * O valor em R$ por unidade. POSITIVO: um item a zero não é um desconto, é um
   * item fora da permuta — e tirá-lo é remontar a permuta, que é o outro
   * caminho (liberar o pedido e devolvê-la ao consultor).
   */
  @IsNumber()
  @IsPositive({ message: 'O valor do item precisa ser maior que zero' })
  unitValue!: number;
}

/**
 * O ATENDIMENTO DO PEDIDO NO VALOR — a terceira saída do desvio.
 *
 * Em vez de devolver a permuta ao rascunho (e jogar fora o parecer do gerente e
 * a decisão do comitê) para corrigir uma linha de R$, o admin corrige a linha e
 * a permuta continua onde está. Ver `priceChangeRefusal`.
 *
 * A LISTA é só do que MUDA, e aqui isso é o oposto de `ReplaceBarterInputsDto`,
 * que vai inteira — e a diferença é de natureza: ali a permuta está sendo
 * REMONTADA, e ela passa pelas regras de mínimo como um conjunto; aqui ela está
 * sendo CORRIGIDA, item a item, e mandar a lista inteira faria o admin
 * reafirmar, a cada correção, o valor de tudo o que ele não quis tocar.
 *
 * A observação é OPCIONAL porque os FATOS já ficam gravados sem ela: o evento da
 * linha do tempo diz qual item mudou, de quanto para quanto, e o item guarda o
 * valor de tabela (`listValue`). O texto é para o que os números não dizem — a
 * cotação que o fornecedor deu, a conversa com o produtor.
 */
export class ChangeBarterPricesDto {
  @IsArray()
  @ArrayMinSize(1, { message: 'Diga qual item muda de valor' })
  @ArrayMaxSize(200, { message: 'Uma permuta não pode ter mais de 200 insumos' })
  @ValidateNested({ each: true })
  @Type(() => BarterItemPriceDto)
  prices!: BarterItemPriceDto[];

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  note?: string;
}

/**
 * O PEDIDO DE FORA DO BARTER — o consultor pedindo um produto que a tabela da
 * versão não tem (ver `barters/product-request.ts`).
 *
 * O pedido é o PRODUTO e a QUANTIDADE, e é por isso que os dois são
 * obrigatórios e o texto não: aqui, ao contrário do pedido de alteração, o
 * essencial já está dito pelo próprio item. Exigir um parágrafo para pedir 20 t
 * de ureia produziria quinhentos "o produtor quer" no histórico.
 *
 * Não há VALOR no payload, pela regra de sempre: preço nunca veio do cliente. O
 * consultor não vê R$ (ver `CAPABILITY.pricesRead`) e o que ele está pedindo é
 * justamente o item que ninguém precificou ainda.
 */
export class RequestBarterProductDto {
  @IsString()
  @MinLength(2, { message: 'Escreva o nome do produto que falta' })
  @MaxLength(120)
  productName!: string;

  /**
   * A unidade em que o consultor conhece o item (l, kg, sc, ha, un…). O admin
   * corrige ao atender, se a embalagem do fornecedor for outra.
   */
  @IsString()
  @MinLength(1)
  @MaxLength(20)
  unit!: string;

  @IsNumber()
  @IsPositive({ message: 'A quantidade pedida precisa ser maior que zero' })
  quantity!: number;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  note?: string;
}

/** A frase que o admin lê quando atende um pedido sem dizer por quanto. */
const PRODUCT_VALUE_MESSAGE = 'Escreva o valor (R$ por unidade) com que este item entra na permuta';

/**
 * A DECISÃO DO ADMIN sobre o pedido de produto: incluir com um valor, ou
 * recusar com o motivo.
 *
 * `accept` é booleano, como na decisão do desvio, porque as saídas são mesmo
 * duas. O que ele carrega junto, e a outra não, é um NÚMERO: atender é
 * precificar, e é o único ato deste sistema em que um valor entra numa permuta
 * sem estar em tabela nenhuma.
 *
 * Nome, unidade e quantidade são CORREÇÕES opcionais do que o consultor
 * escreveu, e o que fica gravado é o que o admin escreveu: a descrição do
 * fornecedor é outra, a embalagem é em 20 l e não em litro, e é o item dele que
 * vai ser separado no balcão. Ausentes, valem os do pedido.
 */
export class DecideBarterProductDto {
  @IsBoolean({ message: 'Diga se o produto entra na permuta (accept: true/false)' })
  accept!: boolean;

  @ValidateIf((dto: DecideBarterProductDto) => dto.accept)
  @IsNumber({}, { message: PRODUCT_VALUE_MESSAGE })
  @IsPositive({ message: PRODUCT_VALUE_MESSAGE })
  unitValue?: number;

  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  productName?: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(20)
  unit?: string;

  @IsOptional()
  @IsNumber()
  @IsPositive({ message: 'A quantidade precisa ser maior que zero' })
  quantity?: number;

  /** O código do fornecedor, quando o admin o tem. Ver `BarterItem.productSku`. */
  @IsOptional()
  @IsString()
  @MaxLength(60)
  sku?: string;

  @ValidateIf((dto: DecideBarterProductDto) => !dto.accept)
  @IsString({ message: DENY_NOTE_MESSAGE })
  @MinLength(MIN_OPINION_LENGTH, { message: DENY_NOTE_MESSAGE })
  @MaxLength(1000, { message: 'Escreva o motivo da recusa em até 1000 caracteres' })
  note?: string;
}

/**
 * A REESCRITA DOS INSUMOS de um rascunho — o que o consultor faz depois de o
 * admin liberar a alteração (ou antes de encaminhar pela primeira vez).
 *
 * A lista vai INTEIRA, e não em pedaços ("tire este, mude aquele"): a permuta é
 * um conjunto que precisa passar pelas regras de mínimo como um todo, e um
 * `PATCH` item a item deixaria a permuta em estados intermediários que nenhuma
 * regra aceita. É o mesmo formato do registro, e de propósito — a tela que
 * monta a permuta é a mesma.
 *
 * Repare no que NÃO está aqui: produtor, unidade e preços. Trocar o produtor
 * seria outra permuta (a área dele é o denominador de tudo e já está congelada
 * no registro); trocar a unidade é logística e não passa por pedido nenhum; e
 * preço nunca veio do cliente.
 */
export class ReplaceBarterInputsDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(200, { message: 'Uma permuta não pode ter mais de 200 insumos' })
  @ValidateNested({ each: true })
  @Type(() => BarterInputDto)
  inputs!: BarterInputDto[];
}

/**
 * O PARECER TÉCNICO do gerente sobre uma negociação do time dele.
 *
 * Repare no que NÃO existe aqui: um `status`. O parecer não aprova nem nega —
 * ele é o que o gerente do consultor tem a dizer sobre o negócio, e quem decide
 * é o COMITÊ, lendo isto antes. Um campo de decisão aqui transformaria a etapa
 * numa segunda aprovação, deixando duas pessoas com o mesmo poder e nenhuma com
 * uma responsabilidade própria.
 *
 * O texto é OBRIGATÓRIO pelo mesmo motivo: parecer em branco não é parecer, é
 * um botão de "seguir".
 */
export class BarterOpinionDto {
  @IsString()
  @MinLength(MIN_OPINION_LENGTH, {
    message: `Escreva o parecer técnico (mínimo de ${MIN_OPINION_LENGTH} caracteres)`,
  })
  @MaxLength(2000)
  note!: string;
}

/**
 * Filtros da listagem. Um status desconhecido é RECUSADO em vez de ignorado:
 * ignorar devolvia a base inteira com cara de lista filtrada, e quem estivesse
 * olhando não teria como perceber.
 */
export class ListBartersQuery extends PaginationQuery {
  @IsOptional()
  @IsIn(BARTER_STATUSES, {
    message: `Filtro de status inválido: use ${BARTER_STATUSES.join(', ')}`,
  })
  status?: BarterStatus;

  /**
   * As permutas a retirar em uma UNIDADE — o recorte da logística: o que
   * precisa ser separado em cada praça.
   *
   * Ele não restringe acesso nenhum — quem enxerga o quê continua sendo decidido
   * pelo service, linha a linha. É recorte, não permissão.
   */
  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'O filtro "unitId" precisa ser um número inteiro' })
  @IsPositive({ message: 'O filtro "unitId" precisa ser um número positivo' })
  unitId?: number;

  /**
   * As permutas endereçadas a um GERENTE. Combinado com
   * `?status=sentToManager`, é a fila de parecer dele.
   */
  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'O filtro "managerId" precisa ser um número inteiro' })
  @IsPositive({ message: 'O filtro "managerId" precisa ser um número positivo' })
  managerId?: number;
}
