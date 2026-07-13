import {
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

export class CreateProductDto {
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(40)
  unit!: string;

  @IsIn(['grain', 'input'])
  type!: 'grain' | 'input';

  @IsNumber()
  @IsPositive()
  currentPrice!: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  requiredPerHa?: number;

  @IsOptional()
  @IsInt()
  @IsPositive()
  categoryId?: number | null;
}

/** Edição de cadastro (nome/unidade/pasta/exigência). Preço tem rota própria. */
export class UpdateProductDto {
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name?: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(40)
  unit?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  requiredPerHa?: number;

  /** null desvincula o insumo da pasta. */
  @IsOptional()
  @IsInt()
  @IsPositive()
  categoryId?: number | null;
}

/** Reajuste do valor de referência — sempre gera entrada no histórico. */
export class UpdatePriceDto {
  @IsNumber()
  @IsPositive()
  price!: number;
}
