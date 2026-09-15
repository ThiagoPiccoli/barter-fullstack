import { BARTER_STATUS, BARTER_STATUS_LABELS, type BarterStatus } from './barter-workflow';

/**
 * O PEDIDO DE FORA DO BARTER — o consultor pede um produto que a tabela da
 * versão não tem, e o admin o adiciona àquela permuta com o valor que acertou.
 *
 * A tabela do Barter é uma lista fechada, publicada de uma vez para a praça
 * inteira (ver `VersionPrice`). A lavoura não é: o produtor quer o adjuvante da
 * marca que ele usa há dez anos, um serviço de pulverização que ninguém lançou,
 * uma semente que o fornecedor só cota sob encomenda. Enquanto não havia este
 * caminho, as saídas eram duas e as duas ruins:
 *
 * - **deixar o item fora da permuta** — e o produtor compra à vista em outro
 *   lugar, que é exatamente a venda que o Barter existe para trazer;
 * - **lançar o produto na versão vigente** — e uma negociação pontual vira preço
 *   de praça, publicado para todo consultor de toda unidade, por causa de um
 *   cliente.
 *
 * ## A quem o item fica amarrado
 *
 * À PERMUTA que originou o pedido, e a nada mais. O valor foi cotado para
 * aquela quantidade, naquela data, naquele negócio — e é isso que ele afirma.
 * Outra permuta do mesmo produtor pede de novo, e é assim que se percebe que o
 * item deixou de ser exceção: quando o mesmo pedido chega pela quinta vez, ele
 * não é mais um pedido, é uma linha que falta na próxima versão do Barter.
 *
 * O item também NÃO entra no catálogo. O catálogo é a lista do fornecedor,
 * carregada da planilha dele; um produto criado a partir de um pedido apareceria
 * no relatório de preços e na carga seguinte como se fosse da praça.
 *
 * ## Quem pede e quem decide
 *
 * Pede o CONSULTOR QUE REGISTROU, como no pedido de alteração, e pelo mesmo
 * motivo: quem falou com o produtor é quem sabe o que ele quer.
 *
 * Decide o ADMIN, e o que ele decide aqui é um VALOR — não o processo. É outra
 * pergunta que a do `change-request.ts` ("o trabalho já feito vai ser jogado
 * fora?"): aqui nada é desfeito, e o que se responde é "por quanto a empresa
 * entrega este item". Daí a capacidade ser própria (`bartersProductReview`).
 *
 * ## Até quando
 *
 * Até a DECISÃO DO COMITÊ, e nem um passo além. Um insumo a mais muda o custo, e
 * o custo muda as sacas: enfiá-lo numa permuta já aprovada seria alterar o que
 * foi aprovado sem passar por quem aprovou. Depois da decisão o caminho é o
 * outro — o pedido de alteração, que devolve a permuta ao consultor e a faz
 * percorrer a linha de novo.
 *
 * O RASCUNHO, ao contrário do pedido de alteração, está DENTRO da janela: é o
 * momento mais natural do pedido (o consultor está montando a permuta e topa
 * com o que falta), e o item que ele quer continua não existindo em lista
 * nenhuma para ele mesmo acrescentar.
 */
export const PRODUCT_REQUEST_STATUS = {
  /** Pedido feito, na mesa do admin. */
  open: 'open',
  /**
   * ATENDIDO: o admin acertou o valor e o item entrou na permuta.
   *
   * Ele sobrevive à decisão — e aqui a regra é o oposto da do pedido de
   * alteração, onde o aceite some porque o efeito conta a história sozinho.
   * Este pedido é a ORIGEM de um item: é ele que explica um insumo que não está
   * na tabela do Barter, e é dele que a remontagem do rascunho tira o item de
   * volta (ver `replaceInputs`). Apagá-lo faria o item sumir da permuta na
   * primeira vez que o consultor mexesse nos insumos.
   */
  added: 'added',
  /** Recusado pelo admin, com o motivo escrito. */
  denied: 'denied',
} as const;

export type ProductRequestStatus =
  (typeof PRODUCT_REQUEST_STATUS)[keyof typeof PRODUCT_REQUEST_STATUS];

/**
 * Os atos do pedido, como eles são gravados na linha do tempo da permuta
 * (`BarterEvent.action`).
 *
 * São três pelo mesmo motivo dos do desvio: "pedi", "atenderam" e "recusaram"
 * são três fatos com autores diferentes. Nenhum deles muda o estado da permuta
 * — o pedido de produto não a tira da fila em que está.
 */
