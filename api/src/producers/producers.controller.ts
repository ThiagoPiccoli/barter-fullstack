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
  UseGuards,
} from '@nestjs/common';
import type { User } from '@prisma/client';
import { AdminGuard } from '../common/admin.guard';
import { CurrentUser } from '../common/decorators';
import { toProducerJson } from '../common/serializers';
import { ListProducersQuery, ProducerDto } from './dto/producer.dto';
import { ProducersService } from './producers.service';

@Controller('producers')
export class ProducersController {
  constructor(private readonly producersService: ProducersService) {}

  /** Carteira escopada. Aceita ?consultantId= (admin), ?limit= e ?offset=. */
  @Get()
  async index(@CurrentUser() user: User, @Query() query: ListProducersQuery) {
    return (await this.producersService.listFor(user, query)).map(toProducerJson);
  }

  @Get(':id')
  async show(@CurrentUser() user: User, @Param('id', ParseIntPipe) id: number) {
    return toProducerJson(await this.producersService.findFor(user, id));
  }

  @Post()
  @UseGuards(AdminGuard)
  async store(@Body() dto: ProducerDto) {
    return toProducerJson(await this.producersService.create(dto));
  }

  @Put(':id')
  @UseGuards(AdminGuard)
  async update(@Param('id', ParseIntPipe) id: number, @Body() dto: ProducerDto) {
    return toProducerJson(await this.producersService.update(id, dto));
  }

  @Delete(':id')
  @UseGuards(AdminGuard)
  @HttpCode(204)
  async destroy(@Param('id', ParseIntPipe) id: number) {
    await this.producersService.delete(id);
  }
}
