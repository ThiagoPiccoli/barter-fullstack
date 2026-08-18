import { Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import type { Prisma, Unit, User } from '@prisma/client';
import { AUDIT_ACTION, AuditService } from '../audit/audit.service';
import { PrismaService } from '../prisma/prisma.service';
import { normalizeName } from '../seasons/product-name';
import { UnitDto } from './dto/unit.dto';

/**
 * As UNIDADES de retirada — os lugares onde o produtor busca os insumos.
 *
 * O cadastro é curto porque a unidade é curta: um nome e uma cidade. Ela não
 * tem dono, não decide fluxo e não escolhe quem analisa a permuta — quem dá o
 * parecer é o gerente do CONSULTOR, e a retirada é combinada com o produtor,
 * podendo ser em qualquer praça.
 *
 * O que ela resolve é o que a filial em texto livre não resolvia: "Filial 02",
 * "filial 02" e "F02" eram três lugares para qualquer lista ou relatório.
 */
@Injectable()
export class UnitsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  /**
   * Todas as unidades, em ordem alfabética.
   *
   * Sem paginação, e pelo mesmo critério do catálogo de classes: a lista tem
   * teto natural (uma cooperativa tem dezenas de unidades) e o app precisa dela
   * inteira — é dela que sai o seletor de retirada da permuta.
   */
  async list(): Promise<Unit[]> {
    return this.prisma.unit.findMany({ orderBy: { name: 'asc' } });
  }

  async find(id: number): Promise<Unit> {
    const unit = await this.prisma.unit.findUnique({ where: { id } });
    if (!unit) throw new NotFoundException('Registro não encontrado.');
    return unit;
  }

  async create(actor: User, dto: UnitDto): Promise<Unit> {
    await this.ensureNameIsFree(dto.name);
    const unit = await this.prisma.unit.create({ data: this.dataOf(dto) });

    await this.audit.record({
      actor,
      action: AUDIT_ACTION.unitCreated,
      targetType: 'unit',
      targetId: unit.id,
      targetLabel: unit.name,
      detail: unit.city,
    });
    return unit;
  }

  async update(actor: User, id: number, dto: UnitDto): Promise<Unit> {
    const before = await this.find(id);
    await this.ensureNameIsFree(dto.name, id);
    const unit = await this.prisma.unit.update({ where: { id }, data: this.dataOf(dto) });

    await this.audit.record({
      actor,
      action: AUDIT_ACTION.unitUpdated,
      targetType: 'unit',
      targetId: unit.id,
      targetLabel: unit.name,
      detail: before.name === unit.name ? undefined : `nome: ${before.name} → ${unit.name}`,
    });
    return unit;
  }

  /**
   * Excluir a unidade NÃO apaga as permutas dela: o vínculo vira NULL e o nome
   * congelado (`Barter.unitName`) mantém o detalhe e o comprovante legíveis —
   * mesma promessa do produtor e do consultor excluídos.
   *
   * E não trava nada do fluxo, porque a unidade não participa dele: uma permuta
   * esperando parecer continua esperando o gerente de quem a registrou, tenha o
   * local de retirada sido excluído ou não.
   */
  async delete(actor: User, id: number): Promise<void> {
    const unit = await this.find(id);
    await this.prisma.unit.delete({ where: { id } });

    await this.audit.record({
      actor,
      action: AUDIT_ACTION.unitDeleted,
      targetType: 'unit',
      targetId: unit.id,
      targetLabel: unit.name,
    });
  }

  /** Campos gravados, com a forma canônica do nome junto. */
  private dataOf(dto: UnitDto): Prisma.UnitUncheckedCreateInput {
    return { name: dto.name, city: dto.city, nameKey: normalizeName(dto.name) };
  }

  /**
   * O índice único do banco é a garantia final, mas ele só sabe dizer "valor
   * repetido". Conferir antes permite a mensagem que o admin entende — e a
   * comparação é sobre a forma canônica: "Filial 02" e "FILIAL 02" são o mesmo
   * lugar, e duas linhas para ele fariam a mesma praça aparecer duas vezes na
   * hora de escolher a retirada.
   */
  private async ensureNameIsFree(name: string, ignoreId?: number): Promise<void> {
    const existing = await this.prisma.unit.findUnique({
      where: { nameKey: normalizeName(name) },
    });
    if (!existing || existing.id === ignoreId) return;
    throw new UnprocessableEntityException(
      `Já existe uma unidade cadastrada como "${existing.name}"`,
    );
  }
}