export const PRODUCT_REQUEST_ACTION = {
  productRequested: 'productRequested',
  productAdded: 'productAdded',
  productDenied: 'productDenied',
} as const;

export type ProductRequestAction =
  (typeof PRODUCT_REQUEST_ACTION)[keyof typeof PRODUCT_REQUEST_ACTION];

/** O rótulo de cada ato, na língua da operação. */
export const PRODUCT_REQUEST_LABELS: Record<ProductRequestAction, string> = {
  [PRODUCT_REQUEST_ACTION.productRequested]: 'Produto solicitado',
  [PRODUCT_REQUEST_ACTION.productAdded]: 'Produto incluído',
  [PRODUCT_REQUEST_ACTION.productDenied]: 'Produto recusado',
};

/**
 * ATÉ ONDE o pedido de produto alcança: os estados em que a permuta ainda pode
 * receber um item.
 *
 * Vem da esteira, e não de uma lista escrita à mão, pela razão de sempre: uma
 * etapa nova antes do comitê entra sozinha; uma depois dele fica de fora
 * sozinha. São os três estados anteriores à decisão — e o rascunho é o primeiro
 * deles, não uma exceção.
 */
export const PRODUCT_REQUEST_WINDOW: readonly BarterStatus[] = [
  BARTER_STATUS.draft,
  BARTER_STATUS.sentToManager,
  BARTER_STATUS.pending,
];

/** O bastante de uma permuta para saber se ela aceita um pedido de produto. */
export interface BarterAtProductRequest {
  status: string;
}

/**
 * POR QUE esta permuta não aceita um pedido de produto agora — ou `null`,
 * quando aceita.
 *
 * Devolve a frase pronta, como `refusalFor` na esteira e `changeRequestRefusal`
 * no desvio: quem bate na porta fechada precisa saber o que fazer em seguida, e
 * essa resposta é do domínio, não da tela.
 */
export function productRequestRefusal(barter: BarterAtProductRequest): string | null {
  if ((PRODUCT_REQUEST_WINDOW as readonly string[]).includes(barter.status)) return null;

  if (barter.status === BARTER_STATUS.denied) {
    return 'Esta permuta foi negada pelo comitê';
  }
  // Decidida (aprovada, com ou sem ressalva) ou já faturada: um insumo a mais
  // muda o custo, e o custo muda as sacas. A frase manda a pessoa para o outro
  // caminho em vez de a deixar procurando um botão que não existe.
  return (
    `Esta permuta já foi decidida pelo comitê (${
      BARTER_STATUS_LABELS[barter.status as BarterStatus] ?? barter.status
    }), e um insumo a mais mudaria o que foi aprovado. ` +
    'Peça a alteração da permuta para refazê-la'
  );
}

/** O bastante de um pedido para saber se ele ainda espera decisão. */
export interface ProductRequestAtDecision {
  status: string;
  productName: string;
}

/**
 * POR QUE não há o que decidir neste pedido — ou `null`, quando há.
 *
 * Como em `changeDecisionRefusal`, a resposta distingue "já foi atendido" de
 * "já foi recusado": quem chega pelo segundo caminho é o admin que abriu a
 * mesma tela em dois aparelhos, e uma frase genérica o mandaria procurar um
 * defeito que não existe.
 */
export function productDecisionRefusal(request: ProductRequestAtDecision): string | null {
  if (request.status === PRODUCT_REQUEST_STATUS.open) return null;
  return request.status === PRODUCT_REQUEST_STATUS.added
    ? `"${request.productName}" já foi incluído nesta permuta`
    : `O pedido de "${request.productName}" já foi recusado`;
}

/** Um pedido atendido, do tamanho que o item da permuta precisa dele. */
export interface GrantedRequest {
  id: number;
  productName: string;
  unit: string;
  quantity: number;
  sku: string | null;
  unitValue: number | null;
}

/**
 * O CUSTO (R$) que os itens de fora do Barter acrescentam à permuta.
 *
 * Ele entra na conta das SACAS — o item foi retirado e é pago como qualquer
 * outro — e não entra em régua nenhuma: nem no mínimo por hectare, nem no
 * mínimo de classe, nem como denominador deles (ver `pricedItemsFor`). O motivo
 * é que ele não está na taxonomia do fornecedor: sem classe, ele nunca somaria
 * no numerador de nenhuma pasta, mas engordaria o denominador de todas — e um
 * pedido atendido derrubaria, na remontagem, uma permuta que cumpria os mínimos
 * antes dele.
 */
export function offBarterCost(granted: GrantedRequest[]): number {
  return granted.reduce((sum, request) => sum + request.quantity * (request.unitValue ?? 0), 0);
}
