import { Controller, Get, Query } from '@nestjs/common';
import { RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toAuditLogJson } from '../common/serializers';
import { AuditService } from './audit.service';
import { ListAuditLogsQuery } from './dto/audit.dto';

/**
 * Leitura da trilha. Uma auditoria que ninguém consegue ler é meia auditoria:
 * o valor dela está em conseguir responder "quem redefiniu a senha do fulano
 * na semana passada?" sem abrir o banco na mão.
 *
 * Só leitura, de propósito — não há rota que edite nem apague linha da trilha.
 */
@Controller('audit-logs')
export class AuditController {
  constructor(private readonly audit: AuditService) {}

  /** Mais recentes primeiro. Aceita ?action=, ?targetType=, ?limit= e ?offset=. */
  @Get()
  @RequireCapability(CAPABILITY.auditRead)
  async index(@Query() query: ListAuditLogsQuery) {
    return (await this.audit.list(query)).map(toAuditLogJson);
  }
}
