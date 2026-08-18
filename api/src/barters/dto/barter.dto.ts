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
}

export class ReviewBarterDto {
  @IsIn(['approved', 'denied'])
  status!: 'approved' | 'denied';

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
 * é quem REVISA, lendo isto antes. Um campo de decisão aqui
 * transformaria a etapa numa segunda aprovação, deixando duas pessoas com o
 * mesmo poder e nenhuma com uma responsabilidade própria.
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

/** Os quatro estados de uma permuta, na ordem em que ela passa por eles. */
export const BARTER_STATUSES = ['sentToManager', 'pending', 'approved', 'denied'] as const;

export type BarterStatusValue = (typeof BARTER_STATUSES)[number];

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
  status?: BarterStatusValue;

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
