import { CAPABILITY, rolesWith, type Capability } from '../common/policy';
import { ROLE, type Role } from '../common/roles';
import {
  INSURANCE_CHOICE,
  choiceInsures,
  type InsuranceChoice,
} from '../insurance/insurance-policy';

/**
 * A LINHA DE PRODUÇÃO da permuta: por quais estados ela passa, quem a empurra
 * de um para o outro e o que responder a quem chega fora de hora.
 *
 * Existe porque o fluxo deixou de caber em `if`s. Enquanto eram duas etapas
 * (parecer e revisão), o `barters.service.ts` conseguia carregar as regras na
 * mão — três comparações de string espalhadas por dois métodos. Com quatro
 * postos e cinco estados, cada etapa nova exigiria reler os outros métodos para
 * descobrir quem mais olha `status`, e a pergunta "de onde uma permuta faturada
 * pode ter vindo?" não teria nenhum arquivo onde ser respondida.
 *
 * Aqui ela tem. A tabela abaixo é a única definição do caminho:
 *
 *     (registro)
 *         │
 *         ▼
 *      draft ──encaminha──▶ sentToManager ──parecer──▶ pending ◀──cumpre──┐
 *   (consultor)              (gerente)                (comitê)            │
 *                                                        │  └─exige──▶ awaitingRequirements
 *                                                        │                (consultor)
 *                                                        │
 *                                     COM SEGURO         │  ├─aprova──▶ awaitingPolicy ──────────────┐
 *                                                        │  └─ressalva─▶ awaitingPolicyWith… ───────┤ apólice
 *                                                        │                (seguradora)               │
 *                                     SEM SEGURO         │  ├─aprova──▶ approved ◀───────────────────┤
 *                                                        │  └─ressalva─▶ approvedWithConditions ◀────┘
 *                                                        └──nega──▶ denied   (faturista)
 *                                                            (fim da linha)        │
 *                     ┌───────────────────────────────────────────────────────────-┘
 *                     ▼
 *                  invoiced ──emite──▶ cprIssued ──assinaturas──▶ cprSigned ──registra──▶ cprRegistered
 *                 (faturista)             (emissor)                (emissor)              (emissor, fim)
 *
 * A TABELA DE ESTADOS — quem está com a permuta em cada um, e o que a tira dali:
 *
 *     estado                        com quem    ato que a move           para onde
 *     ────────────────────────────  ──────────  ───────────────────────  ──────────────────────────
 *     draft                         consultor   forward  (encaminha)     sentToManager
 *     sentToManager                 gerente     opinion  (parecer)       pending
 *     pending                       comitê      review   (decide)        awaitingPolicy… (com seguro)
 *                                                                        | approved… (sem seguro)
 *                                                                        | denied
 *                                               require  (exige)         awaitingRequirements
 *     awaitingRequirements          consultor   fulfill  (cumpre)        pending  (sem o gerente)
 *     awaitingPolicy                seguradora  insure   (apólice)       approved
 *     awaitingPolicyWithConditions  seguradora  insure   (apólice)       approvedWithConditions
 *     approved                      faturista   invoice  (fatura)        invoiced
 *     approvedWithConditions        faturista   invoice  (fatura)        invoiced
 *     invoiced                      emissor     cprIssue (emite)         cprIssued
 *     cprIssued                     emissor     cprSign  (assinaturas)   cprSigned
 *     cprSigned                     emissor     cprRegister (registra)   cprRegistered
 *     cprRegistered                 —           —                        (fim da linha)
 *     denied                        —           —                        (fim da linha)
 *
 * A ETAPA DA SEGURADORA é a única que NEM TODA PERMUTA atravessa. Quem decide
 * se ela acontece é o SEGURO da permuta (`insuranceChoice`, congelado no
 * registro): obrigatório na versão, ou opcional e aceito pelo produtor, a
 * aprovação cai na mesa da seguradora; sem seguro — a versão não oferecia ou o
 * produtor recusou —, ela cai direto na do faturista. É o COMITÊ quem faz a
 * permuta tomar um caminho ou o outro, mas não por escolha: o caminho é a
 * consequência do seguro, e a decisão dele continua sendo só aprovar, aprovar
 * com ressalva ou negar (ver `reviewOutcomeFor`).
 *
 * O DESVIO DAS EXIGÊNCIAS (`require` → `fulfill`) é a única volta da linha, e
 * ela é curta de propósito: o comitê pede avalista e/ou hipoteca, a
 * permuta volta ao CONSULTOR, e quando ele cumpre ela vai DIRETO ao comitê. O
 * gerente já deu o parecer sobre a negociação, e a negociação não mudou — o que
 * mudou é a garantia. Mandá-la de volta à mesa dele seria pedir um segundo
 * parecer sobre a mesma coisa; ele é AVISADO nas duas pontas (ver `Notice`), e
 * não chamado a agir.
 *
 * Cada posto tem UM dono e UMA pergunta:
 *
 * - **consultor**: monta a negociação, escreve o PARECER dele sobre o próprio
 *   cliente e PREENCHE a cédula. Enquanto ele não encaminha, a permuta é
 *   rascunho e não está na mesa de ninguém — ver `draft`;
 * - **gerente**: conhece o produtor e a negociação — escreve o parecer técnico.
 *   Não decide;
 * - **comitê**: lê o pedido do consultor, o parecer dele e o parecer do gerente,
 *   e DECIDE. É a única instância que aprova, aprova COM RESSALVA ou nega — e,
 *   antes de decidir, pode EXIGIR garantias (avalista, hipoteca), o que
 *   devolve a permuta ao consultor. O admin não decide — ele administra o
 *   sistema, e um administrador que também aprova é a mesma pessoa concedendo o
 *   acesso e usando-o;
 * - **seguradora**: o setor que cuida dos seguros. Só recebe a permuta aprovada
 *   QUE TEM SEGURO: cria a apólice, ANEXA o documento e informa o NÚMERO dele —
 *   o número que a cédula cita. Não avalia e não devolve;
 * - **faturista**: recebe o que as etapas anteriores produziram, FATURA e anexa
 *   as notas fiscais que saíram da permuta. Não avalia e não devolve;
 * - **emissor**: pega a permuta faturada, CONFERE a cédula que o consultor
 *   preencheu, EMITE, colhe as ASSINATURAS e a leva a REGISTRO. São três atos, e
 *   três estados, porque eles acontecem em dias diferentes — e "a CPR está em
 *   que pé?" é a pergunta que a operação faz o tempo todo sobre a entrega.
 *
 * POR QUE A CÉDULA É UM TRECHO E NÃO UM CAMPO: enquanto ela foi "o que o
 * faturista preenche junto com o faturamento", a emissão não tinha etapa, não
 * tinha prazo e não tinha dono. Uma permuta faturada ficava parada com a cédula
 * pela metade e nada no sistema dizia isso — a linha terminava em `invoiced` e
 * afirmava que o trabalho tinha acabado. Ele não tinha: faltava o título.
 *
 * O que este arquivo NÃO decide: quem é o gerente DESTA permuta (é o do
 * consultor, gravado no envio) nem qualquer alçada por valor. Isso é política
 * sobre o recurso e mora no service — ver o comentário no fim de `policy.ts`.
 */

