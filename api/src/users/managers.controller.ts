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
 * GERENTE — acompanha a operação inteira (volumes, carteiras, filiais).
 *
 * Rota própria para que a etapa dele no fluxo de aprovação, quando existir,
 * seja guardada e evoluída aqui — inclusive quem pode provisionar um gerente,
 * que hoje é só o admin e não precisa continuar sendo.
 */
@Controller('managers')
@RequireCapability(CAPABILITY.usersManage)
export class ManagersController {
  constructor(private readonly users: UserProvisioningService) {}

  @Get()
  async index() {
    return (await this.users.list(ROLE.manager)).map(toUserJson);
  }

  /**
   * Provisiona o gerente. A resposta traz `provisionalPassword` UMA ÚNICA
   * VEZ — é o que o admin dita para ele entrar. Não há como recuperar esse
   * valor depois; o caminho para isso é o reset abaixo.
   */
  @Post()
  async store(@CurrentUser() actor: User, @Body() dto: CreateUserDto) {
    return toProvisionedUserJson(await this.users.create(actor, ROLE.manager, dto));
  }

  @Put(':id')
  async update(
    @CurrentUser() actor: User,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateUserDto,
  ) {
    return toUserJson(await this.users.update(actor, ROLE.manager, id, dto));
  }

  /**
   * Nova senha provisória para quem perdeu o acesso — ou cuja conta caiu em
   * mãos erradas. Encerra todas as sessões abertas dele.
   */
  @Post(':id/reset-password')
  @HttpCode(200)
  async resetPassword(@CurrentUser() actor: User, @Param('id', ParseIntPipe) id: number) {
    return toProvisionedUserJson(await this.users.resetPassword(actor, ROLE.manager, id));
  }

  @Delete(':id')
  @HttpCode(204)
  async destroy(@CurrentUser() actor: User, @Param('id', ParseIntPipe) id: number) {
    await this.users.delete(actor, ROLE.manager, id);
  }
}
