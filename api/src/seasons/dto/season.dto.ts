import { Transform, Type } from 'class-transformer';
import { INSURANCE_POLICIES, INSURANCE_POLICY_MESSAGE } from '../../insurance/insurance-policy';
import type { InsurancePolicy } from '../../insurance/insurance-policy';
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
  IsIn,
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
 * Abertura da SAFRA DE UMA CULTURA — "Soja 26/27", "Canola 2027".
 *
 * O ANO é o que o admin digita: `startYear` e `endYear`, iguais na cultura que
 * cabe num ano só. Que o final não venha antes do inicial, nem mais de um ano
 * depois, é conferido no service — é uma regra sobre os dois campos juntos, e
 * o DTO vê um de cada vez.
 *
 * `insurancePolicy` é o SEGURO PADRÃO da cultura — o que vem preenchido ao
 * publicar cada versão. Sem ele, `none`.
 */
export class OpenSeasonDto {
  @IsInt()
  @IsPositive({ message: 'Escolha o grão da safra' })
  grainId!: number;

  @IsInt()
  @Min(2000)
  @Max(2999)
  startYear!: number;

  @IsInt()
  @Min(2000)
  @Max(2999)
  endYear!: number;

  @IsOptional()
  @IsIn(INSURANCE_POLICIES, { message: INSURANCE_POLICY_MESSAGE })
  insurancePolicy?: InsurancePolicy;
}

/**
 * A POLÍTICA DE SEGURO — da versão vigente (`PUT /barter-versions/:slug/insurance`)
 * ou o padrão da safra (`PUT /seasons/:slug/insurance`). Um DTO para os dois
 * porque é a mesma pergunta: obrigatório, opcional ou sem seguro.
 *
 * O QUE ELA NÃO FAZ é mexer em permuta já registrada: a escolha e a taxa estão
 * congeladas nela (`Barter.insuranceChoice`, `insuranceRatePerHa`). Vale para
 * as PRÓXIMAS.
 */
export class InsurancePolicyDto {
  @IsIn(INSURANCE_POLICIES, { message: INSURANCE_POLICY_MESSAGE })
  policy!: InsurancePolicy;
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
 * Os TERMOS de uma versão: o que a cultura vale nela, o seguro, as metas e a
 * vigência. É o formulário que acompanha a tabela de insumos na publicação.
 *
 * A cotação e a produtividade são as metades da mesma conversão — o preço leva o
 * custo dos insumos a SACAS, a produtividade leva as sacas à ÁREA de lavoura que
 * precisa garanti-las —, e por isso as duas são obrigatórias: uma versão sem
 * produtividade é uma versão em que nenhuma permuta pode ser registrada.
 */
export class VersionLimitsDto {
  /** A cotação da saca da cultura nesta versão (R$). */
  @NumberFromText()
  @IsNumber()
  @IsPositive({ message: 'Informe o valor da saca' })
  grainPrice!: number;

  @NumberFromText()
  @IsNumber()
  @IsPositive({ message: 'Informe a produtividade estimada da cultura (sacas por hectare)' })
  estimatedYield!: number;

  /**
   * O VENCIMENTO DA CPR desta versão. Opcional no lançamento porque o Barter
   * costuma abrir antes de a data estar acertada; enquanto faltar, nenhuma
   * cédula da versão pode ser emitida, e `cprGaps()` diz isso.
   */
  @IsOptional()
  @IsDateString({}, { message: 'Vencimento da CPR inválido' })
  cprDueDate?: string;

  /**
   * A POLÍTICA DE SEGURO desta versão. Sem ela, vale o padrão da safra — é o
   * que a tela traz preenchido, e o admin muda quando esta versão é diferente.
   */
  @IsOptional()
  @IsIn(INSURANCE_POLICIES, { message: INSURANCE_POLICY_MESSAGE })
  insurancePolicy?: InsurancePolicy;

  @IsOptional()
  @IsDateString({}, { message: 'Data de encerramento inválida' })
  endsAt?: string;

  /**
   * Bater a meta ENCERRA a versão (true) ou apenas avisa (false, o padrão)?
   * Que exista pelo menos uma meta é conferido no service (`assertPublishable`).
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
 * O ACERTO dos termos da cultura numa versão já publicada: a cotação, a
 * produtividade, o vencimento da CPR ou a meta de sacas.
 *
 * Rota própria porque esses números nascem no lançamento, e mudar um deles no
 * meio do Barter obrigaria a republicar a tabela inteira — o que encerraria a
 * versão vigente e reiniciaria a contagem do realizado por causa de um campo.
 *
 * TODOS OPCIONAIS porque os quatro se acertam separadamente. O QUE ELE NÃO FAZ
 * é reescrever permuta registrada nem cédula emitida: a produtividade está
 * congelada em `Barter.pledgeYield`, a cotação no item de grão, e o vencimento
 * congela na emissão.
 */
export class VersionTermsPatchDto {
  @IsOptional()
  @NumberFromText()
  @IsNumber()
  @IsPositive()
  grainPrice?: number;

  @IsOptional()
  @NumberFromText()
  @IsNumber()
  @IsPositive({ message: 'Informe a produtividade estimada da cultura (sacas por hectare)' })
  estimatedYield?: number;

  @IsOptional()
  @IsDateString({}, { message: 'Vencimento da CPR inválido' })
  cprDueDate?: string;

  @IsOptional()
  @NumberFromText()
  @IsNumber()
  @IsPositive()
  targetSacks?: number;
}

/**
 * Publicação de uma versão com a tabela no próprio corpo (o caminho usado por
 * testes, seed e integrações). O caminho do admin no app é o arquivo — ver
 * ImportVersionDto.
 *
 * A MESMA constante de teto que a planilha usa (MAX_VERSION_PRICES, em
 * version-import.ts) — importada, não copiada: os dois caminhos publicam a
 * mesma tabela.
 */
export class PublishVersionDto extends VersionLimitsDto {
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
 * Publicação por ARQUIVO — a planilha DESTA cultura.
 *
 * `carryOver` existe por um detalhe do mundo real: o arquivo do fornecedor às
 * vezes traz só o que mudou. Ligado, os insumos ausentes seguem com o preço da
 * versão anterior DA MESMA SAFRA; desligado (o padrão), a planilha É a tabela e
 * o que não está nela deixa de ser permutável.
 */
export class ImportVersionDto extends VersionLimitsDto {
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
export class CloseOnGoalDto {
  @BooleanFromText()
  @IsBoolean({ message: 'Informe true para encerrar ao bater meta, ou false para manual' })
  enabled!: boolean;
}
