import type { INestApplication } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';

/**
 * Documentação navegável em /api/v1/docs (e o JSON em /api/v1/docs-json).
 *
 * Serve para responder sozinho "o que esta API aceita?" — hoje a resposta está
 * espalhada pelos DTOs. O plugin do @nestjs/swagger (ver nest-cli.json) lê os
 * tipos e os comentários dos DTOs na compilação, então os campos aparecem
 * documentados sem uma segunda cópia das regras dentro de decorators.
 *
 * Em produção fica FECHADA por padrão: um mapa completo das rotas é presente
 * demais para quem estiver sondando o servidor. Ligue com SWAGGER=on quando
 * quiser expô-la de propósito.
 */
export function swaggerEnabled(): boolean {
  const configured = process.env.SWAGGER?.trim().toLowerCase();
  if (configured === 'on' || configured === 'true') return true;
  if (configured === 'off' || configured === 'false') return false;
  return process.env.NODE_ENV !== 'production';
}

export function setupSwagger(app: INestApplication): void {
  const config = new DocumentBuilder()
    .setTitle('Barter API')
    .setDescription(
      'Permuta de grãos por insumos. Os insumos retirados formam um custo em R$ ' +
        'e esse custo é convertido em sacas do grão de pagamento — quem calcula é ' +
        'o servidor, nunca o cliente.\n\n' +
        'Toda resposta de sucesso vem envelopada em `{ "data": ... }`; as listas ' +
        'paginadas trazem também `meta` com `total`, `limit` e `offset`.',
    )
    .setVersion('1.0')
    .addBearerAuth(
      { type: 'http', scheme: 'bearer', description: 'Token opaco devolvido por POST /auth/login' },
      'bearer',
    )
    .build();

  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('api/v1/docs', app, document, {
    swaggerOptions: { persistAuthorization: true },
  });
}
