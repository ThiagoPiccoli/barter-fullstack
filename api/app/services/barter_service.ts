import { DateTime } from 'luxon'
import db from '@adonisjs/lucid/services/db'
import { Exception } from '@adonisjs/core/exceptions'
import BusinessException from '#exceptions/business_exception'
import Barter, { type BarterStatus } from '#models/barter'
import InputCategory from '#models/input_category'
import Producer from '#models/producer'
import Product from '#models/product'
import User from '#models/user'
import {
  MONEY_EPSILON,
  categoryRequired,
  categorySpend,
  inputCost,
  minQuantityFor,
  sacksToCover,
  type PricedInput,
} from '#services/barter_math'

export interface CreateBarterPayload {
  producerId: number
  grainId: number
  inputs: { productId: number; quantity: number }[]
}

/**
 * Regras de negócio da permuta. O servidor é a autoridade: preços saem do
 * banco (nunca do cliente), mínimos por hectare e por categoria travam a
 * criação, e as sacas do grão são calculadas aqui.
 */
export default class BarterService {
  /**
   * Permutas visíveis para o usuário: vendedor enxerga apenas as próprias;
   * admin enxerga todas. Regra de acesso central do domínio.
   */
  async listFor(user: User, filters: { status?: BarterStatus } = {}) {
    const query = Barter.query().preload('items').orderBy('created_at', 'desc')
    if (!user.isAdmin) {
      query.where('seller_id', user.id)
    }
    if (filters.status) {
      query.where('status', filters.status)
    }
    return query
  }

  /** Uma permuta pelo código público, respeitando o escopo do usuário. */
  async findFor(user: User, code: string) {
    const barter = await Barter.query().where('code', code).preload('items').firstOrFail()
    if (!user.isAdmin && barter.sellerId !== user.id) {
      throw new Exception('Você não tem acesso a esta permuta', {
        status: 403,
        code: 'E_FORBIDDEN_BARTER',
      })
    }
    return barter
  }

