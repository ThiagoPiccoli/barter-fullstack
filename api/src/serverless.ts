import { NestFactory } from '@nestjs/core';
import { ExpressAdapter } from '@nestjs/platform-express';
import express, { type Express, type Request, type Response } from 'express';
import { AppModule } from './app.module';
import { setupApp } from './app.setup';

/**
 * A API COMO FUNÇÃO — o que a Vercel executa a cada requisição.
 *
 * Este arquivo mora em `src/` e é compilado pelo `tsc` (via `nest build`), e
 * isso não é arrumação: a função que a Vercel empacota (`api/index.js`) é um
 * arquivo trivial de três linhas justamente para NÃO passar por aqui. O
 * empacotador dela usa esbuild, que não implementa `emitDecoratorMetadata` — e
 * é dessa metadata que a injeção de dependência do Nest vive. Compilado por
 * esbuild, todo `@Injectable` deste projeto subiria sem saber o que recebe no
 * construtor, e a falha apareceria só em produção, na primeira requisição.
 *
 * O `main.ts` continua sendo o servidor de verdade: ele escuta uma porta, sobe
 * uma vez e fica de pé. Aqui não há porta nem processo permanente — a Vercel
 * chama uma função por requisição —, então o que este arquivo faz é montar o
 * mesmo aplicativo Nest sobre um Express e devolver o Express para ela.
 *
 * O QUE MUDA EM RELAÇÃO AO main.ts, e por quê:
 *
 * - **não semeia nada**. O `main.ts` chama `bootstrapAdmin` (produção) ou
 *   `seedIfEmpty` (desenvolvimento) na subida. Aqui isso seria uma escrita no
 *   banco a cada instância fria, disparada por uma requisição qualquer, sem
 *   ninguém olhando o log — e num ambiente onde as instâncias sobem e descem
 *   sozinhas. Quem provisiona é o `npm run provision`, rodado à mão, contra um
 *   banco que a pessoa vê na tela antes de confirmar;
 * - **não chama `listen`**. Quem escuta é a plataforma;
 * - **guarda o app entre invocações**. Montar o Nest custa segundos; a Vercel
 *   reaproveita o processo enquanto ele estiver quente, e é a `promise` que fica
 *   guardada, não o resultado — duas requisições que cheguem juntas na mesma
 *   instância fria esperam o MESMO arranque em vez de dispararem dois.
 *
 * O `setupApp` é o mesmo dos outros dois caminhos (servidor e testes e2e): os
 * cabeçalhos de segurança, o prefixo `/api/v1`, o CORS e o `trust proxy` valem
 * aqui exatamente como valem lá. Repare que TRUST_PROXY não é opcional nesta
 * hospedagem — a Vercel é um proxy por definição, e sem ela o limite por IP
 * contaria o mundo inteiro como um cliente só (ver o aviso em app.setup.ts).
 */

let cached: Promise<Express> | undefined;

async function bootstrap(): Promise<Express> {
  const server = express();
  // `bodyParser: false` espelha o main.ts e os testes: quem registra o parser,
  // com limite explícito, é o setupApp.
  const app = await NestFactory.create(AppModule, new ExpressAdapter(server), {
    bodyParser: false,
  });
  setupApp(app);
  await app.init();
  return server;
}

/** O Express pronto, montado uma vez por instância. */
export function app(): Promise<Express> {
  cached ??= bootstrap();
  return cached;
}

export default async function handler(request: Request, response: Response): Promise<void> {
  const server = await app();
  server(request, response);
}
