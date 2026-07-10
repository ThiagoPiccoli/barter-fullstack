import { test } from '@japa/runner'
import testUtils from '@adonisjs/core/services/test_utils'

test.group('Auth', (group) => {
  group.each.setup(() => testUtils.db().withGlobalTransaction())

  test('login devolve token e o papel do usuário', async ({ client, assert }) => {
    const response = await client.post('/api/v1/auth/login').json({
      email: 'joao.silva@barter.com.br',
      password: '123456',
    })

    response.assertStatus(200)
    assert.exists(response.body().data.token)
    assert.equal(response.body().data.user.role, 'seller')
    assert.equal(response.body().data.user.fullName, 'João Silva')
  })

  test('senha errada não loga', async ({ client }) => {
    const response = await client.post('/api/v1/auth/login').json({
      email: 'joao.silva@barter.com.br',
      password: 'senha-errada',
    })
    response.assertStatus(400)
  })

  test('rotas autenticadas exigem token', async ({ client }) => {
    const response = await client.get('/api/v1/me')
    response.assertStatus(401)
  })

  test('não existe signup público', async ({ client }) => {
    const response = await client.post('/api/v1/auth/signup').json({
      email: 'intruso@barter.com.br',
      password: '12345678',
    })
    response.assertStatus(404)
  })
})
