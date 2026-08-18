import { Module } from '@nestjs/common';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR, APP_PIPE } from '@nestjs/core';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerGuard } from '@nestjs/throttler';
import { AppController } from './app.controller';
import { AuditModule } from './audit/audit.module';
import { AuthGuard } from './auth/auth.guard';
import { AuthModule } from './auth/auth.module';
import { BartersModule } from './barters/barters.module';
import { ClassesModule } from './classes/classes.module';
import { EnvelopeInterceptor } from './common/envelope.interceptor';
import { AllExceptionsFilter } from './common/exception.filter';
import { AccessGuard } from './common/access.guard';
import { throttlerModule } from './common/throttling';
import { buildValidationPipe } from './common/validation';
import { PrismaModule } from './prisma/prisma.module';
import { ProducersModule } from './producers/producers.module';
import { ProductsModule } from './products/products.module';
import { SeasonsModule } from './seasons/seasons.module';
import { UnitsModule } from './units/units.module';
import { UsersModule } from './users/users.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    throttlerModule(),
    PrismaModule,
    AuditModule,
    AuthModule,
    ProducersModule,
    UnitsModule,
    UsersModule,
    ClassesModule,
    ProductsModule,
    SeasonsModule,
    BartersModule,
  ],
  controllers: [AppController],
  providers: [
    // Limite de requisições ANTES da autenticação: um atacante sem token não
    // pode consumir o servidor tentando adivinhar senhas.
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    // Autenticação por token em TODAS as rotas (exceto @Public()).
    { provide: APP_GUARD, useClass: AuthGuard },
    // Autorização. Depois do AuthGuard, que é quem resolve o usuário. NEGA
    // por padrão: rota sem política declarada não passa.
    { provide: APP_GUARD, useClass: AccessGuard },
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
