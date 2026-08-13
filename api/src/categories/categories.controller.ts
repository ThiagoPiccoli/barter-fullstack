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
} from '@nestjs/common';
import { AnyRole, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toCategoryJson } from '../common/serializers';
import { CategoriesService } from './categories.service';
import { CategoryDto } from './dto/category.dto';

@Controller('categories')
export class CategoriesController {
  constructor(private readonly categoriesService: CategoriesService) {}

  @Get()
  @AnyRole() // as pastas são comuns a todos os papéis
  async index() {
    return (await this.categoriesService.list()).map(toCategoryJson);
  }

  @Post()
  @RequireCapability(CAPABILITY.catalogManage)
  async store(@Body() dto: CategoryDto) {
    return toCategoryJson(await this.categoriesService.create(dto));
  }

  @Put(':id')
  @RequireCapability(CAPABILITY.catalogManage)
  async update(@Param('id', ParseIntPipe) id: number, @Body() dto: CategoryDto) {
    return toCategoryJson(await this.categoriesService.update(id, dto));
  }

  @Delete(':id')
  @RequireCapability(CAPABILITY.catalogManage)
  @HttpCode(204)
  async destroy(@Param('id', ParseIntPipe) id: number) {
    await this.categoriesService.delete(id);
  }
}
