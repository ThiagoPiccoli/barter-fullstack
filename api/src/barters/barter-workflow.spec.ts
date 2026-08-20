import { CAPABILITY, rolesWith } from '../common/policy';
import { ROLE } from '../common/roles';
import {
  BARTER_ACTION,
  BARTER_HOLDER,
  BARTER_LINE,
  BARTER_STATUS,
  BARTER_STATUSES,
  BARTER_STATUS_LABELS,
  BARTER_STEPS,
  lineFrom,
  nextActionOf,
  refusalFor,
  stepAt,
  type BarterAction,
  type BarterStatus,
} from './barter-workflow';

/**
 * A MÁQUINA DE ESTADOS da permuta, escrita por extenso.
 *
 * O que estes testes protegem não é o código — é o CAMINHO. Uma etapa nova, uma
 * transição a mais ou um estado que passe a aceitar outro ato mudam quem manda
 * em quê na cooperativa, e a diferença entre fazer isso de propósito e fazer
 * isso sem perceber é um teste que quebra.
 */
describe('Máquina de estados da permuta', () => {
  const barterIn = (status: string, managerName = 'Beatriz Nogueira') => ({
    status,
    managerName,
  });

  /* ── O desenho da linha ─────────────────────────────────────────────── */

  it('a linha vai do gerente ao faturamento, com a negativa como saída lateral', () => {
    expect([...BARTER_LINE]).toEqual([
      BARTER_STATUS.sentToManager,
      BARTER_STATUS.pending,
      BARTER_STATUS.approved,
      BARTER_STATUS.invoiced,
    ]);
    expect([...BARTER_STATUSES].sort()).toEqual([...BARTER_LINE, BARTER_STATUS.denied].sort());
  });

  it('todo estado é alcançável a partir do registro', () => {
    const alcançados = new Set<string>();
    for (const step of Object.values(BARTER_STEPS)) {
      for (const destino of step.to) alcançados.add(destino);
    }
    expect([...alcançados].sort()).toEqual([...BARTER_STATUSES].sort());
  });

  it('cada estado da linha tem UM dono, e o fim de linha não tem nenhum', () => {
    expect(BARTER_HOLDER[BARTER_STATUS.sentToManager]).toBe(ROLE.manager);
    expect(BARTER_HOLDER[BARTER_STATUS.pending]).toBe(ROLE.committee);
    expect(BARTER_HOLDER[BARTER_STATUS.approved]).toBe(ROLE.biller);

    // Fim de linha: ninguém está com ela, e não há próximo ato. É o que o JSON
    // da permuta devolve como `waitingFor: null` / `nextAction: null`.
    for (const fim of [BARTER_STATUS.denied, BARTER_STATUS.invoiced]) {
      expect(BARTER_HOLDER[fim]).toBeNull();
      expect(nextActionOf(fim)).toBeUndefined();
      expect(stepAt(fim)).toBeUndefined();
    }
  });

  it('todo estado tem rótulo — nenhum aparece na tela pelo nome técnico', () => {
    for (const status of BARTER_STATUSES) {
      expect(BARTER_STATUS_LABELS[status]).toBeTruthy();
    }
  });

  /**
   * O ALCANCE DE UM POSTO: o estado em que ele age e tudo o que vem depois.
   *
   * É `lineFrom` que recorta o que o faturista enxerga (ver
   * `bartersReadInvoicing` em policy.ts). Duas coisas ficam presas aqui: o
   * faturista NÃO alcança o que ainda está no gerente ou no comitê, e não
   * alcança permuta negada — ela morre no comitê e nunca chegou ao faturamento.
   */
  it('o alcance de um posto é o trecho da linha a partir dele', () => {
    expect(lineFrom(BARTER_ACTION.invoice)).toEqual([
      BARTER_STATUS.approved,
      BARTER_STATUS.invoiced,
    ]);
    expect(lineFrom(BARTER_ACTION.invoice)).not.toContain(BARTER_STATUS.denied);

    expect(lineFrom(BARTER_ACTION.review)).toEqual([
      BARTER_STATUS.pending,
      BARTER_STATUS.approved,
      BARTER_STATUS.invoiced,
    ]);

    // O registro não sai de estado nenhum: quem o faz alcança a linha inteira.
    expect(lineFrom(BARTER_ACTION.register)).toEqual([...BARTER_LINE]);
  });

  /* ── Quem move o quê ────────────────────────────────────────────────── */

  /**
   * A tabela de capacidades responde "quem pode"; esta responde "em que ponto".
   * As duas precisam apontar para a mesma pessoa — uma etapa cuja capacidade
   * pertença a dois papéis seria uma etapa sem dono.
   */
  it('cada etapa é de um papel só, e são papéis diferentes entre si', () => {
    const donos = Object.values(BARTER_STEPS).map((step) => rolesWith(step.capability));
    for (const papéis of donos) expect(papéis).toHaveLength(1);

    expect(donos.flat()).toEqual([ROLE.consultant, ROLE.manager, ROLE.committee, ROLE.biller]);
  });

  it('as capacidades das etapas são as do fluxo, nenhuma a mais', () => {
    expect(BARTER_STEPS[BARTER_ACTION.register].capability).toBe(CAPABILITY.bartersRegister);
    expect(BARTER_STEPS[BARTER_ACTION.opinion].capability).toBe(CAPABILITY.bartersOpinion);
    expect(BARTER_STEPS[BARTER_ACTION.review].capability).toBe(CAPABILITY.bartersReview);
    expect(BARTER_STEPS[BARTER_ACTION.invoice].capability).toBe(CAPABILITY.bartersInvoice);
  });

  /** A decisão é a única bifurcação: as outras etapas só empurram adiante. */
  it('só a decisão do comitê tem duas saídas', () => {
    expect(BARTER_STEPS[BARTER_ACTION.review].to).toEqual([
      BARTER_STATUS.approved,
      BARTER_STATUS.denied,
    ]);
    for (const action of [BARTER_ACTION.register, BARTER_ACTION.opinion, BARTER_ACTION.invoice]) {
      expect(BARTER_STEPS[action].to).toHaveLength(1);
    }
  });

  /* ── Quem passa e quem não passa ────────────────────────────────────── */

  it('cada ato passa no estado dele, e só nele', () => {
    const casos: [BarterAction, BarterStatus][] = [
      [BARTER_ACTION.opinion, BARTER_STATUS.sentToManager],
      [BARTER_ACTION.review, BARTER_STATUS.pending],
      [BARTER_ACTION.invoice, BARTER_STATUS.approved],
    ];

    for (const [action, permitido] of casos) {
      expect(refusalFor(action, barterIn(permitido))).toBeNull();

      for (const outro of BARTER_STATUSES.filter((status) => status !== permitido)) {
        expect(refusalFor(action, barterIn(outro))).toBeTruthy();
      }
    }
  });

  /**
   * O REGISTRO não olha estado: ele cria a permuta. Está na tabela para o
   * caminho ficar completo (é ele quem produz o primeiro estado), não para ser
   * conferido contra um estado anterior que não existe.
   */
  it('o registro não é recusado por estado nenhum', () => {
    for (const status of BARTER_STATUSES) {
      expect(refusalFor(BARTER_ACTION.register, barterIn(status))).toBeNull();
    }
  });

  /* ── O que se responde a quem chega fora de hora ────────────────────── */

  /**
   * As três recusas dizem coisas DIFERENTES de propósito, e é a diferença que
   * tem valor: "já foi decidida" respondido a quem espera o gerente manda a
   * pessoa procurar uma decisão que ninguém tomou.
   */
  it('quem chega cedo é informado de onde a permuta parou — com nome e tudo', () => {
    expect(refusalFor(BARTER_ACTION.review, barterIn(BARTER_STATUS.sentToManager))).toBe(
      'Esta permuta aguarda o parecer do gerente Beatriz Nogueira',
    );
    expect(refusalFor(BARTER_ACTION.invoice, barterIn(BARTER_STATUS.sentToManager))).toBe(
      'Esta permuta aguarda o parecer do gerente Beatriz Nogueira',
    );
    expect(refusalFor(BARTER_ACTION.invoice, barterIn(BARTER_STATUS.pending))).toBe(
      'Esta permuta aguarda a decisão do comitê',
    );
  });

  /** Sem gerente gravado (permutas anteriores à etapa dele), a frase se sustenta. */
  it('a permuta sem gerente gravado não produz um "undefined" na mensagem', () => {
    expect(refusalFor(BARTER_ACTION.review, { status: BARTER_STATUS.sentToManager })).toBe(
      'Esta permuta aguarda o parecer do gerente responsável',
    );
  });

  it('quem chega tarde ouve que a etapa dele já passou', () => {
    expect(refusalFor(BARTER_ACTION.opinion, barterIn(BARTER_STATUS.pending))).toBe(
      'Esta permuta já recebeu o parecer do gerente',
    );
    expect(refusalFor(BARTER_ACTION.review, barterIn(BARTER_STATUS.approved))).toBe(
      'Esta permuta já foi decidida pelo comitê',
    );
    expect(refusalFor(BARTER_ACTION.invoice, barterIn(BARTER_STATUS.invoiced))).toBe(
      'Esta permuta já foi faturada',
    );
  });

  /**
   * NEGADA é fim de linha, e a mensagem não finge que ela está esperando algo.
   * Em especial: negada não fatura, que é a única forma de dinheiro sair daqui.
   */
  it('a permuta negada não recebe mais nenhum ato', () => {
    for (const action of [BARTER_ACTION.opinion, BARTER_ACTION.review, BARTER_ACTION.invoice]) {
      expect(refusalFor(action, barterIn(BARTER_STATUS.denied))).toBe(
        'Esta permuta foi negada pelo comitê',
      );
    }
  });

  /**
   * Estado que não está na esteira — banco adulterado, ou um servidor à frente
   * deste. Recusa sem inventar uma explicação: falhar fechando vale mais do que
   * uma frase confiante sobre um fluxo que este código não conhece.
   */
  it('estado desconhecido recusa sem inventar explicação', () => {
    expect(refusalFor(BARTER_ACTION.review, barterIn('cancelada'))).toBe(
      'Esta permuta está em uma etapa que não permite esta ação',
    );
  });
});
