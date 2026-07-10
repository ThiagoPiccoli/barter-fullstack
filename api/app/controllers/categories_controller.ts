import type { HttpContext } from '@adonisjs/core/http'
import BusinessException from '#exceptions/business_exception'
import InputCategory from '#models/input_category'
import InputCategoryTransformer from '#transformers/input_category_transformer'
import { categoryValidator } from '#validators/category'

export default class CategoriesController {
  async index({ serialize }: HttpContext) {
    const categories = await InputCategory.query().orderBy('id')
    return serialize(InputCategoryTransformer.transform(categories))
  }

  async store({ request, serialize, response }: HttpContext) {
    const payload = await this.validated(request)
    const category = await InputCategory.create(payload)
    response.status(201)
    return serialize(InputCategoryTransformer.transform(category))
  }

  async update({ params, request, serialize }: HttpContext) {
    const category = await InputCategory.findOrFail(params.id)
    category.merge(await this.validated(request))
    await category.save()
    return serialize(InputCategoryTransformer.transform(category))
  }

  /** Excluir a pasta desvincula os insumos (FK SET NULL) sem apagá-los. */
  async destroy({ params, response }: HttpContext) {
    const category = await InputCategory.findOrFail(params.id)
    await category.delete()
    return response.noContent()
  }

  private async validated(request: HttpContext['request']) {
    const payload = await request.validateUsing(categoryValidator)
    if (payload.ruleType === 'percentOfTotal' && payload.ruleValue > 100) {
      throw new BusinessException('O percentual mínimo não pode passar de 100')
    }
    // Sem exigência, o valor da regra não tem significado — normaliza para 0.
    if (payload.ruleType === 'none') {
      payload.ruleValue = 0
    }
    return payload
  }
}
