import vine from '@vinejs/vine'

/**
 * Registro de permuta. Repare que NÃO há preços no payload: o cliente escolhe
 * produtos e quantidades; quem precifica e calcula as sacas é o servidor.
 */
export const createBarterValidator = vine.create({
  producerId: vine.number().positive(),
  grainId: vine.number().positive(),
  inputs: vine
    .array(
      vine.object({
        productId: vine.number().positive(),
        quantity: vine.number().positive(),
      })
    )
    .minLength(1),
})

export const reviewBarterValidator = vine.create({
  status: vine.enum(['approved', 'denied'] as const),
  note: vine.string().trim().maxLength(500).optional(),
})
