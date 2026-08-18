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
import { lensFor, toProductJson, toProductListJson } from '../common/serializers';
import { CreateProductDto, ListProductsQuery, UpdateProductDto } from './dto/product.dto';
import { ProductsService } from './products.service';

@Controller('products')
export class ProductsController {
  constructor(private readonly productsService: ProductsService) {}

  /**
   * Catálogo; filtro opcional ?type=grain|input.
   *
   * SEM a linha do tempo de valores: ela cresce um ponto por produto a cada
   * versão do Barter publicada, e esta rota é pedida a cada login e a cada
   * refresh do app. Vai o resumo (`firstPrice`, `priceHistoryCount`), que é o
   * que a tela de lista usa; a série inteira está em `GET /products/:id`.
   */
  @Get()
  @AnyRole() // o catálogo é comum a todos os papéis
  async index(@CurrentUser() user: User, @Query() query: ListProductsQuery) {
    const lens = lensFor(user);
    return (await this.productsService.list(query)).map((p) => toProductListJson(p, lens));
  }

  /** O produto com a linha do tempo completa — a fonte do relatório de preço. */
  @Get(':id')
  @AnyRole()
  async show(@CurrentUser() user: User, @Param('id', ParseIntPipe) id: number) {
    return toProductJson(await this.productsService.find(id), lensFor(user));
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

  /*
   * NÃO existe mais `PUT /products/:id/price`.
   *
   * Preço deixou de ser atributo do catálogo: ele pertence à VERSÃO do Barter
   * (`PUT /barter-versions/:code/prices/:productId`), que é o acordo publicado.
   * Manter as duas portas abertas deixaria o catálogo e a versão vigente
   * discordarem — e a permuta usa a versão, então o número editado por aqui
   * seria um valor que não vale para nada, exibido como se valesse.
   */

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
