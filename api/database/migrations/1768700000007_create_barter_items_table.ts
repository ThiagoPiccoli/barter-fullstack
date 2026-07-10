import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Itens de uma permuta. kind=input é insumo retirado; kind=grain é o grão de
 * pagamento (normalmente um único item, criado pelo servidor). Nome, unidade e
 * valor unitário são snapshots do momento da permuta: reajustes futuros de
 * preço não podem alterar permutas já registradas.
 */
export default class extends BaseSchema {
  protected tableName = 'barter_items'

  async up() {
    this.schema.createTable(this.tableName, (table) => {
      table.increments('id').notNullable()
      table
        .integer('barter_id')
        .unsigned()
        .notNullable()
        .references('id')
        .inTable('barters')
        .onDelete('CASCADE')
      table
        .integer('product_id')
        .unsigned()
        .nullable()
        .references('id')
        .inTable('products')
        .onDelete('SET NULL')

      table.string('kind').notNullable() // grain | input
      table.string('product_name').notNullable()
      table.string('unit').notNullable()
      // Sacas do grão são fracionárias (ex.: 251.4142) — 4 casas decimais.
      table.decimal('quantity', 16, 4).notNullable()
      table.decimal('unit_value', 12, 2).notNullable()

      table.timestamp('created_at').notNullable()
      table.timestamp('updated_at').nullable()
    })
  }

  async down() {
    this.schema.dropTable(this.tableName)
  }
}
