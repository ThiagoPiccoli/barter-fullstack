import { CAPABILITY, rolesWith } from '../common/policy';
import { ROLE } from '../common/roles';
import { BARTER_STATUS, BARTER_STATUSES, progressOf } from './barter-workflow';
import {
  CHANGE_REQUEST_ACTION,
  CHANGE_REQUEST_LABELS,
  CHANGE_REQUEST_STATUS,
  CLEARED_BY_CHANGE,
  RESOLVED_REQUEST,
  changeDecisionRefusal,
  changeRequestRefusal,
  cultureRefusal,
  itemPriceRefusal,
  priceChangeRefusal,
  requestedFrom,
} from './change-request';

/**
 * O DESVIO da esteira, escrito por extenso.
 *
 * A esteira só anda para a frente, e este é o único caminho de volta que existe
 * no sistema. O que estes testes protegem é POR ONDE ele passa: quem pode
 * pedir, até quando, e o que o aceite desfaz. Alargá-lo sem perceber (uma
 * permuta faturada que aceita pedido, um segundo pedido por cima de um em
 * aberto) é a diferença entre corrigir uma permuta e apagar o trabalho de três
 * postos sem ninguém decidir isso.
 */
describe('Pedido de alteração da permuta', () => {
  const barterIn = (status: string, changeRequestStatus: string | null = null) => ({
    status,
    changeRequestStatus,
  });

  /* ── Quem pede e quem decide ────────────────────────────────────────── */

  /**
   * Os dois lados do desvio têm capacidades DIFERENTES, e nenhum papel tem as
   * duas: pedir é do consultor, decidir é do admin. Se um dia coincidirem, o
   * pedido nasce concedido — e o portão vira enfeite.
   */
  it('o consultor pede e o admin decide, e ninguém faz as duas coisas', () => {
    expect(rolesWith(CAPABILITY.bartersChangeRequest)).toEqual([ROLE.consultant]);
    expect(rolesWith(CAPABILITY.bartersChangeReview)).toEqual([ROLE.admin]);
  });

  /**
   * O admin decide o PROCESSO e continua sem decidir o NEGÓCIO. As duas coisas
   * juntas na mesma pessoa fariam do "libere e refaça" um caminho para aprovar
   * o que o comitê negou.
   */
  it('quem decide o pedido não decide a permuta', () => {
    expect(rolesWith(CAPABILITY.bartersReview)).not.toContain(ROLE.admin);
    expect(rolesWith(CAPABILITY.bartersChangeReview)).not.toContain(ROLE.committee);
  });

  /* ── Até quando se pode pedir ───────────────────────────────────────── */

  it('pede-se em qualquer permuta que já saiu da mão do consultor', () => {
    for (const status of [
      BARTER_STATUS.sentToManager,
      BARTER_STATUS.pending,
      BARTER_STATUS.approved,
      BARTER_STATUS.approvedWithConditions,
      // A NEGADA também: o pedido é o caminho de refazer a permuta que o comitê
      // recusou, e é ele que substitui o "registra outra igual e esquece esta".
      BARTER_STATUS.denied,
    ]) {
      expect(changeRequestRefusal(barterIn(status))).toBeNull();
    }
  });

  /** O rascunho já é dele: pedir permissão para mexer no próprio é burocracia. */
  it('o rascunho não pede nada — ele se altera direto', () => {
    expect(changeRequestRefusal(barterIn(BARTER_STATUS.draft))).toContain('rascunho seu');
  });

  /** O que saiu para fora não volta: a nota se corrige onde ela foi emitida. */
  it('a faturada não aceita pedido', () => {
    expect(changeRequestRefusal(barterIn(BARTER_STATUS.invoiced))).toContain('faturada');
    // E DO FATURAMENTO EM DIANTE, não só nele. A conferência é pelo DEGRAU da
    // esteira porque a comparação por estado envelheceu mal: quando a emissão
    // da cédula virou etapa, três estados passaram a existir depois de
    // `invoiced` — e todos escapavam por aqui. Uma permuta com o TÍTULO JÁ
    // EMITIDO aceitava pedido de alteração, e o admin podia devolvê-la a
    // rascunho com o papel na mão do produtor.
    for (const depois of [
      BARTER_STATUS.cprIssued,
      BARTER_STATUS.cprSigned,
      BARTER_STATUS.cprRegistered,
    ]) {
      expect(changeRequestRefusal(barterIn(depois))).toContain('faturada');
    }
    // A NEGADA continua passando, e é de propósito: refazer a permuta negada é
    // justamente para o que este caminho serve. Ela está FORA da esteira.
    expect(changeRequestRefusal(barterIn(BARTER_STATUS.denied))).toBeNull();
  });

  /**
   * Um pedido por vez. Dois em aberto sobre a mesma permuta dariam ao admin
   * duas versões do que precisa mudar, e a decisão sobre uma apagaria a outra
   * em silêncio.
   */
  it('não se pede duas vezes antes de o admin responder', () => {
    const refusal = changeRequestRefusal(
      barterIn(BARTER_STATUS.approved, CHANGE_REQUEST_STATUS.open),
    );
    expect(refusal).toContain('Já existe um pedido');
  });

  /** Recusado, pede-se de novo: o motivo da recusa pode ter sido resolvido. */
  it('depois de recusado, pede-se outra vez', () => {
    expect(
      changeRequestRefusal(barterIn(BARTER_STATUS.approved, CHANGE_REQUEST_STATUS.denied)),
    ).toBeNull();
  });

  /* ── A decisão ──────────────────────────────────────────────────────── */

  it('só há o que decidir quando há pedido em aberto', () => {
    expect(
      changeDecisionRefusal(barterIn(BARTER_STATUS.approved, CHANGE_REQUEST_STATUS.open)),
    ).toBeNull();
    expect(changeDecisionRefusal(barterIn(BARTER_STATUS.approved))).toContain('não tem pedido');
    // Quem chega tarde ouve que o pedido JÁ FOI decidido, e não que ele nunca
    // existiu: é o segundo admin na mesma permuta, e a diferença entre as duas
    // frases é ele procurar (ou não) um defeito que não há.
    expect(
      changeDecisionRefusal(barterIn(BARTER_STATUS.approved, CHANGE_REQUEST_STATUS.denied)),
    ).toContain('já foi decidido');
  });

  /* ── A terceira saída: o admin atende mexendo no valor ──────────────── */

  /**
   * Alterar valor é ATENDER um pedido, e não um poder solto do admin. Sem
   * pedido em aberto ele estaria reprecificando permuta por conta própria — que
   * é decidir o negócio, o que ele não faz.
   */
  it('o valor só se altera dentro de um pedido em aberto', () => {
    expect(
      priceChangeRefusal(barterIn(BARTER_STATUS.pending, CHANGE_REQUEST_STATUS.open)),
    ).toBeNull();

    const semPedido = priceChangeRefusal(barterIn(BARTER_STATUS.pending));
    expect(semPedido).toContain('ATENDENDO a um pedido');
  });

  /** Pedido já decidido: a frase é a mesma da decisão, e pelo mesmo motivo. */
  it('pedido já decidido não se atende de novo', () => {
    expect(
      priceChangeRefusal(barterIn(BARTER_STATUS.approved, CHANGE_REQUEST_STATUS.denied)),
    ).toContain('já foi decidido');
  });

  /**
   * O GRÃO não se digita: as sacas são o RESULTADO do custo dos insumos e da
   * cotação da versão. Escrever nelas seria abrir um Barter particular para um
   * produtor, e ainda por cima por um caminho que existe para corrigir insumo.
   */
  it('o valor do grão não é campo de formulário', () => {
    expect(itemPriceRefusal({ kind: 'input', productName: 'Ureia 45%' })).toBeNull();
    expect(itemPriceRefusal({ kind: 'grain', productName: 'Soja' })).toContain('pagamento');
  });

  /**
   * As duas saídas que ATENDEM zeram o pedido; a que recusa não. O "atendido"
   * pendurado seria um segundo lugar contando a mesma história que o efeito já
   * conta — e a recusa, sem o campo, viraria uma permuta parada sem nada
   * dizendo que alguém já pediu e ouviu não.
   */
  it('o pedido atendido some, e o recusado fica', () => {
    expect(RESOLVED_REQUEST).toEqual({
      changeRequestStatus: null,
      changeRequestNote: null,
      changeRequestBy: null,
      changeRequestById: null,
      changeRequestAt: null,
      changeRequestFrom: null,
      changeRequestReply: null,
    });
  });

  /* ── O que o aceite desfaz ──────────────────────────────────────────── */

  /**
   * A permuta liberada volta a ser um rascunho DE VERDADE: sem parecer do
   * gerente e sem decisão do comitê pendurados nela. Os dois falavam de insumos
   * que estão prestes a mudar — e a linha do tempo continua guardando que eles
   * existiram.
   */
  it('o aceite apaga o parecer do gerente e a decisão do comitê', () => {
    expect(CLEARED_BY_CHANGE).toEqual({
      consultantSentAt: null,
      managerId: null,
      managerName: null,
      managerNote: null,
      managerReviewedAt: null,
      reviewNote: null,
      reviewedBy: null,
      reviewedById: null,
      reviewedAt: null,
      // AS EXIGÊNCIAS caem junto com a decisão que as criou: elas foram
      // exigidas de uma permuta que está prestes a mudar, e mantidas fariam a
      // tela do consultor mostrar "exige avalista" num rascunho que ninguém
      // decidiu.
      requiresGuarantor: false,
      requiresCollateral: false,
      requiresInsurance: false,
    });
  });

  /**
   * O que ele NÃO apaga: o parecer do consultor. É o texto dele sobre o próprio
   * cliente, ele vai reencaminhar a permuta, e o que continua valendo não se
   * pede para reescrever.
   */
  it('o aceite preserva o parecer de quem pediu', () => {
    expect(Object.keys(CLEARED_BY_CHANGE)).not.toContain('consultantNote');
  });

  /**
   * O rascunho de volta é um rascunho como outro qualquer: a checklist recomeça
   * do registro, e as três etapas seguintes voltam a estar por vir. É o que
   * garante que a permuta refeita passe pelo gerente e pelo comitê de novo, em
   * vez de reaparecer aprovada do outro lado.
   */
  it('a permuta liberada recomeça a esteira', () => {
    const steps = progressOf({ status: BARTER_STATUS.draft });
    // Só o REGISTRO segue cumprido — a permuta continua existindo, e é a única
    // etapa que o desvio não desfaz.
    expect(steps.filter((step) => step.state === 'done').map((step) => step.action)).toEqual([
      'register',
    ]);
    expect(steps.find((step) => step.state === 'current')?.action).toBe('forward');
  });

  /* ── Até onde a alteração alcança: versões sim, culturas não ────────── */

  const cultureOf = (grainId: number | null, grainName: string) => ({ grainId, grainName });
  const versionOf = (code: string, grains: { grainId: number | null; grainName: string }[]) => ({
    code,
    grains,
  });

  /**
   * A permuta fechada na PRIMEIRA versão da soja continua alterável com a
   * terceira no ar: ela não foi faturada, e o que falta nela é uma correção de
   * insumos. Amarrá-la à versão vigente faria de cada publicação de tabela um
   * prazo de validade para as permutas em aberto.
   */
  it('a alteração atravessa versões enquanto a cultura estiver aberta', () => {
    expect(
      cultureRefusal(cultureOf(1, 'Soja'), versionOf('B2026.03', [cultureOf(1, 'Soja')])),
    ).toBeNull();
  });

  /**
   * E a cultura da permuta pode ser QUALQUER UMA das que o lançamento aceita —
   * que é o ponto das culturas que coexistem: a permuta de milho e a de soja
   * são alteráveis no mesmo Barter, sem que uma tenha de esperar a outra fechar.
   */
  it('qualquer cultura do lançamento aberto vale', () => {
    const aberto = versionOf('B2026.02', [cultureOf(1, 'Soja'), cultureOf(2, 'Milho')]);
    expect(cultureRefusal(cultureOf(1, 'Soja'), aberto)).toBeNull();
    expect(cultureRefusal(cultureOf(2, 'Milho'), aberto)).toBeNull();
  });

  /**
   * O que ela não atravessa é a cultura que SAIU do lançamento: sem cotação e
   * sem produtividade, a permuta seria remontada com a régua de outro grão.
   */
  it('a cultura que saiu do lançamento recusa, e a recusa diz o que está aberto', () => {
    const refusal = cultureRefusal(
      cultureOf(2, 'Milho'),
      versionOf('B2026.03', [cultureOf(1, 'Soja')]),
    );
    expect(refusal).toContain('Milho');
    expect(refusal).toContain('Soja');
    expect(refusal).toContain('B2026.03');
  });

  /**
   * Grão EXCLUÍDO do catálogo: o FK virou null e sobrou o nome congelado.
   * Comparar por nome aí é a única comparação possível, e é melhor do que
   * recusar toda permuta paga naquele grão.
   */
  it('sem id do grão, a cultura é comparada pelo nome congelado', () => {
    expect(
      cultureRefusal(cultureOf(null, 'Soja'), versionOf('B2026.03', [cultureOf(null, ' soja ')])),
    ).toBeNull();
    expect(
      cultureRefusal(cultureOf(null, 'Soja'), versionOf('B2026.03', [cultureOf(null, 'Milho')])),
    ).not.toBeNull();
  });

  /* ── O registro do desvio ───────────────────────────────────────────── */

  /** Três fatos, três autores possíveis, três linhas na história da permuta. */
  it('cada ato do desvio tem nome e rótulo', () => {
    expect(Object.keys(CHANGE_REQUEST_LABELS).sort()).toEqual(
      Object.values(CHANGE_REQUEST_ACTION).sort(),
    );
  });

  /**
   * `changeRequestFrom` guarda um estado da esteira — é ele que deixa a linha
   * do tempo dizer "pediu com a permuta já aprovada", que é o que muda o peso
   * da decisão do admin.
   */
  it('o pedido guarda de onde foi feito', () => {
    expect(requestedFrom({ changeRequestFrom: BARTER_STATUS.approved })).toBe(
      BARTER_STATUS.approved,
    );
    expect(requestedFrom({})).toBeNull();
    expect(BARTER_STATUSES).toContain(requestedFrom({ changeRequestFrom: 'pending' })!);
  });
});
