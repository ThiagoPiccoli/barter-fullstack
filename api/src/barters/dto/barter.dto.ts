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
 * Filtros da listagem. Um status desconhecido é RECUSADO em vez de ignorado:
 * ignorar devolvia a base inteira com cara de lista filtrada, e quem estivesse
 * olhando não teria como perceber.
 */
export class ListBartersQuery extends PaginationQuery {
  @IsOptional()
  @IsIn(['pending', 'approved', 'denied'], {
    message: 'Filtro de status inválido: use pending, approved ou denied',
  })
  status?: 'pending' | 'approved' | 'denied';
}
