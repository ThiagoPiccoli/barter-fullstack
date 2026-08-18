import { Type } from 'class-transformer';
import {
  ArrayNotEmpty,
  ArrayUnique,
  IsArray,
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

  /**
   * Os consultores que atendem este produtor — a carteira dele, que pode ser
   * de mais de um (consultores dividem região).
   *
   * PELO MENOS UM, e é regra de negócio, não formalidade: produtor sem
   * consultor nenhum não aparece para quem registra permuta, e um cadastro que
   * ninguém enxerga é um cadastro perdido. (O produtor CHEGA a esse estado por
   * outro caminho — a exclusão do último consultor vinculado —, e aí é o admin
   * quem realoca.)
   *
   * `ArrayUnique` porque o vínculo é uma linha só por par: repetir o mesmo id
   * no payload é engano de quem chama, e aceitá-lo em silêncio esbarraria na
   * chave primária composta como erro de banco.
   */
  @IsArray()
  @ArrayNotEmpty({ message: 'Escolha pelo menos um consultor para a carteira' })
  @ArrayUnique({ message: 'O mesmo consultor aparece duas vezes na carteira' })
  @Type(() => Number)
  @IsInt({ each: true })
  @IsPositive({ each: true })
  consultantIds!: number[];

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
 * Filtros da listagem (o filtro por consultor é do admin). Continua no
 * singular, e continua certo: a pergunta é "quem o consultor X atende?", e a
 * resposta agora inclui os produtores que ele divide com outros.
 *
 * Um valor que não é número é RECUSADO: antes ele virava NaN, o filtro sumia
 * do `where` e a resposta trazia todas as carteiras parecendo a carteira
 * pedida.
 */
export class ListProducersQuery extends PaginationQuery {
  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'O filtro "consultantId" precisa ser um número inteiro' })
  @IsPositive({ message: 'O filtro "consultantId" precisa ser um número positivo' })
  consultantId?: number;
}
