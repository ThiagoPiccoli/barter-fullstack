import { ProductSchema } from '#database/schema'
import { belongsTo, hasMany } from '@adonisjs/lucid/orm'
import type { BelongsTo, HasMany } from '@adonisjs/lucid/types/relations'
import InputCategory from '#models/input_category'
import PriceHistoryEntry from '#models/price_history_entry'

/** grain = grão de pagamento; input = insumo retirado (origem do custo). */
export type ProductType = 'grain' | 'input'

export default class Product extends ProductSchema {
  declare type: ProductType

  /** "Pasta" do insumo (null se não classificado; só faz sentido p/ insumos). */
  @belongsTo(() => InputCategory, { foreignKey: 'categoryId' })
  declare category: BelongsTo<typeof InputCategory>

  @hasMany(() => PriceHistoryEntry, { foreignKey: 'productId' })
  declare priceHistory: HasMany<typeof PriceHistoryEntry>
}
