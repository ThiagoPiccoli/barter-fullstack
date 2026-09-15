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
  /**
   * Cadastrar as unidades de retirada — os lugares onde o produtor busca os
   * insumos.
   *
   * Separada de `producersManage` e `usersManage` apesar de as três serem do
   * admin hoje: a lista de locais é operação (abrir e fechar praça), enquanto
   * as outras duas são carteira e acesso. Quando abrir unidade deixar de ser do
   * admin, é esta linha que muda — sem levar junto o poder de criar contas.
   */
  unitsManage: 'units.manage',
  /** Catálogo: produtos, valores de referência e pastas de insumos. */
  catalogManage: 'catalog.manage',
  /**
   * Lançar o Barter: abrir safra, publicar versões (a tabela de valores),
   * corrigir um preço e encerrar. É a capacidade que DECIDE POR QUANTO se
   * permuta — por isso é separada de `catalog.manage`, que só mexe no cadastro
   * do produto (nome, unidade, pasta) e não move dinheiro.
   */
  barterManage: 'barter.manage',
  /** Enxergar TODAS as carteiras de produtores, não só a própria. */
  producersReadAll: 'producers.readAll',
  /** Enxergar TODAS as permutas, não só as próprias. */
  bartersReadAll: 'barters.readAll',
  /**
   * Enxergar as permutas DO PRÓPRIO TIME — as endereçadas a este gerente.
   *
   * É um terceiro escopo, entre "só as minhas" (consultor) e "todas"
   * (retaguarda), e existe porque o gerente não é auditor: ele responde por um
   * time, e a permuta de outro time não é assunto dele. Enquanto ele teve
   * `bartersReadAll`, a fila que pedia ação dele ficava misturada com a
   * operação inteira — e a tela não tinha como dar ênfase ao que era dele.
   */
  bartersReadTeam: 'barters.readTeam',
  /**
   * Enxergar as permutas QUE CHEGARAM AO FATURAMENTO — as aprovadas e as já
   * faturadas.
   *
   * É o quarto escopo, e o mais estreito da retaguarda. O faturista trabalhava
   * com `bartersReadAll` desde que o papel nasceu, e isso lhe dava a operação
   * inteira: a fila do gerente, a mesa do comitê e as permutas negadas apareciam
   * na tela de quem não participa de nenhuma dessas etapas. Não é só ruído —
   * é o andamento de negociações em aberto na mão de quem só emite a nota.
   *
   * Ele enxerga o próprio trecho da linha e nada antes dele. QUAIS estados são
   * esses não está escrito aqui: quem responde é `lineFrom(invoice)` em
   * `barters/barter-workflow.ts`, que é onde o caminho da permuta mora.
   */
  bartersReadInvoicing: 'barters.readInvoicing',
  /** Registrar permuta (ato do consultor dono da carteira). */
  bartersRegister: 'barters.register',
  /**
   * PEDIR a alteração de uma permuta que já saiu da mão de quem a registrou.
   *
   * É do consultor, e anda junto com `bartersRegister` na prática — mas é
   * capacidade própria porque responde a outra pergunta: registrar é o ato de
   * entrada da esteira, e pedir alteração é o único caminho de VOLTA nela (ver
   * `barters/change-request.ts`). Um dia o gerente vai poder pedir pelo time
   * dele, e é esta linha que muda — sem lhe dar de carona o registro de
   * permutas em carteira que não é dele.
   */
  bartersChangeRequest: 'barters.changeRequest',
  /**
   * DECIDIR o pedido de alteração: liberar a permuta para o consultor refazê-la
   * ou recusar o pedido, com o motivo.
   *
   * É do ADMIN, e não do comitê — apesar de o comitê ser quem decide permuta.
   * As duas decisões são de naturezas diferentes: o comitê julga o NEGÓCIO
   * ("esta permuta se aprova?"), e o que se julga aqui é o PROCESSO ("o
   * trabalho já feito pelos outros postos vai ser jogado fora?"). Liberar
   * apaga o parecer do gerente e a decisão do comitê da permuta — é
   * administração da linha, que é justamente o que o admin faz.
   */
  bartersChangeReview: 'barters.changeReview',
  /**
   * Dar o PARECER TÉCNICO sobre uma permuta enviada pelo consultor.
   *
   * A capacidade é o portão ("este papel participa da etapa do gerente"); ela
   * não diz sobre QUAL permuta. Isso é política sobre o recurso, e mora no
   * service: o parecer é do gerente A QUEM a permuta foi enviada, e qualquer
   * outro gerente leva 403. É o primeiro caso do que o comentário no fim deste
   * arquivo previa — e hoje quem responde por ele é o ESCOPO DE LEITURA do
   * gerente (`bartersReadTeam`), porque "não é do meu time" e "não posso opinar
   * nela" acabaram sendo a mesma pergunta.
   */
  bartersOpinion: 'barters.opinion',
  /**
   * DECIDIR a permuta: aprovar ou negar a que já tem parecer do gerente.
   *
   * Era do admin, e saiu de lá. O admin administra o sistema — cria as contas,
   * lança os valores, abre e fecha praça —, e quem administra o acesso não pode
   * ser também quem decide o negócio: é a mesma pessoa concedendo o poder e
   * usando-o, sem ninguém a quem a decisão preste contas.
   *
   * Quem decide é o COMITÊ, e ele decide lendo as duas peças que chegam prontas:
   * o pedido do consultor e o parecer técnico do gerente. Como em
   * `bartersOpinion`, a capacidade é só o portão — a etapa só aceita permuta que
   * esteja no ponto dela, e disso cuida a máquina de estados
   * (`barters/barter-workflow.ts`).
   */
  bartersReview: 'barters.review',
  /**
   * FATURAR a permuta aprovada — o último posto da linha.
   *
   * É a etapa mais simples do fluxo de propósito: o faturista não avalia nada,
   * não devolve para trás e não escolhe. Ele recebe o que as etapas anteriores
   * produziram e fatura o que foi APROVADO — o estado é quem lhe entrega o
   * trabalho, e é por isso que ele não precisa de nenhuma capacidade de decisão.
   */
  bartersInvoice: 'barters.invoice',
  /**
   * LER a mesa da cédula e gerar o documento — sem preenchê-la e sem faturar.
   *
   * Ela existe porque VER a cédula e ESCREVER nela deixaram de ser a mesma
   * pergunta. Preencher continua sendo do posto que fatura: é ele quem apura a
   * matrícula do imóvel e responde pelo que o título afirma, e `bartersInvoice`
   * segue guardando o `PUT`. Mas o documento de uma permuta já faturada é
   * registro da operação, e o admin — que já enxerga a operação inteira por
   * `bartersReadAll` e já responde pelo timbre por `creditorManage` — precisava
   * pedir a alguém uma segunda via daquilo que ele mesmo administra.
   *
   * O par com `creditorManage` é de propósito: as duas dizem que o admin
   * alcança o PAPEL que a empresa emite, sem por isso alcançar o ATO que o
   * produziu.
   */
  bartersCprRead: 'barters.cprRead',
  /**
   * Ler e editar o CADASTRO DA CREDORA — a identidade da empresa nos documentos
   * que ela emite (razão social, CNPJ, endereço da sede e foro eleito).
   *
   * É a única capacidade que o admin DIVIDE com um posto da linha: ela é do
   * admin **e** do faturista, e de propósito. Ela não decide permuta nem
   * concede acesso — é o cabeçalho do papel timbrado. Quem percebe que o CNPJ
   * saiu com um dígito trocado é quem monta a cédula, e mandá-lo abrir chamado
   * com o admin para corrigir o próprio timbre trocaria um campo de texto por
   * um processo.
   *
   * Ela é SEPARADA de `usersManage` pelo mesmo motivo de `unitsManage`: um dia
   * alguém vai poder corrigir o endereço da sede sem poder criar contas, e é
   * esta linha que responde por isso.
   */
  creditorManage: 'creditor.manage',
  /** Ler a trilha de auditoria. */
  auditRead: 'audit.read',
  /**
   * VER VALORES EM R$ — preços de catálogo, tabela da versão e cotação da saca.
   *
   * O consultor não a tem, e isso não é enfeite de tela: para ele a permuta é
   * "insumos retirados → sacas do grão", e a API passa a devolver os valores JÁ
   * CONVERTIDOS em sacas (`sacksPerUnit`). Antes, esconder R$ era decisão do
   * app enquanto o JSON os carregava — bastava um `curl` com o token dele para
   * ler a tabela inteira do fornecedor, e o cache offline ainda os gravava no
   * aparelho.
   *
   * Repare que ela é de LEITURA e mora ao lado de `barterManage`, que é quem
   * DECIDE os valores. Um dia alguém vai poder ver sem poder mexer (auditoria,
   * um gerente comercial) — e é esta linha que responde por isso.
   */
  pricesRead: 'prices.read',
  /**
   * Ver o INVESTIMENTO POR HECTARE da permuta — quantas sacas do grão a lavoura
   * está comprometendo por hectare de área cultivável (sc/ha).
   *
   * É a única medida que compara duas permutas de tamanhos diferentes: R$ 400
   * mil numa fazenda de 2.000 ha e R$ 400 mil numa de 300 ha são negócios
   * distintos, e o total sozinho não diz qual é qual. Quem decide, quem
   * administra e quem fatura leem esse número; o consultor e o gerente não —
   * não por sigilo, mas porque para eles a permuta é UMA, e uma régua de
   * comparação sem com quem comparar é ruído na tela.
   *
   * Ela é SEPARADA de `pricesRead` de propósito: sc/ha não é R$, e o dia em que
   * o gerente precisar comparar as permutas do time dele é esta linha que muda —
   * sem lhe dar de carona a tabela de valores do fornecedor.
   */
  bartersInvestmentPerHa: 'barters.investmentPerHa',
} as const;

