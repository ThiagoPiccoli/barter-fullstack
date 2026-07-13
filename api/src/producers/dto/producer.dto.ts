import { IsInt, IsNumber, IsOptional, IsPositive, IsString, MaxLength, MinLength } from 'class-validator';

export class ProducerDto {
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name!: string;

  /** Carteira: todo produtor nasce vinculado a um vendedor. */
  @IsInt()
  @IsPositive()
  sellerId!: number;

  @IsString()
  @MinLength(3)
  @MaxLength(40)
  document!: string;

  @IsOptional()
  @IsString()
  @MaxLength(30)
  phone?: string;

  @IsString()
  @MinLength(2)
  @MaxLength(120)
  farmName!: string;

  @IsString()
  @MinLength(2)
  @MaxLength(80)
  city!: string;

  /** Área cultivável (ha): base das exigências mínimas de insumo. */
  @IsNumber()
  @IsPositive()
  areaHa!: number;
}
