import { test } from '@japa/runner'
import testUtils from '@adonisjs/core/services/test_utils'
import User from '#models/user'

const admin = () => User.findByOrFail('email', 'admin@barter.com.br')
const joao = () => User.findByOrFail('email', 'joao.silva@barter.com.br')

test.group('Products & Categories', (group) => {
  group.each.setup(() => testUtils.db().withGlobalTransaction())

  test('catálogo traz histórico de valores em ordem cronológica', async ({ client, assert }) => {
    const response = await client.get('/api/v1/products?type=grain').loginAs(await joao())

    response.assertStatus(200)
    const soja = response.body().data.find((p: { name: string }) => p.name === 'Soja')
    assert.equal(soja.currentPrice, 148.5)
    assert.lengthOf(soja.priceHistory, 7)
    assert.equal(soja.priceHistory[0].price, 142.0) // mais antigo primeiro
    assert.equal(soja.priceHistory[6].price, 148.5)
  })

  test('reajuste de valor é do admin e alimenta a linha do tempo', async ({
    client,
    assert,
  }) => {
    const asSeller = await client
      .put('/api/v1/products/1/price')
      .json({ price: 150 })
      .loginAs(await joao())
    asSeller.assertStatus(403)

    const asAdmin = await client
      .put('/api/v1/products/1/price')
      .json({ price: 152.75 })
      .loginAs(await admin())
    asAdmin.assertStatus(200)
    const soja = asAdmin.body().data
    assert.equal(soja.currentPrice, 152.75)
    assert.lengthOf(soja.priceHistory, 8)
    assert.equal(soja.priceHistory[7].changedBy, 'Carlos Mendes')
  })

  test('reajuste não altera permutas antigas (snapshot nos itens)', async ({
    client,
    assert,
  }) => {
    await client.put('/api/v1/products/1/price').json({ price: 999 }).loginAs(await admin())

    const barter = await client.get('/api/v1/barters/PRM-2026-001').loginAs(await admin())
    const grain = barter.body().data.items.find((i: { kind: string }) => i.kind === 'grain')
    assert.equal(grain.unitValue, 148.5)
  })

  test('grão não pertence a categoria (só insumos)', async ({ client }) => {
    const response = await client
      .put('/api/v1/products/1')
      .json({ categoryId: 1 })
      .loginAs(await admin())
    response.assertStatus(422)
  })

  test('percentual de categoria acima de 100 é rejeitado', async ({ client }) => {
    const response = await client
      .post('/api/v1/categories')
      .json({ name: 'Inválida', ruleType: 'percentOfTotal', ruleValue: 120 })
      .loginAs(await admin())
    response.assertStatus(422)
  })

  test('excluir a pasta desvincula os insumos sem apagá-los', async ({ client, assert }) => {
    // Sementes (id 3) tem a Semente Soja (produto 9).
    const del = await client.delete('/api/v1/categories/3').loginAs(await admin())
    del.assertStatus(204)

    const products = await client.get('/api/v1/products?type=input').loginAs(await admin())
    const semente = products
      .body()
      .data.find((p: { name: string }) => p.name.startsWith('Semente Soja'))
    assert.isNull(semente.categoryId)
  })
})
