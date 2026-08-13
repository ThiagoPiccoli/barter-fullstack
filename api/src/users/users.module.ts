import { Module } from '@nestjs/common';
import { BillersController } from './billers.controller';
import { CommitteeController } from './committee.controller';
import { ConsultantsController } from './consultants.controller';
import { ManagersController } from './managers.controller';
import { UserProvisioningService } from './user-provisioning.service';

/**
 * Gestão de USUÁRIOS pelo admin — não existe signup público.
 *
 * Uma rota por papel (quatro controllers), um motor só
 * ([user-provisioning.service.ts](./user-provisioning.service.ts)). Papel novo
 * = um controller de ~50 linhas aqui dentro; regra nova de provisionamento =
 * um lugar só para mudar.
 *
 * `admin` não tem controller de propósito — ver `ManagedRole` em
 * common/roles.ts.
 */
@Module({
  controllers: [ConsultantsController, ManagersController, CommitteeController, BillersController],
  providers: [UserProvisioningService],
})
export class UsersModule {}
