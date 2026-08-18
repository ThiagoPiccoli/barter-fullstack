import { Body, Controller, Get, HttpCode, Param, ParseIntPipe, Post, Put } from '@nestjs/common';
import type { User } from '@prisma/client';
import { AnyRole, CurrentUser, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toBarterVersionJson } from '../common/serializers';
import { UpdateVersionPriceDto } from './dto/season.dto';
import { SeasonsService } from './seasons.service';

/**
 * A VERSÃO do Barter — o lançamento com que se permuta.
 *
 * `current` é a única rota aberta a qualquer autenticado: o consultor precisa
 * dela para saber se há Barter aberto e para a prévia das sacas. As metas
 * (`progress`) ficam só no detalhe, que é do admin.
 */
@Controller('barter-versions')
export class BarterVersionsController {
  constructor(private readonly seasons: SeasonsService) {}

  /**
   * A versão vigente, com a tabela de valores. Devolve `null` quando não há
   * Barter lançado — é uma resposta legítima, não um 404: "não existe Barter
   * aberto" é exatamente o que o app precisa mostrar na tela do consultor.
   */
  @Get('current')
  @AnyRole()
  async current(@CurrentUser() user: User) {
    const version = await this.seasons.currentVersion();
    // O usuário viaja junto porque é ele quem decide a UNIDADE dos valores: o
    // consultor recebe a tabela em sacas por unidade, sem R$ e sem a cotação da
    // saca. Ver `lensFor` em common/serializers.ts.
    return version ? toBarterVersionJson(version, undefined, user) : null;
  }

  /** Detalhe de uma versão, com o realizado contra as metas. */
  @Get(':code')
  @RequireCapability(CAPABILITY.barterManage)
  async show(@Param('code') code: string) {
    const version = await this.seasons.findVersion(code);
    return toBarterVersionJson(version, await this.seasons.progressOf(version));
  }

  /** Correção pontual de um valor da versão vigente (o grão inclusive). */
  @Put(':code/prices/:productId')
  @RequireCapability(CAPABILITY.barterManage)
  async updatePrice(
    @CurrentUser() admin: User,
    @Param('code') code: string,
    @Param('productId', ParseIntPipe) productId: number,
    @Body() dto: UpdateVersionPriceDto,
  ) {
    return toBarterVersionJson(await this.seasons.updatePrice(admin, code, productId, dto));
  }

  /** Encerra a versão: o Barter para de aceitar permuta, a safra continua. */
  @Post(':code/close')
  @RequireCapability(CAPABILITY.barterManage)
  @HttpCode(200)
  async close(@CurrentUser() admin: User, @Param('code') code: string) {
    return toBarterVersionJson(await this.seasons.closeVersion(admin, code));
  }
}
