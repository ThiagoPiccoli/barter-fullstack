import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * "Pastas" de insumos (ex.: Fertilizantes, Defensivos). Podem carregar uma
 * regra de mínimo que trava o envio da permuta enquanto não for atingida:
 * - percent_of_total: a pasta deve representar >= rule_value % do custo total
 * - value_per_ha:     a pasta deve somar >= rule_value R$ × área (ha) do produtor
 */
export default class extends BaseSchema {
  protected tableName = 'input_categories'

  async up() {
    this.schema.createTable(this.tableName, (table) => {
      table.increments('id').notNullable()
      table.string('name').notNullable()
      table.string('rule_type').notNullable().defaultTo('none')
      table.decimal('rule_value', 12, 2).notNullable().defaultTo(0)

      table.timestamp('created_at').notNullable()
      table.timestamp('updated_at').nullable()
    })
  }

  async down() {
    this.schema.dropTable(this.tableName)
  }
}
