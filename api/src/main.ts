import { NestFactory } from '@nestjs/core';
import { seedIfEmpty } from '../prisma/seed-if-empty';
import { AppModule } from './app.module';
import { setupApp } from './app.setup';
import { PrismaService } from './prisma/prisma.service';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  setupApp(app);

  // Conveniência de dev: se o banco estiver vazio, carrega o dataset de
  // demonstração automaticamente. Bancos já populados não são tocados.
  const seeded = await seedIfEmpty(app.get(PrismaService));
  if (seeded) {
    console.log('Banco vazio — dataset de demonstração carregado (senha: 123456).');
  }

  await app.listen(process.env.PORT ?? 3333);
  console.log(`Barter API no ar: ${await app.getUrl()}`);
}
void bootstrap();
