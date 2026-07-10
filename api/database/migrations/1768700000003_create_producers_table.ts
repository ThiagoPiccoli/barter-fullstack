import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Produtor (cliente) designado nas permutas. Não loga no app. Pertence à
 * CARTEIRA de exatamente um vendedor (seller_id): o vendedor só enxerga os
 * produtores da própria carteira; o admin enxerga todos.
 *
 * seller_id é SET NULL na exclusão do vendedor: o produtor fica "sem carteira"
 * até o admin realocá-lo (mesma semântica do app).
 */
export default class extends BaseSchema {
  protected tableName = 'producers'

  async up() {
    this.schema.createTable(this.tableName, (table) => {
      table.increments('id').notNullable()
      table.string('name').notNullable()
      table
        .integer('seller_id')
        .unsigned()
        .nullable()
        .references('id')
        .inTable('users')
        .onDelete('SET NULL')
      table.string('document').notNullable()
      table.string('phone').nullable()
      table.string('farm_name').notNullable()
      table.string('city').notNullable()
      // Base de cálculo das exigências mínimas por hectare.
      table.decimal('area_ha', 12, 2).notNullable()

      table.timestamp('created_at').notNullable()
      table.timestamp('updated_at').nullable()
    })
  }

  async down() {
    this.schema.dropTable(this.tableName)
  }
}
