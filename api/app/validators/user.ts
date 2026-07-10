import vine from '@vinejs/vine'

/**
 * Não há signup público neste domínio: vendedores são provisionados pelo
 * admin (ver validators/seller.ts). Aqui fica apenas o login.
 */
export const loginValidator = vine.create({
  email: vine.string().email().maxLength(254),
  password: vine.string(),
})
