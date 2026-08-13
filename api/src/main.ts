import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { bootstrapAdmin } from '../prisma/bootstrap-admin';
import { seedIfEmpty } from '../prisma/seed-if-empty';
import { AppModule } from './app.module';
import { setupApp } from './app.setup';
import { PrismaService } from './prisma/prisma.service';
import { setupSwagger, swaggerEnabled } from './swagger';

async function bootstrap() {
  const logger = new Logger('Bootstrap');
  // O parser de corpo é registrado no setupApp, com limite explícito.
  const app = await NestFactory.create(AppModule, { bodyParser: false });
  setupApp(app);
  if (swaggerEnabled()) setupSwagger(app);

  const prisma = app.get(PrismaService);
  if (process.env.NODE_ENV === 'production') {
    // Em produção o dataset de demonstração NUNCA roda: ele criaria contas com
    // senha pública num servidor exposto. O primeiro admin vem do ambiente.
    const result = await bootstrapAdmin(prisma);
    if (result === 'created') {
      logger.log(
        `Admin inicial criado (${process.env.ADMIN_EMAIL}) — troque a senha no primeiro login.`,
      );
    } else if (result === 'missing-env') {
      logger.warn(
        'Banco vazio e sem ADMIN_EMAIL/ADMIN_PASSWORD definidos: nenhum usuário foi criado. ' +
          'Defina as duas variáveis e reinicie para provisionar o primeiro acesso.',
      );
    }
  } else {
    // Conveniência de dev: se o banco estiver vazio, carrega o dataset de
    // demonstração automaticamente. Bancos já populados não são tocados.
    const seeded = await seedIfEmpty(prisma);
    if (seeded) {
      logger.log('Banco vazio — dataset de demonstração carregado (senha: 123456).');
    }
  }

  await app.listen(process.env.PORT ?? 3333);
  const url = await app.getUrl();
  logger.log(`Barter API no ar: ${url}`);
  if (swaggerEnabled()) logger.log(`Documentação: ${url}/api/v1/docs`);
}
void bootstrap();
