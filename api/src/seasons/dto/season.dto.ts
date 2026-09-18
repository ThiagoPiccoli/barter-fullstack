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

/**
 * Booleano que pode chegar como TEXTO — o mesmo motivo do `NumberFromText`: os
 * dois caminhos de publicação são JSON (booleano de verdade) e multipart (onde
 * `true` é a palavra "true").
 *
 * Só "true"/"false" passam. Texto de outra forma é devolvido intacto para o
 * `@IsBoolean` reclamar: um `Boolean("qualquer coisa")` silencioso ligaria o
 * encerramento automático por causa de um erro de digitação.
 */
const BooleanFromText = (): PropertyDecorator =>
  Transform(({ value }: { value: unknown }) => {
    if (typeof value === 'boolean') return value;
    if (typeof value !== 'string') return value;
    const text = value.trim().toLowerCase();
    if (text === '') return undefined;
    if (text === 'true') return true;
    if (text === 'false') return false;
    return value;
  });
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
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

  /**
   * O VENCIMENTO DA CPR desta safra — a data em que a entrega do grão vence.
   *
   * Opcional na abertura porque a safra costuma abrir antes de a data estar
   * acertada, e travar a abertura por causa dela empurraria o admin a chutar um
   * dia. Enquanto ela faltar, nenhuma cédula da safra pode ser emitida, e
   * `cprGaps()` diz isso com o recado endereçado a quem pode resolver. Ver
   * `SeasonCprDueDateDto`, que é por onde ela se acerta depois.
   */
  @IsOptional()
  @IsDateString({}, { message: 'Vencimento da CPR inválido' })
  cprDueDate?: string;
}

/**
 * O VENCIMENTO DA CPR de uma safra, acertado depois da abertura.
 *
 * Rota própria porque a safra ABERTA não se edita de resto: o grão, o ano e o
 * código dela são o que as permutas já fechadas apontam, e um `PUT` genérico de
 * safra abriria a porta para mexer neles. Esta data é a única coisa da safra que
 * muda legitimamente depois — ela é decisão comercial, e a colheita se antecipa
 * ou atrasa.
 *
 * O QUE ELA NÃO FAZ é reescrever cédula emitida: `dueDate` é copiado para a
 * cédula a cada gravação e congela na emissão (ver `saveCpr`). Mudar a data aqui
 * vale para as cédulas que ainda não saíram, que é a leitura certa — o título
 * que já está com o produtor diz o que diz.
 */
export class SeasonCprDueDateDto {
  @IsDateString({}, { message: 'Vencimento da CPR inválido' })
  cprDueDate!: string;
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

  /**
   * Bater a meta ENCERRA o Barter (true) ou apenas avisa (false, o padrão)?
   *
   * Que exista pelo menos uma meta é conferido no service, e não aqui: o DTO vê
   * um campo por vez, e esta é uma regra sobre a combinação deles. Ver
   * `assertPublishable`.
   */
  @IsOptional()
  @BooleanFromText()
  @IsBoolean({ message: 'closeOnGoal deve ser true ou false' })
  closeOnGoal?: boolean;

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
   * A PRODUTIVIDADE ESTIMADA da cultura (sc/ha) — obrigatória, como o preço da
   * saca, e pelo mesmo motivo.
   *
   * As duas são as metades da mesma conversão: o preço leva o custo dos insumos
   * a sacas, a produtividade leva as sacas à área de lavoura que precisa
   * garanti-las. Publicar sem ela é publicar um Barter em que nenhuma permuta
   * pode ser registrada (`POST /barters` recusa) — e recusar AQUI é dizer isso no
   * único momento em que o admin está com a tela do lançamento aberta, em vez de
   * deixar a descoberta para o primeiro consultor que tentar vender.
   */
  @IsNumber()
  @IsPositive({ message: 'Informe a produtividade estimada da cultura (sacas por hectare)' })
  estimatedYield!: number;

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

  /** A produtividade estimada (sc/ha) — ver `PublishVersionDto.estimatedYield`. */
  @NumberFromText()
  @IsNumber()
  @IsPositive({ message: 'Informe a produtividade estimada da cultura (sacas por hectare)' })
  estimatedYield!: number;

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

/**
 * Troca o modo de encerramento da versão vigente, sem republicar a tabela.
 *
 * Existe porque a alternativa era pior: a opção nasce no lançamento, junto das
 * metas, e mudar de ideia no meio do Barter obrigaria a publicar uma versão nova
 * — o que encerraria a atual e reiniciaria a contagem do realizado só para
 * virar um interruptor.
 */
/**
 * A PRODUTIVIDADE ESTIMADA de uma versão já publicada.
 *
 * Rota própria pelo mesmo motivo do `cprDueDate` da safra e do `closeOnGoal`: ela
 * é obrigatória no lançamento, mas as versões anteriores a este campo nasceram
 * sem ela — e elas são justamente as vigentes hoje, que travariam toda venda até
 * alguém republicar a tabela inteira só para informar um número. Republicar
 * encerraria a versão atual e reiniciaria a contagem do realizado: um preço de
 * dois dígitos por um campo de dois dígitos.
 *
 * O QUE ELA NÃO FAZ é reescrever permuta já registrada — a taxa é congelada em
 * `Barter.pledgeYield` no ato do registro. Corrigi-la aqui vale para as
 * próximas, que é a mesma leitura do vencimento da safra: o que já foi acordado
 * continua dizendo o que diz.
 */
export class VersionEstimatedYieldDto {
  @NumberFromText()
  @IsNumber()
  @IsPositive({ message: 'Informe a produtividade estimada da cultura (sacas por hectare)' })
  estimatedYield!: number;
}

export class CloseOnGoalDto {
  @BooleanFromText()
  @IsBoolean({ message: 'Informe true para encerrar ao bater meta, ou false para manual' })
  enabled!: boolean;
}
