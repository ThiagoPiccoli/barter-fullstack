import { Body, Controller, Get, HttpCode, Param, Post, Query } from '@nestjs/common';
import type { User } from '@prisma/client';
import { AnyRole, CurrentUser, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toBarterJson } from '../common/serializers';
import { BartersService } from './barters.service';
import {
  BarterOpinionDto,
  CreateBarterDto,
  InvoiceBarterDto,
  ListBartersQuery,
  ReviewBarterDto,
} from './dto/barter.dto';

@Controller('barters')
export class BartersController {
  constructor(private readonly bartersService: BartersService) {}

  /**
   * Listagem escopada (consultor: as suas; retaguarda: todas). Aceita ?status=,
   * ?limit= e ?offset=; a resposta traz `meta.total` com o tamanho real da
   * coleção por trás da página.
   */
  @Get()
  @AnyRole() // escopo por linha: consultor vê as suas (service)
  async index(@CurrentUser() user: User, @Query() query: ListBartersQuery) {
    return (await this.bartersService.listFor(user, query)).map((b) => toBarterJson(b, user));
  }

  /** Detalhe pelo código público (ex.: PRM-2026-001). */
  @Get(':code')
  @AnyRole() // idem: o service recusa permuta de carteira alheia
  async show(@CurrentUser() user: User, @Param('code') code: string) {
    return toBarterJson(await this.bartersService.findFor(user, code), user);
  }

  /**
   * Registro de permuta pelo consultor. O payload traz apenas produtos e
   * quantidades: preços, mínimos e o cálculo das sacas são autoridade do
   * servidor (BartersService).
   */
  @Post()
  @RequireCapability(CAPABILITY.bartersRegister)
  async store(@CurrentUser() user: User, @Body() dto: CreateBarterDto) {
    return toBarterJson(await this.bartersService.create(user, dto), user);
  }

  /**
   * PARECER TÉCNICO do gerente sobre uma permuta que chegou à unidade dele.
   *
   * A capacidade abre a porta para o papel; quem confere que a permuta é de uma
   * unidade DESTE gerente é o service — a política sobre o recurso não cabe no
   * decorator.
   */
  @Post(':code/opinion')
  @RequireCapability(CAPABILITY.bartersOpinion)
  @HttpCode(200)
  async opinion(
    @CurrentUser() manager: User,
    @Param('code') code: string,
    @Body() dto: BarterOpinionDto,
  ) {
    return toBarterJson(await this.bartersService.giveOpinion(manager, code, dto), manager);
  }

  /**
   * A DECISÃO DO COMITÊ: aprova ou nega a permuta que já tem parecer, com
   * observação opcional.
   *
   * A rota continua sendo `/review` — o vocabulário da etapa não mudou, só o
   * papel que a exerce. Quem decide agora é o comitê; o admin administra o
   * sistema e não passa por aqui (ver CAPABILITY.bartersReview).
   */
  @Post(':code/review')
  @RequireCapability(CAPABILITY.bartersReview)
  @HttpCode(200)
  async review(
    @CurrentUser() committee: User,
    @Param('code') code: string,
    @Body() dto: ReviewBarterDto,
  ) {
    return toBarterJson(await this.bartersService.review(committee, code, dto), committee);
  }

  /**
   * O FATURAMENTO da permuta aprovada — o último posto da linha.
   *
   * A capacidade abre a porta para o faturista; quem confere que só o APROVADO
   * fatura é a máquina de estados, no service.
   */
  @Post(':code/invoice')
  @RequireCapability(CAPABILITY.bartersInvoice)
  @HttpCode(200)
  async invoice(
    @CurrentUser() biller: User,
    @Param('code') code: string,
    @Body() dto: InvoiceBarterDto,
  ) {
    return toBarterJson(await this.bartersService.invoice(biller, code, dto), biller);
  }
}
