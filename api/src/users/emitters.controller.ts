import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseIntPipe,
  Post,
  Put,
} from '@nestjs/common';
import type { User } from '@prisma/client';
import { CurrentUser, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { ROLE } from '../common/roles';
import { toProvisionedUserJson, toUserJson } from '../common/serializers';
import { CreateUserDto, UpdateUserDto } from './dto/user.dto';
import { UserProvisioningService } from './user-provisioning.service';

/**
 * EMISSOR — emite a Cédula de Produto Rural, colhe as assinaturas e a registra.
 *
 * Rota própria pelo mesmo motivo das outras, e com uma razão a mais: o posto é
 * NOVO, e o cadastro dele é a primeira coisa que precisa existir para a esteira
 * chegar ao fim. Sem um emissor provisionado, toda permuta faturada para em
 * `invoiced` — o que é exatamente o que acontecia antes deste papel existir, só
 * que agora está escrito na tela.
 *
 * Ele NÃO é conta única (ver SINGLE_ACCOUNT_ROLES): conferir um título e
 * assinar por essa conferência é ofício de gente, e cada um responde pelo que
 * emitiu.
 */
@Controller('emitters')
@RequireCapability(CAPABILITY.usersManage)
export class EmittersController {
  constructor(private readonly users: UserProvisioningService) {}

  @Get()
  async index() {
    return (await this.users.list(ROLE.emitter)).map(toUserJson);
  }

  /**
   * Provisiona o emissor. A resposta traz `provisionalPassword` UMA ÚNICA VEZ —
   * é o que o admin dita para ele entrar. Não há como recuperar esse valor
   * depois; o caminho para isso é o reset abaixo.
   */
  @Post()
  async store(@CurrentUser() actor: User, @Body() dto: CreateUserDto) {
    return toProvisionedUserJson(await this.users.create(actor, ROLE.emitter, dto));
  }

  @Put(':id')
  async update(
    @CurrentUser() actor: User,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateUserDto,
  ) {
    return toUserJson(await this.users.update(actor, ROLE.emitter, id, dto));
  }

  /**
   * Nova senha provisória para quem perdeu o acesso — ou cuja conta caiu em
   * mãos erradas. Encerra todas as sessões abertas dele.
   */
  @Post(':id/reset-password')
  @HttpCode(200)
  async resetPassword(@CurrentUser() actor: User, @Param('id', ParseIntPipe) id: number) {
    return toProvisionedUserJson(await this.users.resetPassword(actor, ROLE.emitter, id));
  }

  @Delete(':id')
  @HttpCode(204)
  async destroy(@CurrentUser() actor: User, @Param('id', ParseIntPipe) id: number) {
    await this.users.delete(actor, ROLE.emitter, id);
  }
}