  /**
   * Registra uma permuta para um produtor da carteira do vendedor. Fluxo:
   * 1. produtor precisa pertencer à carteira de quem registra;
   * 2. todo insumo com exigência por hectare é obrigatório, no mínimo
   *    `taxa × área` (o app pré-preenche, o servidor confere);
   * 3. as regras de mínimo das categorias precisam estar satisfeitas;
   * 4. o custo é precificado com os valores vigentes do banco e convertido em
   *    sacas do grão de pagamento — o item de grão é criado pelo servidor.
   */
  async create(seller: User, payload: CreateBarterPayload) {
    if (seller.isAdmin) {
      throw new Exception('Permutas são registradas pelo vendedor da carteira', {
        status: 403,
        code: 'E_FORBIDDEN_ADMIN_CREATE',
      })
    }

    const producer = await Producer.find(payload.producerId)
    if (!producer) {
      throw new BusinessException('Produtor não encontrado')
    }
    if (producer.sellerId !== seller.id) {
      throw new Exception('Este produtor não pertence à sua carteira', {
        status: 403,
        code: 'E_FORBIDDEN_WALLET',
      })
    }

    const grain = await Product.find(payload.grainId)
    if (!grain || grain.type !== 'grain') {
      throw new BusinessException('Escolha um grão de pagamento válido')
    }
    if (grain.currentPrice <= 0) {
      throw new BusinessException(`O grão ${grain.name} está sem valor de referência`)
    }

    // Consolida quantidades por produto (payload pode repetir ids).
    const quantities = new Map<number, number>()
    for (const item of payload.inputs) {
      quantities.set(item.productId, (quantities.get(item.productId) ?? 0) + item.quantity)
    }

    const products = await Product.query()
      .whereIn(
        'id',
        [...quantities.keys()].length > 0 ? [...quantities.keys()] : [0]
      )
      .where('type', 'input')
    if (products.length !== quantities.size) {
      throw new BusinessException('A permuta contém insumos inexistentes')
    }

    const pricedInputs: PricedInput[] = products.map((product) => ({
      productId: product.id,
      quantity: quantities.get(product.id)!,
      unitPrice: product.currentPrice,
      categoryId: product.categoryId,
    }))

    if (pricedInputs.some((item) => item.quantity <= 0)) {
      throw new BusinessException('Quantidades de insumo devem ser maiores que zero')
    }

    // 2. Insumos com exigência por hectare são obrigatórios para a área do produtor.
    const requiredProducts = await Product.query()
      .where('type', 'input')
      .where('required_per_ha', '>', 0)
    for (const product of requiredProducts) {
      const min = minQuantityFor(product.requiredPerHa, producer.areaHa)
      const chosen = quantities.get(product.id) ?? 0
      if (chosen + 0.005 < min) {
        throw new BusinessException(
          `${product.name} exige no mínimo ${min} ${product.unit} para ${producer.areaHa} ha`
        )
      }
    }

    // 3. Regras de mínimo por categoria ("pasta") travam o envio.
    const totalCost = inputCost(pricedInputs)
    if (totalCost <= 0) {
      throw new BusinessException('Escolha ao menos um insumo para retirar')
    }

    const ruledCategories = (await InputCategory.query().whereNot('rule_type', 'none')).filter(
      (category) => category.hasRule
    )
    const unmet = ruledCategories.filter((category) => {
      const required = categoryRequired(category, { totalCost, areaHa: producer.areaHa })
      return required > 0 && categorySpend(pricedInputs, category.id) < required - MONEY_EPSILON
    })
    if (unmet.length > 0) {
      throw new BusinessException(
        `Mínimo da categoria não atingido: ${unmet.map((c) => c.name).join(', ')}`
      )
    }

    // 4. Converte o custo em sacas do grão — o coração do escambo.
    const sacks = sacksToCover(totalCost, grain.currentPrice)

    return db.transaction(async (trx) => {
      const barter = new Barter()
      barter.useTransaction(trx)
      barter.merge({
        code: await this.nextCode(trx),
        sellerId: seller.id,
        sellerName: seller.fullName ?? seller.email,
        sellerBranch: seller.branch ?? '',
        producerId: producer.id,
        producerName: producer.name,
        status: 'pending',
      })
      await barter.save()

      await barter.related('items').createMany([
        {
          productId: grain.id,
          kind: 'grain',
          productName: grain.name,
          unit: grain.unit,
          quantity: sacks,
          unitValue: grain.currentPrice,
        },
        ...products.map((product) => ({
          productId: product.id,
          kind: 'input' as const,
          productName: product.name,
          unit: product.unit,
          quantity: quantities.get(product.id)!,
          unitValue: product.currentPrice,
        })),
      ])

      await barter.load('items')
      return barter
    })
  }

  /**
   * Revisão do admin: aprova ou nega uma permuta pendente, com observação
   * opcional. Grava o snapshot do revisor e o momento da revisão.
   */
  async review(admin: User, code: string, decision: { status: 'approved' | 'denied'; note?: string }) {
    const barter = await Barter.query().where('code', code).preload('items').firstOrFail()
    if (barter.status !== 'pending') {
      throw new BusinessException('Esta permuta já foi revisada')
    }

    barter.merge({
      status: decision.status,
      adminNote: decision.note?.trim() ? decision.note.trim() : null,
      reviewedBy: admin.fullName ?? admin.email,
      reviewedById: admin.id,
      reviewedAt: DateTime.now(),
    })
    await barter.save()
    return barter
  }

  /**
   * Próximo código público no formato PRM-<ano>-NNN, sequencial dentro do ano.
   * Roda dentro da transação de criação para evitar corrida.
   */
  private async nextCode(trx: Parameters<Barter['useTransaction']>[0]) {
    const year = DateTime.now().year
    const prefix = `PRM-${year}-`
    const rows = await trx.from('barters').where('code', 'like', `${prefix}%`).select('code')
    let max = 0
    for (const row of rows) {
      const sequence = Number.parseInt(String(row.code).slice(prefix.length), 10)
      if (Number.isFinite(sequence) && sequence > max) {
        max = sequence
      }
    }
    return `${prefix}${String(max + 1).padStart(3, '0')}`
  }
}
