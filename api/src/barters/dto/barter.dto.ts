import { Type } from 'class-transformer';
import {
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
 */
export class CreateBarterDto {
  @IsInt()
  @IsPositive()
  producerId!: number;

  @IsInt()
  @IsPositive()
  grainId!: number;

  @IsArray()
  @ArrayMinSize(1)
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
