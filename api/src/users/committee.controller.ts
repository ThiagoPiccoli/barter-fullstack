import { Body, Controller, Get, HttpCode, Post, Put } from '@nestjs/common';
import type { User } from '@prisma/client';
import { CurrentUser, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { ROLE } from '../common/roles';
import { toProvisionedUserJson, toUserJson } from '../common/serializers';
import { CreateUserDto, UpdateUserDto } from './dto/user.dto';
import { UserProvisioningService } from './user-provisioning.service';

/**
 * O COMITÊ — a instância que DECIDE a permuta, e um cadastro só.
 *
 * A rota é `/committee`, no singular, e as outras três de usuário são plurais:
 * a diferença é o que se cadastra. Consultor, gerente e faturista são PESSOAS
 * (várias, cada uma com a sua conta); o comitê é uma REUNIÃO — quem decide não é
 * o fulano do comitê, é o comitê reunido.
 *
 * Ela já se chamou `/committee-members`, e o comentário de então dizia que
 * `/committee` "daria a entender que se está criando o órgão". É exatamente o
 * que se faz aqui: o cadastro É o do órgão. Uma conta por integrante fazia a
 * decisão do colegiado sair assinada por uma pessoa, transformava entrar no
 * comitê em cadastro de usuário (quando é ata de reunião) e obrigava o admin a
 * manter em dia uma lista que muda a cada composição.
 *
 * Por isso não há `:id` em lugar nenhum — não há qual comitê escolher — e não há
 * DELETE: a conta é a ETAPA, e sem ela nenhuma permuta é decidida. Tirar o
 * acesso de quem está com ela é `reset-password`, que derruba as sessões
 * abertas.
 */
@Controller('committee')
@RequireCapability(CAPABILITY.usersManage)
export class CommitteeController {
  constructor(private readonly users: UserProvisioningService) {}

  /**
   * O cadastro do comitê, ou `null` enquanto ele não existe.
   *
   * Null e não 404: sistema recém-instalado ainda não tem comitê, e isso é
   * estado normal — é justamente o que a tela do admin resolve.
   */
  @Get()
  async show() {
    const committee = await this.users.findSingle(ROLE.committee);
    return committee ? toUserJson(committee) : null;
  }

  /**
   * Cria o cadastro do comitê. Uma vez só: com um já existente, a resposta é
   * 422 dizendo para editar aquele — dois órgãos decidindo a mesma fila, cada
   * um sem saber do outro, é o estado que a unicidade existe para impedir.
   *
   * A resposta traz `provisionalPassword` UMA ÚNICA VEZ — é a senha que abre a
   * reunião, e ela nunca mais pode ser lida de volta.
   */
  @Post()
  async store(@CurrentUser() actor: User, @Body() dto: CreateUserDto) {
    return toProvisionedUserJson(await this.users.create(actor, ROLE.committee, dto));
  }

  /** Corrige o nome, o e-mail de acesso ou a unidade do comitê. */
  @Put()
  async update(@CurrentUser() actor: User, @Body() dto: UpdateUserDto) {
    const committee = await this.users.requireSingle(ROLE.committee);
    return toUserJson(await this.users.update(actor, ROLE.committee, committee.id, dto));
  }

  /**
   * Nova senha para a conta do comitê — e todas as sessões abertas caem.
   *
   * Numa conta compartilhada isto vale mais do que nos outros papéis: a senha
   * circula entre quem participa da reunião, e é aqui que ela se troca quando a
   * composição muda.
   */
  @Post('reset-password')
  @HttpCode(200)
  async resetPassword(@CurrentUser() actor: User) {
    const committee = await this.users.requireSingle(ROLE.committee);
    return toProvisionedUserJson(
      await this.users.resetPassword(actor, ROLE.committee, committee.id),
    );
  }
}
