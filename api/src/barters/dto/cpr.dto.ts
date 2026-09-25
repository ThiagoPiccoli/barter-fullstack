import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsDateString,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';

/**
 * O PREENCHIMENTO DA CÉDULA pelo consultor.
 *
 * TUDO É OPCIONAL, e isso é a decisão de desenho deste arquivo: a cédula é
 * montada aos pedaços. A qualificação do emitente o consultor tem da visita; a
 * matrícula da lavoura costuma vir por e-mail do produtor no dia seguinte; o SCR
 * sai depois da consulta. Exigir tudo de uma vez faria o formulário recusar
 * exatamente o estado em que o trabalho passa a maior parte do tempo, e o
 * rascunho voltaria para o papel ao lado do computador.
 *
 * Quem responde "está completa?" é `cprGaps()`, em cpr.ts, sobre o que está
 * GRAVADO — a pergunta é outra e o momento é outro. Este DTO só diz se o que
 * chegou é gravável.
 *
 * O que NÃO existe aqui, de propósito:
 *
 * - nada da CREDORA (razão social, CNPJ, endereço, foro): é configuração da
 *   instalação, e digitá-la a cada cédula é digitar o CNPJ do próprio
 *   empregador trezentas vezes;
 * - nada que a PERMUTA já sabe (sacas, produto, preço, valor total, emitente, o
 *   vencimento da safra e os números das notas fiscais): o `whitelist` do
 *   ValidationPipe descarta se vier, e é para descartar mesmo — um valor de
 *   cédula que discorde do registro é um título cobrando o que não foi acordado;
 * - nenhum EXTENSO: eles são a escrita do número ao lado, e pertencem à geração
 *   do documento. O modelo recebido mostra por quê — ele traz "367 (quatrocentos
 *   e quarenta) sacas", com o algarismo e o extenso discordando.
 */
export class CprOwnerDto {
  @IsString()
  @MaxLength(120)
  name!: string;

  /** CPF ou CNPJ do dono do imóvel, com a pontuação que for digitada. */
  @IsString()
  @MaxLength(40)
  document!: string;
}

/**
 * UMA LAVOURA dada em penhor. A cédula as enumera — "(i)", "(ii)" —, e por isso
 * a ordem em que chegam é a ordem em que elas saem impressas.
 */
export class CprAreaDto {
  @IsString()
  @MaxLength(120)
  locality!: string;

  /** Município/UF, no mesmo formato do produtor ("Maringá/PR"). */
  @IsString()
  @MaxLength(80)
  city!: string;

  /**
   * Hectares PLANTADOS nesta matrícula. Aceita zero porque o rascunho aceita —
   * `cprGaps()` é quem cobra o número antes de a cédula sair.
   */
  @IsNumber()
  @Min(0)
  areaHa!: number;

  /** O "dentro de uma área maior" do modelo: o plantio ocupa parte do imóvel. */
  @IsOptional()
  @IsBoolean()
  withinLargerArea?: boolean;

  @IsString()
  @MaxLength(60)
  registryNumber!: string;

  @IsString()
  @MaxLength(60)
  registryBook!: string;

  /** A comarca do Registro de Imóveis, como cidade/UF. */
  @IsString()
  @MaxLength(80)
  registryDistrict!: string;

  /**
   * Os donos do imóvel — que raramente são o emitente: a lavoura penhorada
   * costuma ser arrendada, e é por isso que o modelo nomeia o proprietário
   * separadamente de quem planta.
   *
   * O teto é o mesmo raciocínio do `ArrayMaxSize` dos insumos: não é sobre o
   * negócio, é sobre o custo da requisição. Imóvel em espólio tem meia dúzia de
   * herdeiros; vinte é folga para nenhum caso real esbarrar.
   */
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(20, { message: 'Uma lavoura não pode listar mais de 20 proprietários' })
  @ValidateNested({ each: true })
  @Type(() => CprOwnerDto)
  owners?: CprOwnerDto[];
}

