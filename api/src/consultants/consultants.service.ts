import { Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import type { User } from '@prisma/client';
import { generateProvisionalPassword, hashPassword } from '../auth/password.util';
import { PrismaService } from '../prisma/prisma.service';
import { CreateConsultantDto, UpdateConsultantDto } from './dto/consultant.dto';

/**
 * Consultor recém-provisionado, com a senha de primeira entrada em texto puro.
 * É a ÚNICA vez que esse valor existe fora do hash: o admin precisa dele para
 * ditar ao consultor, e ele nunca mais pode ser lido de volta.
 */
export interface ProvisionedConsultant {
  user: User;
  provisionalPassword: string;
}

/** Gestão de CONSULTORES pelo admin — não existe signup público. */
@Injectable()
export class ConsultantsService {
  constructor(private readonly prisma: PrismaService) {}

  async list(): Promise<User[]> {
    return this.prisma.user.findMany({ where: { role: 'consultant' }, orderBy: { id: 'asc' } });
  }

  /**
   * Cria o consultor com uma senha de primeira entrada ALEATÓRIA (ou a que o
   * admin escolheu). Ela nasce marcada como provisória: quem entra com ela é
   * obrigado a trocá-la antes de usar o app.
   *
   * A aleatoriedade é o ponto. Enquanto essa senha era um valor fixo igual
   * para todo mundo, qualquer um que soubesse o e-mail podia entrar antes do
   * titular, definir a senha definitiva e ficar com a conta — e não havia como
   * o admin retomá-la.
   */
  async create(dto: CreateConsultantDto): Promise<ProvisionedConsultant> {
    const emailTaken = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (emailTaken) {
      throw new UnprocessableEntityException('Este e-mail já está em uso por outro usuário');
    }

    const { password, ...data } = dto;
    const provisionalPassword = password ?? generateProvisionalPassword();
    const user = await this.prisma.user.create({
      data: {
        ...data,
        password: await hashPassword(provisionalPassword),
        role: 'consultant',
        mustChangePassword: true,
      },
    });
    return { user, provisionalPassword };
  }

  async update(id: number, dto: UpdateConsultantDto): Promise<User> {
    const consultant = await this.findConsultant(id);
    const emailTaken = await this.prisma.user.findFirst({
      where: { email: dto.email, NOT: { id: consultant.id } },
    });
    if (emailTaken) {
      throw new UnprocessableEntityException('Este e-mail já está em uso por outro usuário');
    }
    return this.prisma.user.update({ where: { id: consultant.id }, data: dto });
  }

  /**
   * Devolve o acesso ao consultor com uma nova senha provisória. É o caminho
   * para os dois problemas reais do dia a dia: esqueceu a senha, ou a conta
   * ficou com quem não devia.
   *
   * Derruba TODAS as sessões abertas da conta — sem isso, redefinir a senha
   * não expulsaria quem já estava dentro, e o reset não resolveria nada no
   * caso que mais importa.
   */
  async resetPassword(id: number): Promise<ProvisionedConsultant> {
    const consultant = await this.findConsultant(id);
    const provisionalPassword = generateProvisionalPassword();

    const [user] = await this.prisma.$transaction([
      this.prisma.user.update({
        where: { id: consultant.id },
        data: {
          password: await hashPassword(provisionalPassword),
          mustChangePassword: true,
        },
      }),
      this.prisma.accessToken.deleteMany({ where: { userId: consultant.id } }),
    ]);

    return { user, provisionalPassword };
  }

  /**
   * Excluir um consultor não apaga permutas (snapshot + FK NULL) e deixa os
   * produtores da carteira "sem consultor" até o admin realocá-los.
   */
  async delete(id: number): Promise<void> {
    const consultant = await this.findConsultant(id);
    await this.prisma.user.delete({ where: { id: consultant.id } });
  }

  /** Só registros role=consultant passam por aqui — admin não se gerencia nesta rota. */
  private async findConsultant(id: number): Promise<User> {
    const consultant = await this.prisma.user.findFirst({ where: { id, role: 'consultant' } });
    if (!consultant) throw new NotFoundException('Registro não encontrado.');
    return consultant;
  }
}
