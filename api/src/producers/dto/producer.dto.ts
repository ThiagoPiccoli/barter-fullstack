import { Type } from 'class-transformer';
import {
  IsInt,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';
import { PaginationQuery } from '../../common/pagination';
import { DOCUMENT_MESSAGE, DOCUMENT_PATTERN } from '../document';

export class ProducerDto {
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name!: string;

  /** Carteira: todo produtor nasce vinculado a um consultor. */
  @IsInt()
  @IsPositive()
  consultantId!: number;

  /** CPF ou CNPJ. A pontuação é livre; o que importa é a contagem de dígitos. */
  @IsString()
  @MaxLength(40)
  @Matches(DOCUMENT_PATTERN, { message: DOCUMENT_MESSAGE })
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

/**
 * Filtros da listagem (o filtro por consultor é do admin). Um valor que não é
 * número é RECUSADO: antes ele virava NaN, o filtro sumia do `where` e a
 * resposta trazia todas as carteiras parecendo a carteira pedida.
 */
export class ListProducersQuery extends PaginationQuery {
  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'O filtro "consultantId" precisa ser um número inteiro' })
  @IsPositive({ message: 'O filtro "consultantId" precisa ser um número positivo' })
  consultantId?: number;
}
