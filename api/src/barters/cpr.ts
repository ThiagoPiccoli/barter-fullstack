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
 *    produto, preço da saca, valor total, safra, o VENCIMENTO (que é da safra,
 *    porque muda conforme a cultura) e as NOTAS FISCAIS que o faturamento
 *    produziu. Sai em `knownFrom()`, e vai para a tela como leitura, não como
 *    campo: um número da cédula que discorde do registro é um título que cobra
 *    o que não foi acordado.
 * 2. A CREDORA é CADASTRO (ver creditor/) — razão social, CNPJ, endereço,
 *    foro. Aparece em quatro cláusulas do modelo, três delas com a
 *    qualificação por inteiro, e é sempre a mesma empresa.
 * 3. O CONSULTOR preenche o resto: a qualificação civil do emitente, as
 *    lavouras dadas em penhor, o padrão de qualidade do grão e o SCR do
 *    produtor. É o que a tabela `BarterCpr` guarda, e quem CONFERE é o emissor,
 *    na hora de gerar o documento.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * O QUE SAIU DA FONTE 3 E FOI PARA A 1, E POR QUÊ
 *
 * - o NÚMERO DA NOTA e o da DUPLICATA: eram digitados por quem não emitia a
 *   nota, cabia um só, e o documento em si não existia em lugar nenhum. Agora
 *   são `BarterInvoice` — lista, com o arquivo anexado, escritos pelo faturista;
 * - o VENCIMENTO: era digitado cédula a cédula, sem nada que dissesse qual era a
 *   data certa daquela cultura, e duas CPRs da mesma safra saíam diferentes.
 *   Agora é `Season.cprDueDate`, acertado uma vez quando a safra abre.
 *
 * Os dois são o mesmo erro, corrigido do mesmo jeito: pedir a informação a quem
 * a tem, e uma vez só.
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

/** O que o consultor preencheu — o rascunho, com o vazio significando "falta". */
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
  /**
   * O SCR do produtor: o id do arquivo anexado e a data da consulta.
   *
   * É o ID, e não o conteúdo: aqui mora a REGRA, e a regra só precisa saber se
   * o anexo existe. Ler os bytes para responder "falta o SCR?" seria carregar um
   * PDF a cada abertura de tela.
   */
  scrFileId: number | null;
  scrConsultedAt: Date | null;
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
  scrFileId: null,
  scrConsultedAt: null,
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
 * O CONTEXTO da cédula que não está no rascunho — o que os OUTROS postos
 * produziram e que o documento exige.
 *
 * Existe porque a emissão confere a cédula inteira, e a cédula inteira não cabe
 * mais numa tabela só: a nota fiscal é do faturista e o vencimento é da safra.
 * Passá-los como contexto é o que permite a `cprGaps` continuar sendo a ÚNICA
 * resposta a "dá para emitir?" — sem ele, a tela teria de somar esta lista com
 * outras duas conferências feitas em outro lugar, e a primeira divergência entre
 * elas seria um documento gerado com lacuna.
 */
/**
 * DE QUEM É cada pendência da cédula.
 *
 * A lista é lida por quatro pessoas diferentes, e nenhuma delas resolve tudo: o
 * consultor traz o que vem da visita, o faturista anexa a nota, o admin acerta o
 * vencimento na safra e o emissor informa o número na hora de emitir. Sem o
 * dono, "falta o vencimento" manda o consultor procurar um campo que não existe
 * na tela dele.
 *
 * E o dono não serve só à frase: é ele que permite a MESMA regra responder a
 * duas perguntas — "dá para emitir?" (todas) e "o consultor já fez a parte
 * dele?" (só as dele, ver `consultantCprGaps`).
 */
export const CPR_GAP_OWNER = {
  consultant: 'consultant',
  biller: 'biller',
  admin: 'admin',
  emitter: 'emitter',
} as const;

export type CprGapOwner = (typeof CPR_GAP_OWNER)[keyof typeof CPR_GAP_OWNER];

/** Uma pendência da cédula: o que falta, e com quem. */
export interface CprGap {
  label: string;
  owner: CprGapOwner;
}

export interface CprContext {
  /** As notas fiscais anexadas ao faturamento — a origem da dívida (cláusula VII). */
  invoices: { number: string; fileId: number | null }[];
  /** A safra em que a permuta foi fechada, para endereçar a pendência do vencimento. */
  seasonName: string;
}

/**
 * O QUE AINDA FALTA para a cédula poder ser emitida — em pt-BR, na ordem em que
 * o documento pede.
 *
 * É uma LISTA e não um booleano porque a resposta útil é "falta o RG e a
 * matrícula da segunda lavoura", e não "incompleta". O servidor escreve as
 * frases pelo mesmo motivo de `statusLabel` e `waitingFor`: a regra do que a
 * cédula exige mora aqui, e uma exigência nova aparece nas telas já instaladas
 * sem uma segunda cópia em Dart.
 *
 * A validação de ENTRADA (o DTO) e esta função respondem a perguntas
 * diferentes, de propósito: o DTO diz se o que chegou é aceitável para gravar
 * (um rascunho pela metade é), e isto diz se o que está gravado é suficiente
 * para gerar o documento (não é, até acabar).
 *
 * ELA É LIDA POR TRÊS PESSOAS DIFERENTES, e por isso cada frase diz ONDE a
 * pendência se resolve: o consultor preenche, o faturista anexa a nota, o admin
 * acerta o vencimento da safra. "Falta o vencimento" mandaria o consultor
 * procurar um campo que não existe na tela dele.
 */
