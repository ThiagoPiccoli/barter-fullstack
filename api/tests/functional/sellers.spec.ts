import { test } from '@japa/runner'
import testUtils from '@adonisjs/core/services/test_utils'
import User from '#models/user'

const admin = () => User.findByOrFail('email', 'admin@barter.com.br')
const joao = () => User.findByOrFail('email', 'joao.silva@barter.com.br')

test.group('Sellers (gestão pelo admin)', (group) => {
  group.each.setup(() => testUtils.db().withGlobalTransaction())

  test('lista de vendedores é restrita ao admin', async ({ client, assert }) => {
    const asSeller = await client.get('/api/v1/sellers').loginAs(await joao())
    asSeller.assertStatus(403)

    const asAdmin = await client.get('/api/v1/sellers').loginAs(await admin())
    asAdmin.assertStatus(200)
    assert.lengthOf(asAdmin.body().data, 5)
    assert.notInclude(
      asAdmin.body().data.map((s: { role: string }) => s.role),
      'admin'
    )
  })

  test('vendedor criado pelo admin loga com a senha padrão', async ({ client, assert }) => {
    const created = await client
      .post('/api/v1/sellers')
      .json({
        fullName: 'Novo Vendedor',
        email: 'novo.vendedor@barter.com.br',
        branch: 'Filial 99',
      })
      .loginAs(await admin())
    created.assertStatus(201)
    assert.equal(created.body().data.role, 'seller')

    const login = await client.post('/api/v1/auth/login').json({
      email: 'novo.vendedor@barter.com.br',
      password: '123456',
    })
    login.assertStatus(200)
  })

  test('e-mail duplicado é rejeitado na edição', async ({ client }) => {
    const seller = await joao()
    const response = await client
      .put(`/api/v1/sellers/${seller.id}`)
      .json({
        fullName: seller.fullName,
        email: 'ana.ferreira@barter.com.br', // já pertence à Ana
        branch: seller.branch,
      })
      .loginAs(await admin())
    response.assertStatus(422)
  })

  test('excluir vendedor deixa a carteira sem dono e preserva permutas', async ({
    client,
    assert,
  }) => {
    const seller = await joao()
    const del = await client.delete(`/api/v1/sellers/${seller.id}`).loginAs(await admin())
    del.assertStatus(204)

    // Antônio Carvalho (id 1) era da carteira do João → fica sem vendedor.
    const producer = await client.get('/api/v1/producers/1').loginAs(await admin())
    assert.isNull(producer.body().data.sellerId)

    // A permuta histórica preserva o nome do vendedor (snapshot).
    const barter = await client.get('/api/v1/barters/PRM-2026-001').loginAs(await admin())
    assert.equal(barter.body().data.sellerName, 'João Silva')
    assert.isNull(barter.body().data.sellerId)
  })

  test('rota de vendedores não gerencia o admin', async ({ client }) => {
    const boss = await admin()
    const response = await client.delete(`/api/v1/sellers/${boss.id}`).loginAs(await admin())
    response.assertStatus(404)
  })
})
