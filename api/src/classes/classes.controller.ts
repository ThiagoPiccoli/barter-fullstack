import { Body, Controller, Get, Param, ParseIntPipe, Put } from '@nestjs/common';
import { AnyRole, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toProductClassJson } from '../common/serializers';
import { ClassesService } from './classes.service';
import { ClassRuleDto } from './dto/class.dto';

/**
 * As classes de produto. Só duas rotas: ler a lista (todo mundo precisa dela —
 * o consultor vê o progresso do mínimo por classe ao montar a permuta) e
 * ajustar a REGRA de uma delas.
 *
 * Não existe POST nem DELETE. A lista é fixa; se um dia o negócio ganhar uma
 * classe nova, ela entra por migration, junto com a decisão de o que fazer com
 * os produtos que já estão classificados.
 */
@Controller('classes')
export class ClassesController {
  constructor(private readonly classes: ClassesService) {}

  @Get()
  @AnyRole()
  async index() {
    return (await this.classes.list()).map((productClass) => toProductClassJson(productClass));
  }

  @Put(':id/rule')
  @RequireCapability(CAPABILITY.catalogManage)
  async updateRule(@Param('id', ParseIntPipe) id: number, @Body() dto: ClassRuleDto) {
    return toProductClassJson(await this.classes.updateRule(id, dto));
  }
}
