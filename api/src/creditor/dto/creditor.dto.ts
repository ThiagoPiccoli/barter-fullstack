import { IsNumber, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';

/**
 * O CADASTRO DA CREDORA — a identidade da empresa nos documentos que ela emite.
 *
 * Todos os campos são OPCIONAIS, pelo mesmo motivo do rascunho da cédula: este
 * é um cadastro que nasce vazio numa instalação nova e é completado quando
 * alguém tem os dados na mão. Recusá-lo pela metade travaria quem só quer
 * gravar a razão social hoje e buscar o número da inscrição depois.
 *
 * Quem diz se ele está completo é `creditorGaps()`, sobre o que está GRAVADO —
 * e a resposta chega junto da cédula, endereçada a quem pode resolvê-la.
 */
export class CreditorDto {
  @IsOptional()
  @IsString()
  @MaxLength(160)
  name?: string;

  /** CNPJ com a pontuação que for digitada — é o que sai impresso. */
  @IsOptional()
  @IsString()
  @MaxLength(40)
  cnpj?: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  address?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  addressNumber?: string;

  /** Município/UF da sede, no mesmo formato do produtor ("Maringá/PR"). */
  @IsOptional()
  @IsString()
  @MaxLength(80)
  city?: string;

  /**
   * O foro eleito. Vazio NÃO é lacuna: eleger a comarca da própria sede é o que
   * quase toda credora faz, e é isso que o vazio significa — ver `forumOf`.
   */
  @IsOptional()
  @IsString()
  @MaxLength(80)
  forum?: string;
}

/**
 * A MARGEM DE SEGURANÇA DO PENHOR (%) — a folga de área que a empresa exige além
 * da que a produção estimada justifica.
 *
 * DTO PRÓPRIO, em ROTA PRÓPRIA, e é esse o ponto: o número mora na mesma linha do
 * cadastro da credora (é a linha única da empresa), mas não é cadastro — é REGRA.
 * `PUT /creditor` é de quem mantém o timbre, e o timbre é do admin E DO EMISSOR;
 * esta é de quem decide política de risco, que é só o admin (ver
 * `pledgePolicyManage`). Enquanto ela foi um campo do `CreditorDto`, o emissor
 * mudava a garantia de toda permuta futura pela porta do CNPJ.
 *
 * OBRIGATÓRIA aqui, ao contrário de tudo no `CreditorDto`: lá o ausente significa
 * "ainda não tenho esse dado", e aqui o ato É informar o número. Zero se diz
 * digitando zero.
 *
 * O TETO de 100% não é decoração: ele é o dobro da área estimada, e uma margem
 * acima disso costuma ser um dígito a mais digitado por engano — com o efeito de
 * exigir uma fazenda inteira em garantia de uma permuta pequena, e de travar a
 * carteira do consultor sem que ninguém entenda por quê.
 */
export class PledgeMarginDto {
  @IsNumber({}, { message: 'A margem de segurança do penhor deve ser um número' })
  @Min(0, { message: 'A margem de segurança do penhor não pode ser negativa' })
  @Max(100, { message: 'A margem de segurança do penhor não pode passar de 100%' })
  pledgeMarginPercent!: number;
}
