import { ProducerSchema } from '#database/schema'
import { belongsTo, hasMany } from '@adonisjs/lucid/orm'
import type { BelongsTo, HasMany } from '@adonisjs/lucid/types/relations'
import User from '#models/user'
import Barter from '#models/barter'

/**
 * Produtor (cliente) designado nas permutas. Não loga no app: é cadastrado
 * pelo admin dentro da CARTEIRA de um vendedor e selecionado por este ao
 * registrar cada permuta. A área (ha) da propriedade é a base de cálculo das
 * exigências mínimas de insumo.
 */
export default class Producer extends ProducerSchema {
  /** Vendedor dono da carteira (null se o vendedor foi excluído). */
  @belongsTo(() => User, { foreignKey: 'sellerId' })
  declare seller: BelongsTo<typeof User>

  @hasMany(() => Barter, { foreignKey: 'producerId' })
  declare barters: HasMany<typeof Barter>

  get initials() {
    const words = this.name.trim().split(/\s+/)
    if (words.length >= 2) {
      return `${words[0].charAt(0)}${words[words.length - 1].charAt(0)}`.toUpperCase()
    }
    return this.name.slice(0, 2).toUpperCase()
  }
}
