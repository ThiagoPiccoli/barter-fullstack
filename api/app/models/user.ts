import { UserSchema } from '#database/schema'
import hash from '@adonisjs/core/services/hash'
import { compose } from '@adonisjs/core/helpers'
import { withAuthFinder } from '@adonisjs/auth/mixins/lucid'
import { type AccessToken, DbAccessTokensProvider } from '@adonisjs/auth/access_tokens'
import { hasMany } from '@adonisjs/lucid/orm'
import type { HasMany } from '@adonisjs/lucid/types/relations'
import Producer from '#models/producer'
import Barter from '#models/barter'

export type UserRole = 'admin' | 'seller'

/**
 * Usuário que loga no app: `admin` (gerencia valores/cadastros e revisa
 * permutas) ou `seller` (vendedor, registra permutas para a própria carteira).
 * Produtores não são usuários — ver [Producer].
 */
export default class User extends compose(UserSchema, withAuthFinder(hash)) {
  static accessTokens = DbAccessTokensProvider.forModel(User)
  declare currentAccessToken?: AccessToken

  declare role: UserRole

  /** Carteira: produtores que só este vendedor atende (admin enxerga todas). */
  @hasMany(() => Producer, { foreignKey: 'sellerId' })
  declare wallet: HasMany<typeof Producer>

  /** Permutas registradas por este vendedor. */
  @hasMany(() => Barter, { foreignKey: 'sellerId' })
  declare barters: HasMany<typeof Barter>

  get isAdmin() {
    return this.role === 'admin'
  }

  get initials() {
    const [first, last] = this.fullName ? this.fullName.split(' ') : this.email.split('@')
    if (first && last) {
      return `${first.charAt(0)}${last.charAt(0)}`.toUpperCase()
    }
    return `${first.slice(0, 2)}`.toUpperCase()
  }
}