export function cprGaps(cpr: CprDraft, areas: CprAreaDraft[], context: CprContext): string[] {
  return cprGapsOf(cpr, areas, context).map((gap) => gap.label);
}

/**
 * O MESMO QUE FALTA, dito com o DONO de cada pendência.
 *
 * Ele existe porque a lista passou a ser lida em DOIS momentos com perguntas
 * diferentes:
 *
 * - na EMISSÃO, "dá para gerar o documento?" — e aí tudo conta, seja de quem
 *   for;
 * - no ENCAMINHAMENTO ao gerente, "o consultor já fez a parte dele?" — e aí só
 *   conta o que é DELE. Cobrar a nota fiscal de quem vai encaminhar uma permuta
 *   que nem foi decidida seria pedir um documento que ainda não existe, e
 *   travar a esteira inteira num impossível.
 *
 * O dono não é enfeite da frase: é o que permite a mesma regra servir às duas
 * perguntas sem uma segunda lista escrita à mão em outro arquivo — que
 * divergiria desta no primeiro campo novo.
 */
export function cprGapsOf(cpr: CprDraft, areas: CprAreaDraft[], context: CprContext): CprGap[] {
  const gaps: CprGap[] = [];
  const of = (owner: CprGapOwner) => (value: string | null, label: string) => {
    if (!value?.trim()) gaps.push({ label, owner });
  };
  const numberOf = (owner: CprGapOwner) => (value: number, label: string) => {
    if (!(value > 0)) gaps.push({ label, owner });
  };

  const text = of(CPR_GAP_OWNER.consultant);
  const number = numberOf(CPR_GAP_OWNER.consultant);

  // O NÚMERO DA CÉDULA é do EMISSOR, e não de quem a preenche.
  //
  // A numeração da CPR é da emissão em papel e costuma vir de fora deste
  // sistema — cartório, B3, controle interno da credora. O consultor não a tem
  // quando visita a fazenda, e cobrá-la dele no encaminhamento travaria a
  // esteira num número que só existe semanas depois. Quem o informa é o emissor,
  // no ato de emitir (ver `IssueCprDto`).
  of(CPR_GAP_OWNER.emitter)(cpr.number, 'número da CPR');
  // O VENCIMENTO é da safra (ele muda conforme a cultura), e a frase diz isso:
  // quem lê esta lista não tem campo de vencimento em tela nenhuma.
  if (!cpr.dueDate) {
    gaps.push({
      owner: CPR_GAP_OWNER.admin,
      label: `vencimento da CPR (defina-o na safra${
        context.seasonName ? ` ${context.seasonName}` : ''
      }, no cadastro do Barter)`,
    });
  }

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

  // O SCR É OBRIGATÓRIO, e é o único anexo que esta função cobra.
  //
  // Uma CPR é concessão de crédito, e o SCR é o que diz quanto o produtor já
  // deve e a quem. Emitir sem ele é conceder no escuro — e é a única exigência
  // desta lista que não vem do modelo do documento, mas da decisão de não
  // assinar um título sem olhar o endividamento de quem o emite.
  if (!cpr.scrFileId) {
    gaps.push({
      owner: CPR_GAP_OWNER.consultant,
      label: 'o SCR do produtor (anexo obrigatório, com o consultor)',
    });
  }

  // A ORIGEM DA DÍVIDA (cláusula VII) é a nota que o faturamento emitiu. Ela não
  // é mais um número digitado aqui: a frase endereça a pendência ao faturista,
  // que é quem tem a nota na mão.
  const withFile = context.invoices.filter((invoice) => invoice.fileId !== null);
  if (context.invoices.length === 0) {
    gaps.push({
      owner: CPR_GAP_OWNER.biller,
      label: 'ao menos uma nota fiscal do faturamento (com o faturista)',
    });
  } else if (withFile.length === 0) {
    gaps.push({
      owner: CPR_GAP_OWNER.biller,
      label: 'o arquivo de ao menos uma nota fiscal (com o faturista)',
    });
  }

  // Sem lavoura não há penhor: as cláusulas V "b" e VI descrevem a garantia
  // pela MATRÍCULA do imóvel, e uma cédula que não diz sobre o que recai o
  // penhor não tem garantia nenhuma — tem uma promessa.
  if (areas.length === 0) {
    gaps.push({
      owner: CPR_GAP_OWNER.consultant,
      label: 'ao menos uma lavoura (a garantia do penhor)',
    });
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
      gaps.push({ owner: CPR_GAP_OWNER.consultant, label: `proprietário da ${which}` });
    }
    area.owners.forEach((owner, position) => {
      const who = `${position + 1}º proprietário da ${which}`;
      text(owner.name, `nome do ${who}`);
      text(owner.document, `CPF/CNPJ do ${who}`);
    });
  });

  return gaps;
}

