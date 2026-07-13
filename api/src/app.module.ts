import { Module } from '@nestjs/common';
import { APP_GUARD, APP_INTERCEPTOR, APP_PIPE } from '@nestjs/core';
import { ConfigModule } from '@nestjs/config';
import { AppController } from './app.controller';
import { AuthGuard } from './auth/auth.guard';
import { AuthModule } from './auth/auth.module';
import { BartersModule } from './barters/barters.module';
import { CategoriesModule } from './categories/categories.module';
import { EnvelopeInterceptor } from './common/envelope.interceptor';
import { buildValidationPipe } from './common/validation';
import { PrismaModule } from './prisma/prisma.module';
import { ProducersModule } from './producers/producers.module';
import { ProductsModule } from './products/products.module';
import { SellersModule } from './sellers/sellers.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    PrismaModule,
    AuthModule,
    ProducersModule,
    SellersModule,
    CategoriesModule,
    ProductsModule,
    BartersModule,
  ],
  controllers: [AppController],
  providers: [
    // Autenticação por token em TODAS as rotas (exceto @Public()).
    { provide: APP_GUARD, useClass: AuthGuard },
    // Envelope { data: ... } — contrato esperado pelo app Flutter.
    { provide: APP_INTERCEPTOR, useClass: EnvelopeInterceptor },
    // Validação: 422 com a primeira mensagem; whitelist descarta campos extras.
    { provide: APP_PIPE, useValue: buildValidationPipe() },
  ],
})
export class AppModule {}
