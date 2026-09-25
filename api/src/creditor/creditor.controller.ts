import { Body, Controller, Get, Put } from '@nestjs/common';
import type { User } from '@prisma/client';
import { CurrentUser, RequireCapability } from '../common/decorators';
import { CAPABILITY } from '../common/policy';
import { toCreditorJson } from '../common/serializers';
import { CreditorService } from './creditor.service';
import { CreditorDto, PledgeMarginDto } from './dto/creditor.dto';

/**
 * A CREDORA — cadastro ÚNICO, na rota no singular.
 *
 * Sem `:id` e sem DELETE, pelo mesmo desenho do `/committee`: uma instalação
 * serve uma empresa. Duas credoras cadastradas fariam a cédula ter de escolher,
 * e nada no documento diz qual.
 *
 * O CADASTRO é de `creditor.manage` — do ADMIN e do EMISSOR. O segundo está aí
 * de propósito: a credora é o timbre dos documentos que ele leva a registro, e
 * quem percebe o CNPJ com um dígito trocado é quem confere a cédula. Não é
 * decisão de negócio nem concessão de acesso, que são as duas coisas que este
 * sistema mantém longe de quem opera.
 *
 * A MARGEM DO PENHOR tem rota À PARTE, e é a exceção que prova a frase acima: ela
 * É decisão de negócio. Uma rota por autoridade, e não um formulário com dois
 * donos — ver `pledgePolicyManage`. É o mesmo desenho de
 * `PUT /seasons/:code/cpr-due-date` e `PUT /barter-versions/:code/estimated-yield`:
 * o campo que tem ciclo ou dono próprio ganha porta própria.
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

  /**
   * A MARGEM DE SEGURANÇA DO PENHOR — só do ADMIN.
   *
   * `PUT` porque é um estado que se declara ("passe a exigir 20%"), como o modo
   * de encerramento da versão. Ela não reescreve permuta já registrada: a margem
   * é congelada no ato do registro, e esta rota vale para o que vier depois.
   */
  @Put('pledge-margin')
  @RequireCapability(CAPABILITY.pledgePolicyManage)
  async pledgeMargin(@CurrentUser() actor: User, @Body() dto: PledgeMarginDto) {
    return toCreditorJson(await this.creditor.setPledgeMargin(actor, dto.pledgeMarginPercent));
  }
}
