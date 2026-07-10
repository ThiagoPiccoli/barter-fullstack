import { DateTime } from 'luxon'
import { BaseSeeder } from '@adonisjs/lucid/seeders'
import Barter from '#models/barter'
import InputCategory from '#models/input_category'
import PriceHistoryEntry from '#models/price_history_entry'
import Producer from '#models/producer'
import Product from '#models/product'
import User from '#models/user'

/**
 * Reproduz o conjunto de dados do mock do app (lib/data/mock_data.dart do
 * projeto original) para que a interface integre com a API sem surpresas.
 * Senha de todos os usuários: 123456.
 */
export default class extends BaseSeeder {
  async run() {
    // Idempotente: não duplica em re-execuções.
    if (await User.first()) {
      return
    }

    const at = (year: number, month: number, day: number, hour = 0, minute = 0) =>
      DateTime.fromObject({ year, month, day, hour, minute })

    /* ── Usuários ─────────────────────────────────────────────────────── */
    const [admin, joao, ana, roberto, maria, lucas] = await User.createMany([
      {
        fullName: 'Carlos Mendes',
        email: 'admin@barter.com.br',
        password: '123456',
        role: 'admin',
        phone: '(44) 99999-0001',
        branch: 'Matriz',
        createdAt: at(2020, 1, 10),
      },
      {
        fullName: 'João Silva',
        email: 'joao.silva@barter.com.br',
        password: '123456',
        role: 'seller',
        phone: '(44) 99999-0002',
        branch: 'Filial 02 – Gran. Santa T.',
        createdAt: at(2021, 3, 15),
      },
      {
        fullName: 'Ana Paula Ferreira',
        email: 'ana.ferreira@barter.com.br',
        password: '123456',
        role: 'seller',
        phone: '(44) 99999-0003',
        branch: 'Filial 04 – Gran. Inharap.',
        createdAt: at(2021, 6, 20),
      },
      {
        fullName: 'Roberto Souza',
        email: 'roberto.souza@barter.com.br',
        password: '123456',
        role: 'seller',
        phone: '(44) 99999-0004',
        branch: 'Filial 34 – Gran. Jari',
        createdAt: at(2022, 2, 8),
      },
      {
        fullName: 'Maria Oliveira',
        email: 'maria.oliveira@barter.com.br',
        password: '123456',
        role: 'seller',
        phone: '(44) 99999-0005',
        branch: 'Filial 24 – Gran. Oliveira',
        createdAt: at(2022, 9, 1),
      },
      {
        fullName: 'Lucas Barros',
        email: 'lucas.barros@barter.com.br',
        password: '123456',
        role: 'seller',
        phone: '(44) 99999-0006',
        branch: 'Filial 18 – Gran. São Joa.',
        createdAt: at(2023, 1, 15),
      },
    ])

    /* ── Carteiras de produtores ──────────────────────────────────────── */
    const [antonio, helena, joaquim, claudia, sebastiao, vanessa, osmar] =
      await Producer.createMany([
        {
          name: 'Antônio Carvalho',
          sellerId: joao.id,
          document: 'CPF 123.456.789-00',
          phone: '(44) 99800-1001',
          farmName: 'Fazenda Boa Vista',
          city: 'Maringá/PR',
          areaHa: 120,
          createdAt: at(2021, 2, 10),
        },
        {
          name: 'Helena Prado',
          sellerId: ana.id,
          document: 'CPF 234.567.890-11',
          phone: '(44) 99800-1002',
          farmName: 'Sítio das Águas',
          city: 'Sarandi/PR',
          areaHa: 45,
          createdAt: at(2021, 5, 18),
        },
        {
          name: 'Joaquim Tavares',
          sellerId: roberto.id,
          document: 'CNPJ 12.345.678/0001-90',
          phone: '(44) 99800-1003',
          farmName: 'Fazenda Santa Rita',
          city: 'Mandaguari/PR',
          areaHa: 320,
          createdAt: at(2020, 11, 3),
        },
        {
          name: 'Cláudia Nunes',
          sellerId: ana.id,
          document: 'CPF 345.678.901-22',
          phone: '(44) 99800-1004',
          farmName: 'Fazenda Recanto',
          city: 'Marialva/PR',
          areaHa: 80,
          createdAt: at(2022, 3, 21),
        },
        {
          name: 'Sebastião Ramos',
          sellerId: joao.id,
          document: 'CPF 456.789.012-33',
          phone: '(44) 99800-1005',
          farmName: 'Sítio Bela Vista',
          city: 'Paiçandu/PR',
          areaHa: 60,
          createdAt: at(2022, 8, 9),
        },
        {
          name: 'Vanessa Lopes',
          sellerId: lucas.id,
          document: 'CNPJ 23.456.789/0001-01',
          phone: '(44) 99800-1006',
          farmName: 'Fazenda Três Irmãos',
          city: 'Floresta/PR',
          areaHa: 210,
          createdAt: at(2023, 1, 30),
        },
        {
          name: 'Osmar Dutra',
          sellerId: maria.id,
          document: 'CPF 567.890.123-44',
          phone: '(44) 99800-1007',
          farmName: 'Fazenda Alto da Serra',
          city: 'Campo Mourão/PR',
          areaHa: 150,
          createdAt: at(2022, 6, 14),
        },
      ])

    /* ── Pastas de insumos (regras vigentes) ──────────────────────────── */
    const [fertilizantes, defensivos, sementes] = await InputCategory.createMany([
      { name: 'Fertilizantes', ruleType: 'percentOfTotal', ruleValue: 30 },
      { name: 'Defensivos', ruleType: 'percentOfTotal', ruleValue: 10 },
      { name: 'Sementes', ruleType: 'none', ruleValue: 0 },
    ])

    /* ── Produtos + histórico de valores ──────────────────────────────── */
    // Meses do histórico do mock: dez/2025 a jun/2026, sempre dia 5.
    const historyDates = [
      at(2025, 12, 5),
      at(2026, 1, 5),
      at(2026, 2, 5),
      at(2026, 3, 5),
      at(2026, 4, 5),
      at(2026, 5, 5),
      at(2026, 6, 5),
    ]

    const catalog: {
      name: string
      unit: string
      type: 'grain' | 'input'
      prices: number[]
      requiredPerHa?: number
      categoryId?: number
    }[] = [
      { name: 'Soja', unit: 'saca 60kg', type: 'grain', prices: [142.0, 144.5, 145.0, 147.2, 146.8, 149.3, 148.5] },
      { name: 'Milho', unit: 'saca 60kg', type: 'grain', prices: [58.0, 59.5, 60.0, 61.2, 63.0, 62.8, 62.3] },
      { name: 'Trigo', unit: 'saca 60kg', type: 'grain', prices: [80.0, 81.5, 82.5, 84.0, 83.2, 86.1, 85.0] },
      { name: 'Aveia', unit: 'saca 40kg', type: 'grain', prices: [43.0, 43.8, 44.5, 45.2, 44.9, 46.1, 45.8] },
      {
        name: 'Fertilizante NPK 04-14-08',
        unit: 'saco 50kg',
        type: 'input',
        prices: [108.0, 110.5, 112.0, 113.5, 116.2, 114.3, 115.0],
        requiredPerHa: 0.4,
        categoryId: fertilizantes.id,
      },
      {
        name: 'Herbicida Glifosato 480g/L',
        unit: 'litro',
        type: 'input',
        prices: [20.5, 20.1, 19.5, 19.1, 18.4, 18.7, 18.9],
        requiredPerHa: 2.5,
        categoryId: defensivos.id,
      },
      {
        name: 'Inseticida Lambda-cialotrina',
        unit: 'litro',
        type: 'input',
        prices: [39.0, 39.8, 40.5, 41.2, 42.5, 41.6, 42.0],
        requiredPerHa: 0.15,
        categoryId: defensivos.id,
      },
      {
        name: 'Fungicida Azoxistrobina',
        unit: 'litro',
        type: 'input',
        prices: [82.0, 83.5, 85.0, 86.2, 88.1, 86.9, 87.5],
        categoryId: defensivos.id,
      },
      {
        name: 'Semente Soja RR – TMG 7062',
        unit: 'saco 40kg',
        type: 'input',
        prices: [300.0, 305.0, 310.0, 312.0, 318.0, 322.0, 320.0],
        categoryId: sementes.id,
      },
    ]

    const products = await Product.createMany(
      catalog.map((item) => ({
        name: item.name,
        unit: item.unit,
        type: item.type,
        currentPrice: item.prices[item.prices.length - 1],
        requiredPerHa: item.requiredPerHa ?? 0,
        categoryId: item.categoryId ?? null,
      }))
    )

    await PriceHistoryEntry.createMany(
      catalog.flatMap((item, index) =>
        item.prices.map((price, i) => ({
          productId: products[index].id,
          price,
          changedBy: 'Carlos Mendes',
          changedById: admin.id,
          changedAt: historyDates[i],
        }))
      )
    )

    const [soja, milho, trigo, , npk, glifosato, lambda, fungicida, semente] = products

    /* ── Permutas históricas (mesmos números do mock) ─────────────────── */
    type SeedItem = {
      productId: number
      kind: 'grain' | 'input'
      productName: string
      unit: string
      quantity: number
      unitValue: number
    }
    const grainItem = (product: Product, quantity: number, unitValue: number): SeedItem => ({
      productId: product.id,
      kind: 'grain',
      productName: product.name,
      unit: product.unit,
      quantity,
      unitValue,
    })
    const inputItem = (product: Product, quantity: number, unitValue: number): SeedItem => ({
      productId: product.id,
      kind: 'input',
      productName: product.name,
      unit: product.unit,
      quantity,
      unitValue,
    })

    const barters: {
      code: string
      seller: User
      producer: Producer
      status: 'pending' | 'approved' | 'denied'
      createdAt: DateTime
      reviewedAt?: DateTime
      adminNote?: string
      items: SeedItem[]
    }[] = [
      {
        code: 'PRM-2026-001',
        seller: joao,
        producer: antonio,
        status: 'approved',
        createdAt: at(2026, 1, 10, 9, 30),
        reviewedAt: at(2026, 1, 11, 14, 0),
        adminNote: 'Permuta aprovada. Entrega dos grãos confirmada no armazém.',
        items: [
          grainItem(soja, 251.4142, 148.5),
          inputItem(npk, 300, 115.0),
          inputItem(glifosato, 150, 18.9),
        ],
      },
      {
        code: 'PRM-2026-002',
        seller: ana,
        producer: helena,
        status: 'pending',
        createdAt: at(2026, 4, 22, 11, 15),
        items: [
          grainItem(soja, 154.8822, 148.5),
          inputItem(semente, 50, 320.0),
          inputItem(fungicida, 80, 87.5),
        ],
      },
      {
        code: 'PRM-2026-003',
        seller: roberto,
        producer: joaquim,
        status: 'denied',
        createdAt: at(2026, 2, 5, 8, 0),
        reviewedAt: at(2026, 2, 6, 10, 30),
        adminNote: 'Estoque de fertilizante indisponível nesta filial para o período solicitado.',
        items: [grainItem(milho, 276.8861, 62.3), inputItem(npk, 150, 115.0)],
      },
      {
        code: 'PRM-2026-004',
        seller: ana,
        producer: claudia,
        status: 'approved',
        createdAt: at(2026, 3, 1, 10, 0),
        reviewedAt: at(2026, 3, 2, 9, 0),
        adminNote: 'Aprovada.',
        items: [
          grainItem(soja, 358.7879, 148.5),
          inputItem(npk, 400, 115.0),
          inputItem(glifosato, 200, 18.9),
          inputItem(fungicida, 40, 87.5),
        ],
      },
      {
        code: 'PRM-2026-005',
        seller: joao,
        producer: sebastiao,
        status: 'pending',
        createdAt: at(2026, 5, 8, 14, 20),
        items: [
          grainItem(soja, 166.6667, 148.5),
          inputItem(semente, 50, 320.0),
          inputItem(fungicida, 100, 87.5),
        ],
      },
      {
        code: 'PRM-2026-006',
        seller: maria,
        producer: osmar,
        status: 'approved',
        createdAt: at(2026, 4, 10, 9, 0),
        reviewedAt: at(2026, 4, 11, 11, 0),
        adminNote: 'Aprovada com prioridade.',
        items: [
          grainItem(soja, 134.0068, 148.5),
          inputItem(lambda, 200, 42.0),
          inputItem(npk, 100, 115.0),
        ],
      },
      {
        code: 'PRM-2026-007',
        seller: lucas,
        producer: vanessa,
        status: 'pending',
        createdAt: at(2026, 5, 11, 16, 0),
        items: [
          grainItem(milho, 245.2649, 62.3),
          inputItem(npk, 100, 115.0),
          inputItem(glifosato, 200, 18.9),
        ],
      },
      {
        code: 'PRM-2026-008',
        seller: roberto,
        producer: joaquim,
        status: 'approved',
        createdAt: at(2026, 3, 20, 10, 45),
        reviewedAt: at(2026, 3, 21, 8, 30),
        adminNote: 'Aprovada.',
        items: [
          grainItem(trigo, 172.9412, 85.0),
          inputItem(glifosato, 500, 18.9),
          inputItem(fungicida, 60, 87.5),
        ],
      },
    ]

    for (const entry of barters) {
      const barter = await Barter.create({
        code: entry.code,
        sellerId: entry.seller.id,
        sellerName: entry.seller.fullName!,
        sellerBranch: entry.seller.branch ?? '',
        producerId: entry.producer.id,
        producerName: entry.producer.name,
        status: entry.status,
        adminNote: entry.adminNote ?? null,
        reviewedBy: entry.reviewedAt ? admin.fullName : null,
        reviewedById: entry.reviewedAt ? admin.id : null,
        reviewedAt: entry.reviewedAt ?? null,
        createdAt: entry.createdAt,
      })
      await barter.related('items').createMany(entry.items)
    }
  }
}
