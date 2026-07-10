import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Linha do tempo dos valores de referência de cada produto. O nome de quem
 * alterou fica desnormalizado (changed_by) para o histórico sobreviver à
 * exclusão do usuário; changed_by_id mantém o vínculo enquanto ele existir.
 */
export default class extends BaseSchema {
  protected tableName = 'price_history_entries'

  async up() {
    this.schema.createTable(this.tableName, (table) => {
      table.increments('id').notNullable()
      table
        .integer('product_id')
        .unsigned()
        .notNullable()
        .references('id')
        .inTable('products')
        .onDelete('CASCADE')
      table.decimal('price', 12, 2).notNullable()
      table.string('changed_by').notNullable()
      table
        .integer('changed_by_id')
        .unsigned()
        .nullable()
        .references('id')
        .inTable('users')
        .onDelete('SET NULL')
      // Momento de negócio do reajuste (mock/seeds têm datas próprias).
      table.timestamp('changed_at').notNullable()

      table.timestamp('created_at').notNullable()
      table.timestamp('updated_at').nullable()
    })
  }

  async down() {
    this.schema.dropTable(this.tableName)
  }
}
