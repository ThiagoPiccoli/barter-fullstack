import { Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import type { User } from '@prisma/client';
import { AUDIT_ACTION, AuditService } from '../audit/audit.service';
import { generateProvisionalPassword, hashPassword } from '../auth/password.util';
import { ROLE_LABELS, type ManagedRole } from '../common/roles';
import { PrismaService } from '../prisma/prisma.service';
import { CreateUserDto, UpdateUserDto } from './dto/user.dto';

/**
 * Usuário recém-provisionado, com a senha de primeira entrada em texto puro.
 * É a ÚNICA vez que esse valor existe fora do hash: o admin precisa dele para
 * ditar ao titular, e ele nunca mais pode ser lido de volta.
 */
export interface ProvisionedUser {
  user: User;
  provisionalPassword: string;
}

/**
 * O motor de provisionamento, compartilhado pelas quatro rotas de usuário
 * (`/consultants`, `/managers`, `/committee-members`, `/billers`).
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
 */
@Injectable()
export class UserProvisioningService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async list(role: ManagedRole): Promise<User[]> {
    return this.prisma.user.findMany({ where: { role }, orderBy: { id: 'asc' } });
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
    await this.ensureEmailIsFree(dto.email);

    const { password, ...data } = dto;
    const provisionalPassword = password ?? generateProvisionalPassword();
    const user = await this.prisma.user.create({
      data: {
        ...data,
        password: await hashPassword(provisionalPassword),
        role,
        mustChangePassword: true,
      },
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

  async update(actor: User, role: ManagedRole, id: number, dto: UpdateUserDto): Promise<User> {
    const user = await this.findWithRole(role, id);
    await this.ensureEmailIsFree(dto.email, user.id);
    const updated = await this.prisma.user.update({ where: { id: user.id }, data: dto });

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
        },
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
   */
  async delete(actor: User, role: ManagedRole, id: number): Promise<void> {
    const user = await this.findWithRole(role, id);
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
