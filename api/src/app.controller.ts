import { Controller, Get } from '@nestjs/common';
import { Public } from './common/decorators';

@Controller()
export class AppController {
  /** Raiz fora do prefixo /api/v1 — só um "sinal de vida" da API. */
  @Public()
  @Get()
  root() {
    return { name: 'Barter API', docs: '/api/v1' };
  }
}
