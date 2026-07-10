import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Produtos da permuta, nos dois papéis do escambo:
 * - type=input: insumo que o produtor RETIRA (forma o custo da permuta)
 * - type=grain: grão com que ele PAGA (sacas calculadas a partir do custo)
 *
 * current_price é o valor de referência (R$) definido pelo admin — a "taxa de
 * câmbio" da permuta. Toda alteração gera um registro em price_history_entries.
 */
export default class extends BaseSchema {
  protected tableName = 'products'

  async up() {
    this.schema.createTable(this.tableName, (table) => {
      table.increments('id').notNullable()
      table.string('name').notNullable()
      table.string('unit').notNullable()
      table.string('type').notNullable() // grain | input
      table.decimal('current_price', 12, 2).notNullable()
      // Exigência mínima por hectare (0 = sem exigência). Só faz sentido p/ insumos.
      table.decimal('required_per_ha', 12, 2).notNullable().defaultTo(0)
      table
        .integer('category_id')
        .unsigned()
        .nullable()
        .references('id')
        .inTable('input_categories')
        .onDelete('SET NULL')

      table.timestamp('created_at').notNullable()
      table.timestamp('updated_at').nullable()
    })
  }

  async down() {
    this.schema.dropTable(this.tableName)
  }
}
