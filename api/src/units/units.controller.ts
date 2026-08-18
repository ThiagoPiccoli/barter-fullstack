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
import { AnyRole, CurrentUser, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toUnitJson } from '../common/serializers';
import { UnitDto } from './dto/unit.dto';
import { UnitsService } from './units.service';

/**
 * As UNIDADES de retirada.
 *
 * A leitura é aberta a qualquer autenticado de propósito: o consultor precisa
 * da lista para escolher onde o produtor vai retirar, e a retaguarda para ler
 * o local nas permutas. O cadastro é do admin.
 */
@Controller('units')
export class UnitsController {
  constructor(private readonly units: UnitsService) {}

  @Get()
  @AnyRole()
  async index() {
    return (await this.units.list()).map(toUnitJson);
  }

  @Post()
  @RequireCapability(CAPABILITY.unitsManage)
  async store(@CurrentUser() actor: User, @Body() dto: UnitDto) {
    return toUnitJson(await this.units.create(actor, dto));
  }

  @Put(':id')
  @RequireCapability(CAPABILITY.unitsManage)
  async update(
    @CurrentUser() actor: User,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UnitDto,
  ) {
    return toUnitJson(await this.units.update(actor, id, dto));
  }

  @Delete(':id')
  @RequireCapability(CAPABILITY.unitsManage)
  @HttpCode(204)
  async destroy(@CurrentUser() actor: User, @Param('id', ParseIntPipe) id: number) {
    await this.units.delete(actor, id);
  }
}
