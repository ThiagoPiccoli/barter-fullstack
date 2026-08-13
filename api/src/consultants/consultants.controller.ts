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
import { toUserJson } from '../common/serializers';
import { CreateSellerDto, UpdateSellerDto } from './dto/seller.dto';
import { SellersService } from './sellers.service';

@Controller('sellers')
@UseGuards(AdminGuard)
export class SellersController {
  constructor(private readonly sellersService: SellersService) {}

  @Get()
  async index() {
    return (await this.sellersService.list()).map(toUserJson);
  }

  @Post()
  async store(@Body() dto: CreateSellerDto) {
    return toUserJson(await this.sellersService.create(dto));
  }

  @Put(':id')
  async update(@Param('id', ParseIntPipe) id: number, @Body() dto: UpdateSellerDto) {
    return toUserJson(await this.sellersService.update(id, dto));
  }

  @Delete(':id')
  @HttpCode(204)
  async destroy(@Param('id', ParseIntPipe) id: number) {
    await this.sellersService.delete(id);
  }
}
