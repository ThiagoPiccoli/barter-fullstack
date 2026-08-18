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
import { CreateConsultantDto, UpdateConsultantDto } from './dto/user.dto';
import { UserProvisioningService } from './user-provisioning.service';

/**
 * CONSULTOR — quem registra permuta para a própria carteira de produtores.
 *
 * É o único dos quatro cujo cadastro tem consequência no domínio, por duas
 * pontas: produtor pertence à carteira de um consultor (excluir um deixa esses
 * produtores sem dono até o admin realocá-los), e toda permuta dele é enviada
 * ao GERENTE apontado aqui, que é quem dará o parecer técnico.
 *
 * É também o único com DTO próprio — `CreateConsultantDto` estende o comum com
 * o gerente. As outras três rotas continuam sem saber que gerente existe.
 */
@Controller('consultants')
@RequireCapability(CAPABILITY.usersManage)
export class ConsultantsController {
  constructor(private readonly users: UserProvisioningService) {}

  @Get()
  async index() {
    return (await this.users.list(ROLE.consultant)).map(toUserJson);
  }

  /**
   * Provisiona o consultor. A resposta traz `provisionalPassword` UMA ÚNICA
   * VEZ — é o que o admin dita para ele entrar. Não há como recuperar esse
   * valor depois; o caminho para isso é o reset abaixo.
   */
  @Post()
  async store(@CurrentUser() actor: User, @Body() dto: CreateConsultantDto) {
    return toProvisionedUserJson(await this.users.create(actor, ROLE.consultant, dto));
  }

  @Put(':id')
  async update(
    @CurrentUser() actor: User,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateConsultantDto,
  ) {
    return toUserJson(await this.users.update(actor, ROLE.consultant, id, dto));
  }

  /**
   * Nova senha provisória para quem perdeu o acesso — ou cuja conta caiu em
   * mãos erradas. Encerra todas as sessões abertas dele.
   */
  @Post(':id/reset-password')
  @HttpCode(200)
  async resetPassword(@CurrentUser() actor: User, @Param('id', ParseIntPipe) id: number) {
    return toProvisionedUserJson(await this.users.resetPassword(actor, ROLE.consultant, id));
  }

  @Delete(':id')
  @HttpCode(204)
  async destroy(@CurrentUser() actor: User, @Param('id', ParseIntPipe) id: number) {
    await this.users.delete(actor, ROLE.consultant, id);
  }
}
