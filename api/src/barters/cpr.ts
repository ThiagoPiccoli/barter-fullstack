/**
 * A CÉDULA DE PRODUTO RURAL, sem I/O — o que o documento exige, o que a permuta
 * já responde e o que ainda falta alguém digitar.
 *
 * Separada do service pelo mesmo motivo de `barter-math.ts` e `tax-regime.ts`:
 * é regra, e regra se testa sem banco. O service traz as linhas; aqui mora a
 * leitura delas contra o modelo do documento.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * DE ONDE VEM CADA LACUNA DO MODELO
 *
 * O documento tem três fontes, e é essa divisão que decide o que vira campo de
 * formulário:
 *
 * 1. A PERMUTA já sabe — e ninguém redigita. Nome do emitente, CPF, sacas,
 *    produto, preço da saca, valor total, safra. Sai em `knownFrom()`, e vai
 *    para a tela como leitura, não como campo: um número da cédula que discorde
 *    do registro é um título que cobra o que não foi acordado.
 * 2. A CREDORA é CADASTRO (ver creditor/) — razão social, CNPJ, endereço,
 *    foro. Aparece em quatro cláusulas do modelo, três delas com a
 *    qualificação por inteiro, e é sempre a mesma empresa.
 * 3. O FATURISTA preenche o resto: a qualificação civil do emitente, as
 *    lavouras dadas em penhor, o padrão de qualidade do grão e os números da
 *    nota e da duplicata. É o que a tabela `BarterCpr` guarda.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * O QUE É DERIVADO, E POR QUE NÃO É CAMPO
 *
 * - a QUANTIDADE em quilos é `sacas × peso da saca`;
 * - o VALOR TOTAL é `sacas × preço da saca`, os dois do registro da permuta;
 * - a quantidade dada em PENHOR (cláusula VI) é a mesma da entrega — penhorar
 *   número diferente do que se deve é um erro de digitação com efeito jurídico,
 *   e o modelo recebido traz exatamente esse erro: "367 (quatrocentos e
 *   quarenta) sacas", em que o algarismo e o extenso não são o mesmo número;
 * - os EXTENSOS ("[VALOR TOTAL EM PALAVRAS]", "[ÁREA EM PALAVRAS]"…) são
 *   escrita do número ao lado, e por isso pertencem à geração do documento, não
 *   à coleta: digitá-los seria abrir a mesma porta pela qual o 367 entrou.
 */

/** O que o faturista preencheu — o rascunho, com o vazio significando "falta". */
export interface CprDraft {
  number: string;
  issuedAt: Date;
  dueDate: Date | null;
  emitterNationality: string;
  emitterMaritalStatus: string;
  emitterProfession: string;
  emitterRg: string;
  emitterAddress: string;
  emitterAddressNumber: string;
  emitterCity: string;
  emitterCoopId: string | null;
  emitterCnh: string;
  emitterFatherName: string;
  emitterMotherName: string;
  emitterEmail: string;
  deliveryPlace: string;
  mortgages: string;
  spouseName: string | null;
  spouseNationality: string | null;
  spouseProfession: string | null;
  spouseDocument: string | null;
  spouseRg: string | null;
  sackWeightKg: number;
  cultivar: string;
  maxMoisture: number;
  maxImpurities: number;
  oilContent: number;
  invoiceNumber: string;
  duplicateNumber: string;
  insurancePolicy: string | null;
}

/**
 * A CÉDULA AINDA NÃO COMEÇADA — todos os campos no seu vazio.
 *
 * Existe para que "não há rascunho" e "rascunho em branco" respondam a mesma
 * coisa a `cprGaps()`: a lista inteira do que falta. Sem ela, a tela de uma
 * permuta ainda sem cédula teria de descobrir por conta própria o que o
 * documento exige — que é a segunda cópia da regra que este arquivo existe para
 * não haver.
 */