/**
 * Um AVALISTA. Todos os campos opcionais, como o resto do rascunho — e a lista
 * inteira substitui a que estava lá, como as lavouras.
 *
 * O bloco é longo porque a proposta o pede longo: quem se obriga por outro é
 * qualificado com o mesmo rigor de quem deve.
 */
export class CprGuarantorDto {
  @IsOptional() @IsString() @MaxLength(120) name?: string;
  @IsOptional() @IsString() @MaxLength(40) document?: string;
  @IsOptional() @IsString() @MaxLength(40) rg?: string;
  @IsOptional() @IsString() @MaxLength(40) cnh?: string;
  @IsOptional() @IsString() @MaxLength(60) nationality?: string;
  @IsOptional() @IsString() @MaxLength(80) profession?: string;
  @IsOptional() @IsString() @MaxLength(60) maritalStatus?: string;
  @IsOptional() @IsString() @MaxLength(120) fatherName?: string;
  @IsOptional() @IsString() @MaxLength(120) motherName?: string;
  @IsOptional() @IsString() @MaxLength(160) email?: string;
  @IsOptional() @IsString() @MaxLength(160) address?: string;
  @IsOptional() @IsString() @MaxLength(20) addressNumber?: string;
  @IsOptional() @IsString() @MaxLength(80) city?: string;
  @IsOptional() @IsString() @MaxLength(120) spouseName?: string;
  @IsOptional() @IsString() @MaxLength(40) spouseDocument?: string;
  @IsOptional() @IsString() @MaxLength(40) spouseRg?: string;
  @IsOptional() @IsString() @MaxLength(60) spouseNationality?: string;
  @IsOptional() @IsString() @MaxLength(80) spouseProfession?: string;
}

export class SaveCprDto {
  /** O número da cédula, como a credora a numera. */
  @IsOptional()
  @IsString()
  @MaxLength(60)
  number?: string;

  /**
   * A EMISSÃO ("Aos [DIA] dias do mês de…").
   *
   * O VENCIMENTO não está aqui, e a ausência é a regra: ele muda conforme a
   * CULTURA e vale para a safra inteira (ver `Season.cprDueDate`). Quem o
   * escreve na cédula é o servidor, copiando-o da safra a cada gravação até a
   * emissão. Um campo aqui devolveria o problema que ele resolve — duas cédulas
   * da mesma safra vencendo em dias diferentes, sem como saber qual está certa.
   */
  @IsOptional()
  @IsDateString({}, { message: 'Data de emissão inválida' })
  issuedAt?: string;

  // ── Qualificação civil do emitente ───────────────────────────────────────
  // O que a lei exige de quem emite título e o cadastro de produtor não guarda.

  @IsOptional()
  @IsString()
  @MaxLength(60)
  emitterNationality?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  emitterMaritalStatus?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  emitterProfession?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  emitterRg?: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  emitterAddress?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  emitterAddressNumber?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  emitterCity?: string;

  /** Matrícula na cooperativa — fecha o bloco de assinatura. */
  @IsOptional()
  @IsString()
  @MaxLength(40)
  emitterCoopId?: string;

  // ── O que a PROPOSTA pede e a cédula não imprime ─────────────────────────
  // CNH, filiação e e-mail não aparecem em cláusula nenhuma do modelo. São
  // coletados porque o cartório e a operação os pedem — a filiação individualiza
  // um homônimo no registro, o e-mail é por onde a assinatura eletrônica chega.
  // `cprGaps()` NÃO os cobra: quem decide o que falta é o documento.

  @IsOptional()
  @IsString()
  @MaxLength(40)
  emitterCnh?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  emitterFatherName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  emitterMotherName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  emitterEmail?: string;

  /**
   * O LOCAL DA ENTREGA do grão (cláusula V, "d") — este SAI no documento, e por
   * isso é cobrado. Ele é campo, e não a unidade de retirada da permuta:
   * retirar insumo na Filial 02 não obriga a entregar o grão lá. A unidade vai
   * como sugestão no formulário.
   */
  @IsOptional()
  @IsString()
  @MaxLength(160)
  deliveryPlace?: string;

