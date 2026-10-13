import { Body, Controller, Get, HttpCode, Param, ParseIntPipe, Post, Put } from '@nestjs/common';
import type { User } from '@prisma/client';
import { AnyRole, CurrentUser, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toBarterVersionJson } from '../common/serializers';
import {
  CloseOnGoalDto,
  InsurancePolicyDto,
  UpdateVersionPriceDto,
  VersionTermsPatchDto,
} from './dto/season.dto';
import { SeasonsService } from './seasons.service';

/**
 * A VERSÃO do Barter — o lançamento de UMA cultura com que se permuta.
 *
 * `current` é a única rota aberta a qualquer autenticado: o consultor precisa
 * dela para saber quais culturas têm Barter aberto e para a prévia das sacas. As
 * metas (`progress`) ficam só no detalhe, que é do admin.
 *
 * O `:slug` é o código sem a barra (`SOJA2627.01`).
 */
@Controller('barter-versions')
export class BarterVersionsController {
  constructor(private readonly seasons: SeasonsService) {}

  /**
   * As versões VIGENTES, uma por cultura com Barter aberto, cada uma com a sua
   * tabela. Lista vazia é resposta legítima: "não existe Barter aberto" é
   * exatamente o que o app precisa mostrar na tela do consultor.
   *
   * O usuário viaja junto porque é ele quem decide a UNIDADE dos valores: o
   * consultor recebe a tabela em sacas por unidade da cultura daquela versão,
   * sem R$ e sem a cotação da saca. Ver `lensFor` em common/serializers.ts.
   */
  @Get('current')
  @AnyRole()
  async current(@CurrentUser() user: User) {
    return (await this.seasons.currentVersions()).map((version) =>
      toBarterVersionJson(version, undefined, user),
    );
  }

  /** Detalhe de uma versão, com o realizado contra as metas. */
  @Get(':slug')
  @RequireCapability(CAPABILITY.barterManage)
  async show(@CurrentUser() user: User, @Param('slug') slug: string) {
    const version = await this.seasons.findVersion(slug);
    return toBarterVersionJson(version, await this.seasons.progressOf(version), user);
  }

  /**
   * Correção pontual de um valor da versão vigente — o GRÃO inclusive: o
   * `productId` dele corrige a cotação da saca.
   */
  @Put(':slug/prices/:productId')
  @RequireCapability(CAPABILITY.barterManage)
  async updatePrice(
    @CurrentUser() admin: User,
    @Param('slug') slug: string,
    @Param('productId', ParseIntPipe) productId: number,
    @Body() dto: UpdateVersionPriceDto,
  ) {
    return toBarterVersionJson(
      await this.seasons.updatePrice(admin, slug, productId, dto),
      undefined,
      admin,
    );
  }

  /**
   * O MODO de encerramento por meta da versão vigente: automático ou manual.
   *
   * `PUT` porque é um estado que se declara ("passe a ser assim"), e não um ato
   * a disparar. O que ele PODE fazer é encerrar o Barter da cultura na hora,
   * quando a meta já estava batida — ver `setCloseOnGoal`.
   */
  @Put(':slug/close-on-goal')
  @RequireCapability(CAPABILITY.barterManage)
  async closeOnGoal(
    @CurrentUser() admin: User,
    @Param('slug') slug: string,
    @Body() dto: CloseOnGoalDto,
  ) {
    return toBarterVersionJson(
      await this.seasons.setCloseOnGoal(admin, slug, dto.enabled),
      undefined,
      admin,
    );
  }

  /**
   * O ACERTO DOS TERMOS DA CULTURA na versão: a cotação da saca, a
   * produtividade estimada, o vencimento da CPR ou a meta de sacas.
   *
   * Ela existe para não obrigar a REPUBLICAR a tabela inteira por causa de um
   * número de dois dígitos, o que encerraria a versão vigente e reiniciaria a
   * contagem do realizado.
   */
  @Put(':slug/terms')
  @RequireCapability(CAPABILITY.barterManage)
  async terms(
    @CurrentUser() admin: User,
    @Param('slug') slug: string,
    @Body() dto: VersionTermsPatchDto,
  ) {
    return toBarterVersionJson(await this.seasons.setTerms(admin, slug, dto), undefined, admin);
  }

  /**
   * A POLÍTICA DE SEGURO da versão vigente — obrigatório, opcional ou sem
   * seguro. Mudar de ideia no meio do Barter (a apólice saiu depois da tabela)
   * não pode custar uma republicação.
   */
  @Put(':slug/insurance')
  @RequireCapability(CAPABILITY.barterManage)
  async insurance(
    @CurrentUser() admin: User,
    @Param('slug') slug: string,
    @Body() dto: InsurancePolicyDto,
  ) {
    return toBarterVersionJson(
      await this.seasons.setVersionInsurance(admin, slug, dto.policy),
      undefined,
      admin,
    );
  }

  /** Encerra a versão: a cultura para de aceitar permuta, a safra continua. */
  @Post(':slug/close')
  @RequireCapability(CAPABILITY.barterManage)
  @HttpCode(200)
  async close(@CurrentUser() admin: User, @Param('slug') slug: string) {
    return toBarterVersionJson(await this.seasons.closeVersion(admin, slug), undefined, admin);
  }
}
