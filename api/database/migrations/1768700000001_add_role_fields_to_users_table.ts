import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Papéis do domínio: `admin` gerencia valores, cadastros e revisa permutas;
 * `seller` (vendedor) registra permutas para os produtores da própria carteira.
 * Produtores NÃO logam no app, portanto não são usuários — ver tabela producers.
 */
export default class extends BaseSchema {
  protected tableName = 'users'

  async up() {
    this.schema.alterTable(this.tableName, (table) => {
      table.string('role').notNullable().defaultTo('seller')
      table.string('phone').nullable()
      table.string('branch').nullable()
    })
  }

  async down() {
    this.schema.alterTable(this.tableName, (table) => {
      table.dropColumn('role')
      table.dropColumn('phone')
      table.dropColumn('branch')
    })
  }
}
