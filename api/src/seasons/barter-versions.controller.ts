import { Body, Controller, Get, HttpCode, Param, ParseIntPipe, Post, Put } from '@nestjs/common';
import type { User } from '@prisma/client';
import { AnyRole, CurrentUser, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toBarterVersionJson } from '../common/serializers';
import { CloseOnGoalDto, UpdateVersionPriceDto, VersionEstimatedYieldDto } from './dto/season.dto';
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
  async show(@CurrentUser() user: User, @Param('code') code: string) {
    const version = await this.seasons.findVersion(code);
    return toBarterVersionJson(version, await this.seasons.progressOf(version), user);
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
    return toBarterVersionJson(
      await this.seasons.updatePrice(admin, code, productId, dto),
      undefined,
      admin,
    );
  }

  /**
   * O MODO de encerramento por meta da versão vigente: automático ou manual.
   *
   * `PUT` porque é um estado que se declara ("passe a ser assim"), e não um ato
   * a disparar: reenviar o mesmo valor não faz nada além do que já está feito.
   * O que ele PODE fazer é encerrar o Barter na hora, quando a meta já estava
   * batida — ver `setCloseOnGoal`.
   */
  @Put(':code/close-on-goal')
  @RequireCapability(CAPABILITY.barterManage)
  async closeOnGoal(
    @CurrentUser() admin: User,
    @Param('code') code: string,
    @Body() dto: CloseOnGoalDto,
  ) {
    return toBarterVersionJson(
      await this.seasons.setCloseOnGoal(admin, code, dto.enabled),
      undefined,
      admin,
    );
  }

  /**
   * A PRODUTIVIDADE ESTIMADA da versão vigente — a taxa que dimensiona a área do
   * penhor das permutas registradas nela.
   *
   * `PUT` pelo mesmo motivo do modo de encerramento: é um estado que se declara.
   * Ela é obrigatória no lançamento, e esta rota existe para as versões que
   * nasceram antes de o campo existir — republicar a tabela inteira para
   * informá-la encerraria a versão e reiniciaria a contagem do realizado. Ver
   * `setEstimatedYield`.
   */
  @Put(':code/estimated-yield')
  @RequireCapability(CAPABILITY.barterManage)
  async estimatedYield(
    @CurrentUser() admin: User,
    @Param('code') code: string,
    @Body() dto: VersionEstimatedYieldDto,
  ) {
    return toBarterVersionJson(
      await this.seasons.setEstimatedYield(admin, code, dto.estimatedYield),
      undefined,
      admin,
    );
  }

  /** Encerra a versão: o Barter para de aceitar permuta, a safra continua. */
  @Post(':code/close')
  @RequireCapability(CAPABILITY.barterManage)
  @HttpCode(200)
  async close(@CurrentUser() admin: User, @Param('code') code: string) {
    return toBarterVersionJson(await this.seasons.closeVersion(admin, code), undefined, admin);
  }
}
