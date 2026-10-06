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
 * SEGURADORA — o setor da empresa que cria as apólices das permutas com seguro
 * e as anexa, com o número.
 *
 * Rota própria pelo mesmo motivo das outras, e pela mesma razão a mais do
 * emissor: o posto é NOVO, e sem uma conta provisionada toda permuta aprovada
 * com seguro para em `awaitingPolicy` — o que agora fica escrito na tela.
 *
 * Ela NÃO é conta única (ver SINGLE_ACCOUNT_ROLES): o nome é de empresa, mas o
 * posto é um setor interno com várias pessoas, e cada uma responde pela apólice
 * que anexou.
 */
@Controller('insurers')
@RequireCapability(CAPABILITY.usersManage)
export class InsurersController {
  constructor(private readonly users: UserProvisioningService) {}

  @Get()
  async index() {
    return (await this.users.list(ROLE.insurer)).map(toUserJson);
  }

  /**
   * Provisiona a pessoa da seguradora. A resposta traz `provisionalPassword` UMA
   * ÚNICA VEZ — é o que o admin dita para ela entrar. Não há como recuperar esse
   * valor depois; o caminho para isso é o reset abaixo.
   */
  @Post()
  async store(@CurrentUser() actor: User, @Body() dto: CreateUserDto) {
    return toProvisionedUserJson(await this.users.create(actor, ROLE.insurer, dto));
  }

  @Put(':id')
  async update(
    @CurrentUser() actor: User,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateUserDto,
  ) {
    return toUserJson(await this.users.update(actor, ROLE.insurer, id, dto));
  }

  /**
   * Nova senha provisória para quem perdeu o acesso — ou cuja conta caiu em
   * mãos erradas. Encerra todas as sessões abertas dela.
   */
  @Post(':id/reset-password')
  @HttpCode(200)
  async resetPassword(@CurrentUser() actor: User, @Param('id', ParseIntPipe) id: number) {
    return toProvisionedUserJson(await this.users.resetPassword(actor, ROLE.insurer, id));
  }

  @Delete(':id')
  @HttpCode(204)
  async destroy(@CurrentUser() actor: User, @Param('id', ParseIntPipe) id: number) {
    await this.users.delete(actor, ROLE.insurer, id);
  }
}
