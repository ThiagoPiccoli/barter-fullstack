import { test } from '@japa/runner'
import testUtils from '@adonisjs/core/services/test_utils'
import User from '#models/user'

const admin = () => User.findByOrFail('email', 'admin@barter.com.br')
const joao = () => User.findByOrFail('email', 'joao.silva@barter.com.br')

test.group('Producers (carteira)', (group) => {
  group.each.setup(() => testUtils.db().withGlobalTransaction())

  test('vendedor enxerga apenas a própria carteira', async ({ client, assert }) => {
    const response = await client.get('/api/v1/producers').loginAs(await joao())

    response.assertStatus(200)
    const names = response.body().data.map((p: { name: string }) => p.name)
    assert.sameMembers(names, ['Antônio Carvalho', 'Sebastião Ramos'])
  })

  test('admin enxerga todas as carteiras e pode filtrar por vendedor', async ({
    client,
    assert,
  }) => {
    const all = await client.get('/api/v1/producers').loginAs(await admin())
    all.assertStatus(200)
    assert.lengthOf(all.body().data, 7)

    const ana = await User.findByOrFail('email', 'ana.ferreira@barter.com.br')
    const filtered = await client
      .get(`/api/v1/producers?sellerId=${ana.id}`)
      .loginAs(await admin())
    const names = filtered.body().data.map((p: { name: string }) => p.name)
    assert.sameMembers(names, ['Helena Prado', 'Cláudia Nunes'])
  })

  test('vendedor não acessa produtor de outra carteira', async ({ client }) => {
    // Helena Prado (id 2) pertence à carteira da Ana.
    const response = await client.get('/api/v1/producers/2').loginAs(await joao())
    response.assertStatus(403)
  })

  test('cadastro de produtor é ato do admin', async ({ client }) => {
    const payload = {
      name: 'Produtor Novo',
      sellerId: (await joao()).id,
      document: 'CPF 999.999.999-99',
      farmName: 'Fazenda Teste',
      city: 'Maringá/PR',
      areaHa: 55,
    }

    const asSeller = await client.post('/api/v1/producers').json(payload).loginAs(await joao())
    asSeller.assertStatus(403)

    const asAdmin = await client.post('/api/v1/producers').json(payload).loginAs(await admin())
    asAdmin.assertStatus(201)
  })

  test('produtor precisa nascer na carteira de um vendedor válido', async ({ client }) => {
    const response = await client
      .post('/api/v1/producers')
      .json({
        name: 'Sem Carteira',
        sellerId: (await admin()).id, // admin não tem carteira
        document: 'CPF 000',
        farmName: 'Fazenda X',
        city: 'Cidade/PR',
        areaHa: 10,
      })
      .loginAs(await admin())
    response.assertStatus(422)
  })
})
