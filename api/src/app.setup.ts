import type { INestApplication } from '@nestjs/common';

/**
 * Configuração de app compartilhada entre o main.ts e os testes e2e, para o
 * servidor de teste se comportar exatamente como o real. Pipes, guard e
 * interceptor globais são providers do AppModule (valem nos dois contextos).
 */
export function setupApp(app: INestApplication): void {
  app.setGlobalPrefix('api/v1', { exclude: ['/'] });
  app.enableCors();
}
