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
} from '@nestjs/common';
import type { User } from '@prisma/client';
import { AnyRole, CurrentUser, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toProducerJson } from '../common/serializers';
import { ListProducersQuery, ProducerDto } from './dto/producer.dto';
import { ProducersService } from './producers.service';

@Controller('producers')
export class ProducersController {
  constructor(private readonly producersService: ProducersService) {}

  /** Carteira escopada. Aceita ?consultantId= (admin), ?limit= e ?offset=. */
  @Get()
  @AnyRole() // escopo por linha: consultor vê a própria carteira (service)
  async index(@CurrentUser() user: User, @Query() query: ListProducersQuery) {
    return (await this.producersService.listFor(user, query)).map(toProducerJson);
  }

  @Get(':id')
  @AnyRole() // idem: o service recusa produtor de carteira alheia
  async show(@CurrentUser() user: User, @Param('id', ParseIntPipe) id: number) {
    return toProducerJson(await this.producersService.findFor(user, id));
  }

  @Post()
  @RequireCapability(CAPABILITY.producersManage)
  async store(@Body() dto: ProducerDto) {
    return toProducerJson(await this.producersService.create(dto));
  }

  @Put(':id')
  @RequireCapability(CAPABILITY.producersManage)
  async update(@Param('id', ParseIntPipe) id: number, @Body() dto: ProducerDto) {
    return toProducerJson(await this.producersService.update(id, dto));
  }

  @Delete(':id')
  @RequireCapability(CAPABILITY.producersManage)
  @HttpCode(204)
  async destroy(@Param('id', ParseIntPipe) id: number) {
    await this.producersService.delete(id);
  }
}
