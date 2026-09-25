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

  /**
   * A EDIÇÃO — do admin e do CONSULTOR da carteira.
   *
   * A capacidade aqui é `producersEdit`, e não `producersManage`, porque a porta
   * é mais larga que o cadastro: quem visita a fazenda é quem sabe que o
   * telefone mudou. O que o consultor NÃO alcança — o documento, a área
   * cultivável, o regime de Funrural e a carteira — é regra sobre o RECURSO, e
   * mora no service (ver `assertEditable`): ela depende do que está gravado, e
   * não só de quem pede.
   */
  @Put(':id')
  @RequireCapability(CAPABILITY.producersEdit)
  async update(
    @CurrentUser() user: User,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: ProducerDto,
  ) {
    return toProducerJson(await this.producersService.update(user, id, dto));
  }

  @Delete(':id')
  @RequireCapability(CAPABILITY.producersManage)
  @HttpCode(204)
  async destroy(@Param('id', ParseIntPipe) id: number) {
    await this.producersService.delete(id);
  }
}
