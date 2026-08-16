import { Transform, Type } from 'class-transformer';
import { MAX_VERSION_PRICES, parseNumber } from '../version-import';

/**
 * Número que pode chegar como TEXTO — e como o Brasil escreve.
 *
 * Dois motivos: no multipart todo campo é texto (o formulário de publicação vai
 * junto com a planilha), e o admin digita "152,50" com vírgula, exatamente como
 * na tabela do fornecedor. Usa o mesmo leitor de número da planilha para não
 * existirem duas regras de conversão no sistema.
 *
 * Valor ilegível é devolvido intacto de propósito: quem reclama é o `@IsNumber`,
 * com a mensagem de validação — e não um NaN silencioso virando preço.
 */
const NumberFromText = (): PropertyDecorator =>
  Transform(({ value }: { value: unknown }) => {
    if (typeof value === 'number') return value;
    if (typeof value !== 'string' || value.trim() === '') return undefined;
    return parseNumber(value) ?? value;
  });
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsDateString,
  IsInt,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

/**
 * Abertura de uma SAFRA: o Barter acontece sobre um grão, durante um ciclo.
 *
 * A `letter` é opcional porque tem sugestão automática (a primeira letra do
 * grão), mas é editável: soja e sorgo disputam o "S", e quem desempata é o
 * admin. Ver season-code.ts.
 */
export class OpenSeasonDto {
  @IsInt()
  @IsPositive()
  grainId!: number;

  @IsInt()
  @Min(2000)
  @Max(2999)
  year!: number;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  name?: string;

  @IsOptional()
  @Matches(/^[A-Za-z]{1,2}$/, { message: 'A letra da safra deve ter 1 ou 2 letras' })
  letter?: string;
}

/** Uma linha da tabela de valores quando a versão é publicada por JSON. */
export class VersionPriceDto {
  @IsInt()
  @IsPositive()
  productId!: number;

  @IsNumber()
  @IsPositive()
  price!: number;
}

/**
 * Metas e vigência de uma versão. Estão aqui juntas porque respondem à mesma
 * pergunta ("até quando este Barter vale?") por dois caminhos: o calendário e
 * o volume. Ver version-progress.ts para a diferença de efeito entre elas.
 */
export class VersionLimitsDto {
  @IsOptional()
  @IsDateString({}, { message: 'Data de encerramento inválida' })
  endsAt?: string;

  // Metas: ver NumberFromText — no multipart elas chegam como texto.
  @IsOptional()
  @NumberFromText()
  @IsNumber()
  @IsPositive()
  targetSales?: number;

  @IsOptional()
  @NumberFromText()
  @IsNumber()
  @IsPositive()
  targetSacks?: number;

  @IsOptional()
  @NumberFromText()
  @IsInt()
  @IsPositive()
  targetBarters?: number;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  note?: string;
}

/**
 * Publicação de uma versão com a tabela no próprio corpo (o caminho usado por
 * testes, seed e integrações). O caminho do admin no app é o arquivo — ver
 * ImportVersionDto.
 */
export class PublishVersionDto extends VersionLimitsDto {
  @IsNumber()
  @IsPositive()
  grainPrice!: number;

  /**
   * A MESMA constante que a planilha usa (MAX_VERSION_PRICES, em
   * version-import.ts) — importada, não copiada. Os dois caminhos publicam a
   * mesma tabela, e um limite diferente em cada um significaria que o arquivo
   * recusa o que o JSON aceita.
   */
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(MAX_VERSION_PRICES, {
    message: `A tabela de valores não pode passar de ${MAX_VERSION_PRICES.toLocaleString('pt-BR')} itens`,
  })
  @ValidateNested({ each: true })
  @Type(() => VersionPriceDto)
  prices!: VersionPriceDto[];
}

/**
 * Publicação por ARQUIVO.
 *
 * `carryOver` existe por um detalhe do mundo real: o arquivo do fornecedor às
 * vezes traz só o que mudou. Ligado, os insumos ausentes seguem com o preço da
 * versão anterior; desligado (o padrão), a planilha É a tabela e o que não
 * está nela deixa de ser permutável — que é o significado forte de "publiquei
 * uma tabela nova".
 */
export class ImportVersionDto extends VersionLimitsDto {
  @NumberFromText()
  @IsNumber()
  @IsPositive()
  grainPrice!: number;

  @IsOptional()
  @Matches(/^(true|false)$/i, { message: 'carryOver deve ser true ou false' })
  carryOver?: string;
}

/** Correção pontual de um valor dentro da versão vigente. */
export class UpdateVersionPriceDto {
  @IsNumber()
  @IsPositive()
  price!: number;
}
