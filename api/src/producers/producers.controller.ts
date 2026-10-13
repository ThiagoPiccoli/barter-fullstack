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

  /**
   * O CADASTRO — do admin e do CONSULTOR.
   *
   * A porta é `producersRegister`, e não `producersManage`: o consultor cadastra
   * o cliente novo que ele mesmo trouxe. EM QUE CARTEIRA o produtor nasce é
   * regra sobre o recurso, e mora no service (ver `ownerOnCreate`): o do
   * consultor nasce na carteira dele, e só o admin escolhe outra.
   */
  @Post()
  @RequireCapability(CAPABILITY.producersRegister)
  async store(@CurrentUser() user: User, @Body() dto: ProducerDto) {
    return toProducerJson(await this.producersService.create(user, dto));
  }

  /**
   * A EDIÇÃO — do admin e do CONSULTOR da carteira.
   *
   * A capacidade aqui é `producersEdit`, e não `producersManage`, porque a porta
   * é mais larga que a administração da base: quem visita a fazenda é quem sabe
   * que o telefone mudou e que a área desta safra é outra. O que o consultor
   * NÃO alcança — o produtor de outra carteira e a própria carteira — é regra
   * sobre o RECURSO, e mora no service (ver `assertEditable`): ela depende do
   * que está gravado, e não só de quem pede.
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
