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
 * ADMINISTRADOR — o responsável final pelo sistema, com todas as capacidades.
 *
 * Um admin cadastra outros. O primeiro continua nascendo do
 * bootstrap-admin.ts; a exclusão é travada para a própria conta e para o
 * último admin (ver `ensureAdminCanLeave`).
 */
@Controller('admins')
@RequireCapability(CAPABILITY.usersManage)
export class AdminsController {
  constructor(private readonly users: UserProvisioningService) {}

  @Get()
  async index() {
    return (await this.users.list(ROLE.admin)).map(toUserJson);
  }

  @Post()
  async store(@CurrentUser() actor: User, @Body() dto: CreateUserDto) {
    return toProvisionedUserJson(await this.users.create(actor, ROLE.admin, dto));
  }

  @Put(':id')
  async update(
    @CurrentUser() actor: User,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateUserDto,
  ) {
    return toUserJson(await this.users.update(actor, ROLE.admin, id, dto));
  }

  @Post(':id/reset-password')
  @HttpCode(200)
  async resetPassword(@CurrentUser() actor: User, @Param('id', ParseIntPipe) id: number) {
    return toProvisionedUserJson(await this.users.resetPassword(actor, ROLE.admin, id));
  }

  @Delete(':id')
  @HttpCode(204)
  async destroy(@CurrentUser() actor: User, @Param('id', ParseIntPipe) id: number) {
    await this.users.delete(actor, ROLE.admin, id);
  }
}
