import { UnprocessableEntityException, ValidationPipe } from '@nestjs/common';
import type { ValidationError } from '@nestjs/common';

/** Primeira mensagem de erro, descendo em erros aninhados (arrays/objetos). */
function firstMessage(errors: ValidationError[]): string {
  for (const error of errors) {
    const constraint = Object.values(error.constraints ?? {})[0];
    if (constraint) return constraint;
    if (error.children?.length) {
      const nested = firstMessage(error.children);
      if (nested) return nested;
    }
  }
  return 'Dados inválidos';
}

/**
 * Pipe global de validação. Erros saem como 422 `{ message: "<primeira>" }` —
 * uma string única, que é o que o app exibe (mesmo contrato da versão
 * anterior). `whitelist` descarta campos não declarados nos DTOs (ex.: preços
 * enviados pelo cliente são simplesmente ignorados).
 */
export function buildValidationPipe(): ValidationPipe {
  return new ValidationPipe({
    whitelist: true,
    transform: true,
    errorHttpStatusCode: 422,
    exceptionFactory: (errors) => new UnprocessableEntityException(firstMessage(errors)),
  });
}
