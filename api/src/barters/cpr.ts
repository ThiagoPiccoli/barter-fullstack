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
 * - a ÁREA EXIGIDA em penhor é `(sacas ÷ produtividade) × (1 + margem)`, e ela
 *   não sai impressa em cláusula nenhuma: é a RÉGUA com que se confere se as
 *   lavouras listadas dão conta da dívida. O documento enumera as matrículas;
 *   esta conta diz se elas bastam. Ver `pledgeReadingOf`.
 */
import { AREA_EPSILON, pledgeAreaFor } from './barter-math';
import type { ReviewRequirement } from './barter-workflow';

/** O que o consultor preencheu — o rascunho, com o vazio significando "falta". */
export interface CprDraft {
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
  /**
   * O LOCAL DA ENTREGA: a filial escolhida e o nome dela congelado na gravação
   * (ver `BarterCpr.deliveryUnitId`). É o TEXTO que esta leitura cobra — é ele
   * que sai na cláusula —, e por isso a cédula do tempo do texto livre, sem
   * unidade, não fica devendo nada.
   */
  deliveryUnitId: number | null;
  deliveryPlace: string;
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
  /**
   * Os AVALISTAS. Opcional porque só interessam a esta leitura quando o comitê
   * EXIGE aval (ver `CprContext.requirements`) — e a cédula sem rascunho não
   * tem nenhum, que é o que a ausência diz.
   */
  guarantors?: CprGuarantorDraft[];
  /**
   * Os BENS DADOS EM HIPOTECA. Opcional pelo mesmo motivo dos avalistas: só
   * interessam quando o comitê exige hipoteca.
   */
  mortgages?: CprMortgageDraft[];
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
  deliveryUnitId: null,
  deliveryPlace: '',
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
};

/**
 * Um AVALISTA — exigido pelo comitê, e que ASSINA a cédula.
 *
 * A forma é a mesma da qualificação do emitente, campo por campo: para o
 * direito os dois são a mesma coisa (pessoas que se obrigam), e o que os separa
 * é o papel. O SCR também: quem garante a dívida é avaliado pelo endividamento
 * dele, como quem a deve.
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
  /** O id do SCR anexado — só a existência importa à regra (ver `CprDraft.scrFileId`). */
  scrFileId?: number | null;
}

/**
 * OS CAMPOS DE QUALIFICAÇÃO do avalista — o que se SUGERE de uma cédula para
 * a outra. O id e o SCR ficam de fora: o id é da linha da outra cédula, e o
 * SCR é uma fotografia com data, que não se reaproveita (ver `suggestFrom`).
 */
export const GUARANTOR_FIELDS = [
  'name',
  'document',
  'rg',
  'cnh',
  'nationality',
  'profession',
  'maritalStatus',
  'fatherName',
  'motherName',
  'email',
  'address',
  'addressNumber',
  'city',
  'spouseName',
  'spouseDocument',
  'spouseRg',
  'spouseNationality',
  'spouseProfession',
] as const satisfies readonly (keyof CprGuarantorDraft)[];

/** Só a qualificação de um avalista — ver `GUARANTOR_FIELDS`. */
export function guarantorQualificationOf(
  guarantor: CprGuarantorDraft,
): Omit<CprGuarantorDraft, 'scrFileId'> {
  return Object.fromEntries(GUARANTOR_FIELDS.map((key) => [key, guarantor[key]])) as Omit<
    CprGuarantorDraft,
    'scrFileId'
  >;
}

/**
 * UM BEM DADO EM HIPOTECA — exigido pelo comitê, conferido e não impresso.
 * Ver `CprMortgage` no schema.
 */
export interface CprMortgageDraft {
  description: string;
  registryNumber: string;
  registryDistrict: string;
  city: string;
  ownerName: string;
  ownerDocument: string;
  appraisedValue: number;
  /** O id do documento do bem anexado (matrícula atualizada, certidão de ônus). */
  documentFileId?: number | null;
}

