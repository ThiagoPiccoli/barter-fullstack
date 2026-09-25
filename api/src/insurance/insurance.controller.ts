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
  UnprocessableEntityException,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import type { User } from '@prisma/client';
import { AnyRole, CurrentUser, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { lensFor, toInsuranceRateJson } from '../common/serializers';
import { SeasonsService } from '../seasons/seasons.service';
import { ImportInsuranceRatesDto, InsuranceRateDto } from './dto/insurance-rate.dto';
import { InsuranceService } from './insurance.service';

/**
 * O upload da planilha — o mesmo teto da carga da tabela de valores.
 *
 * A base de seguros é um arquivo da mesma natureza (algumas centenas de linhas
 * de texto), e um limite próprio aqui seria um segundo número para manter em
 * dia sem nenhuma razão de ser diferente.
 */
const SHEET_LIMIT_BYTES = 5 * 1024 * 1024;

/**
 * A BASE DE SEGUROS POR MUNICÍPIO.
 *
 * A LEITURA é aberta a qualquer autenticado, de propósito e pelo mesmo motivo
 * das unidades: o consultor precisa saber quanto o seguro vai custar ao cliente
 * dele antes de fechar a permuta, e a retaguarda precisa conferir a taxa que a
 * permuta congelou. Quem não vê R$ recebe o valor em sacas (ver
 * `toInsuranceRateJson`).
 *
 * A ESCRITA é do admin (`insurance.manage`), por linha ou por planilha.
 */
@Controller('insurance-rates')
export class InsuranceController {
  constructor(
    private readonly insurance: InsuranceService,
    private readonly seasons: SeasonsService,
  ) {}

  /**
   * A base inteira.
   *
   * A LENTE precisa da cotação da saca para converter R$/ha em sacas/ha, e a
   * cotação é a da CULTURA escolhida na versão VIGENTE — a base não pertence a
   * versão nenhuma (é do município), e a saca de hoje é a do Barter aberto
   * agora. Com mais de uma cultura aberta, o mesmo seguro custa duas
   * quantidades de saca diferentes, e quem diz qual interessa é quem chama
   * (`?grainId=`, a cultura que o consultor selecionou); sem escolha, a
   * primeira do lançamento.
   *
   * Sem Barter aberto a conversão não acontece e quem não vê R$ recebe zero:
   * não é permissivo — sem Barter aberto ele não registra permuta nenhuma.
   */
  @Get()
  @AnyRole()
  async index(@CurrentUser() viewer: User, @Query('grainId') grainId?: string) {
    const lens = lensFor(viewer, await this.currentGrainPrice(Number(grainId) || null));
    return (await this.insurance.list()).map((rate) => toInsuranceRateJson(rate, lens));
  }

  @Post()
  @RequireCapability(CAPABILITY.insuranceManage)
  async store(@CurrentUser() admin: User, @Body() dto: InsuranceRateDto) {
    return toInsuranceRateJson(await this.insurance.create(admin, dto));
  }

  @Put(':id')
  @RequireCapability(CAPABILITY.insuranceManage)
  async update(
    @CurrentUser() admin: User,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: InsuranceRateDto,
  ) {
    return toInsuranceRateJson(await this.insurance.update(admin, id, dto));
  }

  @Delete(':id')
  @RequireCapability(CAPABILITY.insuranceManage)
  @HttpCode(204)
  async destroy(@CurrentUser() admin: User, @Param('id', ParseIntPipe) id: number) {
    await this.insurance.delete(admin, id);
  }

  /**
   * A CARGA DA PLANILHA — o caminho do admin quando a cotação chega com dezenas
   * de praças.
   *
   * Devolve a BASE INTEIRA, e não um resumo do que entrou: a tela que acabou de
   * carregar o arquivo é a mesma que lista o cadastro, e o que ela precisa
   * mostrar em seguida é o estado final. No modo `replace`, isso é também a
   * única maneira honesta de responder — o que saiu da base saiu, e um "12
   * linhas atualizadas" esconderia as 40 apagadas.
   */
  @Post('import')
  @RequireCapability(CAPABILITY.insuranceManage)
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: SHEET_LIMIT_BYTES } }))
  async import(
    @CurrentUser() admin: User,
    @UploadedFile() file: Express.Multer.File | undefined,
    @Body() dto: ImportInsuranceRatesDto,
  ) {
    if (!file) {
      throw new UnprocessableEntityException(
        'Envie a planilha (.xlsx) com os municípios e o valor por hectare',
      );
    }
    if (!/\.xlsx$/i.test(file.originalname)) {
      throw new UnprocessableEntityException('O arquivo precisa ser uma planilha .xlsx');
    }
    const report = await this.insurance.import(admin, file, dto);
    return {
      rates: report.rates.map((rate) => toInsuranceRateJson(rate)),
      // O RELATÓRIO da leitura: de qual coluna o valor saiu, quantas praças
      // entraram e quantas linhas de enfeite foram ignoradas. É o que a tela
      // mostra de volta ao admin — a carga decidiu algo em nome dele.
      priceColumn: report.priceColumn,
      imported: report.imported,
      ignored: report.ignored,
    };
  }

  /**
   * A cotação da saca de uma CULTURA do Barter aberto, ou 0 quando não há
   * Barter nenhum.
   *
   * Zero não trava a listagem de propósito: quem vê R$ (a retaguarda inteira)
   * não depende dela, e para o consultor a base sem Barter aberto é informação
   * que ele não vai usar — ele não consegue registrar permuta nenhuma nesse
   * estado. Cultura pedida que não está no lançamento cai na primeira, pelo
   * mesmo desenho de `toBarterVersionJson`.
   */
  private async currentGrainPrice(grainId: number | null): Promise<number> {
    const version = await this.seasons.currentVersion();
    if (!version) return 0;
    const grain = version.grains.find((row) => row.grainId === grainId) ?? version.grains[0];
    return grain?.price ?? 0;
  }
}
