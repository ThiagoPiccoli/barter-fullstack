import { Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import type { ProductClass } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ClassRuleDto } from './dto/class.dto';

/**
 * As CLASSES de produto. Lista fixa (ver a migration
 * `20260814140000_classes_fixas_de_produto`): aqui não há create nem delete —
 * de propósito, e não por falta de tempo.
 *
 * Classe é o vocabulário com que a cooperativa fala de mix, exigência mínima e
 * relatório. Enquanto era editável, cada carga de planilha inventava uma pasta
 * nova e o mínimo por classe passava a medir um conjunto diferente a cada
 * versão do Barter — a regra continuava lá, medindo outra coisa.
 */
@Injectable()
export class ClassesService {
  constructor(private readonly prisma: PrismaService) {}

  /** Na ordem em que o negócio lê a lista, não na ordem em que o banco gravou. */
  async list(): Promise<ProductClass[]> {
    return this.prisma.productClass.findMany({ orderBy: [{ position: 'asc' }, { id: 'asc' }] });
  }

  async find(id: number): Promise<ProductClass> {
    const found = await this.prisma.productClass.findUnique({ where: { id } });
    if (!found) throw new NotFoundException('Registro não encontrado.');
    return found;
  }

  /** Define a exigência mínima da classe — a única alteração que ela aceita. */
  async updateRule(id: number, dto: ClassRuleDto): Promise<ProductClass> {
    await this.find(id);
    if (dto.ruleType === 'percentOfTotal' && dto.ruleValue > 100) {
      throw new UnprocessableEntityException('O percentual mínimo não pode passar de 100');
    }
    // Sem exigência, o valor da regra não tem significado — normaliza para 0.
    const ruleValue = dto.ruleType === 'none' ? 0 : dto.ruleValue;
    return this.prisma.productClass.update({
      where: { id },
      data: { ruleType: dto.ruleType, ruleValue },
    });
  }
}
