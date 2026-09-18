import { Injectable, Logger } from '@nestjs/common';
import type { AuditLog, User } from '@prisma/client';
import { Paginated, windowOf } from '../common/pagination';
import { PrismaService } from '../prisma/prisma.service';
import type { ListAuditLogsQuery } from './dto/audit.dto';

/**
 * Os atos que deixam rastro. Lista fechada: auditar "tudo" produz ruído que
 * ninguém lê, e o que interessa aqui é o que muda QUEM tem acesso e o que
 * decide dinheiro.
 */
export const AUDIT_ACTION = {
  userCreated: 'user.created',
  userUpdated: 'user.updated',
  userPasswordReset: 'user.password-reset',
  userDeleted: 'user.deleted',
  /**
   * As UNIDADES, porque designar o gerente de uma é decidir para quem vão as
   * permutas que serão retiradas nela.
   *
   * Sem isto, trocar o responsável por uma unidade tiraria permutas da fila de
   * alguém e as colocaria na de outro sem deixar rastro — e a pergunta que
   * aparece depois ("por que esta permuta parou de aparecer para mim?") não
   * teria como ser respondida. É a mesma natureza do reset de senha: o ato é
   * pequeno, o efeito é sobre quem alcança o quê.
   */
  unitCreated: 'unit.created',
  unitUpdated: 'unit.updated',
  unitDeleted: 'unit.deleted',
  /**
   * A LINHA DE PRODUÇÃO da permuta: o parecer do gerente, a decisão do comitê e
   * o faturamento.
   *
   * Os três estão aqui porque decidem dinheiro — e continuam aqui mesmo agora
   * que cada permuta tem a PRÓPRIA linha do tempo (`BarterEvent`). São trilhas
   * de naturezas diferentes: a da permuta conta a história DAQUELE registro, e é
   * lida por quem está trabalhando nele; esta é global, cruza contas, unidades e
   * permutas, e é onde uma investigação começa — "o que o fulano fez na terça?"
   * não se responde abrindo permuta por permuta.
   */
  barterOpinion: 'barter.opinion',
  barterReviewed: 'barter.reviewed',
  barterInvoiced: 'barter.invoiced',
  /**
   * O DESVIO da linha: o pedido de alteração do consultor e a decisão do admin
   * sobre ele (ver `barters/change-request.ts`).
   *
   * Os dois entram pelo critério dos três acima — o efeito, não o esforço. A
   * liberação APAGA da permuta o parecer do gerente e a decisão do comitê, que é
   * o ato de maior alcance que o admin pratica sobre uma permuta; e o pedido é
   * o que o justifica. Ler um sem o outro na trilha global (a que cruza contas e
   * permutas) deixaria "por que esta permuta aprovada voltou a rascunho?" sem
   * resposta fora do registro dela.
   */
  barterChangeRequested: 'barter.change-requested',
  barterChangeDecided: 'barter.change-decided',
  /**
   * O VALOR DE UMA PERMUTA REESCRITO pelo admin ao atender o pedido (ver
   * `priceChangeRefusal` em `barters/change-request.ts`).
   *
   * É o ato de maior alcance financeiro que o admin pratica sobre um registro
   * já feito: ele muda o custo dos insumos e, com ele, as sacas que o produtor
   * entrega — dentro de uma permuta que já passou pelo gerente, e pode já ter
   * sido decidida pelo comitê. Se algum ato deste sistema precisa ser lido por
   * alguém de fora dele um dia, é este.
   */
  barterPricesChanged: 'barter.prices-changed',
  /**
   * O PEDIDO DE FORA DO BARTER: o consultor pedindo um produto que a tabela não
   * tem, e o admin atendendo com um valor (ver `barters/product-request.ts`).
   *
   * Entram pelo mesmo critério do desvio. O que a decisão do admin faz aqui é
   * pôr na permuta um item CUJO VALOR NÃO ESTÁ EM TABELA NENHUMA — ele não é
   * conferível contra a versão publicada, e a única maneira de saber de onde
   * ele veio é este par de linhas.
   */
  barterProductRequested: 'barter.product-requested',
  barterProductDecided: 'barter.product-decided',
  /**
   * O PREENCHIMENTO DA CÉDULA (CPR). Entra aqui pelo mesmo critério dos três
   * acima, e com folga: a cédula é um título de crédito, e o que ela diz — a
   * qualificação de quem se obriga, a matrícula do imóvel dado em penhor, o
   * vencimento — é o que vale contra o produtor num inadimplemento.
   *
   * Ela é o único registro do sistema que é RASCUNHO e sério ao mesmo tempo:
   * pode ser reescrito quantas vezes for preciso (é o que um rascunho é), e
   * cada reescrita muda o conteúdo de um documento executável. A linha do tempo
   * da permuta não a alcança — `BarterEvent` guarda mudança de ESTADO, e
   * preencher cédula não move a permuta de posto —, então sem isto a única
   * pergunta sem resposta seria a que mais importa: quem trocou a matrícula.
   */
  barterCprSaved: 'barter.cpr-saved',
  /**
   * A EMISSÃO DA CÉDULA, a coleta de assinaturas e o registro — os três atos do
   * emissor.
   *
   * Eles entram pelo critério dos outros (o efeito, não o esforço), e o primeiro
   * com uma razão só dele: emitir é a CONFERÊNCIA. É o ato que afirma que o
   * título está correto — que o RG é daquela pessoa, que a matrícula é daquela
   * lavoura, que a nota existe. Quando um título for questionado, "quem conferiu
   * e em que dia?" é a primeira pergunta, e ela precisa de resposta fora do
   * registro da permuta.
   *
   * O REGISTRO entra porque é o momento em que a garantia passa a valer contra
   * terceiros, e porque o número dele é o que se leva ao cartório para pedir a
   * certidão. A assinatura, por estar entre os dois.
   */
  barterCprIssued: 'barter.cpr-issued',
  barterCprSigned: 'barter.cpr-signed',
  barterCprRegistered: 'barter.cpr-registered',
  /**
   * AS NOTAS FISCAIS anexadas ao faturamento — e as removidas.
   *
   * A REMOÇÃO é o motivo deste par existir. Anexar é rotina; tirar a nota de uma
   * permuta faturada apaga a prova do faturamento, e a cédula que a cita como
   * origem da dívida passa a apontar para o vazio. É um ato pequeno com efeito
   * sobre um documento executável, que é exatamente o perfil do que esta trilha
   * guarda.
   */
  barterInvoiceAttached: 'barter.invoice-attached',
  barterInvoiceRemoved: 'barter.invoice-removed',
  /**
   * O CADASTRO DA CREDORA. É a parte da cédula que identifica QUEM cobra, e um
   * CNPJ trocado aqui vale para todas as emitidas dali em diante.
   *
   * A linha do tempo da permuta não alcança isto — ela é do registro, e a
   * credora é global —, e o cadastro tem DOIS donos (admin e emissor), o que
   * torna "quem mudou o CNPJ?" uma pergunta que aparece de verdade.
   */
  creditorUpdated: 'creditor.updated',
  /**
   * ENTRADA no sistema — e as tentativas que não entraram.
   *
   * A trilha registrava muito bem o que se faz DEPOIS de entrar, e nada sobre
   * o entrar. É a primeira pergunta de qualquer investigação ("quem estava
   * dentro na terça à noite?") e a única evidência de ataque em andamento: dez
   * falhas seguidas na conta do admin não se parecem com nada no registro de
   * atos administrativos, porque nenhum ato aconteceu.
   *
   * O log HTTP mostra `POST /auth/login 400`, mas ele vai para a saída padrão,
   * é volátil e não sabe de QUEM era a conta.
   */
  sessionStarted: 'session.started',
  sessionFailed: 'session.failed',
  sessionLocked: 'session.locked',
  // O lançamento do Barter decide POR QUANTO a cooperativa troca insumo por
  // grão: publicar uma versão, corrigir um preço dentro dela e encerrá-la
  // valem tanto quanto aprovar uma permuta, e pelo mesmo motivo — é dinheiro.
  seasonOpened: 'season.opened',
  seasonClosed: 'season.closed',
  /**
   * O VENCIMENTO DA CPR da safra. Entra na trilha porque ele vale para TODAS as
   * cédulas da safra: mudá-lo antecipa ou adia a entrega de cada produtor que
   * ainda não teve o título emitido, num campo que ninguém mais confere depois.
   */
  seasonCprDueDateSet: 'season.cpr-due-date-set',
  versionPublished: 'barter.version-published',
  versionPriceChanged: 'barter.price-changed',
  versionClosed: 'barter.version-closed',
  /**
   * Trocou o MODO de encerramento da versão (automático ao bater meta ↔ manual).
   *
   * Entra na trilha porque decide quando a cooperativa para de aceitar permuta:
   * desligar o automático no dia em que a meta está para bater é uma decisão de
   * quanto crédito a mais vai ser aprovado.
   */
  versionCloseRuleChanged: 'barter.version-close-rule',
  /**
   * Mudou a PRODUTIVIDADE ESTIMADA da versão — a taxa que dimensiona a área do
   * penhor.
   *
   * Entra na trilha porque ela decide quanta terra a empresa exige em garantia:
   * baixá-la de 60 para 50 sc/ha faz cada permuta nova pedir 20% mais lavoura, e
   * subi-la afrouxa a garantia de todas elas na mesma proporção. É decisão de
   * risco tomada num campo de dois dígitos, e "por que as permutas de março
   * pediram menos área?" se responde aqui.
   */
  versionYieldChanged: 'barter.version-yield-changed',
  /**
   * Mudou a MARGEM DE SEGURANÇA DO PENHOR no cadastro da credora.
   *
   * O par da de cima, pelo outro lado da conta: a produtividade é estimativa
   * agronômica, esta é apetite de risco da empresa. As duas multiplicam a área
   * exigida, as duas valem para tudo o que for registrado depois delas, e
   * nenhuma das duas reescreve permuta já fechada — o que torna a data do ato a
   * informação principal da linha.
   */
  creditorPledgeMarginChanged: 'creditor.pledge-margin-changed',
} as const;

