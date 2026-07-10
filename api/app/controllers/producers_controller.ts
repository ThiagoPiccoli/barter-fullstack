import type { HttpContext } from '@adonisjs/core/http'
import { Exception } from '@adonisjs/core/exceptions'
import BusinessException from '#exceptions/business_exception'
import Producer from '#models/producer'
import User from '#models/user'
import ProducerTransformer from '#transformers/producer_transformer'
import { createProducerValidator, updateProducerValidator } from '#validators/producer'

export default class ProducersController {
  /**
   * Carteira visível: vendedor enxerga apenas os próprios produtores; admin
   * enxerga todos (com filtro opcional ?sellerId=). É a regra de acesso
   * central que o mock resolvia em producersForSeller().
   */
  async index({ auth, request, serialize }: HttpContext) {
    const user = auth.getUserOrFail()
    const query = Producer.query().orderBy('id')

    if (user.isAdmin) {
      const sellerId = request.input('sellerId')
      if (sellerId) {
        query.where('seller_id', Number(sellerId))
      }
    } else {
      query.where('seller_id', user.id)
    }

    return serialize(ProducerTransformer.transform(await query))
  }

  async show({ auth, params, serialize }: HttpContext) {
    const user = auth.getUserOrFail()
    const producer = await Producer.findOrFail(params.id)
    if (!user.isAdmin && producer.sellerId !== user.id) {
      throw new Exception('Este produtor não pertence à sua carteira', {
        status: 403,
        code: 'E_FORBIDDEN_WALLET',
      })
    }
    return serialize(ProducerTransformer.transform(producer))
  }

  /** Cadastro é ato do admin: todo produtor nasce na carteira de um vendedor. */
  async store({ request, serialize, response }: HttpContext) {
    const payload = await request.validateUsing(createProducerValidator)
    await this.ensureSeller(payload.sellerId)

    const producer = await Producer.create(payload)
    response.status(201)
    return serialize(ProducerTransformer.transform(producer))
  }

  async update({ params, request, serialize }: HttpContext) {
    const producer = await Producer.findOrFail(params.id)
    const payload = await request.validateUsing(updateProducerValidator)
    await this.ensureSeller(payload.sellerId)

    producer.merge(payload)
    await producer.save()
    return serialize(ProducerTransformer.transform(producer))
  }

  /**
   * Exclusão não apaga o histórico: permutas antigas guardam o nome do
   * produtor no próprio registro (snapshot) e o FK vira NULL.
   */
  async destroy({ params, response }: HttpContext) {
    const producer = await Producer.findOrFail(params.id)
    await producer.delete()
    return response.noContent()
  }

  private async ensureSeller(sellerId: number) {
    const seller = await User.find(sellerId)
    if (!seller || seller.role !== 'seller') {
      throw new BusinessException('Escolha um vendedor válido para a carteira')
    }
  }
}
