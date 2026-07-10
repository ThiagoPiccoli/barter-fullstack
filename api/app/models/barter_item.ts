import { BarterItemSchema } from '#database/schema'
import { belongsTo } from '@adonisjs/lucid/orm'
import type { BelongsTo } from '@adonisjs/lucid/types/relations'
import Barter from '#models/barter'
import Product from '#models/product'

/** input = insumo retirado; grain = grão de pagamento (criado pelo servidor). */
export type BarterItemKind = 'grain' | 'input'

export default class BarterItem extends BarterItemSchema {
  declare kind: BarterItemKind

  @belongsTo(() => Barter, { foreignKey: 'barterId' })
  declare barter: BelongsTo<typeof Barter>

  @belongsTo(() => Product, { foreignKey: 'productId' })
  declare product: BelongsTo<typeof Product>

  /** Valor total de troca do item (R$) no momento da permuta. */
  get total() {
    return this.quantity * this.unitValue
  }
}