export const EMPTY_CPR: CprDraft = {
  number: '',
  issuedAt: new Date(0),
  dueDate: null,
  emitterNationality: '',
  emitterMaritalStatus: '',
  emitterProfession: '',
  emitterRg: '',
  emitterAddress: '',
  emitterAddressNumber: '',
  emitterCity: '',
  emitterCoopId: null,
  emitterCnh: '',
  emitterFatherName: '',
  emitterMotherName: '',
  emitterEmail: '',
  deliveryPlace: '',
  mortgages: '',
  spouseName: null,
  spouseNationality: null,
  spouseProfession: null,
  spouseDocument: null,
  spouseRg: null,
  // 60 kg é o padrão do mercado e o default da coluna: uma cédula sem rascunho
  // nenhum já converte sacas em quilos por ele, e não fica devendo o número.
  sackWeightKg: 60,
  cultivar: '',
  maxMoisture: 0,
  maxImpurities: 0,
  oilContent: 0,
  invoiceNumber: '',
  duplicateNumber: '',
  insurancePolicy: null,
};

/**
 * Um AVALISTA — coletado pela proposta, ainda não impresso na cédula.
 *
 * A forma é a mesma da qualificação do emitente, campo por campo: para o
 * direito os dois são a mesma coisa (pessoas que se obrigam), e o que os separa
 * é o papel.
 */
export interface CprGuarantorDraft {
  name: string;
  document: string;
  rg: string;
  cnh: string;
  nationality: string;
  profession: string;
  maritalStatus: string;
  fatherName: string;
  motherName: string;
  email: string;
  address: string;
  addressNumber: string;
  city: string;
  spouseName: string;
  spouseDocument: string;
  spouseRg: string;
  spouseNationality: string;
  spouseProfession: string;
}

/** Uma lavoura do penhor, com os donos do imóvel. */
export interface CprAreaDraft {
  locality: string;
  city: string;
  areaHa: number;
  withinLargerArea: boolean;
  registryNumber: string;
  registryBook: string;
  registryDistrict: string;
  owners: { name: string; document: string }[];
}

/**
 * O ESTADO CIVIL que exige anuência do cônjuge.
 *
 * O penhor agrícola recai sobre a safra, mas a cédula é assinada pelo casal
 * quando há regime de bens a preservar — é o bloco "ANUÊNCIA DO CÔNJUGE DO
 * DEVEDOR" do modelo. A comparação é sobre o texto normalizado porque o campo é
 * livre: "Casado", "casada", "CASADO(A)" e "união estável" são a mesma resposta.
 *
 * Solteiro, divorciado e viúvo não pedem anuência, e por isso o bloco do cônjuge
 * nasce vazio e assim fica na maioria das cédulas — ausência não é pendência.
 */
const MARRIED = ['casad', 'uniao estavel'];

export function requiresSpouse(maritalStatus: string): boolean {
  const normalized = maritalStatus
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
  return MARRIED.some((term) => normalized.includes(term));
}

/**
 * O QUE AINDA FALTA para a cédula poder ser emitida — em pt-BR, na ordem em que
 * o documento pede.
 *
 * É uma LISTA e não um booleano porque a resposta útil ao faturista é "falta o
 * RG e a matrícula da segunda lavoura", e não "incompleta". O servidor escreve
 * as frases pelo mesmo motivo de `statusLabel` e `waitingFor`: a regra do que a
 * cédula exige mora aqui, e uma exigência nova aparece nas telas já instaladas
 * sem uma segunda cópia em Dart.
 *
 * A validação de ENTRADA (o DTO) e esta função respondem a perguntas
 * diferentes, de propósito: o DTO diz se o que chegou é aceitável para gravar
 * (um rascunho pela metade é), e isto diz se o que está gravado é suficiente
 * para gerar o documento (não é, até acabar).
 */
