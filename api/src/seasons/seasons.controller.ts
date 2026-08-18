import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  Post,
  UnprocessableEntityException,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import type { User } from '@prisma/client';
import { CurrentUser, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toBarterVersionJson, toSeasonJson } from '../common/serializers';
import { ImportVersionDto, OpenSeasonDto, PublishVersionDto } from './dto/season.dto';
import { SeasonsService } from './seasons.service';

/**
 * Teto da planilha. Uma tabela de fornecedor com milhares de itens não passa de
 * alguns MB; o limite existe para o upload não virar um caminho de exaustão de
 * memória — o arquivo é lido inteiro na RAM (multer em memória).
 */
const SHEET_LIMIT_BYTES = 5 * 1024 * 1024;

/**
 * A SAFRA — a temporada em que o Barter acontece, sobre um grão.
 *
 * Só quem lança o Barter enxerga esta rota: para o consultor, safra é
 * consequência (ele vê a versão vigente em /barter-versions/current).
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

  /** Encerra a safra e a versão vigente dela. */
  @Post(':code/close')
  @RequireCapability(CAPABILITY.barterManage)
  @HttpCode(200)
  async close(@CurrentUser() admin: User, @Param('code') code: string) {
    return toSeasonJson(await this.seasons.close(admin, code), admin);
  }

  /**
   * Publica a próxima versão com a tabela no corpo. O caminho do admin no app
   * é a planilha (`/seasons/:code/versions/import`); este existe para o seed,
   * os testes e integrações que já têm os dados na mão.
   */
  @Post(':code/versions')
  @RequireCapability(CAPABILITY.barterManage)
  async publish(
    @CurrentUser() admin: User,
    @Param('code') code: string,
    @Body() dto: PublishVersionDto,
  ) {
    return toBarterVersionJson(await this.seasons.publish(admin, code, dto), undefined, admin);
  }

  /**
   * Publica a próxima versão a partir da PLANILHA (.xlsx) — o caminho do admin
   * no app. O arquivo traz os insumos; o valor da saca, a vigência e as metas
   * vêm nos campos do formulário.
   */
  @Post(':code/versions/import')
  @RequireCapability(CAPABILITY.barterManage)
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: SHEET_LIMIT_BYTES } }))
  async import(
    @CurrentUser() admin: User,
    @Param('code') code: string,
    @UploadedFile() file: Express.Multer.File | undefined,
    @Body() dto: ImportVersionDto,
  ) {
    if (!file) {
      throw new UnprocessableEntityException('Envie a planilha (.xlsx) com a tabela de valores');
    }
    if (!/\.xlsx$/i.test(file.originalname)) {
      throw new UnprocessableEntityException('O arquivo precisa ser uma planilha .xlsx');
    }
    return toBarterVersionJson(await this.seasons.import(admin, code, file, dto), undefined, admin);
  }
}
