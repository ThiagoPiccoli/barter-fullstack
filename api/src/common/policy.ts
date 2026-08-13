import type { User } from '@prisma/client';
import { ROLE, ROLES, type Role } from './roles';

/**
 * O QUE cada papel pode fazer — a resposta em UM lugar só.
 *
 * Antes disso, a autorização morava em dois sítios que não se falavam: o
 * decorator da rota ("quem pode chamar") e um `seesEverything()` dentro dos
 * services ("quem enxerga além da própria carteira"). Os dois estavam certos e
 * respondem perguntas diferentes — porta e linha —, mas não havia arquivo
 * nenhum onde se lesse "o que um faturista pode". Descobrir isso exigia caçar
 * decorators por seis controllers e `if`s por quatro services.
 *
 * Agora a rota declara a CAPACIDADE de que precisa, não quem entra; a tabela
 * abaixo decide quem tem essa capacidade; e os services perguntam à mesma
 * tabela. Dar uma atribuição nova ao gerente vira uma linha aqui, não uma
 * caçada.
 *
 * O que isto NÃO é: política sobre o RECURSO. "O gerente aprova até R$ 50 mil"
 * depende do valor da permuta, não só de quem pede — é uma regra de outra
 * natureza, e ela entra quando as alçadas existirem. Ver o comentário no fim
 * do arquivo.
 */
export const CAPABILITY = {
  /** Provisionar, editar, resetar senha e excluir usuários. */
  usersManage: 'users.manage',
  /** Cadastrar/editar/excluir produtores e definir a carteira de cada um. */
  producersManage: 'producers.manage',
  /** Catálogo: produtos, valores de referência e pastas de insumos. */
  catalogManage: 'catalog.manage',
  /** Enxergar TODAS as carteiras de produtores, não só a própria. */
  producersReadAll: 'producers.readAll',
  /** Enxergar TODAS as permutas, não só as próprias. */
  bartersReadAll: 'barters.readAll',
  /** Registrar permuta (ato do consultor dono da carteira). */
  bartersRegister: 'barters.register',
  /** Aprovar ou negar uma permuta pendente. */
  bartersReview: 'barters.review',
  /** Ler a trilha de auditoria. */
  auditRead: 'audit.read',
} as const;

export type Capability = (typeof CAPABILITY)[keyof typeof CAPABILITY];

export const CAPABILITIES = Object.values(CAPABILITY) as Capability[];

/**
 * A tabela. `Record<Role, ...>` é de propósito: papel novo em roles.ts não
 * compila até alguém escrever, aqui, o que ele pode — que é exatamente a
 * decisão que não pode passar batida.
 *
 * Gerente, comitê e faturista estão em LEITURA. Não é esquecimento: as ações
 * de cada um nascem com o contrato entre eles, e até lá o correto é a linha
 * vazia de escrita — papel novo não herda poder por omissão.
 */
export const ROLE_CAPABILITIES: Record<Role, readonly Capability[]> = {
  [ROLE.admin]: [
    CAPABILITY.usersManage,
    CAPABILITY.producersManage,
    CAPABILITY.catalogManage,
    CAPABILITY.producersReadAll,
    CAPABILITY.bartersReadAll,
    CAPABILITY.bartersReview,
    CAPABILITY.auditRead,
  ],
  [ROLE.manager]: [CAPABILITY.producersReadAll, CAPABILITY.bartersReadAll],
  [ROLE.committee]: [CAPABILITY.producersReadAll, CAPABILITY.bartersReadAll],
  [ROLE.biller]: [CAPABILITY.producersReadAll, CAPABILITY.bartersReadAll],
  [ROLE.consultant]: [CAPABILITY.bartersRegister],
};

/** O usuário tem a capacidade? É a única pergunta de autorização do sistema. */
export function can(user: Pick<User, 'role'>, capability: Capability): boolean {
  const granted = ROLE_CAPABILITIES[user.role as Role];
  return granted ? granted.includes(capability) : false;
}

/**
 * As capacidades de um usuário, para o cliente montar a interface a partir
 * delas. Papel desconhecido devolve lista vazia — falha fechando, e o app
 * mostra o mínimo em vez de arriscar oferecer o que o servidor recusaria.
 */
export function capabilitiesOf(user: Pick<User, 'role'>): Capability[] {
  return [...(ROLE_CAPABILITIES[user.role as Role] ?? [])];
}

/** Papéis que têm a capacidade — usado por mensagens de erro e pela documentação. */
export function rolesWith(capability: Capability): Role[] {
  return ROLES.filter((role) => ROLE_CAPABILITIES[role].includes(capability));
}

/*
 * PRÓXIMO PASSO, quando as responsabilidades estiverem definidas.
 *
 * Uma capacidade responde "pode aprovar?". O fluxo que vem por aí pergunta
 * "pode aprovar ESTA permuta?" — e a resposta depende do valor, da alçada de
 * quem pede e do estado em que a permuta está. Isso não cabe nesta tabela e
 * NÃO deve ser forçado dentro dela: vira uma função de política que recebe o
 * usuário E o recurso.
 *
 * O que fica pronto aqui é o encaixe. A capacidade continua sendo o portão
 * ("este papel participa da revisão"); a política decide o caso concreto
 * ("esta permuta, deste valor, com este histórico"). O erro a evitar é o
 * `if (user.role === 'manager' && total < limite)` solto num service — que é
 * de onde este arquivo veio.
 */
