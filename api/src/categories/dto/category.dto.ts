import { IsIn, IsNumber, IsString, MaxLength, Min, MinLength } from 'class-validator';

/**
 * "Pasta" de insumos e sua regra de mínimo vigente. A coerência
 * percentual <= 100 é conferida no service (regra cruzada simples).
 */
export class CategoryDto {
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  name!: string;

  @IsIn(['none', 'percentOfTotal', 'valuePerHa'])
  ruleType!: 'none' | 'percentOfTotal' | 'valuePerHa';

  @IsNumber()
  @Min(0)
  ruleValue!: number;
}
