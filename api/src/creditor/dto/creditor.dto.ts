import { IsOptional, IsString, MaxLength } from 'class-validator';

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
