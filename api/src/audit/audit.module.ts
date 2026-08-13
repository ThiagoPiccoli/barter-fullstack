import { Global, Module } from '@nestjs/common';
import { AuditController } from './audit.controller';
import { AuditService } from './audit.service';

/**
 * Global: a trilha é transversal. Provisionamento e revisão de permuta vivem
 * em módulos diferentes e os dois precisam gravar — sem isto, cada um teria
 * que importar o módulo, e o que se esquece de importar é o que deixa de
 * auditar.
 */
@Global()
@Module({
  controllers: [AuditController],
  providers: [AuditService],
  exports: [AuditService],
})
export class AuditModule {}
