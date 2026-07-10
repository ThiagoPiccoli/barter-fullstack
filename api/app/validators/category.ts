import vine from '@vinejs/vine'

/**
 * "Pasta" de insumos e sua regra de mínimo vigente. A coerência
 * percentual <= 100 é conferida no controller (regra cruzada simples).
 */
export const categoryValidator = vine.create({
  name: vine.string().trim().minLength(2).maxLength(80),
  ruleType: vine.enum(['none', 'percentOfTotal', 'valuePerHa'] as const),
  ruleValue: vine.number().min(0),
})
