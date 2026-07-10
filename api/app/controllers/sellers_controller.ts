import type { HttpContext } from '@adonisjs/core/http'
import BusinessException from '#exceptions/business_exception'
import User from '#models/user'
import UserTransformer from '#transformers/user_transformer'
import { createSellerValidator, updateSellerValidator } from '#validators/seller'

/**
 * Senha padrão de primeira entrada quando o admin não define uma na criação.
 * Deve ser trocada pelo vendedor (fluxo futuro de troca de senha).
 */
const DEFAULT_PASSWORD = '123456'

/** Gestão de VENDEDORES pelo admin — não existe signup público. */
export default class SellersController {
  async index({ serialize }: HttpContext) {
    const sellers = await User.query().where('role', 'seller').orderBy('id')
    return serialize(UserTransformer.transform(sellers))
  }

  async store({ request, serialize, response }: HttpContext) {
    const { password, ...payload } = await request.validateUsing(createSellerValidator)
    const seller = await User.create({
      ...payload,
      password: password ?? DEFAULT_PASSWORD,
      role: 'seller',
    })
    response.status(201)
    return serialize(UserTransformer.transform(seller))
  }

  async update({ params, request, serialize }: HttpContext) {
    const seller = await this.findSeller(params.id)
    const payload = await request.validateUsing(updateSellerValidator)

    const emailTaken = await User.query()
      .where('email', payload.email)
      .whereNot('id', seller.id)
      .first()
    if (emailTaken) {
      throw new BusinessException('Este e-mail já está em uso por outro usuário')
    }

    seller.merge(payload)
    await seller.save()
    return serialize(UserTransformer.transform(seller))
  }

  /**
   * Excluir um vendedor não apaga permutas (snapshot + FK NULL) e deixa os
   * produtores da carteira "sem vendedor" até o admin realocá-los.
   */
  async destroy({ params, response }: HttpContext) {
    const seller = await this.findSeller(params.id)
    await seller.delete()
    return response.noContent()
  }

  /** Só registros role=seller passam por aqui — admin não se gerencia nesta rota. */
  private async findSeller(id: string | number) {
    return User.query().where('id', id).where('role', 'seller').firstOrFail()
  }
}
