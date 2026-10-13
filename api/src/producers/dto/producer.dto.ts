import { Type } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsOptional,
  IsPositive,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';
import { TAX_REGIMES, TAX_REGIME_MESSAGE, type TaxRegime } from '../../barters/tax-regime';
import { PaginationQuery } from '../../common/pagination';
import { DOCUMENT_MESSAGE, DOCUMENT_PATTERN } from '../document';

export class ProducerDto {
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name!: string;

  /**
   * O consultor que atende este produtor — a carteira dele, uma só.
   *
   * OPCIONAL porque o CONSULTOR também cadastra e edita o produtor, e a carteira
   * continua sendo decisão do admin (ver `producersRegister` e `producersEdit`
   * em policy.ts). Na edição, ausente significa "não mexa em quem atende"; no
   * CADASTRO, quem resolve é o service: o do admin exige o consultor, e o do
   * consultor nasce na carteira de quem cadastrou.
   *
   * Não aceita nulo: tirar o produtor de toda carteira não é uma escolha do
   * formulário. Ele só chega a esse estado pela exclusão do consultor, e aí o
   * admin o realoca.
   */
  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'Escolha um consultor válido para a carteira' })
  @IsPositive({ message: 'Escolha um consultor válido para a carteira' })
  consultantId?: number;

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

  // A ÁREA não é mais do cadastro: ela é de cada PERMUTA (a área plantada da
  // cultura que ela cobre — ver `Barter.plantedAreaHa`). A fazenda planta mais de
  // uma coisa, e um número só para ela media soja contra a terra do trigo.

  /**
   * COMO ESTE PRODUTOR RECOLHE o Funrural: `comercializacao` (sobre a receita da
   * venda) ou `folha` (sobre a folha de pagamento — e aí sobre a entrega fica só
   * o Senar). Ver `barters/tax-regime.ts`.
   *
   * É dado de CADASTRO porque é o que ele é: a opção formal perante o fisco vale
   * para o ano e para todas as entregas dele, e não para uma permuta. Cada
   * permuta continua gravando o regime e a alíquota que aplicou.
   *
   * Opcional, e o ausente vale `comercializacao`: é o regime de quem não fez
   * opção nenhuma, que é a maioria — e é o que os cadastros anteriores a este
   * campo têm de verdade. Exigi-lo recusaria o formulário de qualquer cliente da
   * API que ainda não conheça o campo.
   */
  @IsOptional()
  @IsIn(TAX_REGIMES, { message: TAX_REGIME_MESSAGE })
  taxRegime?: TaxRegime;
}

/**
 * Filtros da listagem (o filtro por consultor é do admin): "quem o consultor X
 * atende?".
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