/**
 * O QUE FALTA AO CONSULTOR — a parte da cédula que é dele, e só ela.
 *
 * É o que o ENCAMINHAMENTO ao gerente exige: a cédula é preenchida logo depois
 * de a permuta ser montada, com o produtor ainda por perto, e não semanas
 * depois, quando alguém tenta emitir o título e descobre que falta a matrícula
 * de uma lavoura que ninguém anotou.
 *
 * A lista é SÓ A DELE de propósito. Cobrar a nota fiscal de quem vai encaminhar
 * uma permuta que nem foi decidida seria exigir um documento que ainda não
 * existe — e travaria a esteira num impossível. Pelo mesmo motivo ficam de fora
 * o vencimento (do admin, na safra) e o número da cédula (do emissor, na
 * emissão).
 *
 * O CONTEXTO é vazio aqui porque nenhuma pendência do consultor depende dele:
 * as dele são o que ele digita e anexa.
 */
export function consultantCprGaps(cpr: CprDraft, areas: CprAreaDraft[]): string[] {
  return cprGapsOf(cpr, areas, { invoices: [], seasonName: '' })
    .filter((gap) => gap.owner === CPR_GAP_OWNER.consultant)
    .map((gap) => gap.label);
}

/** A parte da permuta que entra na cédula sem passar por formulário nenhum. */
export interface CprKnown {
  barterCode: string;
  emitterName: string;
  emitterDocument: string;
  grainName: string;
  /**
   * O VENCIMENTO da entrega — da SAFRA, e não da cédula.
   *
   * Ele está aqui, entre o que ninguém digita, porque essa é a correção: o
   * vencimento muda conforme a CULTURA e vale para a safra inteira. `null`
   * enquanto a safra não o tiver acertado, e aí `cprGaps` cobra dizendo onde.
   */
  dueDate: Date | null;
  /** O nome da safra — é ele que endereça a pendência do vencimento. */
  seasonName: string;
  /**
   * AS NOTAS FISCAIS do faturamento — a origem da dívida (cláusula VII).
   *
   * Leitura, como o resto daqui: quem as emite é o faturista, e redigitar o
   * número dentro da cédula era exatamente o erro que criou a versão anterior
   * deste arquivo.
   */
  invoices: CprInvoiceRef[];
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

/** UMA NOTA do faturamento, como a cédula a cita: número, série e duplicata. */
export interface CprInvoiceRef {
  number: string;
  series: string;
  duplicateNumber: string;
}

/**
 * O que a cédula tira do registro. Recebe o peso da saca porque ele é o único
 * número desta lista que a permuta NÃO tem: a permuta conta sacas, e a cédula
 * fala em quilos.
 *
 * Os quilos são arredondados a duas casas pelo mesmo motivo de `roundQuantity`:
 * é um número que vai impresso, e a impressão não pode discordar do cálculo.
 *
 * A SAFRA e as NOTAS entram por parâmetro pelo mesmo motivo do peso da saca:
 * elas não estão na permuta. A primeira é do cadastro do Barter (é ela que diz o
 * vencimento da cultura) e as segundas são o que o faturamento produziu.
 */
export function knownFrom(
  barter: { code: string; producerName: string; versionCode: string; unitName: string },
  grainItem: { productName: string; quantity: number; unitValue: number } | undefined,
  producerDocument: string,
  sackWeightKg: number,
  season: { name: string; cprDueDate: Date | null },
  invoices: CprInvoiceRef[],
): CprKnown {
  const sacks = grainItem?.quantity ?? 0;
  const sackPrice = grainItem?.unitValue ?? 0;
  return {
    barterCode: barter.code,
    emitterName: barter.producerName,
    emitterDocument: producerDocument,
    grainName: grainItem?.productName ?? '',
    dueDate: season.cprDueDate,
    seasonName: season.name,
    invoices,
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
 * dando ao consultor a caneta do cadastro trocaria um incômodo por uma mudança
 * de quem pode alterar cliente. O cadastro entra só onde ele já sabe a resposta
 * (o município), como sugestão.
 *
 * SUGESTÃO, e não preenchimento automático: ela vai num campo à parte do JSON,
 * e quem decide usá-la é quem assina embaixo. Copiar o estado civil de uma
 * cédula de dois anos atrás por conta própria escreveria "casado" sobre um
 * divórcio.
 *
 * O SCR NÃO É SUGERIDO, e é a exceção mais importante desta lista: ele é uma
 * fotografia com data, e a da safra passada não diz nada sobre o endividamento
 * de hoje — que é a única coisa que ele existe para dizer. Reaproveitá-lo faria
 * a pendência sumir da tela com um documento vencido no lugar dela.
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
