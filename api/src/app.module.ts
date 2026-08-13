import { Module } from '@nestjs/common';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR, APP_PIPE } from '@nestjs/core';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerGuard } from '@nestjs/throttler';
import { AppController } from './app.controller';
import { AuthGuard } from './auth/auth.guard';
import { AuthModule } from './auth/auth.module';
import { BartersModule } from './barters/barters.module';
import { CategoriesModule } from './categories/categories.module';
import { EnvelopeInterceptor } from './common/envelope.interceptor';
import { AllExceptionsFilter } from './common/exception.filter';
import { throttlerModule } from './common/throttling';
import { buildValidationPipe } from './common/validation';
import { PrismaModule } from './prisma/prisma.module';
import { ProducersModule } from './producers/producers.module';
import { ProductsModule } from './products/products.module';
import { ConsultantsModule } from './consultants/consultants.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    throttlerModule(),
    PrismaModule,
    AuthModule,
    ProducersModule,
    ConsultantsModule,
    CategoriesModule,
    ProductsModule,
    BartersModule,
  ],
  controllers: [AppController],
  providers: [
    // Limite de requisições ANTES da autenticação: um atacante sem token não
    // pode consumir o servidor tentando adivinhar senhas.
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    // Autenticação por token em TODAS as rotas (exceto @Public()).
    { provide: APP_GUARD, useClass: AuthGuard },
    // Envelope { data: ... } — contrato esperado pelo app Flutter.
    { provide: APP_INTERCEPTOR, useClass: EnvelopeInterceptor },
    // Validação: 422 com a primeira mensagem; whitelist descarta campos extras.
    { provide: APP_PIPE, useValue: buildValidationPipe() },
    // Rede de segurança: todo erro sai como { message, statusCode }, e o que
    // for bug nosso vira log com id em vez de detalhe interno na resposta.
    { provide: APP_FILTER, useClass: AllExceptionsFilter },
  ],
})
export class AppModule {}
