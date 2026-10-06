/**
 * Os PAPÉIS do sistema, em um só lugar. `role` é String no banco, e não `enum`
 * do Postgres, então a lista abaixo é a única definição do que vale — guard,
 * seed, serializador e app conferem por aqui.
 *
 * Eles estão na ORDEM DA ESTEIRA depois do admin: o consultor monta, o gerente
 * opina, o comitê decide, a seguradora emite a apólice (quando a permuta tem
 * seguro), o faturista fatura e o emissor emite a cédula. Ver
 * `barters/barter-workflow.ts`, que é onde o caminho mora.
 *
 * Os identificadores são em inglês para acompanhar os dois que já existiam
 * (`admin`, `consultant`): o valor gravado é chave técnica, e o nome que a
 * pessoa lê está em ROLE_LABELS.
 */
export const ROLE = {
  /** Administra o sistema: cadastros, catálogo, valores e usuários. */
  admin: 'admin',
  /** Gerente: acompanha a operação inteira (visão de retaguarda). */
  manager: 'manager',
  /** Comitê: instância de análise das permutas (visão de retaguarda). */
  committee: 'committee',
  /**
   * SEGURADORA: o setor da empresa que cuida dos seguros — cria a apólice da
   * permuta aprovada, anexa o documento e informa o número dela.
   *
   * Não é a companhia de seguros: é um posto INTERNO, com várias pessoas, que
   * gerencia as apólices que a empresa contrata para o produtor. Ele só entra
   * na esteira quando a permuta TEM seguro (obrigatório na versão, ou opcional
   * e aceito pelo produtor); sem seguro, a aprovada vai direto ao faturista.
   *
   * Nasceu pelo mesmo motivo do emissor: a apólice era um número que o
   * consultor digitava na cédula, e quem a emitia não tinha etapa, prazo nem
   * lugar para pôr o documento. Agora o número só existe se foi a seguradora que
   * o informou — junto com a apólice anexada.
   */
  insurer: 'insurer',
  /** Faturista: fatura a permuta aprovada e anexa as notas (retaguarda). */
  biller: 'biller',
  /**
   * EMISSOR: emite a Cédula de Produto Rural, colhe as assinaturas e a registra.
   *
   * É o posto que vem DEPOIS do faturamento, e nasceu de uma correção: a cédula
   * era do faturista, e não é. Faturar é emitir nota — ato fiscal, contra o
   * estoque e a nota de venda. Emitir CPR é pôr em circulação um TÍTULO DE
   * CRÉDITO: ele é conferido, assinado por gente (às vezes por um casal, às
   * vezes com avalista) e levado a registro. São dois ofícios, com duas
   * responsabilidades diferentes, e enquanto foram um só o segundo acontecia
   * "junto com" o primeiro — isto é, sem etapa, sem prazo e sem quem responda
   * por ele.
   *
   * O que ele NÃO faz é preencher a cédula: as informações são do CONSULTOR, que
   * é quem conhece o produtor, a lavoura e as matrículas. O emissor CONFERE na
   * hora de gerar — ver `bartersCprIssue` em policy.ts.
   */
  emitter: 'emitter',
  /** Consultor: registra permutas para a PRÓPRIA carteira de produtores. */
  consultant: 'consultant',
} as const;

export type Role = (typeof ROLE)[keyof typeof ROLE];

export const ROLES = Object.values(ROLE) as Role[];

/** Nome de exibição de cada papel (o app usa o mesmo vocabulário). */
export const ROLE_LABELS: Record<Role, string> = {
  [ROLE.admin]: 'Administrador',
  [ROLE.manager]: 'Gerente',
  [ROLE.committee]: 'Comitê',
  [ROLE.insurer]: 'Seguradora',
  [ROLE.biller]: 'Faturista',
  [ROLE.emitter]: 'Emissor',
  [ROLE.consultant]: 'Consultor',
};

/**
 * Papéis cujo cadastro é ÚNICO no sistema — a conta é do ÓRGÃO, não de uma
 * pessoa.
 *
 * O COMITÊ é o caso: ele é uma REUNIÃO. Quem decide a permuta não é o fulano do
 * comitê — é o comitê reunido —, e o cadastro segue essa verdade em vez de
 * contrariá-la. Uma conta por integrante criaria três problemas de uma vez: a
 * decisão passaria a ser assinada por uma pessoa (quando ela é do colegiado),
 * entrar no comitê viraria cadastro de usuário (quando é ata de reunião), e o
 * admin teria de manter em dia uma lista de gente que muda a cada composição.
 *
 * O que se perde, e vale dizer: com o login compartilhado, a trilha registra
 * "Comitê", não quem estava na sala. É por isso que a observação da decisão é o
 * lugar da ATA — quem participou e o que foi acordado. Se um dia isso precisar
 * ser estruturado, o caminho é um cadastro de reunião com participantes, e não
 * uma conta por pessoa.
 *
 * O FATURISTA não está aqui de propósito: faturar é ofício de gente, várias
 * pessoas fazem, e cada uma responde pelo que emitiu. O EMISSOR pelo mesmo
 * motivo — quem assina a conferência de um título responde por ela com o
 * próprio nome. E a SEGURADORA também: apesar do nome de empresa, ela é um
 * setor com vários logins, e cada pessoa responde pela apólice que anexou.
 */
export const SINGLE_ACCOUNT_ROLES: readonly Role[] = [ROLE.committee];

/** O cadastro deste papel é único (o órgão), e não um por pessoa? */
export function isSingleAccount(role: Role): boolean {
  return SINGLE_ACCOUNT_ROLES.includes(role);
}
