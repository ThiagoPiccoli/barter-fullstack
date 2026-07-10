import { BarterSchema } from '#database/schema'
import { belongsTo, hasMany } from '@adonisjs/lucid/orm'
import type { BelongsTo, HasMany } from '@adonisjs/lucid/types/relations'
import User from '#models/user'
import Producer from '#models/producer'
import BarterItem from '#models/barter_item'

export type BarterStatus = 'pending' | 'approved' | 'denied'

/**
 * Permuta (escambo). Regra central do domínio: primeiro montam-se os INSUMOS
 * retirados (eles formam um custo), depois calcula-se quantas SACAS do grão de
 * pagamento cobrem esse custo — nunca o inverso. O cálculo autoritativo é do
 * servidor (BarterService); os itens guardam snapshots imutáveis de preço.
 */
export default class Barter extends BarterSchema {
  declare status: BarterStatus

  @belongsTo(() => User, { foreignKey: 'sellerId' })
  declare seller: BelongsTo<typeof User>

  @belongsTo(() => Producer, { foreignKey: 'producerId' })
  declare producer: BelongsTo<typeof Producer>

  @hasMany(() => BarterItem, { foreignKey: 'barterId' })
  declare items: HasMany<typeof BarterItem>
}
