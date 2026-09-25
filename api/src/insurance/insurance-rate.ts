import { normalizeName } from '../seasons/product-name';

/**
 * O SEGURO AGRÍCOLA por município — a conta, a chave e o que dizer quando falta.
 *
 * Aqui não há I/O, pelo mesmo desenho de `barter-math.ts`: a matemática do
 * seguro é conferida no registro, refeita na remontagem do rascunho e mostrada
 * na prévia do app, e as três precisam produzir o mesmo número. Uma cópia dela
 * dentro do service seria a primeira a divergir.
 *
 * A REGRA inteira cabe em uma linha:
 *
 *     custo do seguro = área cultivável do produtor (ha) × taxa do município (R$/ha)
 *
 * A ÁREA é a do CADASTRO do produtor — a mesma que mede os mínimos por hectare
 * e o investimento por hectare —, e não a área penhorada na cédula. As duas são
 * diferentes de propósito: a penhorada é quanto de lavoura garante ESTA dívida
 * (ver `pledgeAreaFor`), e o que se segura é a lavoura que o produtor planta.
 * Segurar só a área do penhor deixaria de fora justamente o pedaço da fazenda
 * que a empresa não tem em garantia.
 */

/**
 * O município reduzido à forma comparável — a chave do cadastro.
 *
 * É `normalizeName` mais uma correção que só o município pede: os espaços em
 * volta da barra. O cadastro escreve "Maringá/PR", mas quem digita escreve
 * "Campo Mourão / PR" tantas vezes quanto "Campo Mourão/PR", e sem isto as duas
 * grafias seriam duas praças — com dois preços, e a permuta encontrando uma
 * delas por acaso.
 */
export function cityKeyOf(city: string): string {
  return normalizeName(city).replace(/\s*\/\s*/g, '/');
}

/**
 * O NOME do município, sem a UF — "tupancireta" tanto de "TUPANCIRETÃ" quanto
 * de "Tupanciretã/RS".
 */
export function cityNameOf(city: string): string {
  return cityKeyOf(city).split('/')[0].trim();
}

/** A UF, quando ela foi escrita. Vazio quando o município veio sozinho. */
export function ufOf(city: string): string {
  const parts = cityKeyOf(city).split('/');
  return parts.length > 1 ? parts[parts.length - 1].trim() : '';
}

/**
 * ESTES DOIS TEXTOS FALAM DO MESMO MUNICÍPIO?
 *
 * A pergunta existe porque as duas pontas escrevem diferente, e nenhuma das
 * duas está errada: a planilha da seguradora traz "TUPANCIRETÃ" — ela é toda de
 * um estado só, e a UF seria ruído em 400 linhas —, enquanto o cadastro do
 * produtor traz "Tupanciretã/RS", porque ali o município aparece sozinho e
 * precisa se identificar.
 *
 * A REGRA é: mesmo nome, e a UF só separa quando AS DUAS a declaram. Ou seja,
 * "TUPANCIRETÃ" casa com "Tupanciretã/RS" (uma delas não disse o estado, e
 * quem não diz não contradiz), e "Bom Jesus/RS" NÃO casa com "Bom Jesus/SC" —
 * essas são duas praças de verdade, com dois riscos e dois preços.
 *
 * O que ela NÃO faz é adivinhar a UF que falta. A planilha sem estado continua
 * sem estado no cadastro: inventar "/RS" nas linhas dela seria afirmar, no
 * registro da empresa, algo que o arquivo não disse — e erraria inteiro no dia
 * em que a mesma seguradora mandar a planilha do Paraná.
 */
export function sameCity(a: string, b: string): boolean {
  if (cityNameOf(a) !== cityNameOf(b)) return false;
  const ufA = ufOf(a);
  const ufB = ufOf(b);
  return ufA === '' || ufB === '' || ufA === ufB;
}

/**
 * O CUSTO (R$) de segurar a área deste produtor a esta taxa.
 *
 * Duas casas porque é dinheiro, e é o número que o comprovante imprime — a
 * mesma precisão de `MONEY_EPSILON`. Zero quando falta qualquer um dos dois
 * lados: não é "seguro de graça", é "não há como calcular", e quem lê a ausência
 * e decide o que ela significa é quem chamou. Aqui não se inventa custo a partir
 * de uma taxa que ninguém cadastrou.
 */
export function insuranceCostFor(areaHa: number, valuePerHa: number): number {
  if (!(areaHa > 0) || !(valuePerHa > 0)) {
    return 0;
  }
  return Math.round(areaHa * valuePerHa * 100) / 100;
}

/**
 * A UNIDADE da linha do seguro dentro da permuta.
 *
 * Hectare, e não "unidade" ou "apólice": a linha é `quantidade × valor
 * unitário` como todas as outras do comprovante, e a quantidade dela é a área.
 * É o que permite ao produtor conferir a conta lendo a própria linha — 1.200 ha
 * × R$ 85,00 —, em vez de receber um valor fechado com a conta em outro lugar.
 */
export const INSURANCE_UNIT = 'ha';

/**
 * O NOME da linha do seguro, com a praça que a precificou dentro dele.
 *
 * O município entra no nome porque ele é a JUSTIFICATIVA do valor: "Seguro
 * agrícola" sozinho, a R$ 140/ha, é um número que ninguém sabe de onde veio;
 * com a praça ao lado, a conferência é possível contra a base de cadastro. É a
 * mesma razão de o item de fora do Barter carregar a marca que o explica.
 */
export function insuranceItemNameOf(city: string): string {
  return `Seguro agrícola — ${city}`;
}

/**
 * O que dizer ao consultor quando o Barter LEVA seguro e a praça do produtor
 * não tem taxa cadastrada.
 *
 * A recusa é no REGISTRO, e é grátis ali: ninguém retirou nada ainda, a permuta
 * não existe, e quem resolve é o admin numa linha de cadastro. A frase diz o
 * município e diz onde se resolve, porque quem a lê não é quem pode resolvê-la —
 * ela é lida pelo consultor, que vai precisar pedir a alguém.
 *
 * O caminho contrário — deixar a permuta nascer sem a linha — é o que esta
 * mensagem existe para impedir: seria uma permuta sem seguro dentro de uma safra
 * que tem seguro, descoberta semanas depois, com o insumo já na fazenda.
 */
export function missingRateRefusal(city: string): string {
  const named = city.trim();
  return (
    `Este Barter leva seguro agrícola, e ${
      named ? `o município "${named}"` : 'o município do produtor'
    } ainda não tem valor por hectare cadastrado. ` +
    'Peça ao administrador para cadastrá-lo na base de seguros por município'
  );
}

/**
 * O que dizer quando o Barter leva seguro e o produtor não tem município no
 * cadastro.
 *
 * Separada da de cima porque manda fazer outra coisa: ali falta uma linha na
 * base de seguros (e quem a escreve é o admin), aqui falta o município no
 * cadastro do produtor (e quem o escreve também é o admin, mas em outra tela).
 * Uma frase só para os dois casos mandaria metade das pessoas ao lugar errado.
 */
export const MISSING_CITY_REFUSAL =
  'Este Barter leva seguro agrícola, e o cadastro deste produtor está sem o município — ' +
  'é ele que define o valor por hectare. Peça ao administrador para completá-lo';
