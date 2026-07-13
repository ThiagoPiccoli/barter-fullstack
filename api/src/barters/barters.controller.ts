import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import type { User } from '@prisma/client';
import { AdminGuard } from '../common/admin.guard';
import { CurrentUser } from '../common/decorators';
import { toBarterJson } from '../common/serializers';
import { BartersService } from './barters.service';
import { CreateBarterDto, ReviewBarterDto } from './dto/barter.dto';

@Controller('barters')
export class BartersController {
  constructor(private readonly bartersService: BartersService) {}

  /** Listagem escopada (vendedor: as suas; admin: todas), ?status= opcional. */
  @Get()
  async index(@CurrentUser() user: User, @Query('status') status?: string) {
    return (await this.bartersService.listFor(user, status)).map(toBarterJson);
  }

  /** Detalhe pelo código público (ex.: PRM-2026-001). */
  @Get(':code')
  async show(@CurrentUser() user: User, @Param('code') code: string) {
    return toBarterJson(await this.bartersService.findFor(user, code));
  }

  /**
   * Registro de permuta pelo vendedor. O payload traz apenas produtos e
   * quantidades: preços, mínimos e o cálculo das sacas são autoridade do
   * servidor (BartersService).
   */
  @Post()
  async store(@CurrentUser() user: User, @Body() dto: CreateBarterDto) {
    return toBarterJson(await this.bartersService.create(user, dto));
  }

  /** Revisão do admin: aprova/nega uma pendente, com observação opcional. */
  @Post(':code/review')
  @UseGuards(AdminGuard)
  @HttpCode(200)
  async review(
    @CurrentUser() admin: User,
    @Param('code') code: string,
    @Body() dto: ReviewBarterDto,
  ) {
    return toBarterJson(await this.bartersService.review(admin, code, dto));
  }
}
