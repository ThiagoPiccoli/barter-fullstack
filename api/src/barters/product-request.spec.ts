import { CAPABILITY, rolesWith } from '../common/policy';
import { ROLE } from '../common/roles';
import { BARTER_STATUS, BARTER_STATUSES } from './barter-workflow';
import {
  PRODUCT_REQUEST_ACTION,
  PRODUCT_REQUEST_LABELS,
  PRODUCT_REQUEST_STATUS,
  PRODUCT_REQUEST_WINDOW,
  offBarterCost,
  productDecisionRefusal,
  productRequestRefusal,
} from './product-request';

/**
 * O PEDIDO DE FORA DO BARTER, escrito por extenso.
 *
 * A tabela do Barter é uma lista fechada e a lavoura não é. Este é o caminho de
 * pôr numa permuta o que a tabela não tem — e o que estes testes protegem é a
 * JANELA dele: até quando um item pode entrar, e o que acontece quando ele
 * entra. Alargá-la sem perceber (uma permuta aprovada que recebe um insumo a
 * mais) é mudar o que o comitê aprovou sem passar por quem aprovou.
 */
describe('Pedido de produto de fora do Barter', () => {
  const barterIn = (status: string) => ({ status });

  /* ── Quem pede e quem decide ────────────────────────────────────────── */

  /**
   * Os dois lados têm capacidades DIFERENTES, e nenhum papel tem as duas: pedir
   * é do consultor, atender é do admin. Juntas na mesma pessoa, quem monta a
   * permuta passaria a escrever o preço dela.
   */
  it('o consultor pede e o admin atende, e ninguém faz as duas coisas', () => {
    expect(rolesWith(CAPABILITY.bartersProductRequest)).toEqual([ROLE.consultant]);
    expect(rolesWith(CAPABILITY.bartersProductReview)).toEqual([ROLE.admin]);
  });

  /**
   * Quem atende é quem PUBLICA A TABELA. Não é coincidência: atender é acertar
   * um valor, e valor é do mesmo dono — só que para uma permuta em vez de para
   * a praça inteira.
   */
  it('quem atende o pedido é quem responde pelos valores', () => {
    expect(rolesWith(CAPABILITY.barterManage)).toEqual(rolesWith(CAPABILITY.bartersProductReview));
    // E continua sem decidir permuta: incluir um item não é aprovar o negócio.
    expect(rolesWith(CAPABILITY.bartersProductReview)).not.toContain(ROLE.committee);
    expect(rolesWith(CAPABILITY.bartersReview)).not.toContain(ROLE.admin);
  });

  /* ── Até quando se pode pedir ───────────────────────────────────────── */

  /**
   * O RASCUNHO está dentro, e é o momento mais natural do pedido: o consultor
   * está montando a permuta e topa com o que falta. É aqui que ele difere do
   * pedido de alteração, que começa onde este termina.
   */
  it('pede-se do rascunho até a mesa do comitê', () => {
    for (const status of [
      BARTER_STATUS.draft,
      BARTER_STATUS.sentToManager,
      BARTER_STATUS.pending,
    ]) {
      expect(productRequestRefusal(barterIn(status))).toBeNull();
    }
    expect([...PRODUCT_REQUEST_WINDOW]).toEqual([
      BARTER_STATUS.draft,
      BARTER_STATUS.sentToManager,
      BARTER_STATUS.pending,
    ]);
  });

  /**
   * Depois da DECISÃO, não: um insumo a mais muda o custo, o custo muda as
   * sacas, e a permuta deixaria de ser a que o comitê aprovou. A recusa manda
   * a pessoa para o outro caminho em vez de a deixar procurando um botão.
   */
  it('a permuta decidida não recebe mais item, e a recusa aponta a saída', () => {
    for (const status of [
      BARTER_STATUS.approved,
      BARTER_STATUS.approvedWithConditions,
      BARTER_STATUS.invoiced,
    ]) {
      expect(productRequestRefusal(barterIn(status))).toContain('Peça a alteração da permuta');
    }
  });

  /** A negada é fim de linha, e a frase é a do fluxo — não a do pedido. */
  it('a negada diz que foi negada', () => {
    expect(productRequestRefusal(barterIn(BARTER_STATUS.denied))).toContain('negada');
  });

  /** Todo estado do sistema tem resposta: nenhum cai num "não foi possível". */
  it('cada estado da permuta sabe responder ao pedido', () => {
    for (const status of BARTER_STATUSES) {
      const refusal = productRequestRefusal(barterIn(status));
      expect(refusal === null || refusal.length > 0).toBe(true);
    }
  });

  /* ── A decisão do admin ─────────────────────────────────────────────── */

  const requestIn = (status: string) => ({ status, productName: 'Adjuvante Prime' });

  it('só há o que decidir enquanto o pedido está aberto', () => {
    expect(productDecisionRefusal(requestIn(PRODUCT_REQUEST_STATUS.open))).toBeNull();
  });

  /**
   * As duas recusas são DIFERENTES de propósito: quem chega tarde precisa saber
   * se o item entrou ou não na permuta — é o segundo admin na mesma tela, e as
   * duas respostas mandam fazer coisas opostas em seguida.
   */
  it('quem chega tarde ouve o que aconteceu com o pedido', () => {
    expect(productDecisionRefusal(requestIn(PRODUCT_REQUEST_STATUS.added))).toContain(
      'já foi incluído',
    );
    expect(productDecisionRefusal(requestIn(PRODUCT_REQUEST_STATUS.denied))).toContain(
      'já foi recusado',
    );
  });

  /* ── O que o item de fora acrescenta ────────────────────────────────── */

  /**
   * Ele soma CUSTO — foi retirado, e as sacas o pagam. É a única conta em que
   * ele entra: as réguas das pastas e do mínimo por hectare não o enxergam,
   * porque ele não tem classe e engordaria o denominador de todas elas.
   */
  it('o item de fora do Barter soma custo à permuta', () => {
    const granted = [
      { id: 1, productName: 'Adjuvante', unit: 'l', quantity: 200, sku: null, unitValue: 12.5 },
      { id: 2, productName: 'Frete', unit: 'un', quantity: 1, sku: null, unitValue: 800 },
    ];
    expect(offBarterCost(granted)).toBeCloseTo(3300, 2);
  });

  /**
   * Pedido sem valor não custa nada: ele ainda não foi atendido, e um número
   * inventado aqui viraria sacas que ninguém combinou.
   */
  it('pedido sem valor acertado não entra na conta', () => {
    expect(
      offBarterCost([
        { id: 1, productName: 'Adjuvante', unit: 'l', quantity: 200, sku: null, unitValue: null },
      ]),
    ).toBe(0);
    expect(offBarterCost([])).toBe(0);
  });

  /* ── O registro do pedido ───────────────────────────────────────────── */

  /** Três fatos, três autores possíveis, três linhas na história da permuta. */
  it('cada ato do pedido tem nome e rótulo', () => {
    expect(Object.keys(PRODUCT_REQUEST_LABELS).sort()).toEqual(
      Object.values(PRODUCT_REQUEST_ACTION).sort(),
    );
  });

  /**
   * O ATENDIDO sobrevive à decisão, ao contrário do que acontece no pedido de
   * alteração: ele é a ORIGEM de um item da permuta, e é dele que a remontagem
   * do rascunho tira o item de volta. Apagá-lo faria o insumo sumir no primeiro
   * `PUT /inputs`.
   */
  it('o pedido atendido continua existindo depois de decidido', () => {
    expect(Object.values(PRODUCT_REQUEST_STATUS)).toContain('added');
  });
});