export const BARTER_STATUS = {
  /**
   * RASCUNHO do consultor: registrada, mas ainda não encaminhada.
   *
   * É o único estado que não está na mesa de ninguém, e é isso que ele existe
   * para dar: o consultor monta a permuta hoje, escreve o parecer dela quando
   * tiver a conversa com o produtor, e só então encaminha. Antes disso, o
   * registro já vale — os valores da versão ficam congelados nele — mas nenhuma
   * fila da retaguarda o enxerga.
   *
   * Rascunho é DO DONO: `scopeFor`, no service, o esconde de quem não o
   * registrou. Uma permuta pela metade na fila do comitê seria trabalho pedido
   * a quem não foi chamado.
   */
  draft: 'draft',
  /** Encaminhada pelo consultor, na mesa do gerente dele, esperando parecer. */
  sentToManager: 'sentToManager',
  /**
   * Com parecer do gerente, na mesa do COMITÊ, esperando decisão.
   *
   * O nome ficou de quando a revisão era do admin, e ficou de propósito: ele
   * descreve o estado ("esperando alguém decidir"), não o cargo de quem decide,
   * e é o que está gravado nas permutas que já existem. Trocá-lo por
   * `atCommittee` renomearia dado histórico para dizer a mesma coisa.
   */
  pending: 'pending',
  /**
   * DEVOLVIDA AO CONSULTOR com EXIGÊNCIAS do comitê — avalista, hipoteca e/ou
   * seguro —, esperando que ele as cumpra.
   *
   * É estado próprio, e não um campo ao lado de `pending`, porque a permuta
   * MUDA DE MÃOS: enquanto o consultor não traz o aval, ela não está na mesa do
   * comitê, e uma fila do comitê que a mostrasse pediria decisão sobre um
   * negócio que ainda não tem a garantia que o próprio comitê exigiu.
   *
   * Ocupa o MESMO DEGRAU de `pending` na esteira (ver `BARTER_LINE`): a permuta
   * não andou nem recuou — o parecer do gerente continua valendo, e a decisão
   * continua por vir. Cumpridas as exigências, ela volta a `pending` DIRETO, sem
   * passar de novo pelo gerente.
   */
  awaitingRequirements: 'awaitingRequirements',
  /**
   * APROVADA pelo comitê, COM SEGURO — na mesa da SEGURADORA, esperando a
   * apólice.
   *
   * É estado próprio, e não um `approved` com uma pendência ao lado, porque a
   * permuta MUDA DE MÃOS: enquanto a apólice não existe, ela não está na fila
   * do faturista, e uma fila que a mostrasse pediria a nota de uma operação
   * cujo seguro — custo que já está dentro das sacas — ainda não foi
   * contratado.
   *
   * São DOIS estados, este e o da ressalva logo abaixo, pelo mesmo motivo de
   * `approvedWithConditions` ser estado e não campo: a ressalva é condição do
   * negócio, e a lista, o filtro e o cartão precisam continuar dizendo isso
   * enquanto a permuta está com a seguradora. A apólice devolve cada um ao seu
   * par — este a `approved`, o outro a `approvedWithConditions`.
   */
  awaitingPolicy: 'awaitingPolicy',
  /** O mesmo ponto da linha de `awaitingPolicy`, para a aprovação COM RESSALVA. */
  awaitingPolicyWithConditions: 'awaitingPolicyWithConditions',
  /** Aprovada pelo comitê — a fila do faturista. */
  approved: 'approved',
  /**
   * Aprovada pelo comitê COM RESSALVA — a mesma fila do faturista, e uma
   * exigência escrita junto.
   *
   * É estado próprio, e não um `approved` com um campo ao lado, porque a
   * ressalva é uma CONDIÇÃO do negócio e quem a cumpre não é quem a escreveu.
   * Enquanto ela fosse uma observação dentro da aprovação, a lista, o filtro e
   * o cartão diriam "Aprovada — a faturar" sobre uma permuta condicionada — e a
   * única maneira de descobrir isso seria abrir a permuta e ler até o fim.
   *
   * O que ela NÃO é: um estado de espera. A permuta está decidida e liberada; o
   * comitê exigiu algo junto, e o texto da decisão (`reviewNote`, obrigatório
   * aqui) diz o quê. Cobrar o cumprimento é da operação, não deste fluxo.
   *
   * AVALISTA E HIPOTECA SAÍRAM DAQUI. Eles eram os exemplos clássicos de
   * ressalva, e foram justamente os que viraram etapa com dono, como este
   * comentário previa: o comitê os EXIGE antes de decidir (`require`), a
   * permuta volta ao consultor (`awaitingRequirements`) e só retorna ao comitê
   * com eles na cédula. O SEGURO saiu por outro caminho: ele é da versão do
   * Barter, e a permuta que o tem passa pela seguradora (`awaitingPolicy…`). A
   * ressalva continua existindo para o resto — a condição que a operação cobra
   * por fora.
   */
  approvedWithConditions: 'approvedWithConditions',
  /** Negada pelo comitê. Fim da linha: não fatura e não volta. */
  denied: 'denied',
  /**
   * Faturada, com as notas anexadas — e na mesa do EMISSOR, esperando a cédula.
   *
   * Deixou de ser fim de linha quando a emissão da CPR virou etapa. A permuta
   * faturada não está pronta: falta o título que formaliza a entrega do grão, e
   * até ele existir a empresa tem uma nota emitida sem a garantia que a
   * acompanha. Chamar isso de "concluída" era a afirmação errada mais cara do
   * fluxo antigo.
   */
  invoiced: 'invoiced',
  /**
   * CÉDULA EMITIDA — conferida pelo emissor e gerada. Esperando as assinaturas.
   *
   * A emissão é o momento da CONFERÊNCIA: o emissor lê contra o modelo o que o
   * consultor preencheu, e o que tem lacuna não sai (ver `cprGaps`). Depois
   * dela, o documento existe no mundo e o que falta é gente assinar.
   */
  cprIssued: 'cprIssued',
  /**
   * CÉDULA ASSINADA pelo emitente (e pelo cônjuge, e pelos avalistas quando
   * houver). Esperando o REGISTRO.
   *
   * Estado próprio, e não um campo dentro da emissão, porque a distância entre
   * assinar e registrar é de dias e o dono dela é outro escritório: a
   * assinatura acontece quando o produtor vem à cidade, e o registro quando o
   * cartório (ou a B3) responde. Uma cédula assinada e não registrada é uma
   * garantia que ainda não vale contra terceiros — exatamente o tipo de coisa
   * que precisa aparecer numa lista, e não ser descoberta na conversa.
   */
  cprSigned: 'cprSigned',
  /**
   * CÉDULA REGISTRADA. Fim da linha do lado bom — agora sim.
   *
   * A permuta foi acordada, analisada, decidida, faturada e o título está
   * registrado. Não há próximo ato: o que vem depois é a colheita, e ela não é
   * deste sistema.
   */
  cprRegistered: 'cprRegistered',
} as const;

