import { Body, Controller, Get, Put } from '@nestjs/common';
import type { User } from '@prisma/client';
import { CurrentUser, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toCreditorJson } from '../common/serializers';
import { CreditorService } from './creditor.service';
import { CreditorDto } from './dto/creditor.dto';

/**
 * A CREDORA — cadastro ÚNICO, na rota no singular.
 *
 * Sem `:id` e sem DELETE, pelo mesmo desenho do `/committee`: uma instalação
 * serve uma empresa. Duas credoras cadastradas fariam a cédula ter de escolher,
 * e nada no documento diz qual.
 *
 * As duas rotas são de `creditor.manage` — do ADMIN e do FATURISTA. O segundo
 * está aí de propósito: a credora é o timbre dos documentos que ele emite, e
 * quem percebe o CNPJ com um dígito trocado é quem monta a cédula. Não é
 * decisão de negócio nem concessão de acesso, que são as duas coisas que este
 * sistema mantém longe de quem opera.
 */
@Controller('creditor')
export class CreditorController {
  constructor(private readonly creditor: CreditorService) {}

  @Get()
  @RequireCapability(CAPABILITY.creditorManage)
  async show() {
    return toCreditorJson(await this.creditor.get());
  }

  @Put()
  @RequireCapability(CAPABILITY.creditorManage)
  async update(@CurrentUser() actor: User, @Body() dto: CreditorDto) {
    return toCreditorJson(await this.creditor.save(actor, dto));
  }
}
