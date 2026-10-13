import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  Post,
  Put,
  UnprocessableEntityException,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import type { User } from '@prisma/client';
import { CurrentUser, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toBarterVersionJson, toSeasonJson } from '../common/serializers';
import {
  ImportVersionDto,
  InsurancePolicyDto,
  OpenSeasonDto,
  PublishVersionDto,
} from './dto/season.dto';
import { SeasonsService } from './seasons.service';

/**
 * Teto da planilha. Uma tabela de fornecedor com milhares de itens não passa de
 * alguns MB; o limite existe para o upload não virar um caminho de exaustão de
 * memória — o arquivo é lido inteiro na RAM (multer em memória).
 */
const SHEET_LIMIT_BYTES = 5 * 1024 * 1024;

/**
 * A SAFRA DA CULTURA — "Soja 26/27", "Canola 2027" — e as versões dela.
 *
 * Só quem lança o Barter enxerga esta rota: para o consultor, safra é
 * consequência (ele vê as versões vigentes em /barter-versions/current).
 *
 * O `:slug` é o código sem a barra (`SOJA2627`): a barra de `SOJA26/27` não
 * cabe numa URL.
 */
@Controller('seasons')
export class SeasonsController {
  constructor(private readonly seasons: SeasonsService) {}

  @Get()
  @RequireCapability(CAPABILITY.barterManage)
  async index(@CurrentUser() user: User) {
    return (await this.seasons.listSeasons()).map((season) => toSeasonJson(season, user));
  }

  @Post()
  @RequireCapability(CAPABILITY.barterManage)
  async store(@CurrentUser() admin: User, @Body() dto: OpenSeasonDto) {
    return toSeasonJson(await this.seasons.open(admin, dto), admin);
  }

  /** Encerra a safra da cultura e a versão vigente dela. As outras culturas seguem. */
  @Post(':slug/close')
  @RequireCapability(CAPABILITY.barterManage)
  @HttpCode(200)
  async close(@CurrentUser() admin: User, @Param('slug') slug: string) {
    return toSeasonJson(await this.seasons.close(admin, slug), admin);
  }

  /** Reabre a safra encerrada — versões novas voltam a poder sair nela. */
  @Post(':slug/reopen')
  @RequireCapability(CAPABILITY.barterManage)
  @HttpCode(200)
  async reopen(@CurrentUser() admin: User, @Param('slug') slug: string) {
    return toSeasonJson(await this.seasons.reopen(admin, slug), admin);
  }

  /**
   * O SEGURO PADRÃO da cultura — o que vem preenchido ao publicar a próxima
   * versão. `PUT` porque é um estado que se declara.
   */
  @Put(':slug/insurance')
  @RequireCapability(CAPABILITY.barterManage)
  async insurance(
    @CurrentUser() admin: User,
    @Param('slug') slug: string,
    @Body() dto: InsurancePolicyDto,
  ) {
    return toSeasonJson(await this.seasons.setSeasonInsurance(admin, slug, dto.policy), admin);
  }

  /**
   * Publica a próxima versão com a tabela no corpo. O caminho do admin no app
   * é a planilha (`/seasons/:slug/versions/import`); este existe para o seed,
   * os testes e integrações que já têm os dados na mão.
   */
  @Post(':slug/versions')
  @RequireCapability(CAPABILITY.barterManage)
  async publish(
    @CurrentUser() admin: User,
    @Param('slug') slug: string,
    @Body() dto: PublishVersionDto,
  ) {
    return toBarterVersionJson(await this.seasons.publish(admin, slug, dto), undefined, admin);
  }

  /**
   * Publica a próxima versão a partir da PLANILHA (.xlsx) DA CULTURA — o
   * caminho do admin no app. O arquivo traz os insumos; a cotação da saca, a
   * produtividade, o vencimento, o seguro, a vigência e as metas vêm nos campos
   * do formulário.
   */
  @Post(':slug/versions/import')
  @RequireCapability(CAPABILITY.barterManage)
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: SHEET_LIMIT_BYTES } }))
  async import(
    @CurrentUser() admin: User,
    @Param('slug') slug: string,
    @UploadedFile() file: Express.Multer.File | undefined,
    @Body() dto: ImportVersionDto,
  ) {
    if (!file) {
      throw new UnprocessableEntityException('Envie a planilha (.xlsx) com a tabela de valores');
    }
    if (!/\.xlsx$/i.test(file.originalname)) {
      throw new UnprocessableEntityException('O arquivo precisa ser uma planilha .xlsx');
    }
    return toBarterVersionJson(await this.seasons.import(admin, slug, file, dto), undefined, admin);
  }
}
