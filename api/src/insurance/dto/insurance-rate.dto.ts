import { Type } from 'class-transformer';
import {
  IsIn,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';
import { PRICE_COLUMN_IDS, type PriceColumnId } from '../insurance-import';

/**
 * UMA PRAÇA da base de seguros — o município e quanto custa segurar um hectare
 * nele.
 *
 * O cadastro é curto porque a cotação é curta: um lugar e um valor. O que NÃO
 * existe aqui é safra nem cultura, e a ausência é escolha: a base responde
 * "quanto custa o hectare nesta praça HOJE", e a permuta CONGELA a taxa que
 * usou (ver `Barter.insuranceRatePerHa`). Recotar a praça no ano seguinte é
 * reescrever esta linha — as permutas já fechadas continuam com a taxa do dia
 * delas, que é a mesma promessa do preço do insumo e da alíquota do imposto.
 *
 * O dia em que a mesma praça tiver duas cotações vivas ao mesmo tempo (soja e
 * milho safrinha, por exemplo), isto ganha a safra como segunda chave — e a
 * permuta já sabe qual usar, porque ela nasce dentro de uma versão do Barter.
 * Até lá, uma linha por município é a afirmação certa.
 */
export class InsuranceRateDto {
  /**
   * O município no formato do cadastro de produtor e de unidade: "Maringá/PR".
   *
   * É por ele que a permuta acha a taxa, comparando a forma canônica (ver
   * `cityKeyOf`) — então a grafia aqui é a de exibição, e não a chave.
   */
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  city!: string;

  /**
   * R$ por hectare. Maior que zero: uma praça a R$ 0,00 não é "seguro de
   * graça", é linha pela metade — e ela produziria permutas com uma linha de
   * seguro que não cobra nada, que é pior do que a praça ausente (essa ao menos
   * recusa o registro dizendo o que falta).
   */
  @Type(() => Number)
  @IsNumber()
  @IsPositive({ message: 'O valor por hectare precisa ser maior que zero' })
  valuePerHa!: number;

  /** A seguradora, a vigência da cotação, a cultura. Opcional. */
  @IsOptional()
  @IsString()
  @MaxLength(300)
  note?: string;
}

/**
 * A CARGA da base por planilha — o caminho do admin quando a cotação chega com
 * dezenas de praças.
 *
 * `mode` é a única decisão do formulário, e ela é grande demais para um padrão
 * silencioso:
 *
 * - `merge` (o padrão) ACRESCENTA e ATUALIZA: a praça que já existe recebe o
 *   valor novo, a que não existe entra, e a que não está na planilha fica como
 *   estava. É a carga da cotação parcial — a seguradora recotou o Paraná e
 *   mandou só ele;
 * - `replace` TROCA A BASE INTEIRA: o que não está na planilha é apagado. É a
 *   carga da tabela nova de safra, e é destrutiva de propósito — praça que saiu
 *   da lista é praça que a seguradora não cobre mais, e mantê-la faria permutas
 *   nascerem seguradas por uma apólice que não existe.
 *
 * O padrão é o que NÃO apaga nada, pelo motivo de sempre: o caminho destrutivo
 * se escolhe, não se cai nele.
 */
export const INSURANCE_IMPORT_MODES = ['merge', 'replace'] as const;

export type InsuranceImportMode = (typeof INSURANCE_IMPORT_MODES)[number];

export class ImportInsuranceRatesDto {
  @IsOptional()
  @IsIn(INSURANCE_IMPORT_MODES, {
    message:
      'Escolha como carregar a planilha: "merge" (acrescenta e atualiza) ou "replace" (troca a base)',
  })
  mode?: InsuranceImportMode;

  /**
   * QUAL COLUNA de valor vale — quando a planilha traz mais de uma.
   *
   * A da seguradora traz três (`SEM Subvenção`, `COM Subvenção` e o `Reajuste
   * para Safra … + x% financeiro`), e elas são três preços diferentes para o
   * mesmo hectare. O leitor escolhe sozinho pela ordem de preferência — o
   * reajuste primeiro, que é o valor que a empresa de fato adianta —, e este
   * campo existe para o dia em que a decisão for outra.
   *
   * Ausente é o caso normal. Preenchido com uma coluna que o arquivo não tem, a
   * carga é RECUSADA em vez de cair para a seguinte: trocar a escolha de quem
   * pediu produziria uma base inteira cobrando outro número, em silêncio.
   */
  @IsOptional()
  @IsIn(PRICE_COLUMN_IDS, {
    message: `Coluna de valor inválida. Use uma destas: ${PRICE_COLUMN_IDS.join(', ')}`,
  })
  column?: PriceColumnId;
}