export type Capability = (typeof CAPABILITY)[keyof typeof CAPABILITY];

export const CAPABILITIES = Object.values(CAPABILITY) as Capability[];

/**
 * A tabela. `Record<Role, ...>` é de propósito: papel novo em roles.ts não
 * compila até alguém escrever, aqui, o que ele pode — que é exatamente a
 * decisão que não pode passar batida.
 *
 * Os TRÊS POSTOS da linha de produção estão escritos abaixo, um por papel:
 * o gerente dá o parecer técnico, o comitê decide e o faturista fatura. Cada um
 * escreve UMA coisa, e nenhum escreve a do outro — é o que faz a etapa ter dono.
 * A ordem em que elas acontecem não está aqui: quem guarda o caminho é
 * `barters/barter-workflow.ts`, e esta tabela só responde quem pode agir.
 *
 * Repare no que o admin PERDEU: `bartersReview`. Ele administra o sistema e
 * enxerga tudo, mas não decide permuta — ver o comentário da capacidade.
 */
export const ROLE_CAPABILITIES: Record<Role, readonly Capability[]> = {
  [ROLE.admin]: [
    CAPABILITY.usersManage,
    CAPABILITY.producersManage,
    CAPABILITY.unitsManage,
    CAPABILITY.catalogManage,
    CAPABILITY.barterManage,
    CAPABILITY.producersReadAll,
    CAPABILITY.bartersReadAll,
    CAPABILITY.creditorManage,
    // A CÉDULA em segunda via: ler e gerar o documento do que já foi faturado.
    // Não vem com `bartersInvoice` junto — o admin não fatura permuta, e
    // preencher a cédula continua sendo de quem apura a matrícula.
    CAPABILITY.bartersCprRead,
    CAPABILITY.auditRead,
    CAPABILITY.pricesRead,
    CAPABILITY.bartersInvestmentPerHa,
    // O caminho de VOLTA da esteira. Ele não é decisão de negócio — é o admin
    // dizendo se o trabalho já feito pelos outros postos vai ser refeito. Ver
    // `bartersChangeReview`, e repare que `bartersReview` continua fora daqui.
    CAPABILITY.bartersChangeReview,
  ],
  // O gerente é o único com escopo de TIME: ele enxerga as permutas
  // endereçadas a ele, e não a operação inteira. Repare que `bartersReadAll`
  // NÃO está aqui — foi removida de propósito, não esquecida.
  // A RETAGUARDA vê valores: o parecer do gerente e a revisão são sobre a
  // negociação, e negociação sem R$ não se avalia. Quem fica de fora é só o
  // consultor — ver `pricesRead`.
  [ROLE.manager]: [
    CAPABILITY.producersReadAll,
    CAPABILITY.bartersReadTeam,
    CAPABILITY.bartersOpinion,
    CAPABILITY.pricesRead,
  ],
  // O COMITÊ decide. É a única instância que aprova ou nega — e ele o faz sobre
  // o que já chegou pronto das duas etapas anteriores, daí a leitura de tudo
  // andar junto com `bartersReview`. Ele é também o único posto que enxerga a
  // etapa ANTERIOR à sua: o que está no gerente é o que vai cair na mesa dele,
  // e prever a fila é parte de decidir.
  [ROLE.committee]: [
    CAPABILITY.producersReadAll,
    CAPABILITY.bartersReadAll,
    CAPABILITY.bartersReview,
    CAPABILITY.pricesRead,
    CAPABILITY.bartersInvestmentPerHa,
  ],
  // O FATURISTA fatura, e é só isso — inclusive no que enxerga. Ele alcança o
  // que CHEGOU ao faturamento e nada antes disso: o parecer que o gerente ainda
  // não deu e a permuta que o comitê ainda não decidiu não são trabalho dele, e
  // uma negociação em aberto não precisa passar pela tela de quem emite a nota.
  // Ver `bartersReadInvoicing`.
  // `creditorManage` é a exceção ao parágrafo acima, e a única: o faturista
  // mantém o cadastro da CREDORA junto com o admin. Não é decisão de negócio
  // nem concessão de acesso — é o timbre dos documentos que ele emite, e quem
  // vê o CNPJ errado é quem monta a cédula.
  [ROLE.biller]: [
    CAPABILITY.producersReadAll,
    CAPABILITY.bartersReadInvoicing,
    CAPABILITY.bartersInvoice,
    // Quem preenche também lê: o `GET` da mesa da cédula passou a pedir esta
    // capacidade, e sem ela o faturista perderia a própria tela.
    CAPABILITY.bartersCprRead,
    CAPABILITY.creditorManage,
    CAPABILITY.pricesRead,
    CAPABILITY.bartersInvestmentPerHa,
  ],
  [ROLE.consultant]: [CAPABILITY.bartersRegister, CAPABILITY.bartersChangeRequest],
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
 * O ENCAIXE, agora com o primeiro caso dentro dele.
 *
 * Uma capacidade responde "pode dar parecer?". O fluxo pergunta "pode dar
 * parecer NESTA permuta?" — e a resposta depende do recurso, não só de quem
 * pede: a permuta foi endereçada a um gerente, e a de outro time não é dele.
 * Isso não cabe nesta tabela e não foi forçado dentro dela: a capacidade é o
 * portão (`barters.opinion` abre a rota) e o BartersService decide o caso
 * concreto — hoje pelo ESCOPO (`scopeFor`), que para o gerente já é o próprio
 * time. Era uma comparação à parte de `barter.managerId`, e ela saiu quando o
 * escopo do faturista obrigou toda ação a conferir a leitura antes de agir:
 * duas regras respondendo à mesma pergunta é uma a mais do que se pode manter
 * em dia.
 *
 * As alçadas seguem o mesmo desenho quando existirem ("o gerente aprova até
 * R$ 50 mil" depende do valor da permuta). O erro a evitar continua sendo o
 * `if (user.role === 'manager' && total < limite)` solto num service — que é de
 * onde este arquivo veio.
 */
