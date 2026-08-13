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
import { toProductJson } from '../common/serializers';
import {
  CreateProductDto,
  ListProductsQuery,
  UpdatePriceDto,
  UpdateProductDto,
} from './dto/product.dto';
import { ProductsService } from './products.service';

@Controller('products')
export class ProductsController {
  constructor(private readonly productsService: ProductsService) {}

  /** Catálogo com histórico de valores; filtro opcional ?type=grain|input. */
  @Get()
  @AnyRole() // o catálogo é comum a todos os papéis
  async index(@Query() query: ListProductsQuery) {
    return (await this.productsService.list(query)).map(toProductJson);
  }

  @Get(':id')
  @AnyRole()
  async show(@Param('id', ParseIntPipe) id: number) {
    return toProductJson(await this.productsService.find(id));
  }

  @Post()
  @RequireCapability(CAPABILITY.catalogManage)
  async store(@CurrentUser() admin: User, @Body() dto: CreateProductDto) {
    return toProductJson(await this.productsService.create(admin, dto));
  }

  @Put(':id')
  @RequireCapability(CAPABILITY.catalogManage)
  async update(@Param('id', ParseIntPipe) id: number, @Body() dto: UpdateProductDto) {
    return toProductJson(await this.productsService.update(id, dto));
  }

  @Put(':id/price')
  @RequireCapability(CAPABILITY.catalogManage)
  async updatePrice(
    @CurrentUser() admin: User,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdatePriceDto,
  ) {
    return toProductJson(await this.productsService.updatePrice(admin, id, dto.price));
  }

  /**
   * Retira o produto do catálogo. As permutas já registradas continuam
   * inteiras (guardam snapshot de nome/unidade/preço nos itens).
   */
  @Delete(':id')
  @RequireCapability(CAPABILITY.catalogManage)
  @HttpCode(204)
  async destroy(@Param('id', ParseIntPipe) id: number) {
    await this.productsService.delete(id);
  }
}
