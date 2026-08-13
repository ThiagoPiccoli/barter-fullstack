/**
 * Os PAPÉIS do sistema, em um só lugar. `role` é String no banco (SQLite não
 * tem enum), então a lista abaixo é a única definição do que vale — guard,
 * seed, serializador e app conferem por aqui.
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
  /** Faturista: cuida do faturamento das permutas (visão de retaguarda). */
  biller: 'biller',
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
  [ROLE.biller]: 'Faturista',
  [ROLE.consultant]: 'Consultor',
};

/**
 * Papéis que o admin provisiona pelas rotas de usuário (`/consultants`,
 * `/managers`, `/committee-members`, `/billers`).
 *
 * `admin` fica de fora — e fica de fora no TIPO, não numa checagem que alguém
 * pode esquecer de escrever: o primeiro admin nasce do
 * bootstrap-admin.ts (banco vazio, variáveis de ambiente) e a senha dele se
 * redefine por scripts/reset-password.ts. Não existe rota que crie admin
 * porque não existe ninguém acima do admin para autorizá-la, e uma rota
 * dessas transformaria "provisionar usuário" em "fabricar um par seu".
 */
export type ManagedRole = Exclude<Role, typeof ROLE.admin>;
