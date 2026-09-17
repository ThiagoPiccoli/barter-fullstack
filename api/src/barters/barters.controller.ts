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
  Query,
  Res,
  UnprocessableEntityException,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import type { Response } from 'express';
import type { User } from '@prisma/client';
import {
  AnyRole,
  CurrentUser,
  RequireAnyCapability,
  RequireCapability,
} from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toBarterJson, toBarterVersionJson, toCprJson } from '../common/serializers';
import { BartersService, MAX_ATTACHMENT_BYTES, type StoredFile } from './barters.service';
import {
  AttachInvoiceDto,
  BarterOpinionDto,
  ChangeBarterPricesDto,
  CreateBarterDto,
  DecideBarterChangeDto,
  DecideBarterProductDto,
  ForwardBarterDto,
  InvoiceBarterDto,
  ListBartersQuery,
  ReplaceBarterInputsDto,
  RequestBarterChangeDto,
  RequestBarterProductDto,
  ReviewBarterDto,
  SaveBarterNoteDto,
} from './dto/barter.dto';
import { IssueCprDto, RegisterCprDto, SaveCprDto, SignCprDto } from './dto/cpr.dto';

/**
 * O UPLOAD de um anexo, configurado em um lugar só.
 *
 * `FileInterceptor` em MEMÓRIA (o padrão do multer sem `storage`): o arquivo
 * chega inteiro na RAM e vai direto para o banco, sem passar por disco. É a
 * mesma escolha da carga da lista de preços (ver seasons.controller.ts), e pelo
 * mesmo motivo — um arquivo temporário em disco é um arquivo que alguém precisa
 * lembrar de apagar.
 *
 * O LIMITE é o do service, e não um número solto aqui: quem sabe quanto pesa um
 * anexo aceitável é o domínio. Ele corta a requisição antes de o corpo inteiro
 * ser recebido; o service confere de novo, e é ELE quem escreve a frase que a
 * pessoa lê (ver `requireAttachable`).
 */
const ATTACHMENT_UPLOAD = FileInterceptor('file', {
  limits: { fileSize: MAX_ATTACHMENT_BYTES },
});

/**
 * Entrega um arquivo guardado como ANEXO (`attachment`), e não inline.
 *
 * `attachment` de propósito: o navegador salva em vez de abrir. Estes arquivos
 * chegaram de fora — quem os enviou foi um usuário —, e abri-los dentro da
 * origem da aplicação é o que transforma um XML enviado por alguém numa página
 * servida pelo nosso domínio. O nome do arquivo vai entre aspas e com as aspas
 * de dentro removidas, que é o que impede um nome de arquivo malicioso de
 * quebrar o cabeçalho.
 */