/**
 * O DIMENSIONAMENTO DO PENHOR desta permuta — o que transforma "tem lavoura?" em
 * "tem lavoura suficiente?".
 *
 * As três parcelas vêm de três lugares e nenhuma delas é digitada no formulário
 * da cédula: as SACAS são o item de grão da permuta, a PRODUTIVIDADE é a da
 * versão em que ela nasceu e a MARGEM é a política da credora — as duas últimas
 * congeladas na permuta no dia do registro (ver `Barter.pledgeYield`).
 *
 * Elas chegam aqui como CONTEXTO, e não dentro do rascunho, pela mesma razão das
 * notas fiscais: o rascunho é o que o consultor escreveu, e nada disto ele
 * escreve. O que ele escreve é a resposta — as matrículas que somam a área.
 */
export interface CprPledge {
  /** Sacas do item de grão. É o que muda quando um produto de fora é deferido. */
  sacks: number;
  /**
   * A produtividade (sc/ha) congelada no registro.
   *
   * ZERO TEM SIGNIFICADO PRÓPRIO: é a permuta anterior a esta regra. Toda permuta
   * registrada a partir daqui nasce com a taxa preenchida, porque `POST /barters`
   * recusa versão sem produtividade — logo 0 não é "faltou preencher", é "nasceu
   * antes de o penhor ser dimensionado", e a permuta fica de fora da exigência.
   * Ver `Barter.pledgeYield` no schema.
   */
  yieldPerHa: number;
  /** A margem de segurança (%) da credora, congelada junto. Zero é legítimo. */
  marginPercent: number;
}

/** O penhor de uma permuta que não está sob a regra — ver `CprPledge.yieldPerHa`. */
export const NO_PLEDGE: CprPledge = { sacks: 0, yieldPerHa: 0, marginPercent: 0 };

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
 * consultor traz o que vem da visita, o faturista anexa a nota e o admin acerta
 * o vencimento na safra. O emissor não deve nada à lista: ele a LÊ antes de
 * emitir (o número da cédula, que era dele, passou a nascer com a permuta). Sem
 * o dono, "falta o vencimento" manda o consultor procurar um campo que não existe
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
} as const;

export type CprGapOwner = (typeof CPR_GAP_OWNER)[keyof typeof CPR_GAP_OWNER];

/** Uma pendência da cédula: o que falta, e com quem. */
export interface CprGap {
  label: string;
  owner: CprGapOwner;
}

/**
 * AS EXIGÊNCIAS DO COMITÊ, como a cédula as lê: cada uma liga um campo que, sem
 * ela, a cédula não cobra. Ver `REVIEW_REQUIREMENT_LABELS`.
 */
export type CprRequirements = Record<ReviewRequirement, boolean>;

/** A permuta de que o comitê não exigiu nada — o caso comum. */
export const NO_REQUIREMENTS: CprRequirements = {
  requiresGuarantor: false,
  requiresCollateral: false,
};

