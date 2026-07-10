import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Permuta (escambo): o produtor retira insumos (itens kind=input, que formam o
 * custo) e paga com UM grão (item kind=grain, com as sacas calculadas pelo
 * servidor para cobrir exatamente o custo).
 *
 * Nomes de vendedor/filial/produtor ficam desnormalizados: a permuta é um
 * registro histórico e não pode mudar se o cadastro for editado ou excluído
 * (mesma regra que o app já documentava). Os FKs seguem SET NULL.
 */
export default class extends BaseSchema {
  protected tableName = 'barters'

  async up() {
    this.schema.createTable(this.tableName, (table) => {
      table.increments('id').notNullable()
      // Código público e estável (ex.: PRM-2026-001) — é o id exibido no app.
      table.string('code').notNullable().unique()

      table
        .integer('seller_id')
        .unsigned()
        .nullable()
        .references('id')
        .inTable('users')
        .onDelete('SET NULL')
      table
        .integer('producer_id')
        .unsigned()
        .nullable()
        .references('id')
        .inTable('producers')
        .onDelete('SET NULL')

      // Snapshots imutáveis das partes no momento da permuta.
      table.string('seller_name').notNullable()
      table.string('seller_branch').notNullable().defaultTo('')
      table.string('producer_name').notNullable()

      table.string('status').notNullable().defaultTo('pending') // pending | approved | denied
      table.text('admin_note').nullable()
      table.string('reviewed_by').nullable() // snapshot do nome do revisor
      table
        .integer('reviewed_by_id')
        .unsigned()
        .nullable()
        .references('id')
        .inTable('users')
        .onDelete('SET NULL')
      table.timestamp('reviewed_at').nullable()

      table.timestamp('created_at').notNullable()
      table.timestamp('updated_at').nullable()
    })
  }

  async down() {
    this.schema.dropTable(this.tableName)
  }
}
