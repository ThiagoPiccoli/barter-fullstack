import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  MaxLength,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { PaginationQuery } from '../../common/pagination';
import { BARTER_STATUS, BARTER_STATUSES, type BarterStatus } from '../barter-workflow';
import { TAX_REGIMES, TAX_REGIME_MESSAGE } from '../tax-regime';
import type { TaxRegime } from '../tax-regime';

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
}

/**
 * A DECISÃO DO COMITÊ. Duas saídas, e só elas: quem lê o pedido e o parecer ou
 * aprova ou nega. Não há "devolver para o gerente" — o parecer já foi dado, e
 * uma permuta que anda para trás perde o dono da etapa.
 */
export class ReviewBarterDto {
  @IsIn([BARTER_STATUS.approved, BARTER_STATUS.denied])
  status!: Extract<BarterStatus, 'approved' | 'denied'>;

  @IsOptional()
  @IsString()
  @MaxLength(500)
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
  @MinLength(10, { message: 'Escreva o parecer técnico (mínimo de 10 caracteres)' })
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
