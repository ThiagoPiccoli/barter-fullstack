import { Module } from '@nestjs/common';
import { BillersController } from './billers.controller';
import { CommitteeController } from './committee.controller';
import { ConsultantsController } from './consultants.controller';
import { EmittersController } from './emitters.controller';
import { ManagersController } from './managers.controller';
import { UserProvisioningService } from './user-provisioning.service';

/**
 * Gestão de USUÁRIOS pelo admin — não existe signup público.
 *
 * Uma rota por papel (cinco controllers), um motor só
 * ([user-provisioning.service.ts](./user-provisioning.service.ts)). Papel novo
 * = um controller de ~50 linhas aqui dentro; regra nova de provisionamento =
 * um lugar só para mudar. O `emitter` acabou de provar isso: ele nasceu inteiro
 * neste módulo com um arquivo e uma linha na lista abaixo.
 *
 * Quatro delas são plurais (`/consultants`, `/managers`, `/billers`,
 * `/emitters`) porque cadastram PESSOAS. A do comitê é singular (`/committee`)
 * porque cadastra um ÓRGÃO: ele é uma reunião, e a conta é uma só — ver o
 * controller.
 *
 * `admin` não tem controller de propósito — ver `ManagedRole` em
 * common/roles.ts.
 */
@Module({
  controllers: [
    ConsultantsController,
    ManagersController,
    CommitteeController,
    BillersController,
    EmittersController,
  ],
  providers: [UserProvisioningService],
})
export class UsersModule {}