export type BarterStatus = (typeof BARTER_STATUS)[keyof typeof BARTER_STATUS];

/**
 * A ESTEIRA, na ordem em que se anda nela — e cada degrau é uma LISTA.
 *
 * Ela era uma fila simples de estados, um por degrau, e deixou de poder ser
 * quando a decisão do comitê ganhou a terceira saída: `approved` e
 * `approvedWithConditions` são o MESMO ponto da linha (a mesa do faturista) com
 * desfechos diferentes. Com a lista antiga, o único jeito de a segunda ser
 * alcançável pelo faturamento era pô-la um degrau adiante da primeira — e aí
 * uma permuta aprovada com ressalva passaria a ser "tarde demais para faturar",
 * porque a posição na esteira é justamente o que responde cedo/tarde.
 *
 * `denied` fica fora: ele é saída lateral, não um degrau adiante.
 */
export const BARTER_LINE = [
  [BARTER_STATUS.draft],
  [BARTER_STATUS.sentToManager],
  // A PERMUTA DEVOLVIDA COM EXIGÊNCIAS divide o degrau com a da mesa do comitê:
  // as duas ainda esperam a decisão, e o parecer do gerente vale para as duas.
  // Um degrau próprio, antes ou depois de `pending`, diria que a volta ao
  // consultor fez a permuta andar ou recuar na esteira — e ela não fez nenhum
  // dos dois.
  [BARTER_STATUS.pending, BARTER_STATUS.awaitingRequirements],
  // A MESA DA SEGURADORA: um degrau antes do faturamento, que a permuta SEM
  // seguro pula — a decisão a leva direto ao degrau seguinte. Ser degrau, e não
  // um estado lateral, é o que faz o faturista que chega cedo ouvir "aguarda a
  // apólice da seguradora", e não um "não pode" genérico.
  [BARTER_STATUS.awaitingPolicy, BARTER_STATUS.awaitingPolicyWithConditions],
  [BARTER_STATUS.approved, BARTER_STATUS.approvedWithConditions],
  [BARTER_STATUS.invoiced],
  // O TRECHO DA CÉDULA — três degraus, um por ato do emissor. Eles são degraus
  // separados, e não um só com três estados, porque a esteira é o que responde
  // cedo/tarde: registrar uma cédula que ainda não foi assinada precisa receber
  // "ela aguarda a coleta de assinaturas", e não um "não pode" genérico.
  [BARTER_STATUS.cprIssued],
  [BARTER_STATUS.cprSigned],
  [BARTER_STATUS.cprRegistered],
] as const satisfies readonly (readonly BarterStatus[])[];

/** Em que DEGRAU da esteira este estado está — `-1` fora dela (só `denied`). */
export function stageOf(status: string): number {
  return BARTER_LINE.findIndex((stage) => (stage as readonly string[]).includes(status));
}

/** Todos os estados possíveis — é o que valida o filtro `?status=` da listagem. */
export const BARTER_STATUSES = [...BARTER_LINE.flat(), BARTER_STATUS.denied] as const;

/** O rótulo de cada estado, na língua da operação. */
export const BARTER_STATUS_LABELS: Record<BarterStatus, string> = {
  [BARTER_STATUS.draft]: 'Rascunho',
  [BARTER_STATUS.sentToManager]: 'No gerente',
  [BARTER_STATUS.pending]: 'No comitê',
  [BARTER_STATUS.awaitingRequirements]: 'Exigências do comitê, com o consultor',
  [BARTER_STATUS.awaitingPolicy]: 'Aprovada, aguardando a apólice',
  [BARTER_STATUS.awaitingPolicyWithConditions]: 'Aprovada com ressalva, aguardando a apólice',
  [BARTER_STATUS.approved]: 'Aprovada, a faturar',
  [BARTER_STATUS.approvedWithConditions]: 'Aprovada com ressalva, a faturar',
  [BARTER_STATUS.denied]: 'Negada',
  // "Faturada" sozinho dizia que tinha acabado. O rótulo agora diz o que falta,
  // que é o que muda a leitura de quem passa os olhos numa lista de cinquenta.
  [BARTER_STATUS.invoiced]: 'Faturada, a emitir a CPR',
  [BARTER_STATUS.cprIssued]: 'CPR emitida, a assinar',
  [BARTER_STATUS.cprSigned]: 'CPR assinada, a registrar',
  [BARTER_STATUS.cprRegistered]: 'CPR registrada',
};

/**
 * COM QUEM a permuta está parada agora — o papel que precisa agir para ela
 * andar. Null nos dois fins de linha, onde não há próximo passo.
 *
 * É o que o app usa para dizer "esperando o comitê" sem manter uma segunda
 * cópia do fluxo em Dart.
 */
