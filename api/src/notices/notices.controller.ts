import { Controller, Get, HttpCode, Param, ParseIntPipe, Post } from '@nestjs/common';
import type { User } from '@prisma/client';
import { AnyRole, CurrentUser } from '../common/decorators';
import { toNoticeJson } from '../common/serializers';
import { NoticesService } from './notices.service';

/**
 * OS AVISOS de quem está logado.
 *
 * `@AnyRole` nas duas rotas: todo mundo pode ter aviso, e o recorte é a própria
 * pessoa — quem confere é o service, que só lê e só dispensa os dela.
 */
@Controller('notices')
export class NoticesController {
  constructor(private readonly notices: NoticesService) {}

  /** Os avisos ainda não vistos, do mais novo para o mais antigo. */
  @Get()
  @AnyRole()
  async index(@CurrentUser() user: User) {
    return (await this.notices.unreadFor(user)).map(toNoticeJson);
  }

  /** Dispensa um aviso — ele some do painel. */
  @Post(':id/read')
  @AnyRole()
  @HttpCode(200)
  async read(@CurrentUser() user: User, @Param('id', ParseIntPipe) id: number) {
    return toNoticeJson(await this.notices.markRead(user, id));
  }
}