function sendFile(response: Response, file: StoredFile): void {
  response.setHeader('Content-Type', file.contentType);
  response.setHeader('Content-Length', String(file.size));
  response.setHeader(
    'Content-Disposition',
    `attachment; filename="${file.fileName.replace(/["\\\r\n]/g, '')}"`,
  );
  response.end(Buffer.from(file.content));
}

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
   * O ATENDIMENTO DO PEDIDO NO VALOR — a terceira saída do desvio: em vez de
   * devolver a permuta ao rascunho para corrigir uma linha de R$, o admin
   * corrige a linha e a permuta continua onde está.
   *
   * Ela mora DENTRO de `change-request` no caminho, e isso é a regra: só se
   * altera valor ATENDENDO a um pedido do consultor. Sem pedido em aberto o
   * service recusa — o admin não reprecifica permuta por conta própria, que
   * seria decidir o negócio (ver `CAPABILITY.bartersReview`).
   *
   * A capacidade é a da decisão do pedido, e não uma nova: é a mesma mesa e o
   * mesmo ato, com um desfecho a mais.
   */
  @Post(':code/change-request/prices')
  @RequireCapability(CAPABILITY.bartersChangeReview)
  @HttpCode(200)
  async changePrices(
    @CurrentUser() admin: User,
    @Param('code') code: string,
    @Body() dto: ChangeBarterPricesDto,
  ) {
    return toBarterJson(await this.bartersService.changePrices(admin, code, dto), admin);
  }

  /**
   * O PEDIDO DE FORA DO BARTER — o consultor pede um produto que a tabela da
   * versão não tem (ver `barters/product-request.ts`).
   *
   * `POST` numa COLEÇÃO, ao contrário do pedido de alteração: uma permuta tem
   * vários pedidos de produto, cada um com a própria decisão, e eles convivem
   * sem relação entre si. O de alteração é um de cada vez, e por isso é campo
   * da permuta.
   */
  @Post(':code/product-requests')
  @RequireCapability(CAPABILITY.bartersProductRequest)
  @HttpCode(200)
  async requestProduct(
    @CurrentUser() consultant: User,
    @Param('code') code: string,
    @Body() dto: RequestBarterProductDto,
  ) {
    return toBarterJson(
      await this.bartersService.requestProduct(consultant, code, dto),
      consultant,
    );
  }

  /**
   * A DECISÃO DO ADMIN sobre o pedido de produto: incluir na permuta com o
   * valor acertado, ou recusar com o motivo.
   *
   * O pedido vai pelo id DENTRO da permuta, e o service o lê assim: um id de
   * pedido de outra permuta não encontra nada por aqui.
   */
  @Post(':code/product-requests/:id/decision')
  @RequireCapability(CAPABILITY.bartersProductReview)
  @HttpCode(200)
  async decideProduct(
    @CurrentUser() admin: User,
    @Param('code') code: string,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: DecideBarterProductDto,
  ) {
    return toBarterJson(await this.bartersService.decideProduct(admin, code, id, dto), admin);
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
   * ANEXA UMA NOTA FISCAL — o arquivo e os dados dele, numa requisição só.
   *
   * `multipart/form-data`, e por isso os campos chegam como texto (ver
   * `AttachInvoiceDto`). Uma requisição só, e não "cria a nota e depois sobe o
   * arquivo": as duas metades não fazem sentido separadas, e o caminho de duas
   * chamadas produziria notas sem arquivo toda vez que a segunda falhasse.
   *
   * `POST` numa COLEÇÃO porque são VÁRIAS: a permuta sai em mais de um
   * carregamento, e cada retirada gera a sua nota.
   */
  @Post(':code/invoices')
  @RequireCapability(CAPABILITY.bartersInvoice)
  @UseInterceptors(ATTACHMENT_UPLOAD)
  @HttpCode(200)
  async attachInvoice(
    @CurrentUser() biller: User,
    @Param('code') code: string,
    @Body() dto: AttachInvoiceDto,
    @UploadedFile() file: Express.Multer.File | undefined,
  ) {
    // A ausência do arquivo é conferida AQUI, e não no DTO: ele não vem no corpo
    // JSON, e nenhum decorator de class-validator o alcança. A frase diz o nome
    // do campo porque quem lê esta recusa é quem está montando a chamada.
    if (!file) {
      throw new UnprocessableEntityException('Anexe o arquivo da nota fiscal (campo "file")');
    }
    return toBarterJson(await this.bartersService.attachInvoice(biller, code, dto, file), biller);
  }

  /**
   * REMOVE uma nota anexada — a cancelada, ou a que subiu trocada.
   *
   * Pelo id DENTRO da permuta, como o pedido de produto: um id de nota de outra
   * permuta não encontra nada por aqui.
   */
  @Delete(':code/invoices/:id')
  @RequireCapability(CAPABILITY.bartersInvoice)
  async removeInvoice(
    @CurrentUser() biller: User,
    @Param('code') code: string,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return toBarterJson(await this.bartersService.removeInvoice(biller, code, id), biller);
  }

  /**
   * O ARQUIVO de uma nota — a única resposta deste controller que não é JSON.
   *
   * `@AnyRole` com escopo no service, como o detalhe da permuta: quem alcança a
   * permuta alcança os documentos dela. É o que permite ao emissor conferir a
   * nota que a cédula cita sem pedir o PDF a ninguém.
   */
  @Get(':code/invoices/:id/file')
  @AnyRole()
  async invoiceFile(
    @CurrentUser() viewer: User,
    @Param('code') code: string,
    @Param('id', ParseIntPipe) id: number,
    @Res() response: Response,
  ) {
    sendFile(response, await this.bartersService.invoiceFile(viewer, code, id));
  }

  /**
   * A CÉDULA DE PRODUTO RURAL desta permuta — o rascunho, o que a permuta já
   * responde, a credora configurada e o que ainda falta.
   *
   * TRÊS PAPÉIS chegam aqui, com perguntas diferentes: o CONSULTOR (para
   * preencher), o EMISSOR (para conferir e emitir) e o ADMIN (para a segunda
   * via). `bartersCprRead` é o portão dos três, e o escopo continua sendo o da
   * PERMUTA — `cprFor` abre pela mesma porta do detalhe, e quem não alcança a
   * permuta não alcança a cédula.
   */
  @Get(':code/cpr')
  @RequireCapability(CAPABILITY.bartersCprRead)
  async cpr(@CurrentUser() viewer: User, @Param('code') code: string) {
    return toCprJson(await this.bartersService.cprFor(viewer, code));
  }

  /**
   * Grava o preenchimento da cédula — inteiro ou pela metade.
   *
   * É DO CONSULTOR, e essa é a mudança de dono desta versão. A cédula era
   * preenchida por quem fatura, e nada do que ela pede está na mesa do
   * faturista: a matrícula do imóvel, o nome do cônjuge, o dono da área
   * arrendada e o SCR são o que se traz da visita à fazenda. Ver
   * `bartersCprFill` em policy.ts.
   *
   * `PUT`, e não `PATCH`, porque é o formulário inteiro que a tela devolve; que
   * um campo ausente preserve o valor gravado é decisão do service (ver
   * `saveCpr`), e é o que permite salvar sem ter tudo em mãos.
   */
  @Put(':code/cpr')
  @RequireCapability(CAPABILITY.bartersCprFill)
  async saveCpr(
    @CurrentUser() consultant: User,
    @Param('code') code: string,
    @Body() dto: SaveCprDto,
  ) {
    return toCprJson(await this.bartersService.saveCpr(consultant, code, dto));
  }

  /**
   * O SCR DO PRODUTOR anexado à cédula — obrigatório para ela poder ser emitida.
   *
   * Rota própria, e `multipart`, pelo mesmo motivo da nota: um anexo de
   * megabytes dentro do JSON do formulário faria cada salvamento de rascunho
   * reenviá-lo. `PUT` porque é UM — o SCR novo substitui o anterior, que é uma
   * fotografia vencida.
   *
   * DOIS POSTOS anexam, e é a única escrita da cédula assim. O CONSULTOR porque
   * é ele quem consulta o SCR; e o EMISSOR porque é ele quem fica TRAVADO por
   * ele — a cédula não sai sem o anexo, e "peça ao consultor e espere" é a
   * resposta errada com o produtor sentado na frente. Anexar não é escrever a
   * cédula: o que o emissor não pode é mexer no que ele confere, e o SCR não é
   * afirmação dele sobre o produtor — é o relatório do Banco Central, do jeito
   * que veio.
   */
  @Put(':code/cpr/scr')
  @RequireAnyCapability(CAPABILITY.bartersCprFill, CAPABILITY.bartersCprIssue)
  @UseInterceptors(ATTACHMENT_UPLOAD)
  async saveScr(
    @CurrentUser() actor: User,
    @Param('code') code: string,
    @UploadedFile() file: Express.Multer.File | undefined,
  ) {
    if (!file) {
      throw new UnprocessableEntityException('Anexe o arquivo do SCR (campo "file")');
    }
    return toCprJson(await this.bartersService.saveScr(actor, code, file));
  }

  /** O arquivo do SCR. Mesma porta do anexo da nota — ver `invoiceFile`. */
  @Get(':code/cpr/scr')
  @RequireCapability(CAPABILITY.bartersCprRead)
  async scrFile(
    @CurrentUser() viewer: User,
    @Param('code') code: string,
    @Res() response: Response,
  ) {
    sendFile(response, await this.bartersService.scrFile(viewer, code));
  }

  /* ── A EMISSÃO: os três atos do emissor ──────────────────────────────── */

  /**
   * EMITE a cédula — o ato que CONFERE.
   *
   * O corpo quase não tem nada de propósito: o emissor não escreve a cédula e
   * não decide o negócio. O que ele faz é ler o que os outros postos produziram
   * contra o que o documento exige, e o que tem lacuna não sai — a recusa é um
   * 422 com a lista por extenso, cada item dizendo com quem ele se resolve.
   */
  @Post(':code/cpr/issue')
  @RequireCapability(CAPABILITY.bartersCprIssue)
  @HttpCode(200)
  async issueCpr(
    @CurrentUser() emitter: User,
    @Param('code') code: string,
    @Body() dto: IssueCprDto,
  ) {
    return toBarterJson(await this.bartersService.issueCpr(emitter, code, dto), emitter);
  }

  /**
   * A COLETA DE ASSINATURAS concluída — o lançamento de um fato de fora, COM O
   * PAPEL.
   *
   * `multipart/form-data` como a nota fiscal, e por isso os campos chegam como
   * texto. Uma requisição só, e não "assine e depois suba o arquivo": as duas
   * metades não fazem sentido separadas — "assinada" sem o papel assinado é um
   * estado afirmando o que o sistema não tem como mostrar.
   */
  @Post(':code/cpr/signatures')
  @RequireCapability(CAPABILITY.bartersCprIssue)
  @UseInterceptors(ATTACHMENT_UPLOAD)
  @HttpCode(200)
  async signCpr(
    @CurrentUser() emitter: User,
    @Param('code') code: string,
    @Body() dto: SignCprDto,
    @UploadedFile() file: Express.Multer.File | undefined,
  ) {
    // Conferido AQUI, e não no DTO: o arquivo não vem no corpo, e nenhum
    // decorator de class-validator o alcança. Ver `attachInvoice`.
    if (!file) {
      throw new UnprocessableEntityException(
        'Anexe a cédula assinada (campo "file") para lançar as assinaturas',
      );
    }
    return toBarterJson(await this.bartersService.signCpr(emitter, code, dto, file), emitter);
  }

  /**
   * O REGISTRO do título, com o número — o fim da linha.
   *
   * O arquivo é OPCIONAL aqui: o que prova o registro é o número, e o cartório
   * devolve a via carimbada quando devolve. Ela entra depois por
   * `PUT :code/cpr/registry-file`.
   */
  @Post(':code/cpr/registration')
  @RequireCapability(CAPABILITY.bartersCprIssue)
  @UseInterceptors(ATTACHMENT_UPLOAD)
  @HttpCode(200)
  async registerCpr(
    @CurrentUser() emitter: User,
    @Param('code') code: string,
    @Body() dto: RegisterCprDto,
    @UploadedFile() file: Express.Multer.File | undefined,
  ) {
    return toBarterJson(await this.bartersService.registerCpr(emitter, code, dto, file), emitter);
  }

  /** A VIA CARIMBADA que chegou depois do ato. Ver `saveCprRegistryFile`. */
  @Put(':code/cpr/registry-file')
  @RequireCapability(CAPABILITY.bartersCprIssue)
  @UseInterceptors(ATTACHMENT_UPLOAD)
  async saveCprRegistryFile(
    @CurrentUser() emitter: User,
    @Param('code') code: string,
    @UploadedFile() file: Express.Multer.File | undefined,
  ) {
    if (!file) {
      throw new UnprocessableEntityException('Anexe o comprovante do registro (campo "file")');
    }
    return toCprJson(await this.bartersService.saveCprRegistryFile(emitter, code, file));
  }

  /**
   * OS ARQUIVOS da cédula — a assinada e a do registro.
   *
   * Mesma porta do SCR e do anexo da nota: `bartersCprRead`, com o escopo da
   * permuta no service. É o que permite ao admin tirar a segunda via da cédula
   * assinada sem pedir o PDF ao emissor.
   */
  @Get(':code/cpr/signed')
  @RequireCapability(CAPABILITY.bartersCprRead)
  async signedCprFile(
    @CurrentUser() viewer: User,
    @Param('code') code: string,
    @Res() response: Response,
  ) {
    sendFile(response, await this.bartersService.signedCprFile(viewer, code));
  }

  @Get(':code/cpr/registry-file')
  @RequireCapability(CAPABILITY.bartersCprRead)
  async cprRegistryFile(
    @CurrentUser() viewer: User,
    @Param('code') code: string,
    @Res() response: Response,
  ) {
    sendFile(response, await this.bartersService.cprRegistryFile(viewer, code));
  }
}
