import { inject } from '@adonisjs/core'
import type { HttpContext } from '@adonisjs/core/http'
import BarterService from '#services/barter_service'
import BarterTransformer from '#transformers/barter_transformer'
import { createBarterValidator, reviewBarterValidator } from '#validators/barter'

@inject()
export default class BartersController {
  constructor(private barterService: BarterService) {}

  /** Listagem escopada (vendedor: as suas; admin: todas), ?status= opcional. */
  async index({ auth, request, serialize }: HttpContext) {
    const status = request.input('status')
    const barters = await this.barterService.listFor(auth.getUserOrFail(), {
      status: ['pending', 'approved', 'denied'].includes(status) ? status : undefined,
    })
    return serialize(BarterTransformer.transform(barters))
  }

  /** Detalhe pelo código público (ex.: PRM-2026-001). */
  async show({ auth, params, serialize }: HttpContext) {
    const barter = await this.barterService.findFor(auth.getUserOrFail(), params.code)
    return serialize(BarterTransformer.transform(barter))
  }

  /**
   * Registro de permuta pelo vendedor. O payload traz apenas produtos e
   * quantidades: preços, mínimos e o cálculo das sacas são autoridade do
   * servidor (BarterService).
   */
  async store({ auth, request, serialize, response }: HttpContext) {
    const payload = await request.validateUsing(createBarterValidator)
    const barter = await this.barterService.create(auth.getUserOrFail(), payload)
    response.status(201)
    return serialize(BarterTransformer.transform(barter))
  }

  /** Revisão do admin: aprova/nega uma pendente, com observação opcional. */
  async review({ auth, params, request, serialize }: HttpContext) {
    const decision = await request.validateUsing(reviewBarterValidator)
    const barter = await this.barterService.review(auth.getUserOrFail(), params.code, decision)
    return serialize(BarterTransformer.transform(barter))
  }
}
