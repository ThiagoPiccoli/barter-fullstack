import { IsIn, IsOptional } from 'class-validator';
import { PaginationQuery } from '../../common/pagination';
import { AUDIT_ACTION } from '../audit.service';

const ACTIONS = Object.values(AUDIT_ACTION);
const TARGET_TYPES = ['user', 'barter', 'season', 'version', 'session'];

/** Filtros da trilha. Investigar é filtrar: "quem mexeu em conta", "o que foi decidido". */
export class ListAuditLogsQuery extends PaginationQuery {
  @IsOptional()
  @IsIn(ACTIONS, { message: `O parâmetro "action" precisa ser um de: ${ACTIONS.join(', ')}` })
  action?: string;

  @IsOptional()
  @IsIn(TARGET_TYPES, {
    message: `O parâmetro "targetType" precisa ser um de: ${TARGET_TYPES.join(', ')}`,
  })
  targetType?: string;
}
