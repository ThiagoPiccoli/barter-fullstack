import { Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import type { InputCategory } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CategoryDto } from './dto/category.dto';

@Injectable()
export class CategoriesService {
  constructor(private readonly prisma: PrismaService) {}

  async list(): Promise<InputCategory[]> {
    return this.prisma.inputCategory.findMany({ orderBy: { id: 'asc' } });
  }

  async create(dto: CategoryDto): Promise<InputCategory> {
    return this.prisma.inputCategory.create({ data: this.normalized(dto) });
  }

  async update(id: number, dto: CategoryDto): Promise<InputCategory> {
    await this.ensureExists(id);
    return this.prisma.inputCategory.update({ where: { id }, data: this.normalized(dto) });
  }

  /** Excluir a pasta desvincula os insumos (FK SetNull) sem apagá-los. */
  async delete(id: number): Promise<void> {
    await this.ensureExists(id);
    await this.prisma.inputCategory.delete({ where: { id } });
  }

  private normalized(dto: CategoryDto): CategoryDto {
    if (dto.ruleType === 'percentOfTotal' && dto.ruleValue > 100) {
      throw new UnprocessableEntityException('O percentual mínimo não pode passar de 100');
    }
    // Sem exigência, o valor da regra não tem significado — normaliza para 0.
    return dto.ruleType === 'none' ? { ...dto, ruleValue: 0 } : dto;
  }

  private async ensureExists(id: number): Promise<void> {
    const category = await this.prisma.inputCategory.findUnique({ where: { id } });
    if (!category) throw new NotFoundException('Registro não encontrado.');
  }
}
