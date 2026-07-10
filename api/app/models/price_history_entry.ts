import { PriceHistoryEntrySchema } from '#database/schema'
import { belongsTo } from '@adonisjs/lucid/orm'
import type { BelongsTo } from '@adonisjs/lucid/types/relations'
import Product from '#models/product'

/**
 * Um reajuste do valor de referência de um produto. `changedBy` guarda o nome
 * desnormalizado para o histórico sobreviver à exclusão do usuário.
 */
export default class PriceHistoryEntry extends PriceHistoryEntrySchema {
  @belongsTo(() => Product, { foreignKey: 'productId' })
  declare product: BelongsTo<typeof Product>
}