export const BARTER_HOLDER: Record<BarterStatus, Role | null> = {
  // O rascunho está com QUEM O ESCREVEU. É o único estado em que o dono da vez
  // é o consultor, e dizê-lo é a diferença entre "esperando você" e uma permuta
  // que parece parada por culpa da retaguarda.
  [BARTER_STATUS.draft]: ROLE.consultant,
  [BARTER_STATUS.sentToManager]: ROLE.manager,
  [BARTER_STATUS.pending]: ROLE.committee,
  // DEVOLVIDA, ela está com o CONSULTOR — é ele quem vai buscar o aval ou a
  // matrícula da hipoteca. Dizer "no comitê" aqui faria o
  // consultor esperar uma decisão que está esperando por ele.
  [BARTER_STATUS.awaitingRequirements]: ROLE.consultant,
  [BARTER_STATUS.awaitingPolicy]: ROLE.insurer,
  [BARTER_STATUS.awaitingPolicyWithConditions]: ROLE.insurer,
  [BARTER_STATUS.approved]: ROLE.biller,
  [BARTER_STATUS.approvedWithConditions]: ROLE.biller,
  [BARTER_STATUS.denied]: null,
  // A permuta faturada está com o EMISSOR, e os três degraus da cédula também:
  // emitir, colher assinatura e registrar são atos do mesmo posto.
  [BARTER_STATUS.invoiced]: ROLE.emitter,
  [BARTER_STATUS.cprIssued]: ROLE.emitter,
  [BARTER_STATUS.cprSigned]: ROLE.emitter,
  [BARTER_STATUS.cprRegistered]: null,
};

/** Os atos que movem uma permuta. `register` é a entrada: cria em vez de mover. */
export const BARTER_ACTION = {
  register: 'register',
  forward: 'forward',
  opinion: 'opinion',
  review: 'review',
  /** O comitê EXIGE garantias (avalista, hipoteca) e devolve ao consultor. */
  require: 'require',
  /** O consultor CUMPRE as exigências e devolve ao comitê — sem passar pelo gerente. */
  fulfill: 'fulfill',
  /** A SEGURADORA informa a apólice — o documento e o número — da permuta com seguro. */
  insure: 'insure',
  invoice: 'invoice',
  /** A EMISSÃO da cédula — a conferência do emissor, e o documento gerado. */
  cprIssue: 'cprIssue',
  /** A COLETA DE ASSINATURAS do emitente (e de quem mais assine com ele). */
  cprSign: 'cprSign',
  /** O REGISTRO do título — em cartório ou na B3, conforme a operação. */
  cprRegister: 'cprRegister',
} as const;

export type BarterAction = (typeof BARTER_ACTION)[keyof typeof BARTER_ACTION];

/** O bastante de uma permuta para decidir se ela pode andar, e para explicar por quê. */
export interface BarterAtStep extends Partial<Record<ReviewRequirement, boolean>> {
  status: string;
  managerName?: string | null;
  /**
   * COMO o seguro chegou a esta permuta — é o que decide se ela passa pela
   * seguradora (ver `insuredOf`). Opcional para quem só pergunta pelos estados;
   * ausente, a permuta é lida como sem seguro, que é o caso que não acrescenta
   * etapa nenhuma.
   */
  insuranceChoice?: string;
}

/**
 * Esta permuta TEM SEGURO? — a pergunta que decide se a etapa da seguradora
 * existe para ela.
 *
 * Quem responde é a escolha congelada no registro, e não a política da versão
 * hoje: o admin pode mudar a política do Barter depois, e uma permuta já
 * fechada não pode ganhar nem perder uma etapa por isso.
 */
export function insuredOf(barter: Pick<BarterAtStep, 'insuranceChoice'>): boolean {
  return choiceInsures((barter.insuranceChoice ?? INSURANCE_CHOICE.none) as InsuranceChoice);
}

export interface WorkflowStep {
  readonly action: BarterAction;
  /**
   * De onde ela sai. `null` só no registro, que não sai de lugar nenhum.
   *
   * É uma LISTA pelo mesmo motivo do degrau da esteira: o faturamento parte de
   * `approved` e de `approvedWithConditions`, que são o mesmo ponto da linha. O
   * primeiro da lista é o representante do degrau — é dele que sai o cálculo de
   * cedo/tarde e o alcance de `lineFrom`.
   */
  readonly from: readonly BarterStatus[] | null;
  /** Para onde ela vai. Mais de um quando o ato é uma DECISÃO (aprova/nega). */
  readonly to: readonly BarterStatus[];
  /** A capacidade que abre a porta — a mesma que o decorator da rota exige. */
  readonly capability: Capability;
  /**
   * O NOME da etapa — o que ela é, e não o que ela virou.
   *
   * Substantivo, e de propósito: o mesmo rótulo serve à etapa cumprida, à que
   * está acontecendo e à que ainda vem. "Parecer do gerente" se lê igual nos
   * três estados; "Aprovada pelo comitê" só se lê depois, e uma checklist é
   * feita principalmente do que ainda não aconteceu.
   */
  readonly label: string;
  /**
   * COMO a etapa terminou, quando ela pode terminar de mais de um jeito.
   *
   * Só a decisão do comitê tem: as outras empurram adiante e nada mais, e
   * carimbar "Faturamento: faturada" seria repetir o nome da etapa. Quem
   * resolve o rótulo é o EVENTO gravado (ver `outcomeLabelOf`), não o estado
   * atual da permuta — uma permuta faturada está em `invoiced`, e a decisão que
   * a levou até lá continua tendo sido "Aprovada".
   */
  readonly outcomes?: Partial<Record<BarterStatus, string>>;
  /**
   * O que dizer a quem chega CEDO: a permuta ainda está parada nesta etapa, e
   * quem pediu a ação é de uma etapa adiante.
   */
  readonly waiting: (barter: BarterAtStep) => string;
  /** O que dizer a quem chega TARDE: esta etapa já foi cumprida. */
  readonly done: string;
  /**
   * É um DESVIO: uma volta que só acontece quando alguém a pede, e não um posto
   * por onde toda permuta passa.
   *
   * O andamento (`progressOf`) não a mostra como etapa "a vir" — prometer a
   * toda permuta uma rodada de exigências que a maioria nunca terá seria a
   * checklist mentindo para o lado oposto do de sempre. Ela aparece só
   * enquanto a permuta está NELA; antes e depois, quem conta que ela houve é a
   * linha do tempo dos eventos.
   */
  readonly detour?: true;
  /**
   * A etapa só existe para ALGUMAS permutas — e esta função diz para quais.
   *
   * Diferente do desvio, que acontece quando alguém o pede, esta é uma etapa da
   * linha que certas permutas simplesmente NÃO TÊM: a da seguradora, para quem
   * não tem seguro. O andamento não a mostra para elas (ela não está "a vir" nem
   * "cumprida" — ela não existe ali), e o ato é recusado com `skipped`.
   */
  readonly appliesTo?: (barter: BarterAtStep) => boolean;
  /** O que dizer a quem pede a etapa numa permuta que não a tem. */
  readonly skipped?: string;
}

/**
 * A TABELA. Uma etapa nova é uma entrada aqui — e o `Record` obriga a escrever
 * as duas mensagens junto com ela, que é a parte que se esquece: sem elas, a
 * pessoa que chega fora de hora recebe "não foi possível" e vai perguntar a
 * alguém onde a permuta parou.
 */
