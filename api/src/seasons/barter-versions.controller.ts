import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  ParseIntPipe,
  Post,
  Put,
  Query,
} from '@nestjs/common';
import type { User } from '@prisma/client';
import { AnyRole, CurrentUser, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toBarterVersionJson } from '../common/serializers';
import {
  CloseOnGoalDto,
  UpdateVersionPriceDto,
  VersionGrainPatchDto,
  VersionInsuranceDto,
} from './dto/season.dto';
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
  async current(@CurrentUser() user: User, @Query('grainId') grainId?: string) {
    const version = await this.seasons.currentVersion();
    // O usuário viaja junto porque é ele quem decide a UNIDADE dos valores: o
    // consultor recebe a tabela em sacas por unidade, sem R$ e sem a cotação da
    // saca. Ver `lensFor` em common/serializers.ts.
    //
    // A CULTURA (`?grainId=`) escolhe por qual cotação a tabela é convertida —
    // o mesmo insumo custa 0,33 saca de soja e 0,69 de milho. Sem ela, a
    // primeira cultura do lançamento, que é a que a tela mostra selecionada.
    return version ? toBarterVersionJson(version, undefined, user, Number(grainId) || null) : null;
  }

  /** Detalhe de uma versão, com o realizado contra as metas. */
  @Get(':code')
  @RequireCapability(CAPABILITY.barterManage)
  async show(
    @CurrentUser() user: User,
    @Param('code') code: string,
    @Query('grainId') grainId?: string,
  ) {
    const version = await this.seasons.findVersion(code);
    return toBarterVersionJson(
      version,
      await this.seasons.progressOf(version),
      user,
      Number(grainId) || null,
    );
  }

  /**
   * Correção pontual de um valor da versão vigente — os GRÃOS inclusive: o
   * `productId` de uma das culturas corrige a cotação da saca dela.
   */
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
   * O ACERTO DE UMA CULTURA da versão: a cotação da saca, a produtividade
   * estimada, o vencimento da CPR ou a meta de sacas dela.
   *
   * `PUT` pelo mesmo motivo do modo de encerramento: é um estado que se declara,
   * e reenviar o mesmo valor não faz nada além do que já está feito. Uma rota
   * para os quatro campos porque eles são o mesmo ato — acertar a cultura —, e
   * porque o admin os revê na mesma tela: a colheita antecipou, a estimativa
   * mudou, a seguradora atrasou.
   *
   * Ela existe para não obrigar a REPUBLICAR a tabela inteira por causa de um
   * número de dois dígitos, o que encerraria a versão vigente e reiniciaria a
   * contagem do realizado.
   */
  @Put(':code/grains/:grainId')
  @RequireCapability(CAPABILITY.barterManage)
  async grain(
    @CurrentUser() admin: User,
    @Param('code') code: string,
    @Param('grainId', ParseIntPipe) grainId: number,
    @Body() dto: VersionGrainPatchDto,
  ) {
    return toBarterVersionJson(
      await this.seasons.setGrain(admin, code, grainId, dto),
      undefined,
      admin,
    );
  }

  /**
   * O SEGURO AGRÍCOLA da versão vigente — liga e desliga.
   *
   * `PUT` pelo mesmo motivo dos dois acima: é um estado que se declara. E existe
   * pela mesma razão do modo de encerramento — a opção nasce no lançamento, e
   * mudar de ideia no meio do Barter (a apólice saiu depois da tabela, a
   * diretoria decidiu incluir) não pode custar uma republicação, que encerraria
   * a versão e reiniciaria a contagem do realizado.
   */
  @Put(':code/insurance')
  @RequireCapability(CAPABILITY.barterManage)
  async insurance(
    @CurrentUser() admin: User,
    @Param('code') code: string,
    @Body() dto: VersionInsuranceDto,
  ) {
    return toBarterVersionJson(
      await this.seasons.setInsuranceRequired(admin, code, dto.enabled),
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
