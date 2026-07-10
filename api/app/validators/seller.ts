import vine from '@vinejs/vine'

/**
 * Vendedores são provisionados pelo ADMIN (não há signup público). A senha é
 * opcional na criação: sem ela, vale a senha padrão de primeira entrada.
 */
export const createSellerValidator = vine.create({
  fullName: vine.string().trim().minLength(2).maxLength(120),
  email: vine
    .string()
    .trim()
    .email()
    .maxLength(254)
    .unique({ table: 'users', column: 'email' }),
  phone: vine.string().trim().maxLength(30).optional(),
  branch: vine.string().trim().minLength(1).maxLength(120),
  password: vine.string().minLength(6).maxLength(64).optional(),
})

/** Edição não troca senha nem papel; e-mail duplicado é conferido no controller. */
export const updateSellerValidator = vine.create({
  fullName: vine.string().trim().minLength(2).maxLength(120),
  email: vine.string().trim().email().maxLength(254),
  phone: vine.string().trim().maxLength(30).optional(),
  branch: vine.string().trim().minLength(1).maxLength(120),
})
