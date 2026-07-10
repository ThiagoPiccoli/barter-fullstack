import vine from '@vinejs/vine'

export const createProductValidator = vine.create({
  name: vine.string().trim().minLength(2).maxLength(120),
  unit: vine.string().trim().minLength(1).maxLength(40),
  type: vine.enum(['grain', 'input'] as const),
  currentPrice: vine.number().positive(),
  requiredPerHa: vine.number().min(0).optional(),
  categoryId: vine.number().positive().nullable().optional(),
})

/** Edição de cadastro (nome/unidade/pasta/exigência). Preço tem rota própria. */
export const updateProductValidator = vine.create({
  name: vine.string().trim().minLength(2).maxLength(120).optional(),
  unit: vine.string().trim().minLength(1).maxLength(40).optional(),
  requiredPerHa: vine.number().min(0).optional(),
  categoryId: vine.number().positive().nullable().optional(),
})

/** Reajuste do valor de referência — sempre gera entrada no histórico. */
export const updatePriceValidator = vine.create({
  price: vine.number().positive(),
})