export const BARTER_STEPS: Record<BarterAction, WorkflowStep> = {
  [BARTER_ACTION.register]: {
    action: BARTER_ACTION.register,
    from: null,
    to: [BARTER_STATUS.draft],
    capability: CAPABILITY.bartersRegister,
    label: 'Registro do consultor',
    waiting: () => 'Esta permuta ainda não foi registrada',
    done: 'Esta permuta já foi registrada',
  },
  /**
   * O PARECER DO CONSULTOR e o encaminhamento — um ato só, e de propósito.
   *
   * Ele é quem conhece o cliente: safras anteriores, pontualidade, o que está
   * plantado e o que a lavoura promete. Isso não estava em lugar nenhum do
   * registro — a permuta chegava ao gerente como uma lista de insumos, e o que
   * o consultor sabia ficava no telefonema que ele dava depois.
   *
   * Encaminhar SEM parecer não existe: o texto é o próprio ato (ver
   * `ForwardBarterDto`). Mas escrevê-lo sem encaminhar existe, e é o que
   * `PUT /barters/:code/note` faz — o rascunho é salvável pela metade, porque a
   * conversa com o produtor não acontece no mesmo minuto em que se montam os
   * insumos.
   */
  [BARTER_ACTION.forward]: {
    action: BARTER_ACTION.forward,
    from: [BARTER_STATUS.draft],
    to: [BARTER_STATUS.sentToManager],
    capability: CAPABILITY.bartersRegister,
    label: 'Parecer do consultor',
    waiting: () => 'Esta permuta é um rascunho e ainda não foi encaminhada ao gerente',
    done: 'Esta permuta já foi encaminhada ao gerente',
  },
  [BARTER_ACTION.opinion]: {
    action: BARTER_ACTION.opinion,
    from: [BARTER_STATUS.sentToManager],
    to: [BARTER_STATUS.pending],
    capability: CAPABILITY.bartersOpinion,
    label: 'Parecer do gerente',
    waiting: (barter) =>
      `Esta permuta aguarda o parecer do gerente ${barter.managerName ?? 'responsável'}`,
    done: 'Esta permuta já recebeu o parecer do gerente',
  },
  [BARTER_ACTION.review]: {
    action: BARTER_ACTION.review,
    from: [BARTER_STATUS.pending],
    // TRÊS desfechos, em CINCO estados: aprovar e aprovar com ressalva caem na
    // seguradora quando a permuta tem seguro, e no faturista quando não tem (ver
    // `reviewOutcomeFor`). `awaitingPolicy` é o primeiro porque é ele que
    // representa o degrau na esteira (ver `from` em WorkflowStep): é o mais
    // próximo que a decisão alcança, e é a partir dele que o andamento conta a
    // decisão como cumprida — inclusive na permuta sem seguro, que pula o degrau.
    to: [
      BARTER_STATUS.awaitingPolicy,
      BARTER_STATUS.awaitingPolicyWithConditions,
      BARTER_STATUS.approved,
      BARTER_STATUS.approvedWithConditions,
      BARTER_STATUS.denied,
    ],
    capability: CAPABILITY.bartersReview,
    label: 'Decisão do comitê',
    outcomes: {
      [BARTER_STATUS.awaitingPolicy]: 'Aprovada',
      [BARTER_STATUS.awaitingPolicyWithConditions]: 'Aprovada com ressalva',
      [BARTER_STATUS.approved]: 'Aprovada',
      [BARTER_STATUS.approvedWithConditions]: 'Aprovada com ressalva',
      [BARTER_STATUS.denied]: 'Negada',
    },
    waiting: () => 'Esta permuta aguarda a decisão do comitê',
    done: 'Esta permuta já foi decidida pelo comitê',
  },
  /**
   * AS EXIGÊNCIAS DO COMITÊ — avalista e/ou hipoteca, pedidos ANTES da
   * decisão. A permuta volta ao consultor.
   *
   * É um ato do comitê, e não um quarto desfecho de `review`, por dois motivos.
   * Ele não DECIDE nada: a permuta volta para a mesma mesa depois, e quem a
   * aprova ou nega é uma decisão que ainda vem. E ele pode se REPETIR — o
   * comitê pede avalista, recebe, e pede também a hipoteca —, enquanto a decisão
   * acontece uma vez. Misturados no mesmo ato, a linha do tempo assinaria a
   * "Decisão do comitê" com a primeira devolução.
   *
   * Vem DEPOIS de `review` na tabela de propósito: os dois partem de `pending`,
   * e `stepAt(pending)` precisa responder com o ato que a permuta ESPERA — a
   * decisão. Exigir é a alternativa a decidir, não o próximo passo dela.
   */
  [BARTER_ACTION.require]: {
    action: BARTER_ACTION.require,
    from: [BARTER_STATUS.pending],
    to: [BARTER_STATUS.awaitingRequirements],
    capability: CAPABILITY.bartersReview,
    label: 'Exigências do comitê',
    detour: true,
    waiting: () => 'Esta permuta aguarda a decisão do comitê',
    done: 'O comitê já fez exigências nesta permuta, e ela está com o consultor',
  },
  /**
   * O CUMPRIMENTO das exigências — o consultor devolve a permuta ao comitê.
   *
   * Ela volta a `pending` DIRETO, sem passar pelo gerente: o parecer dele foi
   * sobre a negociação, e a negociação não mudou. O que mudou foi a garantia, e
   * quem a pediu foi o comitê. O gerente é AVISADO, não chamado a agir.
   *
   * Quem confere que o pedido foi mesmo cumprido é a cédula (ver
   * `consultantCprGaps`): avalista e hipoteca passam a ser pendências DO
   * CONSULTOR assim que o comitê as exige, e este ato não anda com elas em
   * aberto.
   */
  [BARTER_ACTION.fulfill]: {
    action: BARTER_ACTION.fulfill,
    from: [BARTER_STATUS.awaitingRequirements],
    to: [BARTER_STATUS.pending],
    capability: CAPABILITY.bartersRegister,
    label: 'Exigências do comitê',
    detour: true,
    waiting: (barter) => {
      const required = requirementsOf(barter);
      return required.length > 0
        ? `Esta permuta aguarda o consultor providenciar o que o comitê exigiu: ${required.join(', ').toLowerCase()}`
        : 'Esta permuta aguarda o consultor cumprir as exigências do comitê';
    },
    done: 'As exigências do comitê já foram cumpridas, e a permuta voltou ao comitê',
  },
  /**
   * A APÓLICE — o ato da seguradora: anexar o documento e informar o número.
   *
   * Só existe para a permuta COM SEGURO (`appliesTo`). A sem seguro nunca passa
   * por aqui: a decisão do comitê a manda direto ao faturamento, e pedir a
   * apólice dela recebe `skipped`, e não "já foi informada" — que é o que a
   * posição na esteira diria, e seria mentira.
   *
   * Ela devolve cada aprovação ao SEU par (ver `policyOutcomeFor`): a aprovada
   * vira `approved`, a aprovada com ressalva vira `approvedWithConditions`. A
   * seguradora não decide nada, e a ressalva que o comitê escreveu continua
   * sendo a ressalva quando a permuta chega ao faturista.
   */
  [BARTER_ACTION.insure]: {
    action: BARTER_ACTION.insure,
    from: [BARTER_STATUS.awaitingPolicy, BARTER_STATUS.awaitingPolicyWithConditions],
    to: [BARTER_STATUS.approved, BARTER_STATUS.approvedWithConditions],
    capability: CAPABILITY.bartersInsure,
    label: 'Apólice do seguro',
    appliesTo: insuredOf,
    skipped: 'Esta permuta não tem seguro — ela não passa pela seguradora',
    waiting: () => 'Esta permuta aguarda a apólice da seguradora',
    done: 'A apólice desta permuta já foi informada',
  },
  [BARTER_ACTION.invoice]: {
    action: BARTER_ACTION.invoice,
    // As duas aprovações faturam. A ressalva é condição do negócio, não um
    // portão deste fluxo — ver `approvedWithConditions`.
    from: [BARTER_STATUS.approved, BARTER_STATUS.approvedWithConditions],
    to: [BARTER_STATUS.invoiced],
    capability: CAPABILITY.bartersInvoice,
    label: 'Faturamento',
    waiting: () => 'Esta permuta aguarda o faturamento',
    done: 'Esta permuta já foi faturada',
  },
  /**
   * A EMISSÃO DA CÉDULA — o primeiro ato do emissor, e o único que CONFERE.
   *
   * Ela parte de `invoiced` porque a cédula cita a nota como origem da dívida
   * (cláusula VII): emitir um título antes de a mercadoria sair afirmaria uma
   * dívida que ainda não nasceu. O preenchimento, esse não espera — o consultor
   * coleta a qualificação e as matrículas desde o rascunho, e é exatamente por
   * isso que a conferência aqui é rápida.
   */
  [BARTER_ACTION.cprIssue]: {
    action: BARTER_ACTION.cprIssue,
    from: [BARTER_STATUS.invoiced],
    to: [BARTER_STATUS.cprIssued],
    capability: CAPABILITY.bartersCprIssue,
    label: 'Emissão da CPR',
    waiting: () => 'Esta permuta aguarda a emissão da cédula',
    done: 'A cédula desta permuta já foi emitida',
  },
  [BARTER_ACTION.cprSign]: {
    action: BARTER_ACTION.cprSign,
    from: [BARTER_STATUS.cprIssued],
    to: [BARTER_STATUS.cprSigned],
    capability: CAPABILITY.bartersCprIssue,
    label: 'Coleta de assinaturas',
    waiting: () => 'A cédula desta permuta aguarda a coleta de assinaturas',
    done: 'A cédula desta permuta já foi assinada',
  },
  [BARTER_ACTION.cprRegister]: {
    action: BARTER_ACTION.cprRegister,
    from: [BARTER_STATUS.cprSigned],
    to: [BARTER_STATUS.cprRegistered],
    capability: CAPABILITY.bartersCprIssue,
    label: 'Registro da CPR',
    waiting: () => 'A cédula desta permuta aguarda o registro',
    done: 'A cédula desta permuta já foi registrada',
  },
};

