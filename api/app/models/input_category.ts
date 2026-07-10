import { InputCategorySchema } from '#database/schema'
import { hasMany } from '@adonisjs/lucid/orm'
import type { HasMany } from '@adonisjs/lucid/types/relations'
import Product from '#models/product'

/**
 * Regra de mínimo de uma "pasta" de insumos:
 * - none:           só agrupa, sem exigência
 * - percentOfTotal: a pasta deve representar >= ruleValue % do custo total
 * - valuePerHa:     a pasta deve somar >= ruleValue R$ × área (ha) do produtor
 */
export type CategoryRuleType = 'none' | 'percentOfTotal' | 'valuePerHa'

/**
 * "Pasta" de insumos (ex.: Defensivos, Fertilizantes). A regra de mínimo é o
 * valor VIGENTE, editável pelo admin a cada período; enquanto o mínimo não é
 * atingido, o envio da permuta é bloqueado (validado no BarterService).
 */
export default class InputCategory extends InputCategorySchema {
  declare ruleType: CategoryRuleType

  @hasMany(() => Product, { foreignKey: 'categoryId' })
  declare products: HasMany<typeof Product>

  get hasRule() {
    return this.ruleType !== 'none' && this.ruleValue > 0
  }
}