export interface CprContext {
  /** As notas fiscais anexadas ao faturamento — a origem da dívida (cláusula VII). */
  invoices: { number: string; fileId: number | null }[];
  /** A safra em que a permuta foi fechada, para endereçar a pendência do vencimento. */
  seasonName: string;
  /**
   * A VERSÃO do Barter em que esta permuta foi fechada, para a mesma pendência:
   * o vencimento é de cada versão, e "defina o vencimento no Barter" não diz em
   * qual — com várias culturas abertas, há várias. Opcional porque nem todo
   * chamador a tem (ver `consultantCprGaps`, que monta um contexto mínimo).
   */
  versionCode?: string;
  /**
   * O DIMENSIONAMENTO DO PENHOR — quanta área esta permuta exige em garantia.
   *
   * Diferente das notas e da safra, esta parte do contexto pertence ao CONSULTOR:
   * ela é o que `consultantCprGaps` cobra no encaminhamento. Foi a chegada dela
   * que obrigou aquela função a receber contexto — até aqui nenhuma pendência do
   * consultor dependia de nada fora do rascunho.
   */
  pledge: CprPledge;
  /**
   * O QUE O COMITÊ EXIGIU — avalista, hipoteca.
   *
   * São pendências DO CONSULTOR, como o penhor, e pelo mesmo motivo chegam como
   * contexto: quem decide que a cédula precisa de um avalista não é o rascunho,
   * é a mesa do comitê. Sem exigência, os três campos não são cobrados — e nem
   * aparecem no formulário dele.
   *
   * SEM PADRÃO, pelo mesmo raciocínio de `pledge`: um parâmetro opcional aqui
   * seria a porta pela qual a próxima chamada esquece o aval que o comitê pediu,
   * e a cédula sairia "completa" sem ele.
   */
  requirements: CprRequirements;
}

/**
 * A LEITURA DO PENHOR: quanto se exige, quanto foi penhorado e quanto falta.
 *
 * Ela é uma peça só porque é lida em três lugares que precisam concordar — a
 * lacuna que trava o encaminhamento, o JSON que a tela do detalhe desenha e o
 * resumo do formulário da cédula. Três contas escritas à mão divergiriam na
 * primeira mudança de arredondamento, e a divergência apareceria como um
 * formulário dizendo "completo" ao lado de um botão que recusa.
 *
 * `applies` é a pergunta anterior a todas: esta permuta está sob a regra? Ela é
 * falsa para as permutas anteriores ao dimensionamento (`yieldPerHa` 0) e para as
 * que ainda não têm sacas. Repare que ela NÃO é "o penhor está em dia" — uma
 * permuta fora da regra continua devendo ao menos uma lavoura, que é a exigência
 * que já existia e que segue valendo para todo mundo.
 */
export interface CprPledgeReading {
  applies: boolean;
  requiredAreaHa: number;
  pledgedAreaHa: number;
  /** Quanto falta (ha), já zerado quando a soma alcança o exigido. */
  shortfallHa: number;
}

export function pledgeReadingOf(pledge: CprPledge, areas: CprAreaDraft[]): CprPledgeReading {
  const requiredAreaHa = pledgeAreaFor(pledge.sacks, pledge.yieldPerHa, pledge.marginPercent);
  // A soma arredondada a duas casas, na mesma precisão em que cada área é
  // digitada: sem isso o total carregaria o lixo do ponto flutuante para dentro
  // da frase da lacuna, e a tela mostraria "as lavouras somam 23,999999999 ha".
  const pledgedAreaHa =
    Math.round(areas.reduce((total, area) => total + (area.areaHa || 0), 0) * 100) / 100;
  const applies = requiredAreaHa > 0;
  const missing = requiredAreaHa - pledgedAreaHa;
  return {
    applies,
    requiredAreaHa,
    pledgedAreaHa,
    // A FOLGA DE UM CENTÉSIMO entra aqui, e não na comparação de quem chama, para
    // que "falta?" tenha uma resposta só no sistema inteiro. Ver `AREA_EPSILON`.
    shortfallHa: applies && missing > AREA_EPSILON ? Math.round(missing * 100) / 100 : 0,
  };
}

