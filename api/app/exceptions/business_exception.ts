import { Exception } from '@adonisjs/core/exceptions'

/**
 * Violação de regra de negócio (HTTP 422). A mensagem é escrita para o usuário
 * final (pt-BR) e exibida diretamente pelo app.
 */
export default class BusinessException extends Exception {
  static status = 422
  static code = 'E_BUSINESS_RULE'
}