  /** Hipotecas oferecidas, como a proposta as pede: texto livre. */
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  mortgages?: string;

  // ── Anuência do cônjuge ──────────────────────────────────────────────────
  // Só quem é casado assina acompanhado; o bloco fica vazio no resto das
  // cédulas, e vazio aqui é "não há", não "falta". O estado civil e o endereço
  // do cônjuge não são pedidos: o primeiro é o do emitente (é o que faz dele
  // cônjuge) e o segundo é o mesmo domicílio.

  @IsOptional()
  @IsString()
  @MaxLength(120)
  spouseName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  spouseNationality?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  spouseProfession?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  spouseDocument?: string;

  /** RG do cônjuge — da proposta; o modelo qualifica o cônjuge por CPF. */
  @IsOptional()
  @IsString()
  @MaxLength(40)
  spouseRg?: string;

  // ── Padrão do grão recebido ──────────────────────────────────────────────

  /**
   * Quilos por saca — o que converte as sacas da permuta nos quilos da cédula.
   * 60 é o padrão do mercado, e é o default da coluna; o teto largo existe
   * porque big-bag e granel não seguem a saca.
   */
  @IsOptional()
  @IsNumber()
  @Min(1, { message: 'O peso da saca precisa ser maior que zero' })
  @Max(2000)
  sackWeightKg?: number;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  cultivar?: string;

  /**
   * Percentuais, e por isso limitados a 100: uma umidade máxima de 140% é
   * dedo escorregado no teclado, e ela sairia impressa num título de crédito.
   */
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100, { message: 'A umidade máxima é um percentual (0 a 100)' })
  maxMoisture?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100, { message: 'As impurezas máximas são um percentual (0 a 100)' })
  maxImpurities?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100, { message: 'O teor de óleo é um percentual (0 a 100)' })
  oilContent?: number;

  // ── O SCR do produtor ────────────────────────────────────────────────────
  //
  // O ARQUIVO não entra aqui: ele sobe por rota própria (`PUT
  // /barters/:code/cpr/scr`, multipart), porque um anexo de dois megabytes
  // dentro de um JSON de formulário faria cada salvamento de rascunho
  // reenviá-lo. O que este campo guarda é a DATA da consulta — o SCR é uma
  // fotografia, e "está anexado" não responde "de quando?".

  @IsOptional()
  @IsDateString({}, { message: 'Data da consulta ao SCR inválida' })
  scrConsultedAt?: string;

  // ── Seguro ───────────────────────────────────────────────────────────────

  /** Apólice do seguro embutido (cláusula XVIII, "j"). Nem toda permuta tem. */
  @IsOptional()
  @IsString()
  @MaxLength(60)
  insurancePolicy?: string;

  // ── As lavouras do penhor ────────────────────────────────────────────────

  /**
   * A lista INTEIRA, sempre: mandar `areas` substitui as que estavam lá.
   *
   * É o formato de um formulário de lista, e não de uma API de coleção — o
   * consultor edita a lavoura na tela e salva a cédula, e ele não deveria ter
   * de excluir a segunda área por uma chamada separada. Omitir o campo mantém
   * as lavouras como estão, que é o que um salvamento parcial precisa.
   */
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(20, { message: 'Uma cédula não pode ter mais de 20 lavouras' })
  @ValidateNested({ each: true })
  @Type(() => CprAreaDto)
  areas?: CprAreaDto[];

  /**
   * Os AVALISTAS, pela mesma regra das lavouras: mandar a lista substitui a que
   * estava; omiti-la preserva.
   */
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(10, { message: 'Uma cédula não pode ter mais de 10 avalistas' })
  @ValidateNested({ each: true })
  @Type(() => CprGuarantorDto)
  guarantors?: CprGuarantorDto[];
}

/* ── A EMISSÃO: os três atos do emissor ─────────────────────────────────── */

