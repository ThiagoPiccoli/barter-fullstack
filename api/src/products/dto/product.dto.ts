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
  classId?: number | null;

  /**
   * CÓDIGO do item — o que se digita na busca e o que casa a planilha do
   * fornecedor com o cadastro. Opcional na entrada: vazio, o servidor gera um
   * (`INS-0007`), para nenhum item ficar sem código.
   */
  @IsOptional()
  @IsString()
  @MaxLength(40)
  sku?: string;
}

/** Edição de cadastro (nome/unidade/código/classe/exigência). */
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

  /** null desvincula o insumo da classe. */
  @IsOptional()
  @IsInt()
  @IsPositive()
  classId?: number | null;

  /**
   * CÓDIGO do item — o que se digita na busca e o que casa a planilha do
   * fornecedor com o cadastro. Opcional na entrada: vazio, o servidor gera um
   * (`INS-0007`), para nenhum item ficar sem código.
   */
  @IsOptional()
  @IsString()
  @MaxLength(40)
  sku?: string;
}

/**
 * Filtro do catálogo. Um `type` desconhecido é recusado: ignorá-lo devolvia
 * grãos e insumos misturados quando o cliente pediu só um dos dois.
 *
 * O catálogo NÃO é paginado de propósito — ele é limitado pelo tamanho da
 * operação e o app precisa dele inteiro para montar a permuta.
 */
export class ListProductsQuery {
  @IsOptional()
  @IsIn(['grain', 'input'], { message: 'Filtro de tipo inválido: use grain ou input' })
  type?: 'grain' | 'input';
}
