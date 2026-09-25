import { BARTER_STATUS, BARTER_STATUS_LABELS, type BarterStatus } from './barter-workflow';

/**
 * O DOSSIÊ DO COMITÊ — as peças que fundamentam a decisão de crédito.
 *
 * A permuta chegava à mesa do comitê com duas peças escritas: o pedido do
 * consultor e o parecer técnico do gerente. O resto — a consulta ao Serasa, o
 * extrato do que o produtor já deve à cooperativa, a certidão que alguém puxou
 * na véspera — existia, circulava por e-mail entre os integrantes e morria na
 * caixa de quem convocou a reunião. A decisão ficava registrada; a base dela,
 * não. Meses depois, "com base em quê vocês aprovaram isto?" era uma pergunta
 * sem lugar onde ser respondida.
 *
 * ## Quem junta e quem lê
 *
 * Junta o COMITÊ (`barters.creditAttach`), e só ele — nem o admin, que lê. Quem
 * põe prova dentro de uma decisão é quem decide; a leitura do admin existe para
 * auditar isso, e ele escrever ali seria escrever dentro da fundamentação de
 * uma decisão que não é dele.
 *
 * Lê o COMITÊ e o ADMIN (`barters.creditRead`), e mais ninguém. É a única
 * leitura de anexo restrita do sistema: nota fiscal, cédula assinada e
 * comprovante de registro vão para quem alcança a permuta, porque são
 * documentos da operação. Estes são a vida financeira de um cliente, colhida
 * para decidir crédito — o consultor que o atende leva ao produtor a DECISÃO, e
 * não o dossiê.
 *
 * ## Até quando
 *
 * A JANELA de anexar vai até a decisão, e para aí. Ela é a mesma do pedido de
 * fora do Barter e pelo mesmo raciocínio: o dossiê existe para DECIDIR, e juntar
 * uma consulta de crédito a uma permuta já aprovada seria acrescentar
 * fundamento a uma decisão já tomada — um documento que parece ter sido lido e
 * não foi. Depois da decisão, o caminho é o pedido de alteração, que devolve a
 * permuta à esteira e a faz ser decidida de novo.
 *
 * A REMOÇÃO segue a mesma janela: o que fundamentou uma decisão tomada não se
 * apaga, e é por isso que a trilha guarda as duas pontas (ver
 * `barterCreditFileRemoved` em audit.service.ts).
 */

/**
 * QUE PEÇA é esta. Três, e a terceira é aberta de propósito: a reunião pede o
 * que a reunião precisa, e uma lista fechada nos dois primeiros faria a certidão
 * de ônus que o gerente trouxe não ter onde entrar — que é exatamente como os
 * documentos voltavam para o e-mail.
 */
export const CREDIT_FILE_KIND = {
  /** A consulta de crédito — Serasa, SPC, o birô que a empresa usa. */
  serasa: 'serasa',
  /**
   * O ENDIVIDAMENTO DENTRO DA COOPERATIVA — quanto este produtor já deve à
   * própria casa.
   *
   * É a peça que nenhum birô responde, e a que mais pesa: o Serasa mostra o que
   * ele deve ao mercado, e este extrato mostra o que ele deve a QUEM está
   * decidindo. Uma permuta aprovada sem olhá-lo é crédito novo concedido por
   * cima de crédito antigo da mesma empresa.
   */
  indebtedness: 'indebtedness',
  /** O que mais a reunião tiver pedido. */
  other: 'other',
} as const;

export type CreditFileKind = (typeof CREDIT_FILE_KIND)[keyof typeof CREDIT_FILE_KIND];

export const CREDIT_FILE_KINDS = Object.values(CREDIT_FILE_KIND) as CreditFileKind[];

/** O nome de cada peça, na língua da operação. */
export const CREDIT_FILE_LABELS: Record<CreditFileKind, string> = {
  [CREDIT_FILE_KIND.serasa]: 'Consulta ao Serasa',
  [CREDIT_FILE_KIND.indebtedness]: 'Endividamento na cooperativa',
  [CREDIT_FILE_KIND.other]: 'Outro documento',
};

/**
 * ATÉ ONDE o dossiê alcança: os estados em que a permuta ainda pode receber (ou
 * perder) uma peça.
 *
 * Os mesmos três do pedido de fora do Barter, e pela mesma razão de eles virem
 * escritos assim e não deduzidos da esteira: são os estados ANTERIORES à
 * decisão. O RASCUNHO está dentro porque o comitê enxerga a etapa anterior à
 * dele (ver `bartersReadAll` em policy.ts) e a consulta de crédito costuma ser
 * puxada antes de a permuta chegar — não faz sentido recusar um documento por
 * ele ter sido providenciado cedo.
 */
export const CREDIT_FILE_WINDOW: readonly BarterStatus[] = [
  BARTER_STATUS.draft,
  BARTER_STATUS.sentToManager,
  BARTER_STATUS.pending,
];

/** O bastante de uma permuta para saber se o dossiê dela ainda se mexe. */
export interface BarterAtCreditFile {
  status: string;
}

/**
 * POR QUE esta permuta não aceita mexer no dossiê agora — ou `null`, quando
 * aceita.
 *
 * Devolve a frase pronta, como `refusalFor` na esteira e `productRequestRefusal`
 * no pedido: quem bate na porta fechada precisa saber o que fazer em seguida, e
 * essa resposta é do domínio, não da tela.
 */
export function creditFileRefusal(barter: BarterAtCreditFile): string | null {
  if ((CREDIT_FILE_WINDOW as readonly string[]).includes(barter.status)) return null;

  if (barter.status === BARTER_STATUS.denied) {
    return 'Esta permuta foi negada pelo comitê, e o que fundamentou a negativa não se altera';
  }
  return (
    `Esta permuta já foi decidida pelo comitê (${
      BARTER_STATUS_LABELS[barter.status as BarterStatus] ?? barter.status
    }), e o dossiê é o que fundamentou a decisão. ` +
    'Peça a alteração da permuta para que ela seja decidida de novo'
  );
}
