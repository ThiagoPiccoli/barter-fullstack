import { plainToInstance, Transform, Type } from 'class-transformer';
import { MAX_VERSION_PRICES, parseNumber } from '../version-import';

/**
 * Quantas CULTURAS um lançamento aceita.
 *
 * O número não é uma regra de negócio — ninguém publica um Barter de vinte
 * grãos —, é a trava que impede um payload defeituoso de virar uma versão com
 * mil culturas dentro. Folgado de propósito: soja, milho, trigo, sorgo, feijão e
 * arroz numa mesma janela já é mais do que a operação faz.
 */
export const MAX_VERSION_GRAINS = 12;

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

/**
 * As CULTURAS chegando como JSON num campo de texto (o multipart da planilha).
 *
 * O `plainToInstance` no fim é o ponto: sem ele os objetos chegariam à validação
 * como objetos simples, e `@ValidateNested` não teria metadados para conferir —
 * uma cotação negativa passaria pelo caminho do arquivo e seria recusada pelo do
 * JSON. Texto ilegível é devolvido intacto, para o `@IsArray` reclamar com a
 * mensagem da validação em vez de virar uma lista vazia em silêncio.
 */
const GrainsFromText = (): PropertyDecorator =>
  Transform(({ value }: { value: unknown }) => {
    if (typeof value !== 'string') return value;
    let parsed: unknown;
    try {
      parsed = JSON.parse(value);
    } catch {
      return value;
    }
    if (!Array.isArray(parsed)) return parsed;
    return plainToInstance(VersionGrainDto, parsed);
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
 * Abertura de uma SAFRA: o CICLO em que o Barter acontece.
 *
 * NÃO HÁ GRÃO AQUI, e essa é a mudança: as culturas são do lançamento (ver
 * `VersionGrainDto`), porque elas coexistem e mudam de uma versão para a outra —
 * o Barter pode abrir só com soja e acrescentar o milho na versão seguinte, sem
 * que a safra tenha deixado de ser a mesma.
 *
 * A `letter` continua opcional e continua editável: ela era a inicial do grão
 * ("S de soja") e hoje é só a letra do ciclo (`B` de Barter, o padrão). Quem
 * roda dois ciclos no mesmo ano — verão e inverno — os separa por ela.
 */
export class OpenSeasonDto {
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

/**
 * UMA CULTURA do lançamento: o grão em que a permuta pode ser paga e as três
 * coisas que mudam de um grão para o outro.
 *
 * As duas primeiras são as metades da mesma conversão — o preço leva o custo dos
 * insumos a SACAS, a produtividade leva as sacas à ÁREA de lavoura que precisa
 * garanti-las —, e por isso as duas são obrigatórias: uma cultura publicada sem
 * produtividade é uma cultura em que nenhuma permuta pode ser registrada (`POST
 * /barters` recusa), e recusar aqui é dizer isso enquanto o admin ainda está com
 * a tela do lançamento aberta.
 */
export class VersionGrainDto {
  @NumberFromText()
  @IsInt()
  @IsPositive()
  grainId!: number;

  /** A cotação da saca desta cultura nesta versão (R$). */
  @NumberFromText()
  @IsNumber()
  @IsPositive()
  price!: number;

  @NumberFromText()
  @IsNumber()
  @IsPositive({ message: 'Informe a produtividade estimada da cultura (sacas por hectare)' })
  estimatedYield!: number;

  /**
   * O VENCIMENTO DA CPR desta cultura — a data em que a entrega vence.
   *
   * Opcional no lançamento porque o Barter costuma abrir antes de a data estar
   * acertada, e travar a publicação por causa dela empurraria o admin a chutar um
   * dia. Enquanto faltar, nenhuma cédula daquela cultura pode ser emitida, e
   * `cprGaps()` diz isso com o recado endereçado a quem resolve. Ver
   * `VersionGrainPatchDto`, que é por onde ela se acerta depois.
   */
  @IsOptional()
  @IsDateString({}, { message: 'Vencimento da CPR inválido' })
  cprDueDate?: string;

  /** A meta de sacas desta cultura. Ver `BarterVersion.targetSales`. */
  @IsOptional()
  @NumberFromText()
  @IsNumber()
  @IsPositive()
  targetSacks?: number;
}

/**
 * O ACERTO de uma cultura já publicada: a cotação, a produtividade, o
 * vencimento da CPR ou a meta de sacas.
 *
 * Rota própria pelo mesmo motivo que o vencimento da safra e o `closeOnGoal`
 * tinham a sua: esses números nascem no lançamento, e mudar um deles no meio do
 * Barter obrigaria a republicar a tabela inteira — o que encerraria a versão
 * vigente e reiniciaria a contagem do realizado por causa de um campo.
 *
 * TODOS OPCIONAIS porque os quatro se acertam separadamente (a colheita se
 * antecipa, a diretoria revê a estimativa), e o service recusa o corpo vazio: um
 * `PUT` que não muda nada gravaria uma linha de trilha dizendo que nada mudou.
 *
 * O QUE ELE NÃO FAZ é reescrever permuta registrada nem cédula emitida: a
 * produtividade está congelada em `Barter.pledgeYield`, a cotação no item de
 * grão, e o vencimento congela na emissão. Vale para o que ainda vai acontecer.
 */
export class VersionGrainPatchDto {
  @IsOptional()
  @NumberFromText()
  @IsNumber()
  @IsPositive()
  price?: number;

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

  /**
   * ESTE LANÇAMENTO LEVA SEGURO AGRÍCOLA? (false, o padrão).
   *
   * É a chave do seguro, e ela mora no lançamento porque contratar seguro é
   * decisão comercial da SAFRA — a empresa fechou apólice com a seguradora, ou
   * não —, e não caso a caso do consultor. Ligada, toda permuta desta versão
   * nasce com a linha do seguro, precificada pelo município do produtor (ver
   * `InsuranceRate`) e paga em sacas como qualquer custo adiantado.
   *
   * Ela vem aqui, nos LIMITES, e não ao lado de `grainPrice` e
   * `estimatedYield`: aquelas duas são taxas obrigatórias que a conta usa; esta
   * é uma opção do lançamento, da mesma natureza de `closeOnGoal` — e, como
   * ela, o padrão é o que não acrescenta nada a ninguém.
   *
   * O que ela NÃO faz é conferir se as praças dos produtores estão na base de
   * seguros: publicar não conhece os produtores, e a base muda depois. Quem
   * cobra é o REGISTRO da permuta, com a frase que nomeia o município que falta
   * (ver `missingRateRefusal`).
   */
  @IsOptional()
  @BooleanFromText()
  @IsBoolean({ message: 'insuranceRequired deve ser true ou false' })
  insuranceRequired?: boolean;

  // Metas: ver NumberFromText — no multipart elas chegam como texto.
  @IsOptional()
  @NumberFromText()
  @IsNumber()
  @IsPositive()
  targetSales?: number;

  // A META DE SACAS não está aqui: ela é de cada CULTURA (ver
  // `VersionGrainDto.targetSacks`). Sacas de soja e de milho não somam, e um
  // número único juntando as duas seria uma barra de progresso sem significado.

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
  /**
   * AS CULTURAS deste lançamento — pelo menos uma, e quantas coexistirem.
   *
   * É uma lista, e não um grão com uma cotação, porque as culturas convivem: na
   * mesma janela o produtor fecha soja e milho, e o Barter aceita as duas com
   * cotações, produtividades e vencimentos próprios (ver `VersionGrainDto`)
   * sobre a MESMA tabela de insumos.
   *
   * O teto é folgado de propósito: ele não existe para limitar o negócio, e sim
   * para que um payload defeituoso não vire uma versão com mil culturas.
   */
  @IsArray()
  @ArrayMinSize(1, { message: 'Escolha ao menos uma cultura para este Barter' })
  @ArrayMaxSize(MAX_VERSION_GRAINS, {
    message: `Um Barter não aceita mais de ${MAX_VERSION_GRAINS} culturas`,
  })
  @ValidateNested({ each: true })
  @Type(() => VersionGrainDto)
  grains!: VersionGrainDto[];

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
  /**
   * AS CULTURAS, em JSON dentro de um campo de texto.
   *
   * No multipart todo campo é texto — o formulário vai junto com a planilha —, e
   * uma lista de objetos não tem como chegar de outro jeito. O `GrainsFromText`
   * a transforma em instâncias do DTO da cultura, para que a validação aninhada
   * seja a MESMA do caminho JSON: uma cotação negativa é recusada com a mesma
   * frase, tenha ela chegado por um formulário ou por um corpo de requisição.
   */
  @GrainsFromText()
  @IsArray()
  @ArrayMinSize(1, { message: 'Escolha ao menos uma cultura para este Barter' })
  @ArrayMaxSize(MAX_VERSION_GRAINS, {
    message: `Um Barter não aceita mais de ${MAX_VERSION_GRAINS} culturas`,
  })
  @ValidateNested({ each: true })
  @Type(() => VersionGrainDto)
  grains!: VersionGrainDto[];

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

/**
 * LIGA ou DESLIGA o seguro agrícola de uma versão já publicada.
 *
 * Rota própria pelo mesmo motivo do `closeOnGoal` e da produtividade estimada: a
 * opção nasce no lançamento, e mudar de ideia no meio do Barter obrigaria a
 * republicar a tabela inteira — o que encerraria a versão vigente e reiniciaria
 * a contagem do realizado só para virar um interruptor.
 *
 * E mudar de ideia acontece: a apólice sai depois da tabela, a seguradora
 * atrasa a cotação de uma região, a diretoria decide incluir o seguro com o
 * Barter já aberto.
 *
 * O QUE ELA NÃO FAZ é mexer em permuta já registrada. A taxa está congelada em
 * `Barter.insuranceRatePerHa`, e as permutas de ontem continuam dizendo o que
 * dizem — inclusive as que nasceram sem seguro nenhum. Vale para as PRÓXIMAS,
 * que é a mesma leitura do vencimento da safra e da produtividade.
 */
export class VersionInsuranceDto {
  @BooleanFromText()
  @IsBoolean({ message: 'Informe true para este Barter levar seguro, ou false para não levar' })
  enabled!: boolean;
}
