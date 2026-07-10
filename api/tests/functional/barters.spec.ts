import { test } from '@japa/runner'
import testUtils from '@adonisjs/core/services/test_utils'
import User from '#models/user'

const admin = () => User.findByOrFail('email', 'admin@barter.com.br')
const joao = () => User.findByOrFail('email', 'joao.silva@barter.com.br')

/**
 * Payload válido para o Antônio Carvalho (120 ha, carteira do João).
 * Mínimos por hectare: 48 sacos NPK (0.4/ha), 300 L glifosato (2.5/ha),
 * 18 L lambda (0.15/ha). Custo: 48×115 + 300×18.9 + 18×42 = R$ 11.946,00.
 */
const validPayload = {
  producerId: 1,
  grainId: 1, // Soja a R$ 148,50
  inputs: [
    { productId: 5, quantity: 48 },
    { productId: 6, quantity: 300 },
    { productId: 7, quantity: 18 },
  ],
}

test.group('Barters', (group) => {
  group.each.setup(() => testUtils.db().withGlobalTransaction())

  test('listagem é escopada: vendedor vê as suas, admin vê todas', async ({
    client,
    assert,
  }) => {
    const asJoao = await client.get('/api/v1/barters').loginAs(await joao())
    asJoao.assertStatus(200)
    assert.sameMembers(
      asJoao.body().data.map((b: { code: string }) => b.code),
      ['PRM-2026-001', 'PRM-2026-005']
    )

    const asAdmin = await client.get('/api/v1/barters').loginAs(await admin())
    assert.lengthOf(asAdmin.body().data, 8)

    const pending = await client.get('/api/v1/barters?status=pending').loginAs(await admin())
    assert.lengthOf(pending.body().data, 3)
  })

  test('vendedor não abre permuta de outro vendedor', async ({ client }) => {
    // PRM-2026-002 é da Ana.
    const response = await client.get('/api/v1/barters/PRM-2026-002').loginAs(await joao())
    response.assertStatus(403)
  })

  test('servidor calcula as sacas para cobrir o custo dos insumos', async ({
    client,
    assert,
  }) => {
    const response = await client.post('/api/v1/barters').json(validPayload).loginAs(await joao())

    response.assertStatus(201)
    const barter = response.body().data
    assert.equal(barter.code, 'PRM-2026-009')
    assert.equal(barter.status, 'pending')
    assert.equal(barter.producerName, 'Antônio Carvalho')

    const grains = barter.items.filter((i: { kind: string }) => i.kind === 'grain')
    assert.lengthOf(grains, 1)
    // 11946 / 148.5 = 80.4444 sacas de soja
    assert.equal(grains[0].quantity, 80.4444)
    assert.equal(grains[0].unitValue, 148.5)
  })

  test('preço enviado pelo cliente é ignorado: quem precifica é o banco', async ({
    client,
    assert,
  }) => {
    const adulterado = {
      ...validPayload,
      inputs: validPayload.inputs.map((i) => ({ ...i, unitValue: 0.01 })),
    }
    const response = await client.post('/api/v1/barters').json(adulterado).loginAs(await joao())

    response.assertStatus(201)
    const npk = response
      .body()
      .data.items.find((i: { productId: number }) => i.productId === 5)
    assert.equal(npk.unitValue, 115.0)
  })

  test('insumo obrigatório por hectare não pode faltar nem ficar abaixo do mínimo', async ({
    client,
  }) => {
    // Sem o NPK (obrigatório: 48 para 120 ha)
    const faltando = await client
      .post('/api/v1/barters')
      .json({ ...validPayload, inputs: validPayload.inputs.slice(1) })
      .loginAs(await joao())
    faltando.assertStatus(422)

    // NPK abaixo do mínimo
    const abaixo = await client
      .post('/api/v1/barters')
      .json({
        ...validPayload,
        inputs: [{ productId: 5, quantity: 10 }, ...validPayload.inputs.slice(1)],
      })
      .loginAs(await joao())
    abaixo.assertStatus(422)
  })

  test('regra de mínimo da categoria trava o envio', async ({ client, assert }) => {
    // Adicionando 30 sacos de semente (R$ 9.600, pasta sem regra), o custo
    // total vai a R$ 21.546 e Fertilizantes cai para 25,6% — abaixo dos 30%.
    const response = await client
      .post('/api/v1/barters')
      .json({
        ...validPayload,
        inputs: [...validPayload.inputs, { productId: 9, quantity: 30 }],
      })
      .loginAs(await joao())

    response.assertStatus(422)
    assert.include(response.body().message, 'Fertilizantes')
  })

  test('produtor precisa pertencer à carteira de quem registra', async ({ client }) => {
    // Helena Prado (id 2) é da carteira da Ana.
    const response = await client
      .post('/api/v1/barters')
      .json({ ...validPayload, producerId: 2 })
      .loginAs(await joao())
    response.assertStatus(403)
  })

  test('admin não registra permuta (ato do vendedor da carteira)', async ({ client }) => {
    const response = await client.post('/api/v1/barters').json(validPayload).loginAs(await admin())
    response.assertStatus(403)
  })

  test('admin aprova pendente com observação e snapshot do revisor', async ({
    client,
    assert,
  }) => {
    const response = await client
      .post('/api/v1/barters/PRM-2026-002/review')
      .json({ status: 'approved', note: 'Tudo certo com o estoque.' })
      .loginAs(await admin())

    response.assertStatus(200)
    const barter = response.body().data
    assert.equal(barter.status, 'approved')
    assert.equal(barter.reviewedBy, 'Carlos Mendes')
    assert.equal(barter.adminNote, 'Tudo certo com o estoque.')
    assert.exists(barter.reviewedAt)
  })

  test('permuta já revisada não pode ser revisada de novo', async ({ client }) => {
    // PRM-2026-001 já está aprovada no dataset.
    const response = await client
      .post('/api/v1/barters/PRM-2026-001/review')
      .json({ status: 'denied' })
      .loginAs(await admin())
    response.assertStatus(422)
  })

  test('vendedor não revisa permuta', async ({ client }) => {
    const response = await client
      .post('/api/v1/barters/PRM-2026-005/review')
      .json({ status: 'approved' })
      .loginAs(await joao())
    response.assertStatus(403)
  })
})