/** Hectares como o Brasil os escreve — é texto de frase, não de cálculo. */
function formatHa(value: number): string {
  return value.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
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

  // O NÚMERO DA CÉDULA não é cobrado: ele nasce com a permuta
  // (`Barter.cprNumber`), e uma cédula sem número não existe mais.
  // O VENCIMENTO é da VERSÃO do Barter, e a frase diz qual: quem lê esta lista
  // não tem campo de vencimento em tela nenhuma, e precisa saber em qual
  // lançamento a data se acerta.
  if (!cpr.dueDate) {
    gaps.push({
      owner: CPR_GAP_OWNER.admin,
      label: `vencimento da CPR (defina-o no lançamento${
        context.versionCode ? ` ${context.versionCode}` : ''
      } do Barter)`,
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
  // é cobrado logo abaixo: CNH, filiação, e-mail e RG do cônjuge são coletados
  // pela proposta e não aparecem em cláusula nenhuma do modelo. Cobrá-los
  // travaria a geração de um documento que não os usa — a pergunta desta função
  // é "dá para emitir?", e não "o cadastro está cheio?". Avalista e hipoteca
  // são cobrados só quando o COMITÊ os exige (ver o fim da função). A APÓLICE
  // não é cobrada aqui: ela é da seguradora, e quem garante que a permuta com
  // seguro chega à emissão com ela é a etapa da seguradora, que não anda sem o
  // número e o documento.
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
  //
  // E QUANDO A PERMUTA É DIMENSIONADA, a mesma frase já diz o TAMANHO. Duas
  // pendências — "falta lavoura" e "faltam 18,00 ha de 18,00 ha" — são a mesma
  // informação dita duas vezes, e a segunda, com as lavouras somando zero, é uma
  // conta que ninguém precisa ler para entender que não há nada ali. O que o
  // consultor precisa saber, quando ainda não anotou matrícula nenhuma, é quanta
  // área ir buscar; é isso que entra aqui.
  const pledge = pledgeReadingOf(context.pledge, areas);
  if (areas.length === 0) {
    gaps.push({
      owner: CPR_GAP_OWNER.consultant,
      label: pledge.applies
        ? `ao menos uma lavoura (a garantia do penhor — esta permuta exige ${formatHa(pledge.requiredAreaHa)} ha)`
        : 'ao menos uma lavoura (a garantia do penhor)',
    });
  }

  // E A LAVOURA PRECISA DAR CONTA DA DÍVIDA — a exigência que faltava ao lado da
  // de cima.
  //
  // "Ao menos uma lavoura" responde "existe garantia?" e não responde "garantia
  // de quanto?": uma permuta de 3.000 sacas passava com uma matrícula de 4 ha
  // anotada, e o penhor ficava do tamanho do que alguém teve tempo de digitar.
  // Aqui a área é medida contra o que a própria permuta pede (ver
  // `pledgeReadingOf`), e é isso que o consultor vai fechar somando matrículas.
  //
  // A FRASE TRAZ OS TRÊS NÚMEROS de propósito. "Área insuficiente" manda alguém
  // adivinhar quanto falta; "faltam 12,4 ha" é o que se resolve pedindo a próxima
  // matrícula ao produtor — que é a ação que esta lacuna existe para provocar, e
  // que só é barata enquanto a visita ainda está acontecendo.
  if (areas.length > 0 && pledge.applies && pledge.shortfallHa > 0) {
    gaps.push({
      owner: CPR_GAP_OWNER.consultant,
      label:
        `área de penhor insuficiente: faltam ${formatHa(pledge.shortfallHa)} ha ` +
        `(a permuta exige ${formatHa(pledge.requiredAreaHa)} ha e as lavouras somam ` +
        `${formatHa(pledge.pledgedAreaHa)} ha)`,
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

  // AS EXIGÊNCIAS DO COMITÊ — a outra exceção, ao lado do SCR, à regra de que
  // quem decide o que falta é o modelo do documento.
  //
  // Avalista e hipoteca não são cobrados de toda cédula: a maioria das
  // permutas não tem nenhum dos dois, e o consultor nem vê esses campos no
  // preenchimento inicial. Quando o comitê os EXIGE, eles passam a ser
  // pendência dele — é o que trava o retorno da permuta ao comitê (`fulfill`)
  // e, depois, a emissão. A decisão de crédito foi tomada contando com eles, e
  // um título emitido sem o aval que a justificou não é o título que foi
  // aprovado.
  const required = context.requirements;
  if (required.requiresGuarantor) {
    const guarantors = cpr.guarantors ?? [];
    if (guarantors.length === 0) {
      gaps.push({
        owner: CPR_GAP_OWNER.consultant,
        label: 'ao menos um avalista (exigido pelo comitê)',
      });
    }
    // A QUALIFICAÇÃO do avalista é a mesma que se cobra do emitente, campo por
    // campo: para o direito os dois são pessoas que se obrigam, e o aval de
    // alguém sem RG ou endereço não se executa contra ninguém.
    guarantors.forEach((guarantor, index) => {
      const who = `${index + 1}º avalista`;
      text(guarantor.name, `nome do ${who}`);
      text(guarantor.document, `CPF do ${who}`);
      text(guarantor.rg, `RG do ${who}`);
      text(guarantor.nationality, `nacionalidade do ${who}`);
      text(guarantor.maritalStatus, `estado civil do ${who}`);
      text(guarantor.profession, `profissão do ${who}`);
      text(guarantor.address, `logradouro do ${who}`);
      text(guarantor.addressNumber, `número do endereço do ${who}`);
      text(guarantor.city, `município/UF do ${who}`);
      if (requiresSpouse(guarantor.maritalStatus)) {
        // O cônjuge do avalista ASSINA a anuência, como o do emitente — e por
        // isso deve a mesma qualificação que sai no bloco de assinatura.
        text(guarantor.spouseName, `nome do cônjuge do ${who} (o avalista é casado)`);
        text(guarantor.spouseDocument, `CPF do cônjuge do ${who}`);
        text(guarantor.spouseNationality, `nacionalidade do cônjuge do ${who}`);
        text(guarantor.spouseProfession, `profissão do cônjuge do ${who}`);
      }
      // O SCR DO AVALISTA, pelo mesmo motivo do SCR do emitente: quem garante
      // a dívida com o próprio patrimônio é avaliado pelo que já deve.
      if (!guarantor.scrFileId) {
        gaps.push({
          owner: CPR_GAP_OWNER.consultant,
          label: `o SCR do ${who} (anexo obrigatório, com o consultor)`,
        });
      }
    });
  }
  // A HIPOTECA É UM CADASTRO, e cada campo dele é conferido: o texto livre de
  // antes não dizia se a matrícula estava lá, de quem era o imóvel nem quanto
  // ele valia — e não havia onde guardar a certidão.
  if (required.requiresCollateral) {
    const mortgages = cpr.mortgages ?? [];
    if (mortgages.length === 0) {
      gaps.push({
        owner: CPR_GAP_OWNER.consultant,
        label: 'ao menos um bem em hipoteca (exigido pelo comitê)',
      });
    }
    mortgages.forEach((mortgage, index) => {
      const which = `${index + 1}º bem em hipoteca`;
      text(mortgage.description, `descrição do ${which}`);
      text(mortgage.registryNumber, `matrícula do ${which}`);
      text(mortgage.registryDistrict, `comarca do registro do ${which}`);
      text(mortgage.city, `município/UF do ${which}`);
      text(mortgage.ownerName, `proprietário do ${which}`);
      text(mortgage.ownerDocument, `CPF/CNPJ do proprietário do ${which}`);
      number(mortgage.appraisedValue, `valor de avaliação do ${which}`);
      if (!mortgage.documentFileId) {
        gaps.push({
          owner: CPR_GAP_OWNER.consultant,
          label: `o documento do ${which} (matrícula atualizada, anexo obrigatório)`,
        });
      }
    });
  }

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
 * O CONTEXTO DEIXOU DE SER VAZIO, e o que o encheu foi o PENHOR.
 *
 * Até ele, nenhuma pendência do consultor dependia de nada fora do rascunho — o
 * que ele deve é o que ele digita e anexa —, e por isso esta função passava
 * `{ invoices: [], seasonName: '' }` e pronto. A área exigida quebra isso: ela é
 * dele (é ele quem soma matrículas para fechá-la), mas não sai do rascunho — sai
 * das sacas da permuta e das duas taxas congeladas no registro.
 *
 * As notas e a safra continuam vazias, e continuam pelo mesmo motivo de antes:
 * as pendências que dependem delas são de OUTROS postos, e este recorte as
 * descarta de qualquer jeito.
 *
 * AS EXIGÊNCIAS DO COMITÊ entraram pelo mesmo caminho do penhor, e pelo mesmo
 * motivo: são do consultor (é ele quem traz o avalista) e não saem do rascunho
 * (saem da mesa do comitê). É esta lista que trava o retorno da permuta ao
 * comitê enquanto o que ele pediu não está na cédula.
 *
 * O PENHOR NÃO TEM PADRÃO, e isso é deliberado: `NO_PLEDGE` existe e seria um
 * default cômodo, mas um parâmetro opcional aqui é a porta pela qual a próxima
 * chamada desliga a exigência sem que ninguém perceba — o portão continuaria
 * respondendo "pode encaminhar" com a garantia pela metade. Quem chama diz de que
 * permuta está falando, mesmo para dizer que ela é das antigas.
 */
export function consultantCprGaps(
  cpr: CprDraft,
  areas: CprAreaDraft[],
  pledge: CprPledge,
  requirements: CprRequirements,
): string[] {
  return cprGapsOf(cpr, areas, { invoices: [], seasonName: '', pledge, requirements })
    .filter((gap) => gap.owner === CPR_GAP_OWNER.consultant)
    .map((gap) => gap.label);
}

/** A parte da permuta que entra na cédula sem passar por formulário nenhum. */
export interface CprKnown {
  barterCode: string;
  /**
   * O NÚMERO DA CPR, reservado no registro da permuta. Está aqui, entre o que
   * ninguém digita, porque deixou de ser digitado: quem numera é o sistema.
   */
  cprNumber: string;
  emitterName: string;
  emitterDocument: string;
  grainName: string;
  /**
   * O VENCIMENTO da entrega — da VERSÃO do Barter, e não da cédula.
   *
   * Ele está aqui, entre o que ninguém digita, porque essa é a correção: o
   * vencimento é o mesmo para todas as cédulas da versão. `null` enquanto a
   * versão não o tiver acertado, e aí `cprGaps` cobra dizendo onde.
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
  /**
   * O NÚMERO DA APÓLICE do seguro (cláusula XVIII, "j") — informado pela
   * SEGURADORA, junto com o documento, na etapa dela.
   *
   * Leitura, pelo mesmo motivo das notas: quem o escreve é outro posto, e
   * enquanto ele foi digitado aqui o título citava uma apólice que ninguém
   * tinha anexado. VAZIO quando não há — a permuta sem seguro, ou a com seguro
   * que ainda não passou pela seguradora —, e aí a alínea simplesmente não
   * sai no documento.
   */
  insurancePolicy: string;
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
  /**
   * A mesma unidade pelo id — é ele que pré-seleciona a filial na lista
   * suspensa do local da entrega. Nulo quando a permuta não tem unidade, ou
   * quando ela foi excluída depois.
   */
  pickupUnitId: number | null;
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
 * elas não estão na permuta. A primeira é do lançamento — o nome da gestão e o
 * vencimento da CULTURA em que esta permuta é paga — e as segundas são o que o
 * faturamento produziu.
 */
export function knownFrom(
  barter: {
    code: string;
    cprNumber: string;
    producerName: string;
    versionCode: string;
    unitId: number | null;
    unitName: string;
    insurancePolicyNumber: string | null;
  },
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
    cprNumber: barter.cprNumber,
    emitterName: barter.producerName,
    emitterDocument: producerDocument,
    grainName: grainItem?.productName ?? '',
    dueDate: season.cprDueDate,
    seasonName: season.name,
    invoices,
    insurancePolicy: barter.insurancePolicyNumber ?? '',
    sacks,
    quantityKg: Math.round(sacks * sackWeightKg * 100) / 100,
    sackPrice,
    totalValue: Math.round(sacks * sackPrice * 100) / 100,
    versionCode: barter.versionCode,
    pickupUnit: barter.unitName,
    pickupUnitId: barter.unitId,
  };
}

/**
 * O MODELO DA CPR de um grão — o padrão de recebimento que a cédula nova traz
 * preenchido (ver `Product.cprSackWeightKg`).
 */
export interface GrainCprModel {
  sackWeightKg: number;
  maxMoisture: number;
  maxImpurities: number;
  oilContent: number;
}

/** O modelo como o cadastro do grão o guarda. */
export function grainCprModelOf(grain: {
  cprSackWeightKg: number;
  cprMaxMoisture: number;
  cprMaxImpurities: number;
  cprOilContent: number;
}): GrainCprModel {
  return {
    sackWeightKg: grain.cprSackWeightKg,
    maxMoisture: grain.cprMaxMoisture,
    maxImpurities: grain.cprMaxImpurities,
    oilContent: grain.cprOilContent,
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
 *
 * O PADRÃO DO GRÃO vem do MODELO DO GRÃO, e não da cédula anterior: ele é da
 * cultura, e não da pessoa. A última cédula do produtor pode ser de outro grão
 * — a canola do inverno passado —, e herdar dela o teor de óleo levaria o
 * número de uma cultura para a cédula da outra. A cédula anterior só responde
 * pelo padrão quando a permuta não tem grão com modelo (a de antes das safras
 * por cultura). A CULTIVAR continua vindo dela: é o que o produtor planta.
 */
export function suggestFrom(
  producer: { city: string } | null,
  previous: (CprDraft & { areas: CprAreaDraft[]; guarantors: CprGuarantorDraft[] }) | null,
  grainModel: GrainCprModel | null = null,
): Omit<Partial<CprDraft>, 'guarantors' | 'mortgages'> & {
  areas?: CprAreaDraft[];
  guarantors?: Omit<CprGuarantorDraft, 'scrFileId'>[];
} {
  const grainStandard: Partial<GrainCprModel> = grainModel
    ? { ...grainModel }
    : previous
      ? {
          sackWeightKg: previous.sackWeightKg,
          maxMoisture: previous.maxMoisture,
          maxImpurities: previous.maxImpurities,
          oilContent: previous.oilContent,
        }
      : {};
  if (!previous) {
    return { ...(producer?.city ? { emitterCity: producer.city } : {}), ...grainStandard };
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
    ...grainStandard,
    cultivar: previous.cultivar,
    // As lavouras vêm junto: matrícula, livro e comarca não mudam de uma safra
    // para a outra, e são a parte mais cara de digitar da cédula inteira. O
    // que muda é a área plantada, e é por isso que ela continua editável.
    areas: previous.areas,
    // Os AVALISTAS também: quem avaliza um produtor costuma ser o mesmo de uma
    // safra para a outra, e o bloco de qualificação deles é o mais longo do
    // formulário inteiro. SÓ A QUALIFICAÇÃO: o id é da linha da outra cédula, e
    // o SCR dele é uma fotografia com data, como o do emitente.
    guarantors: previous.guarantors.map(guarantorQualificationOf),
    // As HIPOTECAS não vêm: o bem dado em garantia é desta negociação, e o
    // documento dele (a matrícula atualizada) envelhece como o SCR.
    // O que NÃO vem: o local da entrega. Ele é da NEGOCIAÇÃO, não da pessoa —
    // repeti-lo faria a entrega desta safra herdar em silêncio a praça da
    // anterior, que é exatamente o tipo de campo que ninguém reconfere.
  };
}