/**
 * AS EXIGÊNCIAS QUE O COMITÊ PODE IMPOR antes de decidir — avalista e hipoteca.
 *
 * Elas moram aqui, ao lado da etapa que as produz (`require`), e não numa
 * tabela do banco: são poucas, são fixas, e cada uma é uma condição de negócio
 * que a operação inteira já nomeia assim. A lista fechada é o que permite à
 * tela desenhar uma caixa para cada e à cédula transformar cada uma num campo
 * obrigatório (ver `cprGapsOf`) sem interpretar prosa.
 *
 * O SEGURO FOI UMA DELAS, e saiu. Exigi-lo fazia o consultor digitar na cédula
 * o número de uma apólice, e a apólice passou a ser da SEGURADORA, que a cria e
 * a anexa. O seguro de uma permuta é decidido na versão do Barter (obrigatório
 * ou opcional) e com o produtor, no registro — não pela mesa do comitê.
 *
 * `requiresCollateral` é a HIPOTECA. A coluna nasceu como "garantia real", que
 * é o gênero; o que o comitê pede e o consultor traz é a espécie — a hipoteca
 * do imóvel, o campo `mortgages` da cédula. O nome da coluna ficou para não
 * reescrever dado gravado; o rótulo diz o que ela é.
 *
 * O rótulo vem daqui pelo mesmo motivo de `BARTER_STATUS_LABELS`: o app não
 * deveria ter uma segunda cópia do vocabulário do fluxo para sair de sincronia
 * com esta.
 */
export const REVIEW_REQUIREMENT_LABELS = {
  requiresGuarantor: 'Avalista',
  requiresCollateral: 'Hipoteca',
} as const;

export type ReviewRequirement = keyof typeof REVIEW_REQUIREMENT_LABELS;

export const REVIEW_REQUIREMENTS = Object.keys(REVIEW_REQUIREMENT_LABELS) as ReviewRequirement[];

/**
 * As exigências LIGADAS, pelos rótulos — a lista que a tela mostra e que a
 * linha do tempo guarda por escrito.
 */
export function requirementsOf(source: Partial<Record<ReviewRequirement, boolean>>): string[] {
  return REVIEW_REQUIREMENTS.filter((key) => source[key] === true).map(
    (key) => REVIEW_REQUIREMENT_LABELS[key],
  );
}

/** Os desfechos que o comitê ESCOLHE — o que a tela dele oferece e o DTO aceita. */
export type ReviewDecision = 'approved' | 'approvedWithConditions' | 'denied';

/**
 * PARA ONDE a decisão do comitê leva ESTA permuta.
 *
 * O comitê escolhe entre três desfechos, e não entre cinco estados: aprovar,
 * aprovar com ressalva ou negar. Se a aprovação cai na seguradora ou direto no
 * faturista é CONSEQUÊNCIA do seguro da permuta, e não uma segunda escolha —
 * pedir ao comitê que marcasse "aprovada, para a seguradora" seria pedir que ele
 * lembrasse de um detalhe do registro que o sistema já sabe.
 */