export type AuditAction = (typeof AUDIT_ACTION)[keyof typeof AUDIT_ACTION];

/**
 * Quem praticou o ato, quando não há um `User` para apontar.
 *
 * Existe por causa da tentativa de login em e-mail que não existe: alguém agiu,
 * e é exatamente esse alguém que interessa registrar, mas não há conta nenhuma
 * a que ele corresponda. Forçar um `User` aqui obrigaria a inventar um.
 */
export interface AuditActor {
  id?: number | null;
  name: string;
  role: string;
}

export interface AuditEntry {
  actor: User | AuditActor;
  action: AuditAction;
  targetType: 'user' | 'unit' | 'barter' | 'season' | 'version' | 'session' | 'creditor';
  targetId?: number | null;
  targetLabel: string;
  detail?: string;
}

/** O ator no formato da trilha, venha ele de uma conta ou de um instantâneo. */
function actorSnapshot(actor: User | AuditActor): AuditActor {
  return 'fullName' in actor
    ? { id: actor.id, name: actor.fullName, role: actor.role }
    : { id: actor.id ?? null, name: actor.name, role: actor.role };
}

@Injectable()
export class AuditService {
  private readonly logger = new Logger('Audit');

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Grava a linha da trilha.
   *
   * NÃO derruba a operação se a gravação falhar. É uma escolha, e vale
   * explicá-la: o ato auditado (redefinir a senha de alguém que perdeu o
   * acesso) já aconteceu e é o que a pessoa precisa; abortar a resposta por
   * causa do registro transformaria uma falha de auditoria em indisponibilidade
   * do sistema. A perda vira ERRO no log, que é onde o alarme deve tocar.
   *
   * A troca seria outra num sistema em que a trilha tem valor legal — aí ela
   * entra na MESMA transação do ato, e sem trilha não há ato. Se o faturamento
   * exigir isso, é aqui que muda.
   */
  async record(entry: AuditEntry): Promise<void> {
    const actor = actorSnapshot(entry.actor);
    try {
      await this.prisma.auditLog.create({
        data: {
          actorId: actor.id ?? null,
          actorName: actor.name,
          actorRole: actor.role,
          action: entry.action,
          targetType: entry.targetType,
          targetId: entry.targetId ?? null,
          targetLabel: entry.targetLabel,
          detail: entry.detail ?? null,
        },
      });
    } catch (error) {
      this.logger.error(
        `Falha ao registrar auditoria (${entry.action} sobre ${entry.targetLabel})`,
        error instanceof Error ? error.stack : undefined,
      );
    }
  }

  /** Mais recentes primeiro — é assim que se investiga: do agora para trás. */
  async list(query: ListAuditLogsQuery): Promise<Paginated<AuditLog>> {
    const { take, skip } = windowOf(query);
    const where = {
      ...(query.action ? { action: query.action } : {}),
      ...(query.targetType ? { targetType: query.targetType } : {}),
    };

    const [items, total] = await this.prisma.$transaction([
      this.prisma.auditLog.findMany({
        where,
        orderBy: [{ at: 'desc' }, { id: 'desc' }],
        take,
        skip,
      }),
      this.prisma.auditLog.count({ where }),
    ]);

    return new Paginated(items, total, take, skip);
  }
}
