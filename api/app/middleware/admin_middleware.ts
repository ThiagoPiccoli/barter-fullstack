import { Exception } from '@adonisjs/core/exceptions'
import type { HttpContext } from '@adonisjs/core/http'
import type { NextFn } from '@adonisjs/core/types/http'

/**
 * Restringe a rota a administradores. Deve vir depois de middleware.auth().
 */
export default class AdminMiddleware {
  async handle(ctx: HttpContext, next: NextFn) {
    const user = ctx.auth.getUserOrFail()
    if (!user.isAdmin) {
      throw new Exception('Apenas administradores podem executar esta ação', {
        status: 403,
        code: 'E_FORBIDDEN_ADMIN',
      })
    }
    return next()
  }
}
