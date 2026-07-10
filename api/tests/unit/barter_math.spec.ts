import { test } from '@japa/runner'
import {
  categoryRequired,
  categorySpend,
  inputCost,
  minQuantityFor,
  sacksToCover,
  type PricedInput,
} from '#services/barter_math'

/**
 * O coração do escambo: insumos formam um custo e o custo vira sacas do grão.
 * Números de referência tirados da permuta PRM-2026-001 do dataset.
 */
test.group('BarterMath', () => {
  const inputs: PricedInput[] = [
    { productId: 5, quantity: 300, unitPrice: 115.0, categoryId: 1 }, // NPK
    { productId: 6, quantity: 150, unitPrice: 18.9, categoryId: 2 }, // Glifosato
  ]

  test('custo dos insumos é a soma de quantidade × preço', ({ assert }) => {
    assert.equal(inputCost(inputs), 37335.0)
    assert.equal(inputCost([]), 0)
  })

  test('sacas do grão cobrem exatamente o custo (4 casas)', ({ assert }) => {
    assert.equal(sacksToCover(37335.0, 148.5), 251.4141)
    assert.equal(sacksToCover(11946.0, 148.5), 80.4444)
  })

  test('grão sem preço não gera sacas (evita divisão por zero)', ({ assert }) => {
    assert.equal(sacksToCover(1000, 0), 0)
    assert.equal(sacksToCover(1000, -5), 0)
  })

  test('gasto por categoria considera apenas os insumos da pasta', ({ assert }) => {
    assert.equal(categorySpend(inputs, 1), 34500.0)
    assert.equal(categorySpend(inputs, 2), 2835.0)
    assert.equal(categorySpend(inputs, 99), 0)
  })

  test('mínimo percentual do total', ({ assert }) => {
    const rule = { ruleType: 'percentOfTotal' as const, ruleValue: 30 }
    assert.equal(categoryRequired(rule, { totalCost: 37335, areaHa: 120 }), 11200.5)
  })

  test('mínimo por hectare multiplica pela área do produtor', ({ assert }) => {
    const rule = { ruleType: 'valuePerHa' as const, ruleValue: 50 }
    assert.equal(categoryRequired(rule, { totalCost: 37335, areaHa: 120 }), 6000)
    assert.equal(
      categoryRequired({ ruleType: 'none', ruleValue: 10 }, { totalCost: 37335, areaHa: 120 }),
      0
    )
  })

  test('quantidade mínima de insumo = taxa por hectare × área', ({ assert }) => {
    assert.equal(minQuantityFor(0.4, 120), 48)
    assert.equal(minQuantityFor(2.5, 120), 300)
    assert.equal(minQuantityFor(0.15, 120), 18)
    assert.equal(minQuantityFor(0, 120), 0)
  })
})
