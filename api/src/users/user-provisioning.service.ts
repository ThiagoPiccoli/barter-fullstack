import { Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import type { User } from '@prisma/client';
import { AUDIT_ACTION, AuditService } from '../audit/audit.service';
import { CLEARED_LOCKOUT } from '../auth/lockout';
import { generateProvisionalPassword, hashPassword } from '../auth/password.util';
import { ROLE, ROLE_LABELS, isSingleAccount, type ManagedRole } from '../common/roles';
import { MANAGER_FIELDS, type UserWithManager } from '../common/serializers';
import { PrismaService } from '../prisma/prisma.service';
import { CreateUserDto, UpdateUserDto } from './dto/user.dto';

/**
 * Usuário recém-provisionado, com a senha de primeira entrada em texto puro.
 * É a ÚNICA vez que esse valor existe fora do hash: o admin precisa dele para
 * ditar ao titular, e ele nunca mais pode ser lido de volta.
 */
export interface ProvisionedUser {
  user: UserWithManager;
  provisionalPassword: string;
}

/**
 * O motor de provisionamento, compartilhado pelas quatro rotas de usuário
 * (`/consultants`, `/managers`, `/committee`, `/billers`).
 *
 * Cada papel tem a SUA rota — é o que permite guardar, documentar e evoluir um
 * sem mexer nos outros —, mas as regras que valem para todos vivem aqui, uma
 * vez só: senha de primeira entrada sorteada, e-mail único, reset que derruba
 * as sessões abertas. Quatro cópias disso seria a receita para corrigir uma
 * falha de senha em três lugares e esquecer o quarto.
 *
 * TODO MÉTODO recebe o papel da rota. Não é parâmetro de conveniência: é ele
 * que fecha o escopo. `PUT /managers/7` procura um registro que seja gerente E
 * tenha id 7 — se o 7 for um consultor, a resposta é 404, e nenhuma rota
 * alcança usuário de papel alheio nem por engano.
 *
 * O COMITÊ entra por aqui pelo mesmo motor, com uma diferença que é do domínio e
 * não da rota: o cadastro dele é ÚNICO (ver `isSingleAccount` em roles.ts). Quem
 * escolhe o registro não é um id vindo da URL — é o papel, que só tem um.
 */
@Injectable()
export class UserProvisioningService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async list(role: ManagedRole): Promise<UserWithManager[]> {
    return this.prisma.user.findMany({
      where: { role },
      include: { manager: MANAGER_FIELDS },
      orderBy: { id: 'asc' },
    });
  }

  /**
   * Cria o usuário com uma senha de primeira entrada ALEATÓRIA (ou a que o
   * admin escolheu). Ela nasce marcada como provisória: quem entra com ela é
   * obrigado a trocá-la antes de usar o app.
   *
   * A aleatoriedade é o ponto. Enquanto essa senha era um valor fixo igual
   * para todo mundo, qualquer um que soubesse o e-mail podia entrar antes do
   * titular, definir a senha definitiva e ficar com a conta — e não havia como
   * o admin retomá-la.
   *
   * O papel vem da ROTA, nunca do payload. Um `role` enviado pelo cliente é
   * descartado pelo `whitelist` do ValidationPipe (não existe no DTO) e, mesmo
   * que passasse, seria sobrescrito aqui. É o que impede que `POST /billers`
   * vire uma fábrica de administradores.
   */
  async create(actor: User, role: ManagedRole, dto: CreateUserDto): Promise<ProvisionedUser> {
    await this.ensureSingleAccountIsFree(role);
    await this.ensureEmailIsFree(dto.email);

    const { password, unitId, managerId, ...data } = dto as CreateUserDto & {
      managerId?: number;
    };
    const provisionalPassword = password ?? generateProvisionalPassword();
    const user = await this.prisma.user.create({
      data: {
        ...data,
        ...(await this.unitFields(unitId)),
        managerId: await this.resolveManager(role, managerId),
        password: await hashPassword(provisionalPassword),
        role,
        mustChangePassword: true,
      },
      include: { manager: MANAGER_FIELDS },
    });

    await this.audit.record({
      actor,
      action: AUDIT_ACTION.userCreated,
      targetType: 'user',
      targetId: user.id,
      targetLabel: user.email,
      detail: `papel: ${ROLE_LABELS[role]}`,
    });
    return { user, provisionalPassword };
  }

  async update(
    actor: User,
    role: ManagedRole,
    id: number,
    dto: UpdateUserDto,
  ): Promise<UserWithManager> {
    const user = await this.findWithRole(role, id);
    await this.ensureEmailIsFree(dto.email, user.id);
    const { unitId, managerId, ...data } = dto as UpdateUserDto & { managerId?: number };
    const updated = await this.prisma.user.update({
      where: { id: user.id },
      data: {
        ...data,
        ...(await this.unitFields(unitId)),
        managerId: await this.resolveManager(role, managerId),
      },
      include: { manager: MANAGER_FIELDS },
    });

    await this.audit.record({
      actor,
      action: AUDIT_ACTION.userUpdated,
      targetType: 'user',
      targetId: updated.id,
      targetLabel: updated.email,
      // Trocar o e-mail troca a chave de login: é o que mais importa aqui.
      detail: user.email === updated.email ? undefined : `e-mail: ${user.email} → ${updated.email}`,
    });
    return updated;
  }

  /**
   * Devolve o acesso ao titular com uma nova senha provisória. É o caminho
   * para os dois problemas reais do dia a dia: esqueceu a senha, ou a conta
   * ficou com quem não devia.
   *
   * Derruba TODAS as sessões abertas da conta — sem isso, redefinir a senha
   * não expulsaria quem já estava dentro, e o reset não resolveria nada no
   * caso que mais importa.
   *
   * E DESTRANCA a conta (CLEARED_LOCKOUT). Sem isso o reset entregava uma senha
   * que não entrava: a trava por tentativas erradas é checada no login ANTES da
   * senha, então a conta bloqueada continuava recusando por até quinze minutos
   * a senha provisória que o admin acabara de ditar ao telefone. O caso não é
   * hipotético — é o mais provável de todos, porque quem procura o admin
   * costuma ser exatamente quem acabou de errar a senha dez vezes.
   */
  async resetPassword(actor: User, role: ManagedRole, id: number): Promise<ProvisionedUser> {
    const target = await this.findWithRole(role, id);
    const provisionalPassword = generateProvisionalPassword();

    const [user] = await this.prisma.$transaction([
      this.prisma.user.update({
        where: { id: target.id },
        data: {
          password: await hashPassword(provisionalPassword),
          mustChangePassword: true,
          ...CLEARED_LOCKOUT,
        },
        include: { manager: MANAGER_FIELDS },
      }),
      this.prisma.accessToken.deleteMany({ where: { userId: target.id } }),
    ]);

    await this.audit.record({
      actor,
      action: AUDIT_ACTION.userPasswordReset,
      targetType: 'user',
      targetId: user.id,
      targetLabel: user.email,
      detail: 'senha provisória sorteada; sessões abertas encerradas',
    });
    return { user, provisionalPassword };
  }

  /**
   * Excluir não apaga permutas: elas guardam nome e filial de quem registrou
   * no próprio registro (snapshot) e o FK vira NULL.
   *
   * No caso do CONSULTOR há um efeito a mais, que é do domínio e não desta
   * rota: os produtores da carteira dele ficam "sem consultor" até o admin
   * realocá-los (`onDelete: SetNull` no schema).
   *
   * O GERENTE, ao contrário, é BARRADO enquanto tiver trabalho na mesa. As
   * duas travas abaixo existem porque a saída dele criaria estados sem saída:
   * um consultor sem gerente não registra permuta (o cadastro exige um), e uma
   * permuta endereçada a alguém que não existe mais fica esperando para sempre
   * um parecer que ninguém pode dar — sem erro e sem alarme. Reatribuir o time
   * e esvaziar a fila são decisões de gente, e a mensagem diz qual falta.
   */
  async delete(actor: User, role: ManagedRole, id: number): Promise<void> {
    // Conta de ÓRGÃO não se exclui: sem ela a linha de produção para, e nenhuma
    // permuta é decidida até alguém reparar. A rota nem existe (ver
    // CommitteeController); isto é a mesma regra como invariante do domínio,
    // para uma rota futura não reabrir o buraco sem ninguém decidir isso.
    if (isSingleAccount(role)) {
      throw new UnprocessableEntityException(
        `O cadastro do ${ROLE_LABELS[role]} não se exclui — ele é a etapa, não uma pessoa. ` +
          'Para tirar o acesso de quem está com ele, redefina a senha.',
      );
    }
    const user = await this.findWithRole(role, id);
    if (role === ROLE.manager) await this.ensureManagerIsFree(user.id);
    await this.prisma.user.delete({ where: { id: user.id } });

    await this.audit.record({
      actor,
      action: AUDIT_ACTION.userDeleted,
      targetType: 'user',
      targetId: user.id,
      targetLabel: user.email,
      detail: `papel: ${ROLE_LABELS[role]}`,
    });
  }

  /**
   * A CONTA ÚNICA de um papel de órgão — ou `null` quando ela ainda não existe.
   *
   * Null e não 404: "o comitê ainda não foi cadastrado" é um estado legítimo do
   * sistema recém-instalado, e é a tela do admin que existe para resolvê-lo. Um
   * erro aqui faria a tela ter de tratar como falha o caso normal do primeiro
   * dia.
   */
  async findSingle(role: ManagedRole): Promise<UserWithManager | null> {
    return this.prisma.user.findFirst({
      where: { role },
      include: { manager: MANAGER_FIELDS },
      orderBy: { id: 'asc' },
    });
  }

  /** A conta única para quem vai ESCREVER nela — 404 enquanto ela não existe. */
  async requireSingle(role: ManagedRole): Promise<UserWithManager> {
    const account = await this.findSingle(role);
    if (!account) {
      throw new NotFoundException(`O ${ROLE_LABELS[role]} ainda não tem cadastro.`);
    }
    return account;
  }

  /**
   * O papel de conta única já tem dono?
   *
   * A unicidade é do PAPEL, não do e-mail: um segundo comitê com outro endereço
   * passaria pela conferência de e-mail sem problema nenhum, e a operação
   * passaria a ter dois órgãos decidindo a mesma coisa — cada um sem saber do
   * outro, e a fila aparecendo inteira para os dois.
   */
  private async ensureSingleAccountIsFree(role: ManagedRole): Promise<void> {
    if (!isSingleAccount(role)) return;
    const existing = await this.prisma.user.count({ where: { role } });
    if (existing > 0) {
      throw new UnprocessableEntityException(
        `O cadastro do ${ROLE_LABELS[role]} é único e já existe — edite o que está lá, ` +
          'ou redefina a senha dele.',
      );
    }
  }

  /**
   * O vínculo com a unidade E o rótulo dela, escritos JUNTOS — este é o único
   * lugar do sistema que os produz.
   *
   * `branch` é o nome da unidade congelado no usuário. Ele existe porque é o
   * que as telas mostram, o que os rankings do painel agrupam e o que a permuta
   * copia para dentro de si (`consultantBranch`); ler o nome pela relação a
   * cada uso obrigaria todo `findUnique` de usuário — inclusive o do AuthGuard,
   * em toda requisição — a carregar um join que ninguém pediu.
   *
   * O preço de um campo derivado é ele divergir da fonte. Aqui isso é contido
   * por dois fatos: quem escreve é só este método, e renomear uma unidade não
   * reescreve o que já foi congelado — que é o comportamento certo, do mesmo
   * jeito que `Barter.producerName` não muda quando o produtor troca de nome.
   */
  private async unitFields(unitId: number): Promise<{ unitId: number; branch: string }> {
    const unit = await this.prisma.unit.findUnique({ where: { id: unitId } });
    if (!unit) {
      throw new UnprocessableEntityException('Escolha uma unidade válida');
    }
    return { unitId: unit.id, branch: unit.name };
  }

  /**
   * O gerente do consultor, conferido.
   *
   * Só o CONSULTOR tem gerente. Nos outros papéis o campo nem existe no DTO, e
   * o `whitelist` do ValidationPipe descartaria um `managerId` enviado à mão —
   * a garantia final é este `null`, que impede um faturista de nascer
   * pendurado num gerente e aparecer no time dele.
   *
   * A conferência é uma lista de permitidos com um papel só: apontar um
   * faturista como gerente de alguém criaria um consultor cujas permutas nunca
   * sairiam de `sentToManager`, porque quem dá parecer é quem tem
   * `barters.opinion` — e ele não tem.
   */
  private async resolveManager(role: ManagedRole, managerId?: number): Promise<number | null> {
    if (role !== ROLE.consultant || managerId === undefined) return null;

    const manager = await this.prisma.user.findUnique({ where: { id: managerId } });
    if (!manager || manager.role !== ROLE.manager) {
      throw new UnprocessableEntityException(
        `Escolha um ${ROLE_LABELS[ROLE.manager]} para responder pelo consultor`,
      );
    }
    return manager.id;
  }

  /** As duas coisas que impedem um gerente de sair — ver `delete`. */
  private async ensureManagerIsFree(managerId: number): Promise<void> {
    const team = await this.prisma.user.count({ where: { managerId } });
    if (team > 0) {
      throw new UnprocessableEntityException(
        `Este gerente ainda responde por ${team} ${team === 1 ? 'consultor' : 'consultores'} — designe outro gerente para ${team === 1 ? 'ele' : 'eles'} antes de excluir`,
      );
    }

    const waiting = await this.prisma.barter.count({
      where: { managerId, status: 'sentToManager' },
    });
    if (waiting > 0) {
      throw new UnprocessableEntityException(
        `Este gerente tem ${waiting} ${waiting === 1 ? 'permuta esperando' : 'permutas esperando'} o parecer dele`,
      );
    }
  }

  /**
   * O índice único do banco é a garantia final, mas ele só sabe dizer "valor
   * repetido". Conferir antes permite a mensagem que o admin entende — e a
   * busca é por e-mail em TODOS os papéis, não só no da rota: dois usuários
   * com o mesmo e-mail quebrariam o login, que não sabe de papel nenhum.
   */
  private async ensureEmailIsFree(email: string, ignoreId?: number): Promise<void> {
    const existing = await this.prisma.user.findUnique({ where: { email } });
    if (!existing || existing.id === ignoreId) return;
    throw new UnprocessableEntityException('Este e-mail já está em uso por outro usuário');
  }

  /** Registro do papel DESTA rota. Papel diferente responde como inexistente. */
  private async findWithRole(role: ManagedRole, id: number): Promise<User> {
    const user = await this.prisma.user.findFirst({ where: { id, role } });
    if (!user) {
      throw new NotFoundException(`${ROLE_LABELS[role]} não encontrado.`);
    }
    return user;
  }
}
