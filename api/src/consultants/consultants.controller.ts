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
  UseGuards,
} from '@nestjs/common';
import { AdminGuard } from '../common/admin.guard';
import { toProvisionedConsultantJson, toUserJson } from '../common/serializers';
import { CreateConsultantDto, UpdateConsultantDto } from './dto/consultant.dto';
import { ConsultantsService } from './consultants.service';

@Controller('consultants')
@UseGuards(AdminGuard)
export class ConsultantsController {
  constructor(private readonly consultantsService: ConsultantsService) {}

  @Get()
  async index() {
    return (await this.consultantsService.list()).map(toUserJson);
  }

  /**
   * Provisiona o consultor. A resposta traz `provisionalPassword` UMA ÚNICA
   * VEZ — é o que o admin dita para o consultor entrar. Não há como recuperar
   * esse valor depois; o caminho para isso é o reset abaixo.
   */
  @Post()
  async store(@Body() dto: CreateConsultantDto) {
    return toProvisionedConsultantJson(await this.consultantsService.create(dto));
  }

  @Put(':id')
  async update(@Param('id', ParseIntPipe) id: number, @Body() dto: UpdateConsultantDto) {
    return toUserJson(await this.consultantsService.update(id, dto));
  }

  /**
   * Nova senha provisória para um consultor que perdeu o acesso — ou cuja
   * conta caiu em mãos erradas. Encerra todas as sessões abertas dele.
   */
  @Post(':id/reset-password')
  @HttpCode(200)
  async resetPassword(@Param('id', ParseIntPipe) id: number) {
    return toProvisionedConsultantJson(await this.consultantsService.resetPassword(id));
  }

  @Delete(':id')
  @HttpCode(204)
  async destroy(@Param('id', ParseIntPipe) id: number) {
    await this.consultantsService.delete(id);
  }
}
