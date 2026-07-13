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
import { toCategoryJson } from '../common/serializers';
import { CategoriesService } from './categories.service';
import { CategoryDto } from './dto/category.dto';

@Controller('categories')
export class CategoriesController {
  constructor(private readonly categoriesService: CategoriesService) {}

  @Get()
  async index() {
    return (await this.categoriesService.list()).map(toCategoryJson);
  }

  @Post()
  @UseGuards(AdminGuard)
  async store(@Body() dto: CategoryDto) {
    return toCategoryJson(await this.categoriesService.create(dto));
  }

  @Put(':id')
  @UseGuards(AdminGuard)
  async update(@Param('id', ParseIntPipe) id: number, @Body() dto: CategoryDto) {
    return toCategoryJson(await this.categoriesService.update(id, dto));
  }

  @Delete(':id')
  @UseGuards(AdminGuard)
  @HttpCode(204)
  async destroy(@Param('id', ParseIntPipe) id: number) {
    await this.categoriesService.delete(id);
  }
}