export function cprGaps(cpr: CprDraft, areas: CprAreaDraft[]): string[] {
  const gaps: string[] = [];
  const text = (value: string | null, label: string) => {
    if (!value?.trim()) gaps.push(label);
  };
  const number = (value: number, label: string) => {
    if (!(value > 0)) gaps.push(label);
  };

  text(cpr.number, 'número da CPR');
  if (!cpr.dueDate) gaps.push('data de vencimento');

  text(cpr.emitterNationality, 'nacionalidade do emitente');
  text(cpr.emitterMaritalStatus, 'estado civil do emitente');
  text(cpr.emitterProfession, 'profissão do emitente');
  text(cpr.emitterRg, 'RG do emitente');
  text(cpr.emitterAddress, 'logradouro do emitente');
  text(cpr.emitterAddressNumber, 'número do endereço do emitente');
  text(cpr.emitterCity, 'município/UF do emitente');

  // A anuência só é exigida de quem é casado — e aí ela é exigida de verdade:
  // cédula de emitente casado sem a assinatura do cônjuge é garantia
  // questionável, que é o oposto do que um título existe para ser.
  if (requiresSpouse(cpr.emitterMaritalStatus)) {
    text(cpr.spouseName, 'nome do cônjuge (o emitente é casado)');
    text(cpr.spouseDocument, 'CPF do cônjuge');
    text(cpr.spouseNationality, 'nacionalidade do cônjuge');
    text(cpr.spouseProfession, 'profissão do cônjuge');
  }

  // O LOCAL DA ENTREGA é cláusula (V, "d"), então é cobrado. Repare no que NÃO
  // é cobrado logo abaixo: CNH, filiação, e-mail, RG do cônjuge, avalista e
  // hipotecas são coletados pela proposta e não aparecem em cláusula nenhuma do
  // modelo. Cobrá-los travaria a geração de um documento que não os usa — a
  // pergunta desta função é "dá para emitir?", e não "o cadastro está cheio?".
  text(cpr.deliveryPlace, 'local da entrega');

  number(cpr.sackWeightKg, 'peso da saca (kg)');
  text(cpr.cultivar, 'cultivar do grão');
  number(cpr.maxMoisture, 'umidade máxima (%)');
  number(cpr.maxImpurities, 'impurezas máximas (%)');
  number(cpr.oilContent, 'teor de óleo (%)');

  text(cpr.invoiceNumber, 'número da nota fiscal');
  text(cpr.duplicateNumber, 'número da duplicata');

  // Sem lavoura não há penhor: as cláusulas V "b" e VI descrevem a garantia
  // pela MATRÍCULA do imóvel, e uma cédula que não diz sobre o que recai o
  // penhor não tem garantia nenhuma — tem uma promessa.
  if (areas.length === 0) {
    gaps.push('ao menos uma lavoura (a garantia do penhor)');
  }
  areas.forEach((area, index) => {
    const which = `${index + 1}ª lavoura`;
    text(area.locality, `localidade da ${which}`);
    text(area.city, `município/UF da ${which}`);
    number(area.areaHa, `área plantada da ${which}`);
    text(area.registryNumber, `matrícula da ${which}`);
    text(area.registryBook, `livro do registro da ${which}`);
    text(area.registryDistrict, `comarca da ${which}`);
    if (area.owners.length === 0) {
      gaps.push(`proprietário da ${which}`);
    }
    area.owners.forEach((owner, position) => {
      const who = `${position + 1}º proprietário da ${which}`;
      text(owner.name, `nome do ${who}`);
      text(owner.document, `CPF/CNPJ do ${who}`);
    });
  });

  return gaps;
}

/** A parte da permuta que entra na cédula sem passar por formulário nenhum. */
export interface CprKnown {
  barterCode: string;
  emitterName: string;
  emitterDocument: string;
  grainName: string;
  /** Sacas do grão de pagamento — a quantidade da cláusula III e a do penhor. */
  sacks: number;
  /** `sacas × peso da saca`: o "[QUANTIDADE] kg" da cláusula III. */
  quantityKg: number;
  /** O preço por saca acordado, congelado no item da permuta. */
  sackPrice: number;
  /** `sacas × preço da saca`: o valor de emissão e o referencial da cláusula XVI. */
  totalValue: number;
  /** A gestão em que a permuta foi fechada (`S2026.02`) — a safra do documento. */
  versionCode: string;
  /**
   * A UNIDADE DE RETIRADA da permuta — a sugestão para o local da entrega.
   *
   * Sugestão, e não o valor: retirar insumo na Filial 02 não obriga a entregar
   * o grão lá. Ela vem junto porque é o palpite certo na maioria das vezes, e
   * quem confirma é quem assina.
   */
  pickupUnit: string;
}

/**
 * O que a cédula tira do registro. Recebe o peso da saca porque ele é o único
 * número desta lista que a permuta NÃO tem: a permuta conta sacas, e a cédula
 * fala em quilos.
 *
 * Os quilos são arredondados a duas casas pelo mesmo motivo de `roundQuantity`:
 * é um número que vai impresso, e a impressão não pode discordar do cálculo.
 */
