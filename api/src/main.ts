import { NestFactory } from '@nestjs/core';
import { bootstrapAdmin } from '../prisma/bootstrap-admin';
import { seedIfEmpty } from '../prisma/seed-if-empty';
import { AppModule } from './app.module';
import { setupApp } from './app.setup';
import { PrismaService } from './prisma/prisma.service';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  setupApp(app);

  const prisma = app.get(PrismaService);
  if (process.env.NODE_ENV === 'production') {
    // Em produção o dataset de demonstração NUNCA roda: ele criaria contas com
    // senha pública num servidor exposto. O primeiro admin vem do ambiente.
    const result = await bootstrapAdmin(prisma);
    if (result === 'created') {
      console.log(`Admin inicial criado (${process.env.ADMIN_EMAIL}) — troque a senha no primeiro login.`);
    } else if (result === 'missing-env') {
      console.warn(
        'Banco vazio e sem ADMIN_EMAIL/ADMIN_PASSWORD definidos: nenhum usuário foi criado. ' +
          'Defina as duas variáveis e reinicie para provisionar o primeiro acesso.',
      );
    }
  } else {
    // Conveniência de dev: se o banco estiver vazio, carrega o dataset de
    // demonstração automaticamente. Bancos já populados não são tocados.
    const seeded = await seedIfEmpty(prisma);
    if (seeded) {
      console.log('Banco vazio — dataset de demonstração carregado (senha: 123456).');
    }
  }

  await app.listen(process.env.PORT ?? 3333);
  console.log(`Barter API no ar: ${await app.getUrl()}`);
}
void bootstrap();