export function reviewOutcomeFor(decision: ReviewDecision, barter: BarterAtStep): BarterStatus {
  if (decision === BARTER_STATUS.denied || !insuredOf(barter)) return decision;
  return decision === BARTER_STATUS.approvedWithConditions
    ? BARTER_STATUS.awaitingPolicyWithConditions
    : BARTER_STATUS.awaitingPolicy;
}

/**
 * PARA ONDE a apólice devolve a permuta: cada aprovação ao seu par.
 *
 * A seguradora não decide nada — ela só tira a permuta da própria mesa —, e a
 * ressalva que o comitê escreveu precisa continuar sendo ressalva quando a
 * permuta chega ao faturista.
 */
export function policyOutcomeFor(status: string): BarterStatus {
  return status === BARTER_STATUS.awaitingPolicyWithConditions
    ? BARTER_STATUS.approvedWithConditions
    : BARTER_STATUS.approved;
}

/** A etapa que age sobre uma permuta parada neste estado, se houver. */
export function stepAt(status: string): WorkflowStep | undefined {
  return Object.values(BARTER_STEPS).find((step) =>
    (step.from as readonly string[] | null)?.includes(status),
  );
}

/**
 * A esteira A PARTIR de um posto: o estado em que ele age e tudo o que vem
 * depois — ou seja, o que JÁ CHEGOU nele.
 *
 * É o que define o alcance de quem só enxerga o próprio trecho da linha. O
 * faturista é o caso: ele recebe o que as etapas anteriores produziram, e o que
 * ainda está no gerente ou no comitê não é trabalho dele nem informação dele.
 *
 * Vem da esteira, e não de uma lista escrita à mão no service, porque a resposta
 * MUDA quando a linha muda: uma etapa nova depois do faturamento entra sozinha
 * no alcance do faturista, e uma etapa nova antes dele fica de fora sozinha.
 * Repare que `denied` não está em [BARTER_LINE] e por isso nunca aparece aqui —
 * uma permuta negada morre no comitê e não chega ao faturamento.
 */
export function lineFrom(action: BarterAction): BarterStatus[] {
  const from = BARTER_STEPS[action].from;
  const at = from === null ? 0 : stageOf(from[0]);
  return at < 0 ? [] : BARTER_LINE.slice(at).flatMap((stage) => [...stage]);
}

/** O próximo ato que esta permuta espera — `undefined` nos fins de linha. */
export function nextActionOf(status: string): BarterAction | undefined {
  return stepAt(status)?.action;
}

/**
 * POR QUE esta permuta não pode receber este ato agora — ou `null`, quando pode.
 *
 * A resposta distingue as três maneiras de dar errado, porque elas mandam a
 * pessoa fazer coisas diferentes:
 *
 * - **chegou cedo**: a etapa anterior não terminou. Dizer "já foi decidida" a
 *   quem espera o comitê o mandaria procurar uma decisão que ninguém tomou — o
 *   que ele precisa saber é com quem a permuta está parada;
 * - **chegou tarde**: a etapa dele já foi cumprida;
 * - **negada**: fim da linha, e nenhuma das duas explicações serve.
 *
 * Isto é a REGRA, não a autorização: quem pode chamar a rota é a capacidade do
 * passo (`step.capability`), conferida pelo AccessGuard antes de a permuta ser
 * lida.
 */
export function refusalFor(action: BarterAction, barter: BarterAtStep): string | null {
  const step = BARTER_STEPS[action];

  // A ETAPA QUE ESTA PERMUTA NÃO TEM vem antes de tudo: a apólice de uma
  // permuta sem seguro não é "cedo" nem "tarde" — ela não vai acontecer, e
  // dizer "já foi informada" mandaria alguém procurar um documento que nunca
  // existiu.
  if (step.appliesTo && !step.appliesTo(barter)) {
    return step.skipped ?? 'Esta etapa não se aplica a esta permuta';
  }

  if (step.from === null || (step.from as readonly string[]).includes(barter.status)) return null;

  if (barter.status === BARTER_STATUS.denied) {
    return 'Esta permuta foi negada pelo comitê';
  }

  const here = stageOf(barter.status);
  const there = stageOf(step.from[0]);

  // Estado que não está na esteira: dado de uma versão futura do servidor, ou
  // escrito à mão no banco. Recusa sem inventar uma explicação.
  if (here < 0) return 'Esta permuta está em uma etapa que não permite esta ação';

  // NO MESMO DEGRAU vale a mesma resposta de quem chega cedo: a permuta está
  // parada no ponto da linha em que o ato acontece, só que com outra pessoa. É
  // o caso do desvio das exigências — o comitê que tenta decidir uma permuta
  // devolvida precisa ouvir que ela aguarda o consultor, e não que "já foi
  // decidida", que é justamente o que ela não foi.
  return here <= there ? (stepAt(barter.status)?.waiting(barter) ?? step.done) : step.done;
}

/* ── O ANDAMENTO: a linha inteira, e não só o trecho já andado ─────────── */

/**
 * Em que pé está uma etapa DESTA permuta.
 *
 * Existe porque "por onde ela passou" e "o que ainda falta" são a mesma
 * pergunta feita dos dois lados, e quem abre uma permuta faz as duas. A linha do
 * tempo dos eventos só responde à primeira: uma permuta parada no comitê mostra
 * dois passos e cala sobre os dois que faltam — e "falta o quê, e com quem?" é
 * justamente o que o consultor veio perguntar, porque é o que ele vai ter de
 * responder ao produtor.
 */
export const BARTER_STEP_STATE = {
  /** Cumprida. É a parte que tem evento gravado. */
  done: 'done',
  /** É AQUI que a permuta está parada agora. */
  current: 'current',
  /** Ainda vai acontecer. */
  ahead: 'ahead',
  /**
   * NÃO vai acontecer: a permuta saiu da linha antes de chegar aqui.
   *
   * Diferente de `ahead` de propósito. Uma permuta negada nunca fatura, e
   * mostrar o faturamento dela como etapa pendente prometeria um passo que
   * ninguém vai dar — o pior tipo de erro numa tela de acompanhamento, porque
   * quem lê fica esperando.
   */
  halted: 'halted',
} as const;

export type BarterStepState = (typeof BARTER_STEP_STATE)[keyof typeof BARTER_STEP_STATE];