/**
 * A EMISSÃO da cédula — a conferência do emissor, e o documento gerado.
 *
 * Ela quase não tem corpo, e é o certo: o emissor não escreve a cédula (isso é
 * do consultor) e não decide o negócio (isso é do comitê). O que ele faz é
 * conferir e gerar — e quem diz se dá para gerar é `cprGaps()`, sobre o que está
 * gravado, não um campo deste DTO.
 *
 * A observação existe para o caso que foge: a cédula saiu em papel timbrado
 * antigo, o produtor pediu duas vias, a conferência achou um detalhe que não
 * trava a emissão mas merece ficar escrito.
 */
export class IssueCprDto {
  /**
   * O NÚMERO DA CÉDULA, informado no ato de emitir.
   *
   * Ele é a ÚNICA coisa da cédula que o emissor escreve, e escreve porque é a
   * única que ele tem: a numeração da CPR é da emissão em papel e vem de fora
   * deste sistema — cartório, B3, controle interno da credora. O consultor não a
   * conhece quando visita a fazenda, e cobrá-la dele no encaminhamento travaria
   * a esteira num número que só existe semanas depois.
   *
   * OPCIONAL aqui porque a cédula pode já tê-lo (a credora numera em bloco, e
   * alguém adiantou). O que não pode é EMITIR sem número — quem cobra isso é
   * `cprGaps()`, sobre o que ficou gravado, e não este campo.
   */
  @IsOptional()
  @IsString()
  @MaxLength(60)
  number?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;
}

/**
 * A COLETA DE ASSINATURAS concluída.
 *
 * `signedAt` é opcional e vale HOJE quando ausente — a assinatura costuma ser
 * registrada no dia, e pedir a data de novo seria pedir que alguém confirme o
 * calendário. Ela existe para o lançamento atrasado, que é o caso real: o
 * produtor assinou na fazenda na quinta e o papel chegou ao escritório na
 * segunda.
 *
 * A observação é onde se diz QUEM assinou — o emitente, o cônjuge, os avalistas
 * — e como (presencial, eletrônica). Ela é opcional porque a assinatura completa
 * é o caso normal e não tem o que explicar.
 */
/**
 * O lançamento das ASSINATURAS. Chega por `multipart/form-data`, ao lado da
 * cédula assinada — por isso todos os campos são texto, como no `AttachInvoiceDto`.
 */
export class SignCprDto {
  @IsOptional()
  @IsDateString({}, { message: 'Data da assinatura inválida' })
  signedAt?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;
}

/**
 * O REGISTRO do título.
 *
 * O NÚMERO é OBRIGATÓRIO, e é a única obrigatoriedade do trecho do emissor: sem
 * ele, "registrada" seria uma afirmação sem como ser conferida — e é justamente
 * nesse estado que a garantia passa a valer contra terceiros. Com o número, a
 * certidão se pede; sem ele, alguém vai ter de refazer a busca no cartório para
 * descobrir se o registro existe mesmo.
 *
 * O LUGAR é opcional porque quase sempre é o mesmo (a comarca do imóvel, ou a
 * B3), e ele já aparece na cédula pela matrícula da lavoura. Ele existe para a
 * exceção — registro em comarca diferente da que o documento cita.
 */
/**
 * O REGISTRO do título. Também `multipart` — a via carimbada pode vir junto,
 * quando o cartório já a devolveu. Ver `registerCpr`.
 */
export class RegisterCprDto {
  // A MENSAGEM em todas as três conferências, e não só no mínimo: com o campo
  // ausente elas falham juntas, e quem lê a recusa precisa entender o que falta
  // seja qual for a que chegar até a tela. É a mesma escolha do motivo da
  // decisão do comitê (ver `ReviewBarterDto`).
  @IsString({ message: 'Informe o número do registro da cédula' })
  @MinLength(1, { message: 'Informe o número do registro da cédula' })
  @MaxLength(80, { message: 'Informe o número do registro da cédula (até 80 caracteres)' })
  registryNumber!: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  registryPlace?: string;

  @IsOptional()
  @IsDateString({}, { message: 'Data do registro inválida' })
  registeredAt?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;
}
