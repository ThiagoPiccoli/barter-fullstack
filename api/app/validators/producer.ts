import vine from '@vinejs/vine'

const fields = {
  name: vine.string().trim().minLength(2).maxLength(120),
  /** Carteira: todo produtor nasce vinculado a um vendedor. */
  sellerId: vine.number().positive(),
  document: vine.string().trim().minLength(3).maxLength(40),
  phone: vine.string().trim().maxLength(30).optional(),
  farmName: vine.string().trim().minLength(2).maxLength(120),
  city: vine.string().trim().minLength(2).maxLength(80),
  /** Área cultivável (ha): base das exigências mínimas de insumo. */
  areaHa: vine.number().positive(),
}

export const createProducerValidator = vine.create(fields)
export const updateProducerValidator = vine.create(fields)
