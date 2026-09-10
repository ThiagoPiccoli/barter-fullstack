import { Body, Controller, Get, HttpCode, Param, Post, Put, Query } from '@nestjs/common';
import type { User } from '@prisma/client';
import { AnyRole, CurrentUser, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toBarterJson, toCprJson } from '../common/serializers';
import { BartersService } from './barters.service';
import {
  BarterOpinionDto,
  CreateBarterDto,
  ForwardBarterDto,
  InvoiceBarterDto,
  ListBartersQuery,
  ReviewBarterDto,
  SaveBarterNoteDto,
} from './dto/barter.dto';
import { SaveCprDto } from './dto/cpr.dto';

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
   * O PARECER DO CONSULTOR gravado no rascunho — sem encaminhar nada.
   *
   * `PUT`, e não `POST`: é o mesmo texto sendo reescrito, e chamá-lo duas vezes
   * com o mesmo corpo dá o mesmo resultado. É a única escrita do fluxo que se
   * repete — as outras são atos, e ato repetido é recusado pela máquina de
   * estados.
   *
   * Ela é do CONSULTOR (a mesma capacidade do registro), e só alcança o próprio
   * rascunho: quem confere é o service, pelo escopo e pela etapa.
   */
  @Put(':code/note')
  @RequireCapability(CAPABILITY.bartersRegister)
  async saveNote(
    @CurrentUser() consultant: User,
    @Param('code') code: string,
    @Body() dto: SaveBarterNoteDto,
  ) {
    return toBarterJson(await this.bartersService.saveNote(consultant, code, dto), consultant);
  }

  /**
   * O ENCAMINHAMENTO ao gerente — o ato que tira a permuta da mesa do consultor
   * e a põe na fila do parecer técnico.
   *
   * Mesma capacidade do registro, e de propósito: encaminhar é a segunda metade
   * do ato de registrar, que foi partido em dois para caber o parecer do
   * consultor. Um papel novo que possa registrar poderá encaminhar o que
   * registrou — o contrário seria uma permuta que nasce sem ninguém para
   * mandá-la adiante.
   */
  @Post(':code/forward')
  @RequireCapability(CAPABILITY.bartersRegister)
  @HttpCode(200)
  async forward(
    @CurrentUser() consultant: User,
    @Param('code') code: string,
    @Body() dto: ForwardBarterDto,
  ) {
    return toBarterJson(await this.bartersService.forward(consultant, code, dto), consultant);
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

  /**
   * A CÉDULA DE PRODUTO RURAL desta permuta — o que a tela do faturista precisa
   * para montar o formulário: o rascunho, o que a permuta já responde, a
   * credora configurada e o que ainda falta.
   *
   * As duas rotas são do FATURISTA, sob a mesma capacidade do faturamento. A
   * cédula é o documento que o posto dele produz — o mesmo motivo pelo qual a
   * nota fiscal é dele —, e por isso não ganharam capacidade própria: quem
   * fatura preenche a cédula do que faturou.
   */
  @Get(':code/cpr')
  @RequireCapability(CAPABILITY.bartersInvoice)
  async cpr(@CurrentUser() biller: User, @Param('code') code: string) {
    return toCprJson(await this.bartersService.cprFor(biller, code));
  }

  /**
   * Grava o preenchimento da cédula — inteiro ou pela metade.
   *
   * `PUT`, e não `PATCH`, porque é o formulário inteiro que a tela devolve; que
   * um campo ausente preserve o valor gravado é decisão do service (ver
   * `saveCpr`), e é o que permite salvar sem ter tudo em mãos.
   */
  @Put(':code/cpr')
  @RequireCapability(CAPABILITY.bartersInvoice)
  async saveCpr(@CurrentUser() biller: User, @Param('code') code: string, @Body() dto: SaveCprDto) {
    return toCprJson(await this.bartersService.saveCpr(biller, code, dto));
  }
}