export function knownFrom(
  barter: { code: string; producerName: string; versionCode: string; unitName: string },
  grainItem: { productName: string; quantity: number; unitValue: number } | undefined,
  producerDocument: string,
  sackWeightKg: number,
): CprKnown {
  const sacks = grainItem?.quantity ?? 0;
  const sackPrice = grainItem?.unitValue ?? 0;
  return {
    barterCode: barter.code,
    emitterName: barter.producerName,
    emitterDocument: producerDocument,
    grainName: grainItem?.productName ?? '',
    sacks,
    quantityKg: Math.round(sacks * sackWeightKg * 100) / 100,
    sackPrice,
    totalValue: Math.round(sacks * sackPrice * 100) / 100,
    versionCode: barter.versionCode,
    pickupUnit: barter.unitName,
  };
}

/**
 * A SUGESTÃO de preenchimento — o que a tela mostra já escrito nos campos ainda
 * vazios.
 *
 * Existe por causa da repetição real do trabalho: o mesmo produtor emite cédula
 * a cada permuta, e a nacionalidade, o estado civil, o RG, o endereço, o cônjuge
 * e as matrículas das lavouras dele são os mesmos da vez passada. Sem isto, a
 * segunda cédula custa a mesma digitação da primeira — e a terceira é onde o RG
 * sai com um dígito trocado.
 *
 * A fonte é a ÚLTIMA CÉDULA do mesmo produtor, e não o cadastro dele: quem
 * escreve o cadastro é o admin (`producers.manage`), e resolver a repetição
 * dando ao faturista a caneta do cadastro trocaria um incômodo por uma mudança
 * de quem pode alterar cliente. O cadastro entra só onde ele já sabe a resposta
 * (o município), como sugestão.
 *
 * SUGESTÃO, e não preenchimento automático: ela vai num campo à parte do JSON,
 * e quem decide usá-la é quem assina embaixo. Copiar o estado civil de uma
 * cédula de dois anos atrás por conta própria escreveria "casado" sobre um
 * divórcio.
 */
export function suggestFrom(
  producer: { city: string } | null,
  previous: (CprDraft & { areas: CprAreaDraft[]; guarantors: CprGuarantorDraft[] }) | null,
): Partial<CprDraft> & { areas?: CprAreaDraft[]; guarantors?: CprGuarantorDraft[] } {
  if (!previous) {
    return producer?.city ? { emitterCity: producer.city } : {};
  }
  return {
    emitterNationality: previous.emitterNationality,
    emitterMaritalStatus: previous.emitterMaritalStatus,
    emitterProfession: previous.emitterProfession,
    emitterRg: previous.emitterRg,
    emitterAddress: previous.emitterAddress,
    emitterAddressNumber: previous.emitterAddressNumber,
    emitterCity: previous.emitterCity || (producer?.city ?? ''),
    emitterCoopId: previous.emitterCoopId,
    // A qualificação da proposta se repete tanto quanto a da cédula: CNH,
    // filiação e e-mail são da PESSOA, e não da negociação.
    emitterCnh: previous.emitterCnh,
    emitterFatherName: previous.emitterFatherName,
    emitterMotherName: previous.emitterMotherName,
    emitterEmail: previous.emitterEmail,
    spouseName: previous.spouseName,
    spouseNationality: previous.spouseNationality,
    spouseProfession: previous.spouseProfession,
    spouseDocument: previous.spouseDocument,
    spouseRg: previous.spouseRg,
    sackWeightKg: previous.sackWeightKg,
    cultivar: previous.cultivar,
    maxMoisture: previous.maxMoisture,
    maxImpurities: previous.maxImpurities,
    oilContent: previous.oilContent,
    // As lavouras vêm junto: matrícula, livro e comarca não mudam de uma safra
    // para a outra, e são a parte mais cara de digitar da cédula inteira. O
    // que muda é a área plantada, e é por isso que ela continua editável.
    areas: previous.areas,
    // Os AVALISTAS também: quem avaliza um produtor costuma ser o mesmo de uma
    // safra para a outra, e o bloco de qualificação deles é o mais longo do
    // formulário inteiro.
    guarantors: previous.guarantors,
    // O que NÃO vem: `deliveryPlace`. Ele é da NEGOCIAÇÃO, não da pessoa —
    // repeti-lo faria a entrega desta safra herdar em silêncio a praça da
    // anterior, que é exatamente o tipo de campo que ninguém reconfere.
  };
}
