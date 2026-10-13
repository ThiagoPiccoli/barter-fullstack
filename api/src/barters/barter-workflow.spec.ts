import { CAPABILITY, rolesWith } from '../common/policy';
import { ROLE } from '../common/roles';
import {
  BARTER_ACTION,
  BARTER_HOLDER,
  BARTER_LINE,
  BARTER_STATUS,
  BARTER_STATUSES,
  BARTER_STATUS_LABELS,
  BARTER_STEP_STATE,
  BARTER_STEPS,
  lineFrom,
  nextActionOf,
  outcomeLabelOf,
  policyOutcomeFor,
  progressOf,
  refusalFor,
  reviewOutcomeFor,
  stageOf,
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

  /** A mesma permuta, COM SEGURO — a que passa pela seguradora. */
  const seguradaEm = (status: string) => ({ ...barterIn(status), insuranceChoice: 'required' });

  /* ── O desenho da linha ─────────────────────────────────────────────── */

  it('a linha vai do rascunho ao registro da cédula, com a negativa como saída lateral', () => {
    expect(BARTER_LINE.map((degrau) => [...degrau])).toEqual([
      [BARTER_STATUS.draft],
      [BARTER_STATUS.sentToManager],
      // A DEVOLVIDA COM EXIGÊNCIAS divide o degrau com a da mesa do comitê: as
      // duas ainda esperam a decisão, e a volta ao consultor não faz a permuta
      // andar nem recuar na esteira.
      [BARTER_STATUS.pending, BARTER_STATUS.awaitingRequirements],
      // A MESA DA SEGURADORA: um degrau antes do faturamento, que a permuta sem
      // seguro pula. As duas aprovações dividem o degrau, como na mesa seguinte.
      [BARTER_STATUS.awaitingPolicy, BARTER_STATUS.awaitingPolicyWithConditions],
      // O MESMO DEGRAU: as duas aprovações são a mesa do faturista, e a ressalva
      // é o desfecho, não um ponto adiante na esteira. Pô-la um degrau à frente
      // faria a permuta aprovada com ressalva ser "tarde demais para faturar".
      [BARTER_STATUS.approved, BARTER_STATUS.approvedWithConditions],
      [BARTER_STATUS.invoiced],
      // O TRECHO DA CÉDULA: três degraus, um por ato do emissor. `invoiced`
      // deixou de ser o fim da linha — uma permuta faturada ainda deve o título
      // que formaliza a entrega, e enquanto isso não tinha etapa, não tinha dono.
      [BARTER_STATUS.cprIssued],
      [BARTER_STATUS.cprSigned],
      [BARTER_STATUS.cprRegistered],
    ]);
    expect([...BARTER_STATUSES].sort()).toEqual(
      [...BARTER_LINE.flat(), BARTER_STATUS.denied].sort(),
    );
  });

  /** O degrau é a POSIÇÃO na esteira, e é ele que responde cedo/tarde. */
  it('as duas aprovações ocupam o mesmo degrau, e a negativa nenhum', () => {
    expect(stageOf(BARTER_STATUS.approvedWithConditions)).toBe(stageOf(BARTER_STATUS.approved));
    expect(stageOf(BARTER_STATUS.awaitingRequirements)).toBe(stageOf(BARTER_STATUS.pending));
    expect(stageOf(BARTER_STATUS.awaitingPolicyWithConditions)).toBe(
      stageOf(BARTER_STATUS.awaitingPolicy),
    );
    // A apólice vem DEPOIS da decisão e ANTES do faturamento.
    expect(stageOf(BARTER_STATUS.awaitingPolicy)).toBe(stageOf(BARTER_STATUS.pending) + 1);
    expect(stageOf(BARTER_STATUS.approved)).toBe(stageOf(BARTER_STATUS.awaitingPolicy) + 1);
    expect(stageOf(BARTER_STATUS.draft)).toBe(0);
    expect(stageOf(BARTER_STATUS.denied)).toBe(-1);
  });

  it('todo estado é alcançável a partir do registro', () => {
    const alcançados = new Set<string>();
    for (const step of Object.values(BARTER_STEPS)) {
      for (const destino of step.to) alcançados.add(destino);
    }
    expect([...alcançados].sort()).toEqual([...BARTER_STATUSES].sort());
  });

  it('cada estado da linha tem UM dono, e o fim de linha não tem nenhum', () => {
    // O rascunho está com quem o escreveu: é o único estado cujo dono da vez é o
    // consultor, e dizê-lo é a diferença entre "esperando você" e uma permuta
    // que parece parada por culpa da retaguarda.
    expect(BARTER_HOLDER[BARTER_STATUS.draft]).toBe(ROLE.consultant);
    expect(BARTER_HOLDER[BARTER_STATUS.sentToManager]).toBe(ROLE.manager);
    expect(BARTER_HOLDER[BARTER_STATUS.pending]).toBe(ROLE.committee);
    // DEVOLVIDA COM EXIGÊNCIAS, ela está com o CONSULTOR — é ele quem vai
    // buscar o aval ou a hipoteca. O comitê só volta a tê-la quando ele
    // cumprir.
    expect(BARTER_HOLDER[BARTER_STATUS.awaitingRequirements]).toBe(ROLE.consultant);
    // APROVADA COM SEGURO, ela está com a SEGURADORA — com ou sem ressalva.
    expect(BARTER_HOLDER[BARTER_STATUS.awaitingPolicy]).toBe(ROLE.insurer);
    expect(BARTER_HOLDER[BARTER_STATUS.awaitingPolicyWithConditions]).toBe(ROLE.insurer);
    expect(BARTER_HOLDER[BARTER_STATUS.approved]).toBe(ROLE.biller);
    expect(BARTER_HOLDER[BARTER_STATUS.approvedWithConditions]).toBe(ROLE.biller);

    // A FATURADA está com o EMISSOR, e não com ninguém: é a mudança que este
    // trecho da esteira existe para fazer. Uma permuta faturada ainda deve o
    // título, e antes disso ela dizia "pronta".
    expect(BARTER_HOLDER[BARTER_STATUS.invoiced]).toBe(ROLE.emitter);
    expect(BARTER_HOLDER[BARTER_STATUS.cprIssued]).toBe(ROLE.emitter);
    expect(BARTER_HOLDER[BARTER_STATUS.cprSigned]).toBe(ROLE.emitter);

    // Fim de linha: ninguém está com ela, e não há próximo ato. É o que o JSON
    // da permuta devolve como `waitingFor: null` / `nextAction: null`.
    for (const fim of [BARTER_STATUS.denied, BARTER_STATUS.cprRegistered]) {
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
    // A APROVADA COM RESSALVA entra aqui, e é o ponto: ela é a mesma fila do
    // faturista. Fora desta lista, a permuta que o comitê aprovou com exigência
    // sumiria da tela de quem tem de faturá-la.
    expect(lineFrom(BARTER_ACTION.invoice)).toEqual([
      BARTER_STATUS.approved,
      BARTER_STATUS.approvedWithConditions,
      BARTER_STATUS.invoiced,
      BARTER_STATUS.cprIssued,
      BARTER_STATUS.cprSigned,
      BARTER_STATUS.cprRegistered,
    ]);
    expect(lineFrom(BARTER_ACTION.invoice)).not.toContain(BARTER_STATUS.denied);
    // E o RASCUNHO não: o faturista não alcança o que ainda nem foi proposto.
    expect(lineFrom(BARTER_ACTION.invoice)).not.toContain(BARTER_STATUS.draft);

    // O ALCANCE DO EMISSOR é o mais estreito de todos: um degrau adiante do
    // faturista. O que ainda não foi faturado não é trabalho de quem leva um
    // título a cartório.
    expect(lineFrom(BARTER_ACTION.cprIssue)).toEqual([
      BARTER_STATUS.invoiced,
      BARTER_STATUS.cprIssued,
      BARTER_STATUS.cprSigned,
      BARTER_STATUS.cprRegistered,
    ]);
    expect(lineFrom(BARTER_ACTION.cprIssue)).not.toContain(BARTER_STATUS.approved);

    // O ALCANCE DA SEGURADORA começa na mesa dela — e o faturista, acima, NÃO a
    // enxerga: a permuta esperando apólice ainda não chegou ao faturamento.
    expect(lineFrom(BARTER_ACTION.insure)).toEqual([
      BARTER_STATUS.awaitingPolicy,
      BARTER_STATUS.awaitingPolicyWithConditions,
      BARTER_STATUS.approved,
      BARTER_STATUS.approvedWithConditions,
      BARTER_STATUS.invoiced,
      BARTER_STATUS.cprIssued,
      BARTER_STATUS.cprSigned,
      BARTER_STATUS.cprRegistered,
    ]);
    expect(lineFrom(BARTER_ACTION.invoice)).not.toContain(BARTER_STATUS.awaitingPolicy);

    expect(lineFrom(BARTER_ACTION.review)).toEqual([
      BARTER_STATUS.pending,
      BARTER_STATUS.awaitingRequirements,
      BARTER_STATUS.awaitingPolicy,
      BARTER_STATUS.awaitingPolicyWithConditions,
      BARTER_STATUS.approved,
      BARTER_STATUS.approvedWithConditions,
      BARTER_STATUS.invoiced,
      BARTER_STATUS.cprIssued,
      BARTER_STATUS.cprSigned,
      BARTER_STATUS.cprRegistered,
    ]);

    // O registro não sai de estado nenhum: quem o faz alcança a linha inteira.
    expect(lineFrom(BARTER_ACTION.register)).toEqual([...BARTER_LINE.flat()]);
  });

  /* ── Quem move o quê ────────────────────────────────────────────────── */

  /**
   * A tabela de capacidades responde "quem pode"; esta responde "em que ponto".
   * As duas precisam apontar para a mesma pessoa — uma etapa cuja capacidade
   * pertença a dois papéis ESPECIALIZADOS seria uma etapa sem dono. O admin é
   * excluído desta contagem de propósito: ele tem todas as capacidades por ser
   * o responsável final, e aparece ao lado do dono especializado em toda
   * etapa — não é a ele que este teste pergunta "de quem é a etapa".
   */
  it('cada etapa é de um papel só (fora o admin), e os postos se sucedem sem se repetir', () => {
    const donos = Object.values(BARTER_STEPS).map((step) =>
      rolesWith(step.capability).filter((role) => role !== ROLE.admin),
    );
    for (const papéis of donos) expect(papéis).toHaveLength(1);

    // O consultor aparece duas vezes (registrar e encaminhar são o mesmo posto
    // partido em dois para caber o parecer dele) e o EMISSOR três: emitir,
    // colher assinaturas e registrar são o mesmo ofício, sobre o mesmo
    // documento, em dias diferentes. O que os separa é o tempo, não o dono — e é
    // por isso que eles são etapas e não um campo.
    //
    // O DESVIO DAS EXIGÊNCIAS é a única volta: o comitê exige, o consultor
    // cumpre — e o GERENTE não aparece nele. O parecer dele já foi dado.
    expect(donos.flat()).toEqual([
      ROLE.consultant,
      ROLE.consultant,
      ROLE.manager,
      ROLE.committee,
      ROLE.committee,
      ROLE.consultant,
      ROLE.insurer,
      ROLE.biller,
      ROLE.emitter,
      ROLE.emitter,
      ROLE.emitter,
    ]);
  });

  it('as capacidades das etapas são as do fluxo, nenhuma a mais', () => {
    expect(BARTER_STEPS[BARTER_ACTION.register].capability).toBe(CAPABILITY.bartersRegister);
    expect(BARTER_STEPS[BARTER_ACTION.forward].capability).toBe(CAPABILITY.bartersRegister);
    expect(BARTER_STEPS[BARTER_ACTION.opinion].capability).toBe(CAPABILITY.bartersOpinion);
    expect(BARTER_STEPS[BARTER_ACTION.review].capability).toBe(CAPABILITY.bartersReview);
    // EXIGIR é do comitê, pela mesma porta da decisão: é a alternativa a
    // decidir. CUMPRIR é do consultor, pela porta do registro — é a mesma pessoa
    // que montou a permuta voltando a ela.
    expect(BARTER_STEPS[BARTER_ACTION.require].capability).toBe(CAPABILITY.bartersReview);
    expect(BARTER_STEPS[BARTER_ACTION.fulfill].capability).toBe(CAPABILITY.bartersRegister);
    expect(BARTER_STEPS[BARTER_ACTION.insure].capability).toBe(CAPABILITY.bartersInsure);
    expect(BARTER_STEPS[BARTER_ACTION.invoice].capability).toBe(CAPABILITY.bartersInvoice);
    // Os três atos da cédula sob a MESMA capacidade: eles são um ofício só.
    expect(BARTER_STEPS[BARTER_ACTION.cprIssue].capability).toBe(CAPABILITY.bartersCprIssue);
    expect(BARTER_STEPS[BARTER_ACTION.cprSign].capability).toBe(CAPABILITY.bartersCprIssue);
    expect(BARTER_STEPS[BARTER_ACTION.cprRegister].capability).toBe(CAPABILITY.bartersCprIssue);
  });

  /**
   * A decisão é a única bifurcação de verdade: três desfechos, que caem na
   * seguradora ou no faturista conforme o seguro da permuta. A apólice tem duas
   * saídas, mas não escolhe — devolve cada aprovação ao seu par.
   */
  it('só a decisão do comitê escolhe a saída — e a apólice só devolve ao par', () => {
    expect(BARTER_STEPS[BARTER_ACTION.review].to).toEqual([
      BARTER_STATUS.awaitingPolicy,
      BARTER_STATUS.awaitingPolicyWithConditions,
      BARTER_STATUS.approved,
      BARTER_STATUS.approvedWithConditions,
      BARTER_STATUS.denied,
    ]);
    expect(BARTER_STEPS[BARTER_ACTION.insure].to).toEqual([
      BARTER_STATUS.approved,
      BARTER_STATUS.approvedWithConditions,
    ]);
    for (const action of [
      BARTER_ACTION.register,
      BARTER_ACTION.forward,
      BARTER_ACTION.opinion,
      BARTER_ACTION.require,
      BARTER_ACTION.fulfill,
      BARTER_ACTION.invoice,
      BARTER_ACTION.cprIssue,
      BARTER_ACTION.cprSign,
      BARTER_ACTION.cprRegister,
    ]) {
      expect(BARTER_STEPS[action].to).toHaveLength(1);
    }
  });

  /* ── Quem passa e quem não passa ────────────────────────────────────── */

  it('cada ato passa nos estados dele, e só neles', () => {
    const casos: [BarterAction, BarterStatus[]][] = [
      [BARTER_ACTION.forward, [BARTER_STATUS.draft]],
      [BARTER_ACTION.opinion, [BARTER_STATUS.sentToManager]],
      [BARTER_ACTION.review, [BARTER_STATUS.pending]],
      // EXIGIR parte do mesmo ponto da decisão, e só dele: a permuta já
      // devolvida não recebe uma segunda devolução por cima da primeira.
      [BARTER_ACTION.require, [BARTER_STATUS.pending]],
      // CUMPRIR só existe na permuta devolvida.
      [BARTER_ACTION.fulfill, [BARTER_STATUS.awaitingRequirements]],
      // O FATURAMENTO parte das duas aprovações: a ressalva é condição do
      // negócio, e não um portão deste fluxo.
      [BARTER_ACTION.invoice, [BARTER_STATUS.approved, BARTER_STATUS.approvedWithConditions]],
      // O TRECHO DO EMISSOR: cada ato parte de um estado só, porque eles
      // acontecem em dias diferentes e a ordem entre eles é a do mundo — não se
      // registra o que ninguém assinou.
      [BARTER_ACTION.cprIssue, [BARTER_STATUS.invoiced]],
      [BARTER_ACTION.cprSign, [BARTER_STATUS.cprIssued]],
      [BARTER_ACTION.cprRegister, [BARTER_STATUS.cprSigned]],
    ];

    for (const [action, permitidos] of casos) {
      for (const permitido of permitidos) {
        expect(refusalFor(action, barterIn(permitido))).toBeNull();
      }

      for (const outro of BARTER_STATUSES.filter((status) => !permitidos.includes(status))) {
        expect(refusalFor(action, barterIn(outro))).toBeTruthy();
      }
    }
  });

  /**
   * A APÓLICE passa nas duas mesas da seguradora, e SÓ na permuta com seguro.
   * Na sem seguro ela não é cedo nem tarde: ela não existe.
   */
  it('a apólice passa nas mesas da seguradora, e só na permuta com seguro', () => {
    const permitidos: string[] = [
      BARTER_STATUS.awaitingPolicy,
      BARTER_STATUS.awaitingPolicyWithConditions,
    ];
    for (const status of BARTER_STATUSES) {
      const recusa = refusalFor(BARTER_ACTION.insure, seguradaEm(status));
      if (permitidos.includes(status)) expect(recusa).toBeNull();
      else expect(recusa).toBeTruthy();

      expect(refusalFor(BARTER_ACTION.insure, barterIn(status))).toBe(
        'Esta permuta não tem seguro — ela não passa pela seguradora',
      );
    }
    // O produtor que RECUSOU o seguro opcional também não passa por ela.
    expect(
      refusalFor(BARTER_ACTION.insure, {
        ...barterIn(BARTER_STATUS.awaitingPolicy),
        insuranceChoice: 'declined',
      }),
    ).toBe('Esta permuta não tem seguro — ela não passa pela seguradora');
    // E o aceito no opcional passa.
    expect(
      refusalFor(BARTER_ACTION.insure, {
        ...barterIn(BARTER_STATUS.awaitingPolicy),
        insuranceChoice: 'accepted',
      }),
    ).toBeNull();
  });

  it('quem chega à seguradora fora de hora ouve onde a permuta está', () => {
    expect(refusalFor(BARTER_ACTION.insure, seguradaEm(BARTER_STATUS.pending))).toBe(
      'Esta permuta aguarda a decisão do comitê',
    );
    expect(refusalFor(BARTER_ACTION.insure, seguradaEm(BARTER_STATUS.approved))).toBe(
      'A apólice desta permuta já foi informada',
    );
    // O FATURISTA que chega cedo é mandado à seguradora, e não a um "não pode".
    expect(refusalFor(BARTER_ACTION.invoice, seguradaEm(BARTER_STATUS.awaitingPolicy))).toBe(
      'Esta permuta aguarda a apólice da seguradora',
    );
    expect(
      refusalFor(BARTER_ACTION.invoice, seguradaEm(BARTER_STATUS.awaitingPolicyWithConditions)),
    ).toBe('Esta permuta aguarda a apólice da seguradora');
    expect(refusalFor(BARTER_ACTION.insure, seguradaEm(BARTER_STATUS.denied))).toBe(
      'Esta permuta foi negada pelo comitê',
    );
  });

  /**
   * O COMITÊ escolhe o desfecho; o SEGURO escolhe a mesa. Com seguro, a
   * aprovação vai à seguradora; sem, direto ao faturista. A negativa é a mesma
   * nos dois casos.
   */
  it('a decisão cai na seguradora com seguro, e no faturista sem', () => {
    const comSeguro = seguradaEm(BARTER_STATUS.pending);
    const semSeguro = barterIn(BARTER_STATUS.pending);

    expect(reviewOutcomeFor('approved', comSeguro)).toBe(BARTER_STATUS.awaitingPolicy);
    expect(reviewOutcomeFor('approvedWithConditions', comSeguro)).toBe(
      BARTER_STATUS.awaitingPolicyWithConditions,
    );
    expect(reviewOutcomeFor('denied', comSeguro)).toBe(BARTER_STATUS.denied);

    expect(reviewOutcomeFor('approved', semSeguro)).toBe(BARTER_STATUS.approved);
    expect(reviewOutcomeFor('approvedWithConditions', semSeguro)).toBe(
      BARTER_STATUS.approvedWithConditions,
    );
    expect(reviewOutcomeFor('denied', semSeguro)).toBe(BARTER_STATUS.denied);
    // Recusado no opcional é "sem seguro".
    expect(reviewOutcomeFor('approved', { ...semSeguro, insuranceChoice: 'declined' })).toBe(
      BARTER_STATUS.approved,
    );

    // A apólice devolve cada aprovação ao SEU par: a ressalva continua ressalva.
    expect(policyOutcomeFor(BARTER_STATUS.awaitingPolicy)).toBe(BARTER_STATUS.approved);
    expect(policyOutcomeFor(BARTER_STATUS.awaitingPolicyWithConditions)).toBe(
      BARTER_STATUS.approvedWithConditions,
    );
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
    // O RASCUNHO não é etapa da retaguarda: quem topa com ele ouve que a permuta
    // ainda nem foi proposta, e não que "aguarda o gerente".
    expect(refusalFor(BARTER_ACTION.opinion, barterIn(BARTER_STATUS.draft))).toBe(
      'Esta permuta é um rascunho e ainda não foi encaminhada ao gerente',
    );
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
    expect(refusalFor(BARTER_ACTION.forward, barterIn(BARTER_STATUS.pending))).toBe(
      'Esta permuta já foi encaminhada ao gerente',
    );
    expect(refusalFor(BARTER_ACTION.opinion, barterIn(BARTER_STATUS.pending))).toBe(
      'Esta permuta já recebeu o parecer do gerente',
    );
    expect(refusalFor(BARTER_ACTION.review, barterIn(BARTER_STATUS.approved))).toBe(
      'Esta permuta já foi decidida pelo comitê',
    );
    expect(refusalFor(BARTER_ACTION.invoice, barterIn(BARTER_STATUS.invoiced))).toBe(
      'Esta permuta já foi faturada',
    );
    expect(refusalFor(BARTER_ACTION.cprIssue, barterIn(BARTER_STATUS.cprSigned))).toBe(
      'A cédula desta permuta já foi emitida',
    );
  });

  /**
   * O TRECHO DA CÉDULA tem ordem, e a ordem é do mundo: não se registra um
   * título que ninguém assinou, e não se assina um que não foi emitido.
   *
   * A mensagem de quem chega cedo diz em que pé a CÉDULA está — e não "a permuta
   * aguarda alguma coisa": quem pede o registro já sabe que ela foi faturada, e
   * o que ele precisa saber é que falta o produtor passar para assinar.
   */
  it('a cédula não se registra antes de ser assinada, nem se assina antes de sair', () => {
    expect(refusalFor(BARTER_ACTION.cprRegister, barterIn(BARTER_STATUS.invoiced))).toBe(
      'Esta permuta aguarda a emissão da cédula',
    );
    expect(refusalFor(BARTER_ACTION.cprRegister, barterIn(BARTER_STATUS.cprIssued))).toBe(
      'A cédula desta permuta aguarda a coleta de assinaturas',
    );
    expect(refusalFor(BARTER_ACTION.cprSign, barterIn(BARTER_STATUS.invoiced))).toBe(
      'Esta permuta aguarda a emissão da cédula',
    );
    // E o EMISSOR não alcança o que ainda não foi faturado: a frase o manda ao
    // posto anterior, com nome e tudo.
    expect(refusalFor(BARTER_ACTION.cprIssue, barterIn(BARTER_STATUS.approved))).toBe(
      'Esta permuta aguarda o faturamento',
    );
  });

  /**
   * O DESVIO DAS EXIGÊNCIAS: a permuta devolvida está no MESMO degrau da mesa do
   * comitê, só que com o consultor. Quem chega nesse degrau precisa ouvir com
   * quem ela está — e "já foi decidida" seria a frase errada para o comitê, que
   * ainda não decidiu nada.
   */
  it('a permuta devolvida com exigências diz que está com o consultor, e o quê falta', () => {
    const devolvida = {
      ...barterIn(BARTER_STATUS.awaitingRequirements),
      requiresGuarantor: true,
      requiresCollateral: true,
    };
    const espera =
      'Esta permuta aguarda o consultor providenciar o que o comitê exigiu: avalista, hipoteca';

    expect(refusalFor(BARTER_ACTION.review, devolvida)).toBe(espera);
    expect(refusalFor(BARTER_ACTION.require, devolvida)).toBe(espera);
    expect(refusalFor(BARTER_ACTION.invoice, devolvida)).toBe(espera);

    // Sem as exigências gravadas (permuta lida pela metade), a frase se sustenta.
    expect(refusalFor(BARTER_ACTION.review, barterIn(BARTER_STATUS.awaitingRequirements))).toBe(
      'Esta permuta aguarda o consultor cumprir as exigências do comitê',
    );

    // O GERENTE chega tarde, e a frase diz isso: o parecer dele continua valendo.
    expect(refusalFor(BARTER_ACTION.opinion, devolvida)).toBe(
      'Esta permuta já recebeu o parecer do gerente',
    );
  });

  it('o consultor que cumpre de novo ouve que a permuta já está com o comitê', () => {
    expect(refusalFor(BARTER_ACTION.fulfill, barterIn(BARTER_STATUS.pending))).toBe(
      'Esta permuta aguarda a decisão do comitê',
    );
    expect(refusalFor(BARTER_ACTION.fulfill, barterIn(BARTER_STATUS.approved))).toBe(
      'As exigências do comitê já foram cumpridas, e a permuta voltou ao comitê',
    );
    // E antes do comitê não há o que cumprir.
    expect(refusalFor(BARTER_ACTION.fulfill, barterIn(BARTER_STATUS.sentToManager))).toBe(
      'Esta permuta aguarda o parecer do gerente Beatriz Nogueira',
    );
  });

  /** A decisão continua sendo o próximo ato da mesa do comitê — exigir é a alternativa. */
  it('a mesa do comitê espera a decisão, e a permuta devolvida espera o consultor', () => {
    expect(nextActionOf(BARTER_STATUS.pending)).toBe(BARTER_ACTION.review);
    expect(nextActionOf(BARTER_STATUS.awaitingRequirements)).toBe(BARTER_ACTION.fulfill);
  });

  /**
   * NEGADA é fim de linha, e a mensagem não finge que ela está esperando algo.
   * Em especial: negada não fatura, que é a única forma de dinheiro sair daqui.
   */
  it('a permuta negada não recebe mais nenhum ato', () => {
    for (const action of [
      BARTER_ACTION.forward,
      BARTER_ACTION.opinion,
      BARTER_ACTION.review,
      BARTER_ACTION.require,
      BARTER_ACTION.fulfill,
      BARTER_ACTION.invoice,
      BARTER_ACTION.cprIssue,
      BARTER_ACTION.cprSign,
      BARTER_ACTION.cprRegister,
    ]) {
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

  /* ── O andamento: a linha inteira, e não só o trecho já andado ──────── */

  /**
   * O que estes testes protegem é a promessa que a tela faz. O andamento é a
   * checklist que o consultor lê para responder ao produtor "e a minha
   * permuta?" — uma etapa marcada errado ali não é um pixel fora do lugar: é
   * ele dizendo ao produtor que falta o comitê quando quem está devendo é o
   * gerente, ou que o faturamento vem aí quando a permuta foi negada.
   */
  describe('andamento da permuta', () => {
    /** Só os estados, na ordem da esteira — é a forma de ler os casos abaixo. */
    const estadosEm = (status: string) => progressOf(barterIn(status)).map((step) => step.state);

    const { done, current, ahead, halted } = BARTER_STEP_STATE;

    it('a esteira aparece inteira desde o primeiro dia da permuta', () => {
      const andamento = progressOf(barterIn(BARTER_STATUS.sentToManager));

      // As OITO etapas, sempre — inclusive as que ainda não aconteceram. É a
      // diferença entre uma checklist e uma linha do tempo, e é ela que faz a
      // emissão da cédula aparecer no dia do registro em vez de surgir do nada
      // depois do faturamento.
      expect(andamento.map((step) => step.action)).toEqual([
        BARTER_ACTION.register,
        BARTER_ACTION.forward,
        BARTER_ACTION.opinion,
        BARTER_ACTION.review,
        BARTER_ACTION.invoice,
        BARTER_ACTION.cprIssue,
        BARTER_ACTION.cprSign,
        BARTER_ACTION.cprRegister,
      ]);
      expect(andamento.map((step) => step.label)).toEqual([
        'Registro do consultor',
        'Parecer do consultor',
        'Parecer do gerente',
        'Decisão do comitê',
        'Faturamento',
        'Emissão da CPR',
        'Coleta de assinaturas',
        'Registro da CPR',
      ]);
      // Cada etapa diz de quem ela é — o que a tela mostra nas que ainda vêm,
      // onde não há autor para mostrar.
      expect(andamento.map((step) => step.role)).toEqual([
        ROLE.consultant,
        ROLE.consultant,
        ROLE.manager,
        ROLE.committee,
        ROLE.biller,
        ROLE.emitter,
        ROLE.emitter,
        ROLE.emitter,
      ]);
    });

    it('a permuta anda, e o que ficou para trás vira etapa cumprida', () => {
      // prettier-ignore
      expect(estadosEm(BARTER_STATUS.draft))
        .toEqual([done, current, ahead, ahead, ahead, ahead, ahead, ahead]);
      // prettier-ignore
      expect(estadosEm(BARTER_STATUS.sentToManager))
        .toEqual([done, done, current, ahead, ahead, ahead, ahead, ahead]);
      // prettier-ignore
      expect(estadosEm(BARTER_STATUS.pending))
        .toEqual([done, done, done, current, ahead, ahead, ahead, ahead]);
      // prettier-ignore
      expect(estadosEm(BARTER_STATUS.approved))
        .toEqual([done, done, done, done, current, ahead, ahead, ahead]);
      // A aprovada COM RESSALVA está no mesmo ponto da aprovada limpa: decidida,
      // esperando o faturamento. A exigência é do negócio, não da esteira.
      // prettier-ignore
      expect(estadosEm(BARTER_STATUS.approvedWithConditions))
        .toEqual([done, done, done, done, current, ahead, ahead, ahead]);
      // A FATURADA não é mais o fim: ela está na EMISSÃO, e as duas etapas
      // seguintes ainda vêm. Era aqui que a esteira antiga mentia — cinco
      // `done` sobre uma permuta que ainda devia o título.
      // prettier-ignore
      expect(estadosEm(BARTER_STATUS.invoiced))
        .toEqual([done, done, done, done, done, current, ahead, ahead]);
      // prettier-ignore
      expect(estadosEm(BARTER_STATUS.cprIssued))
        .toEqual([done, done, done, done, done, done, current, ahead]);
      // prettier-ignore
      expect(estadosEm(BARTER_STATUS.cprSigned))
        .toEqual([done, done, done, done, done, done, done, current]);
      // prettier-ignore
      expect(estadosEm(BARTER_STATUS.cprRegistered))
        .toEqual([done, done, done, done, done, done, done, done]);
    });

    /**
     * O DESVIO não é etapa de toda permuta, e a checklist não o promete: a
     * maioria nunca terá exigência nenhuma. Ele aparece só enquanto a permuta
     * está nele — logo antes da decisão, que é para onde ele a devolve.
     */
    it('as exigências do comitê só aparecem no andamento enquanto a permuta está nelas', () => {
      const devolvida = progressOf({
        ...barterIn(BARTER_STATUS.awaitingRequirements),
        requiresCollateral: true,
      });

      expect(devolvida.map((step) => step.action)).toEqual([
        BARTER_ACTION.register,
        BARTER_ACTION.forward,
        BARTER_ACTION.opinion,
        BARTER_ACTION.fulfill,
        BARTER_ACTION.review,
        BARTER_ACTION.invoice,
        BARTER_ACTION.cprIssue,
        BARTER_ACTION.cprSign,
        BARTER_ACTION.cprRegister,
      ]);
      // O parecer do gerente continua cumprido; a decisão continua por vir.
      expect(devolvida.map((step) => step.state)).toEqual([
        done,
        done,
        done,
        current,
        ahead,
        ahead,
        ahead,
        ahead,
        ahead,
      ]);
      const agora = devolvida[3];
      expect(agora.label).toBe('Exigências do comitê');
      expect(agora.role).toBe(ROLE.consultant);
      expect(agora.stateNote).toBe(
        'Esta permuta aguarda o consultor providenciar o que o comitê exigiu: hipoteca',
      );

      // CUMPRIDAS, a permuta está de novo na mesa do comitê — e a checklist volta
      // a ser a de sempre. Que houve uma volta, quem conta é a linha do tempo.
      // prettier-ignore
      expect(estadosEm(BARTER_STATUS.pending))
        .toEqual([done, done, done, current, ahead, ahead, ahead, ahead]);
      expect(progressOf(barterIn(BARTER_STATUS.pending)).map((s) => s.action)).not.toContain(
        BARTER_ACTION.fulfill,
      );
    });

    /**
     * A NEGATIVA é o caso que justifica `halted` existir. Uma permuta negada
     * nunca fatura — mostrar o faturamento dela como etapa pendente prometeria
     * um passo que ninguém vai dar, e quem lesse ficaria esperando.
     */
    /**
     * A PERMUTA COM SEGURO ganha uma etapa na checklist, entre a decisão e o
     * faturamento — e a sem seguro não a mostra nem como cumprida nem como a
     * vir: ela não existe ali.
     */
    it('a permuta com seguro mostra a apólice da seguradora, e a sem seguro não', () => {
      const segurada = progressOf(seguradaEm(BARTER_STATUS.sentToManager));
      expect(segurada.map((step) => step.action)).toEqual([
        BARTER_ACTION.register,
        BARTER_ACTION.forward,
        BARTER_ACTION.opinion,
        BARTER_ACTION.review,
        BARTER_ACTION.insure,
        BARTER_ACTION.invoice,
        BARTER_ACTION.cprIssue,
        BARTER_ACTION.cprSign,
        BARTER_ACTION.cprRegister,
      ]);
      expect(segurada[4].label).toBe('Apólice do seguro');
      expect(segurada[4].role).toBe(ROLE.insurer);

      const estados = (status: string) => progressOf(seguradaEm(status)).map((step) => step.state);
      // prettier-ignore
      expect(estados(BARTER_STATUS.pending))
        .toEqual([done, done, done, current, ahead, ahead, ahead, ahead, ahead]);
      // prettier-ignore
      expect(estados(BARTER_STATUS.awaitingPolicy))
        .toEqual([done, done, done, done, current, ahead, ahead, ahead, ahead]);
      // prettier-ignore
      expect(estados(BARTER_STATUS.awaitingPolicyWithConditions))
        .toEqual([done, done, done, done, current, ahead, ahead, ahead, ahead]);
      // prettier-ignore
      expect(estados(BARTER_STATUS.approved))
        .toEqual([done, done, done, done, done, current, ahead, ahead, ahead]);
      // prettier-ignore
      expect(estados(BARTER_STATUS.denied))
        .toEqual([done, done, done, done, halted, halted, halted, halted, halted]);

      expect(progressOf(seguradaEm(BARTER_STATUS.awaitingPolicy))[4].stateNote).toBe(
        'Esta permuta aguarda a apólice da seguradora',
      );

      expect(progressOf(barterIn(BARTER_STATUS.approved)).map((step) => step.action)).not.toContain(
        BARTER_ACTION.insure,
      );
    });

    it('a permuta negada não fica devendo um faturamento que não vem', () => {
      // prettier-ignore
      expect(estadosEm(BARTER_STATUS.denied))
        .toEqual([done, done, done, done, halted, halted, halted, halted]);

      // A etapa que não acontece DIZ que não acontece, e por quê. Deixá-la muda
      // seria a mesma coisa que mostrá-la pendente: quem lê fica esperando. E
      // são QUATRO agora, porque a cédula de uma permuta negada também não sai.
      expect(progressOf(barterIn(BARTER_STATUS.denied)).map((s) => s.stateNote)).toEqual([
        null,
        null,
        null,
        null,
        'Não acontece: a permuta foi negada',
        'Não acontece: a permuta foi negada',
        'Não acontece: a permuta foi negada',
        'Não acontece: a permuta foi negada',
      ]);
    });

    it('a etapa de agora diz o que espera, com nome e tudo — e só ela', () => {
      const notas = (status: string) => progressOf(barterIn(status)).map((step) => step.stateNote);

      const so = (indice: number, frase: string) =>
        Array.from({ length: 8 }, (_, i) => (i === indice ? frase : null));

      expect(notas(BARTER_STATUS.draft)).toEqual(
        so(1, 'Esta permuta é um rascunho e ainda não foi encaminhada ao gerente'),
      );
      expect(notas(BARTER_STATUS.sentToManager)).toEqual(
        so(2, 'Esta permuta aguarda o parecer do gerente Beatriz Nogueira'),
      );
      expect(notas(BARTER_STATUS.pending)).toEqual(
        so(3, 'Esta permuta aguarda a decisão do comitê'),
      );
      // A FATURADA espera a cédula, e o dizer é a razão de ser deste trecho: a
      // permuta que antes aparecia como concluída agora diz o que falta nela.
      expect(notas(BARTER_STATUS.invoiced)).toEqual(
        so(5, 'Esta permuta aguarda a emissão da cédula'),
      );
      expect(notas(BARTER_STATUS.cprIssued)).toEqual(
        so(6, 'A cédula desta permuta aguarda a coleta de assinaturas'),
      );
      expect(notas(BARTER_STATUS.cprSigned)).toEqual(
        so(7, 'A cédula desta permuta aguarda o registro'),
      );
    });

    /**
     * O rótulo da SAÍDA sai do estado que o ato alcançou, e não de onde a
     * permuta está hoje: a decisão de uma permuta já faturada continua tendo
     * sido uma aprovação, e é isso que a linha do tempo mostra.
     */
    it('a decisão do comitê diz para que lado foi', () => {
      expect(outcomeLabelOf(BARTER_ACTION.review, BARTER_STATUS.approved)).toBe('Aprovada');
      expect(outcomeLabelOf(BARTER_ACTION.review, BARTER_STATUS.approvedWithConditions)).toBe(
        'Aprovada com ressalva',
      );
      expect(outcomeLabelOf(BARTER_ACTION.review, BARTER_STATUS.denied)).toBe('Negada');
      // A aprovação que foi para a seguradora continua tendo sido uma aprovação.
      expect(outcomeLabelOf(BARTER_ACTION.review, BARTER_STATUS.awaitingPolicy)).toBe('Aprovada');
      expect(outcomeLabelOf(BARTER_ACTION.review, BARTER_STATUS.awaitingPolicyWithConditions)).toBe(
        'Aprovada com ressalva',
      );

      // As outras etapas não têm saída para escolher — "Faturamento: faturada"
      // seria o nome da etapa dito duas vezes.
      for (const action of [
        BARTER_ACTION.register,
        BARTER_ACTION.forward,
        BARTER_ACTION.opinion,
        BARTER_ACTION.require,
        BARTER_ACTION.fulfill,
        BARTER_ACTION.insure,
        BARTER_ACTION.invoice,
        BARTER_ACTION.cprIssue,
        BARTER_ACTION.cprSign,
        BARTER_ACTION.cprRegister,
      ]) {
        for (const status of BARTER_STATUSES) {
          expect(outcomeLabelOf(action, status)).toBeNull();
        }
      }
    });

    /**
     * Estado que nenhuma etapa produz — banco adulterado, ou um servidor à
     * frente deste. Devolve nada, e a tela cai na linha do tempo dos eventos,
     * que é fato gravado: não desenhar caminho nenhum vale mais do que desenhar
     * um caminho inventado.
     */
    it('estado desconhecido não produz um andamento inventado', () => {
      expect(progressOf(barterIn('cancelada'))).toEqual([]);
    });
  });
});
