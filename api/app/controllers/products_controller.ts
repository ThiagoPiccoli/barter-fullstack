import { DateTime } from 'luxon'
import type { HttpContext } from '@adonisjs/core/http'
import db from '@adonisjs/lucid/services/db'
import BusinessException from '#exceptions/business_exception'
import InputCategory from '#models/input_category'
import Product from '#models/product'
import ProductTransformer from '#transformers/product_transformer'
import {
  createProductValidator,
  updatePriceValidator,
  updateProductValidator,
} from '#validators/product'

export default class ProductsController {
  /**
   * Catálogo com histórico de preços (o app usa o histórico nos gráficos).
   * Filtro opcional ?type=grain|input.
   */
  async index({ request, serialize }: HttpContext) {
    const type = request.input('type')
    const query = Product.query()
      .preload('priceHistory', (history) => history.orderBy('changed_at', 'asc'))
      .orderBy('id')
    if (type === 'grain' || type === 'input') {
      query.where('type', type)
    }
    return serialize(ProductTransformer.transform(await query))
  }

  async show({ params, serialize }: HttpContext) {
    const product = await Product.query()
      .where('id', params.id)
      .preload('priceHistory', (history) => history.orderBy('changed_at', 'asc'))
      .firstOrFail()
    return serialize(ProductTransformer.transform(product))
  }

  async store({ auth, request, serialize, response }: HttpContext) {
    const admin = auth.getUserOrFail()
    const payload = await request.validateUsing(createProductValidator)
    await this.ensureCategory(payload.categoryId ?? null, payload.type)

    const product = await db.transaction(async (trx) => {
      const created = new Product()
      created.useTransaction(trx)
      created.merge({
        name: payload.name,
        unit: payload.unit,
        type: payload.type,
        currentPrice: payload.currentPrice,
        requiredPerHa: payload.requiredPerHa ?? 0,
        categoryId: payload.categoryId ?? null,
      })
      await created.save()

      // Todo produto nasce com o primeiro ponto da linha do tempo de valores.
      await created.related('priceHistory').create({
        price: payload.currentPrice,
        changedBy: admin.fullName ?? admin.email,
        changedById: admin.id,
        changedAt: DateTime.now(),
      })
      await created.load('priceHistory')
      return created
    })

    response.status(201)
    return serialize(ProductTransformer.transform(product))
  }

  async update({ params, request, serialize }: HttpContext) {
    const product = await Product.findOrFail(params.id)
    const payload = await request.validateUsing(updateProductValidator)
    if (payload.categoryId !== undefined) {
      await this.ensureCategory(payload.categoryId, product.type)
    }

    product.merge(payload)
    await product.save()
    await product.load('priceHistory', (history) => history.orderBy('changed_at', 'asc'))
    return serialize(ProductTransformer.transform(product))
  }

  /**
   * Reajuste do valor de referência — a "taxa de câmbio" das novas permutas.
   * Sempre acrescenta um ponto ao histórico; permutas antigas não mudam
   * (guardam snapshot de preço nos itens).
   */
  async updatePrice({ auth, params, request, serialize }: HttpContext) {
    const admin = auth.getUserOrFail()
    const product = await Product.findOrFail(params.id)
    const { price } = await request.validateUsing(updatePriceValidator)

    await db.transaction(async (trx) => {
      product.useTransaction(trx)
      product.currentPrice = price
      await product.save()
      await product.related('priceHistory').create({
        price,
        changedBy: admin.fullName ?? admin.email,
        changedById: admin.id,
        changedAt: DateTime.now(),
      })
    })

    await product.load('priceHistory', (history) => history.orderBy('changed_at', 'asc'))
    return serialize(ProductTransformer.transform(product))
  }

  private async ensureCategory(categoryId: number | null, type: string) {
    if (categoryId === null) {
      return
    }
    if (type !== 'input') {
      throw new BusinessException('Apenas insumos podem pertencer a uma categoria')
    }
    const category = await InputCategory.find(categoryId)
    if (!category) {
      throw new BusinessException('Categoria não encontrada')
    }
  }
}