/** Uma etapa da esteira vista de dentro de uma permuta concreta. */
export interface BarterProgressStep {
  readonly action: BarterAction;
  readonly state: BarterStepState;
  /** O nome da etapa — ver `label` em [WorkflowStep]. */
  readonly label: string;
  /** O papel dono dela: quem a cumpriu, ou quem ainda vai cumpri-la. */
  readonly role: Role | null;
  /**
   * O que há para dizer sobre o ESTADO desta etapa, por extenso:
   *
   * - na etapa de agora, o que ela espera ("aguarda a decisão do comitê");
   * - na que não vai acontecer, por que não ("a permuta foi negada").
   *
   * Null nas cumpridas — elas se explicam sozinhas, com o autor e a data — e
   * nas que ainda vêm, onde não há nada a dizer além do nome e do dono.
   *
   * A frase sai daqui, e não da tela, porque o motivo é do FLUXO: uma saída
   * lateral nova (uma permuta cancelada, digamos) chegaria escrita certa no app
   * já instalado, em vez de ele continuar dizendo "foi negada" sobre uma
   * permuta que não foi.
   */
  readonly stateNote: string | null;
}

/** A POSIÇÃO da etapa na esteira — o degrau do estado que ela produz. */
function orderOf(step: WorkflowStep): number {
  return stageOf(step.to[0]);
}

/**
 * O papel dono da etapa, tirado da CAPACIDADE que a abre.
 *
 * Não é um campo da tabela porque seria a mesma verdade escrita duas vezes: a
 * política já diz quem tem `barters.review`, e uma etapa cuja capacidade
 * pertencesse a dois papéis especializados seria uma etapa sem dono — o que os
 * testes da máquina de estados já não deixam acontecer.
 *
 * O ADMIN É EXCLUÍDO DESTA BUSCA, de propósito: ele tem todas as capacidades
 * porque é o responsável final pelo sistema, mas a esteira mostra quem
 * EXECUTA cada etapa na prática — o posto especializado (consultor, gerente,
 * comitê, faturista, emissor) — e não o admin, que a compartilha por
 * supervisão. Sem esta exclusão, `rolesWith` devolveria o admin para toda
 * etapa (ele é o primeiro papel da tabela e tem a capacidade de todas), e a
 * linha do tempo perderia o autor de cada etapa.
 */
function ownerOf(step: WorkflowStep): Role | null {
  return rolesWith(step.capability).find((role) => role !== ROLE.admin) ?? null;
}

/**
 * O CAMINHO INTEIRO desta permuta, etapa por etapa, do registro ao faturamento.
 *
 * É a esteira vista de dentro de uma permuta: as mesmas quatro etapas de
 * [BARTER_STEPS], na mesma ordem, cada uma dizendo em que pé está. Sai daqui, e
 * não de uma lista escrita à mão no app, pelo motivo de sempre — uma etapa nova
 * aparece nas telas já instaladas em vez de exigir versão nova, e o Dart não
 * ganha uma segunda cópia do fluxo para sair de sincronia com esta.
 *
 * Estado que nenhuma etapa produz (banco adulterado, ou um servidor à frente
 * deste) devolve lista VAZIA: a tela cai na linha do tempo dos eventos, que é
 * fato gravado, em vez de desenhar um caminho inventado.
 */
export function progressOf(barter: BarterAtStep): BarterProgressStep[] {
  const now = stepAt(barter.status);

  // OS DESVIOS ficam fora da checklist, menos o que a permuta está fazendo
  // AGORA (ver `WorkflowStep.detour`). Ele entra logo antes da etapa para a
  // qual devolve a permuta: "exigências do comitê" e depois "decisão do
  // comitê", que é a ordem em que as duas vão acontecer.
  //
  // AS ETAPAS QUE A PERMUTA NÃO TEM saem também, e por outro motivo: elas não
  // são uma volta que pode acontecer — são uma parada que ela pula. A permuta
  // sem seguro não mostra "Apólice do seguro" nem como cumprida nem como a vir.
  const line = Object.values(BARTER_STEPS).filter(
    (step) => !step.detour && (!step.appliesTo || step.appliesTo(barter)),
  );
  const detour = now?.detour ? now : undefined;
  const resumes = detour ? stepAt(detour.to[0]) : undefined;
  const steps =
    detour && resumes ? line.flatMap((step) => (step === resumes ? [detour, step] : [step])) : line;

  const here = stageOf(barter.status);

  // SAÍDA LATERAL (hoje só a negativa): fora da esteira, mas produzida por
  // alguma etapa. Essa etapa foi cumprida — e o que vinha depois dela não vem.
  const exit =
    here < 0
      ? steps.find((step) => (step.to as readonly string[]).includes(barter.status))
      : undefined;

  if (here < 0 && !exit) return [];

  const lastDone = exit ? orderOf(exit) : here;

  // POR QUE a linha parou, quando ela parou — dito a partir do estado em que a
  // permuta saiu, e não de uma frase escrita para a negativa: uma saída lateral
  // nova é uma linha na tabela de estados, e esta frase a acompanha.
  const stoppedNote = exit
    ? `Não acontece: a permuta foi ${(
        BARTER_STATUS_LABELS[barter.status as BarterStatus] ?? barter.status
      ).toLowerCase()}`
    : null;

  return steps.map((step) => {
    // A ETAPA DE AGORA é perguntada primeiro: o desvio devolve a permuta ao
    // mesmo degrau em que ela está, e pela posição ele contaria como cumprido.
    const state =
      step === now
        ? BARTER_STEP_STATE.current
        : orderOf(step) <= lastDone
          ? BARTER_STEP_STATE.done
          : exit
            ? BARTER_STEP_STATE.halted
            : BARTER_STEP_STATE.ahead;

    return {
      action: step.action,
      state,
      label: step.label,
      role: ownerOf(step),
      stateNote:
        state === BARTER_STEP_STATE.current
          ? step.waiting(barter)
          : state === BARTER_STEP_STATE.halted
            ? stoppedNote
            : null,
    };
  });
}

/**
 * COMO uma etapa terminou, quando ela podia terminar de mais de um jeito —
 * "Aprovada" ou "Negada" na decisão do comitê, `null` nas demais.
 *
 * A pergunta é sobre o estado ALCANÇADO pelo ato (o `toStatus` do evento), e não
 * sobre onde a permuta está hoje: a decisão de uma permuta já faturada continua
 * tendo sido uma aprovação, e é isso que a linha do tempo mostra.
 */
export function outcomeLabelOf(action: string, toStatus: string): string | null {
  const step = BARTER_STEPS[action as BarterAction];
  return step?.outcomes?.[toStatus as BarterStatus] ?? null;
}
