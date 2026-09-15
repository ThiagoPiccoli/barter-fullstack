import { Body, Controller, Get, HttpCode, Param, Post, Put, Query } from '@nestjs/common';
import type { User } from '@prisma/client';
import { AnyRole, CurrentUser, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toBarterJson, toBarterVersionJson, toCprJson } from '../common/serializers';
import { BartersService } from './barters.service';
import {
  BarterOpinionDto,
  CreateBarterDto,
  DecideBarterChangeDto,
  ForwardBarterDto,
  InvoiceBarterDto,
  ListBartersQuery,
  ReplaceBarterInputsDto,
  RequestBarterChangeDto,
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
   * A TABELA DE VALORES com que esta permuta foi fechada.
   *
   * É o que a tela precisa para REMONTAR os insumos de um rascunho que veio de
   * uma gestão anterior: os preços da permuta são os daquela versão, e não os da
   * vigente. Sem ela, o consultor montaria a permuta lendo um número e o
   * servidor gravaria outro.
   *
   * `@AnyRole` com escopo no service, como o detalhe da permuta: quem alcança a
   * permuta alcança a tabela dela, e nos valores da própria lente (o consultor
   * recebe sacas por unidade, sem R$).
   */
  @Get(':code/version')
  @AnyRole()
  async version(@CurrentUser() user: User, @Param('code') code: string) {
    return toBarterVersionJson(await this.bartersService.versionOf(user, code), undefined, user);
  }

  /**
   * A REESCRITA DOS INSUMOS do rascunho — a permuta remontada por quem a
   * registrou.
   *
   * `PUT`, e não `PATCH`: a lista vai inteira, porque a permuta passa pelas
   * regras de mínimo como um conjunto (ver `ReplaceBarterInputsDto`). Chamar
   * duas vezes com o mesmo corpo dá o mesmo resultado, que é o que a etapa do
   * rascunho tem de diferente das outras — as demais são atos, e ato repetido a
   * máquina de estados recusa.
   *
   * Mesma capacidade e mesma porta do parecer salvo: é do CONSULTOR, e só
   * alcança o próprio rascunho.
   */
  @Put(':code/inputs')
  @RequireCapability(CAPABILITY.bartersRegister)
  async replaceInputs(
    @CurrentUser() consultant: User,
    @Param('code') code: string,
    @Body() dto: ReplaceBarterInputsDto,
  ) {
    return toBarterJson(await this.bartersService.replaceInputs(consultant, code, dto), consultant);
  }

  /**
   * O PEDIDO DE ALTERAÇÃO — o caminho de volta da esteira, aberto pelo
   * consultor que registrou a permuta (ver `barters/change-request.ts`).
   *
   * `POST`, e não `PUT`: é um ato, e um segundo pedido sobre o mesmo pedido em
   * aberto é recusado pelo service — não é a mesma escrita repetida.
   */
  @Post(':code/change-request')
  @RequireCapability(CAPABILITY.bartersChangeRequest)
  @HttpCode(200)
  async requestChange(
    @CurrentUser() consultant: User,
    @Param('code') code: string,
    @Body() dto: RequestBarterChangeDto,
  ) {
    return toBarterJson(await this.bartersService.requestChange(consultant, code, dto), consultant);
  }

  /**
   * A DECISÃO DO ADMIN sobre o pedido: libera a permuta para o consultor
   * refazê-la, ou recusa o pedido com o motivo.
   *
   * A capacidade é OUTRA que a da decisão do comitê, e isso é o desenho: o admin
   * decide o processo, o comitê decide o negócio. Ver `bartersChangeReview`.
   */
  @Post(':code/change-request/decision')
  @RequireCapability(CAPABILITY.bartersChangeReview)
  @HttpCode(200)
  async decideChange(
    @CurrentUser() admin: User,
    @Param('code') code: string,
    @Body() dto: DecideBarterChangeDto,
  ) {
    return toBarterJson(await this.bartersService.decideChange(admin, code, dto), admin);
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
   * As duas rotas ANDAVAM sob a mesma capacidade do faturamento, com o
   * argumento de que a cédula é o documento que o posto do faturista produz —
   * o mesmo motivo pelo qual a nota fiscal é dele. O argumento continua de pé
   * para ESCREVER, e é por isso que o `PUT` não se mexeu: quem apura a
   * matrícula do imóvel e responde pelo que o título afirma é quem fatura.
   *
   * O que se separou foi LER. A segunda via de uma cédula já emitida é registro
   * da operação, e o admin — que enxerga a operação inteira e responde pelo
   * timbre dela — precisava pedir a outra pessoa uma cópia do papel que ele
   * mesmo administra. Ver `bartersCprRead`.
   *
   * O escopo não afrouxou junto: `cprFor` abre a permuta por `findFor`, a mesma
   * porta do detalhe. Quem não alcança a permuta continua sem alcançar a cédula.
   */
  @Get(':code/cpr')
  @RequireCapability(CAPABILITY.bartersCprRead)
  async cpr(@CurrentUser() viewer: User, @Param('code') code: string) {
    return toCprJson(await this.bartersService.cprFor(viewer, code));
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
