import { Prisma, PrismaClient } from '@prisma/client';
import { hashPassword } from '../src/auth/password.util';
import { ROLE, type Role } from '../src/common/roles';
import { documentDigitsOf } from '../src/producers/document';

/**
 * Dataset de demonstração — reproduz o mock original do app (mesmos números
 * das permutas PRM-2026-001..008). Senha de todos os usuários: 123456.
 *
 * Usado pelo `prisma db seed` e pelos testes e2e (reset por spec), por isso
 * apaga tudo antes de inserir.
 */
export async function seedDatabase(prisma: PrismaClient): Promise<void> {
  // Ordem respeita os FKs (filhos primeiro).
  await prisma.barterItem.deleteMany();
  await prisma.barter.deleteMany();
  await prisma.versionPrice.deleteMany();
  await prisma.barterVersion.deleteMany();
  await prisma.season.deleteMany();
  await prisma.priceHistoryEntry.deleteMany();
  await prisma.product.deleteMany();
  await prisma.productClass.deleteMany();
  await prisma.producer.deleteMany();
  await prisma.accessToken.deleteMany();
  await prisma.auditLog.deleteMany();
  await prisma.user.deleteMany();

  const at = (year: number, month: number, day: number, hour = 0, minute = 0) =>
    new Date(Date.UTC(year, month - 1, day, hour, minute));

  const password = await hashPassword('123456');

  /* ── Usuários ─────────────────────────────────────────────────────── */
  const mkUser = (data: {
    fullName: string;
    email: string;
    role: Role;
    phone: string;
    branch: string;
    createdAt: Date;
  }) => prisma.user.create({ data: { ...data, password } });

  const admin = await mkUser({
    fullName: 'Carlos Mendes',
    email: 'admin@agrobarter.com.br',
    role: ROLE.admin,
    phone: '(44) 99999-0001',
    branch: 'Matriz',
    createdAt: at(2020, 1, 10),
  });
  const joao = await mkUser({
    fullName: 'João Silva',
    email: 'joao.silva@agrobarter.com.br',
    role: ROLE.consultant,
    phone: '(44) 99999-0002',
    branch: 'Filial 02 – Gran. Santa T.',
    createdAt: at(2021, 3, 15),
  });
  const ana = await mkUser({
    fullName: 'Ana Paula Ferreira',
    email: 'ana.ferreira@agrobarter.com.br',
    role: ROLE.consultant,
    phone: '(44) 99999-0003',
    branch: 'Filial 04 – Gran. Inharap.',
    createdAt: at(2021, 6, 20),
  });
  const roberto = await mkUser({
    fullName: 'Roberto Souza',
    email: 'roberto.souza@agrobarter.com.br',
    role: ROLE.consultant,
    phone: '(44) 99999-0004',
    branch: 'Filial 34 – Gran. Jari',
    createdAt: at(2022, 2, 8),
  });
  const maria = await mkUser({
    fullName: 'Maria Oliveira',
    email: 'maria.oliveira@agrobarter.com.br',
    role: ROLE.consultant,
    phone: '(44) 99999-0005',
    branch: 'Filial 24 – Gran. Oliveira',
    createdAt: at(2022, 9, 1),
  });
  const lucas = await mkUser({
    fullName: 'Lucas Barros',
    email: 'lucas.barros@agrobarter.com.br',
    role: ROLE.consultant,
    phone: '(44) 99999-0006',
    branch: 'Filial 18 – Gran. São Joa.',
    createdAt: at(2023, 1, 15),
  });

  /* Retaguarda: um usuário de cada papel novo, para entrar e ver o sistema
     pelos olhos dele. Vêm DEPOIS dos consultores de propósito — os ids 1..6
     (admin e consultores) são fixados por testes e pelas carteiras acima. */
  await mkUser({
    fullName: 'Beatriz Nogueira',
    email: 'gerente@agrobarter.com.br',
    role: ROLE.manager,
    phone: '(44) 99999-0010',
    branch: 'Matriz',
    createdAt: at(2020, 2, 3),
  });
  await mkUser({
    fullName: 'Ricardo Alencar',
    email: 'comite@agrobarter.com.br',
    role: ROLE.committee,
    phone: '(44) 99999-0011',
    branch: 'Matriz',
    createdAt: at(2020, 2, 3),
  });
  await mkUser({
    fullName: 'Patrícia Lemos',
    email: 'faturista@agrobarter.com.br',
    role: ROLE.biller,
    phone: '(44) 99999-0012',
    branch: 'Matriz',
    createdAt: at(2020, 2, 3),
  });

  /* ── Carteiras de produtores ──────────────────────────────────────── */
  // `documentDigits` (a forma canônica que garante a unicidade) é derivada
  // aqui para o dataset não precisar repetir o documento duas vezes.
  type ProducerSeed = Omit<Prisma.ProducerUncheckedCreateInput, 'documentDigits'>;
  const mkProducer = (data: ProducerSeed) =>
    prisma.producer.create({
      data: { ...data, documentDigits: documentDigitsOf(data.document) },
    });

  const antonio = await mkProducer({
    name: 'Antônio Carvalho',
    consultantId: joao.id,
    document: 'CPF 123.456.789-00',
    phone: '(44) 99800-1001',
    farmName: 'Fazenda Boa Vista',
    city: 'Maringá/PR',
    areaHa: 120,
    createdAt: at(2021, 2, 10),
  });
  const helena = await mkProducer({
    name: 'Helena Prado',
    consultantId: ana.id,
    document: 'CPF 234.567.890-11',
    phone: '(44) 99800-1002',
    farmName: 'Sítio das Águas',
    city: 'Sarandi/PR',
    areaHa: 45,
    createdAt: at(2021, 5, 18),
  });
  const joaquim = await mkProducer({
    name: 'Joaquim Tavares',
    consultantId: roberto.id,
    document: 'CNPJ 12.345.678/0001-90',
    phone: '(44) 99800-1003',
    farmName: 'Fazenda Santa Rita',
    city: 'Mandaguari/PR',
    areaHa: 320,
    createdAt: at(2020, 11, 3),
  });
  const claudia = await mkProducer({
    name: 'Cláudia Nunes',
    consultantId: ana.id,
    document: 'CPF 345.678.901-22',
    phone: '(44) 99800-1004',
    farmName: 'Fazenda Recanto',
    city: 'Marialva/PR',
    areaHa: 80,
    createdAt: at(2022, 3, 21),
  });
  const sebastiao = await mkProducer({
    name: 'Sebastião Ramos',
    consultantId: joao.id,
    document: 'CPF 456.789.012-33',
    phone: '(44) 99800-1005',
    farmName: 'Sítio Bela Vista',
    city: 'Paiçandu/PR',
    areaHa: 60,
    createdAt: at(2022, 8, 9),
  });
  const vanessa = await mkProducer({
    name: 'Vanessa Lopes',
    consultantId: lucas.id,
    document: 'CNPJ 23.456.789/0001-01',
    phone: '(44) 99800-1006',
    farmName: 'Fazenda Três Irmãos',
    city: 'Floresta/PR',
    areaHa: 210,
    createdAt: at(2023, 1, 30),
  });
  const osmar = await mkProducer({
    name: 'Osmar Dutra',
    consultantId: maria.id,
    document: 'CPF 567.890.123-44',
    phone: '(44) 99800-1007',
    farmName: 'Fazenda Alto da Serra',
    city: 'Campo Mourão/PR',
    areaHa: 150,
    createdAt: at(2022, 6, 14),
  });

  /* ── Classes de produto ───────────────────────────────────────────── */
  //
  // As classes NASCEM DO ARQUIVO do fornecedor: é a lista de preços que define
  // a taxonomia, e a carga em massa cria a que ainda não existe. Aqui o
  // dataset de demonstração cria as que os produtos abaixo usam — os nomes são
  // os mesmos da lista real, para uma carga de verdade reconhecê-las em vez de
  // duplicar.
  const mkClass = async (slug: string, name: string, position: number, rule?: [string, number]) =>
    prisma.productClass.create({
      data: {
        slug,
        name,
        position,
        ruleType: rule?.[0] ?? 'none',
        ruleValue: rule?.[1] ?? 0,
      },
    });

  const herbicidas = await mkClass('herbicidas', 'HERBICIDAS', 1, ['percentOfTotal', 10]);
  const inseticidas = await mkClass('inseticidas', 'INSETICIDAS', 2);
  const fungicidas = await mkClass('fungicidas', 'FUNGICIDAS', 3);
  const fertilizantes = await mkClass('fertilizantes', 'FERTILIZANTES', 4, ['percentOfTotal', 30]);
  const sementes = await mkClass('sementes', 'SEMENTES', 5);

  /* ── Produtos + histórico de valores (dez/2025..jun/2026, dia 5) ──── */
  const historyDates = [
    at(2025, 12, 5),
    at(2026, 1, 5),
    at(2026, 2, 5),
    at(2026, 3, 5),
    at(2026, 4, 5),
    at(2026, 5, 5),
    at(2026, 6, 5),
  ];

  const catalog: {
    sku: string;
    name: string;
    unit: string;
    type: 'grain' | 'input';
    prices: number[];
    requiredPerHa?: number;
    classId?: number;
  }[] = [
    {
      sku: 'GRA-0001',
      name: 'Soja',
      unit: 'saca 60kg',
      type: 'grain',
      prices: [142.0, 144.5, 145.0, 147.2, 146.8, 149.3, 148.5],
    },
    {
      sku: 'GRA-0002',
      name: 'Milho',
      unit: 'saca 60kg',
      type: 'grain',
      prices: [58.0, 59.5, 60.0, 61.2, 63.0, 62.8, 62.3],
    },
    {
      sku: 'GRA-0003',
      name: 'Trigo',
      unit: 'saca 60kg',
      type: 'grain',
      prices: [80.0, 81.5, 82.5, 84.0, 83.2, 86.1, 85.0],
    },
    {
      sku: 'GRA-0004',
      name: 'Aveia',
      unit: 'saca 40kg',
      type: 'grain',
      prices: [43.0, 43.8, 44.5, 45.2, 44.9, 46.1, 45.8],
    },
    {
      sku: 'NPK-0414',
      name: 'Fertilizante NPK 04-14-08',
      unit: 'saco 50kg',
      type: 'input',
      prices: [108.0, 110.5, 112.0, 113.5, 116.2, 114.3, 115.0],
      requiredPerHa: 0.4,
      classId: fertilizantes.id,
    },
    {
      sku: 'GLI-480',
      name: 'Herbicida Glifosato 480g/L',
      unit: 'litro',
      type: 'input',
      prices: [20.5, 20.1, 19.5, 19.1, 18.4, 18.7, 18.9],
      requiredPerHa: 2.5,
      classId: herbicidas.id,
    },
    {
      sku: 'LAM-050',
      name: 'Inseticida Lambda-cialotrina',
      unit: 'litro',
      type: 'input',
      prices: [39.0, 39.8, 40.5, 41.2, 42.5, 41.6, 42.0],
      requiredPerHa: 0.15,
      classId: inseticidas.id,
    },
    {
      sku: 'AZO-200',
      name: 'Fungicida Azoxistrobina',
      unit: 'litro',
      type: 'input',
      prices: [82.0, 83.5, 85.0, 86.2, 88.1, 86.9, 87.5],
      classId: fungicidas.id,
    },
    {
      sku: 'SEM-7062',
      name: 'Semente Soja RR – TMG 7062',
      unit: 'saco 40kg',
      type: 'input',
      prices: [300.0, 305.0, 310.0, 312.0, 318.0, 322.0, 320.0],
      classId: sementes.id,
    },
  ];

  const products: {
    id: number;
    name: string;
    unit: string;
    price: number;
    type: 'grain' | 'input';
    prices: number[];
  }[] = [];
  for (const item of catalog) {
    const product = await prisma.product.create({
      data: {
        sku: item.sku,
        name: item.name,
        unit: item.unit,
        type: item.type,
        currentPrice: item.prices[item.prices.length - 1],
        requiredPerHa: item.requiredPerHa ?? 0,
        classId: item.classId ?? null,
        priceHistory: {
          create: item.prices.map((price, i) => ({
            price,
            changedBy: 'Carlos Mendes',
            changedById: admin.id,
            changedAt: historyDates[i],
          })),
        },
      },
    });
    products.push({
      id: product.id,
      name: product.name,
      unit: product.unit,
      price: product.currentPrice,
      type: item.type,
      prices: item.prices,
    });
  }

  const [soja, milho, trigo, , npk, glifosato, lambda, fungicida, semente] = products;

  /* ── Safras e versões do Barter ───────────────────────────────────── */
  //
  // O dataset conta a história do modelo: duas safras já encerradas (é delas
  // que vêm as permutas antigas pagas em milho e trigo) e a safra de soja
  // ABERTA, com duas versões — a primeira encerrada quando os valores foram
  // reajustados, a segunda vigente. É nela que uma permuta nova cai.
  const inputs = products.filter((product) => product.type === 'input');

  const mkVersion = async (args: {
    seasonId: number;
    number: number;
    code: string;
    status: 'active' | 'closed';
    grainPrice: number;
    priceIndex: number;
    startsAt: Date;
    closedAt?: Date;
    note: string;
    targets?: { sales?: number; sacks?: number; barters?: number };
  }) =>
    prisma.barterVersion.create({
      data: {
        seasonId: args.seasonId,
        number: args.number,
        code: args.code,
        status: args.status,
        grainPrice: args.grainPrice,
        startsAt: args.startsAt,
        closedAt: args.closedAt ?? null,
        closedBy: args.closedAt ? admin.fullName : null,
        closedById: args.closedAt ? admin.id : null,
        note: args.note,
        targetSales: args.targets?.sales ?? null,
        targetSacks: args.targets?.sacks ?? null,
        targetBarters: args.targets?.barters ?? null,
        prices: {
          create: inputs.map((product) => ({
            productId: product.id,
            productName: product.name,
            unit: product.unit,
            price: product.prices[args.priceIndex],
          })),
        },
      },
    });

  const trigoSeason = await prisma.season.create({
    data: {
      code: 'T2025',
      name: 'Trigo 2025',
      year: 2025,
      grainId: trigo.id,
      grainName: trigo.name,
      grainUnit: trigo.unit,
      status: 'closed',
      openedAt: at(2025, 12, 1),
      closedAt: at(2026, 3, 31),
    },
  });
  const trigoVersion = await mkVersion({
    seasonId: trigoSeason.id,
    number: 1,
    code: 'T2025.01',
    status: 'closed',
    grainPrice: trigo.price,
    priceIndex: 6,
    startsAt: at(2025, 12, 1),
    closedAt: at(2026, 3, 31),
    note: 'Tabela de abertura da safra de trigo.',
  });

  const milhoSeason = await prisma.season.create({
    data: {
      code: 'M2026',
      name: 'Milho 2026',
      year: 2026,
      grainId: milho.id,
      grainName: milho.name,
      grainUnit: milho.unit,
      status: 'closed',
      openedAt: at(2026, 1, 15),
      closedAt: at(2026, 6, 30),
    },
  });
  const milhoVersion = await mkVersion({
    seasonId: milhoSeason.id,
    number: 1,
    code: 'M2026.01',
    status: 'closed',
    grainPrice: milho.price,
    priceIndex: 6,
    startsAt: at(2026, 1, 15),
    closedAt: at(2026, 6, 30),
    note: 'Safra de milho encerrada por atingir a meta de vendas.',
  });

  const sojaSeason = await prisma.season.create({
    data: {
      code: 'S2026',
      name: 'Soja 2026',
      year: 2026,
      grainId: soja.id,
      grainName: soja.name,
      grainUnit: soja.unit,
      status: 'open',
      openedAt: at(2026, 1, 5),
    },
  });
  // A primeira tabela da soja viveu três dias: foi publicada com a cotação
  // antiga e corrigida logo em seguida. É de propósito que ela não tenha
  // nenhuma permuta — é o caso de quem republica antes de alguém usar.
  await mkVersion({
    seasonId: sojaSeason.id,
    number: 1,
    code: 'S2026.01',
    status: 'closed',
    grainPrice: 145.0,
    priceIndex: 2,
    startsAt: at(2026, 1, 5),
    closedAt: at(2026, 1, 8),
    note: 'Tabela de abertura — corrigida três dias depois.',
  });
  const sojaV2 = await mkVersion({
    seasonId: sojaSeason.id,
    number: 2,
    code: 'S2026.02',
    status: 'active',
    grainPrice: soja.price,
    priceIndex: 6,
    startsAt: at(2026, 1, 8),
    note: 'Tabela vigente da safra de soja.',
    targets: { sales: 500000, sacks: 5000, barters: 40 },
  });

  /* ── Permutas históricas (mesmos números do mock) ─────────────────── */
  type Ref = (typeof products)[number];
  const grainItem = (p: Ref, quantity: number, unitValue: number) => ({
    productId: p.id,
    kind: 'grain',
    productName: p.name,
    unit: p.unit,
    quantity,
    unitValue,
  });
  const inputItem = (p: Ref, quantity: number, unitValue: number) => ({
    productId: p.id,
    kind: 'input',
    productName: p.name,
    unit: p.unit,
    quantity,
    unitValue,
  });

  const barters = [
    {
      code: 'PRM-2026-001',
      version: sojaV2,
      consultant: joao,
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
      version: sojaV2,
      consultant: ana,
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
      version: milhoVersion,
      consultant: roberto,
      producer: joaquim,
      status: 'denied',
      createdAt: at(2026, 2, 5, 8, 0),
      reviewedAt: at(2026, 2, 6, 10, 30),
      adminNote: 'Estoque de fertilizante indisponível nesta filial para o período solicitado.',
      items: [grainItem(milho, 276.8861, 62.3), inputItem(npk, 150, 115.0)],
    },
    {
      code: 'PRM-2026-004',
      version: sojaV2,
      consultant: ana,
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
      version: sojaV2,
      consultant: joao,
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
      version: sojaV2,
      consultant: maria,
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
      version: milhoVersion,
      consultant: lucas,
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
      version: trigoVersion,
      consultant: roberto,
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
  ];

  for (const entry of barters) {
    await prisma.barter.create({
      data: {
        code: entry.code,
        versionId: entry.version.id,
        versionCode: entry.version.code,
        consultantId: entry.consultant.id,
        consultantName: entry.consultant.fullName,
        consultantBranch: entry.consultant.branch ?? '',
        producerId: entry.producer.id,
        producerName: entry.producer.name,
        status: entry.status,
        adminNote: entry.adminNote ?? null,
        reviewedBy: entry.reviewedAt ? admin.fullName : null,
        reviewedById: entry.reviewedAt ? admin.id : null,
        reviewedAt: entry.reviewedAt ?? null,
        createdAt: entry.createdAt,
        items: { create: entry.items },
      },
    });
  }
}
