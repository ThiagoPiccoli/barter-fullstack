import '../models/models.dart';

final UserModel mockAdminUser = UserModel(
  id: 'u001',
  name: 'Carlos Mendes',
  email: 'carlos.mendes@barter.com.br',
  phone: '(44) 99999-0001',
  branch: 'Matriz',
  role: UserRole.admin,
  avatarInitials: 'CM',
  createdAt: DateTime(2020, 1, 10),
);

final UserModel mockSellerUser = UserModel(
  id: 'u002',
  name: 'João Silva',
  email: 'joao.silva@barter.com.br',
  phone: '(44) 99999-0002',
  branch: 'Filial 02 – Gran. Santa T.',
  role: UserRole.seller,
  avatarInitials: 'JS',
  createdAt: DateTime(2021, 3, 15),
  totalBarters: 2,
  totalSacks: 1000,
);

final List<UserModel> mockSellers = [
  mockSellerUser,
  UserModel(
    id: 'u003',
    name: 'Ana Paula Ferreira',
    email: 'ana.ferreira@barter.com.br',
    phone: '(44) 99999-0003',
    branch: 'Filial 04 – Gran. Inharap.',
    role: UserRole.seller,
    avatarInitials: 'AP',
    createdAt: DateTime(2021, 6, 20),
    totalBarters: 2,
    totalSacks: 1500,
  ),
  UserModel(
    id: 'u004',
    name: 'Roberto Souza',
    email: 'roberto.souza@barter.com.br',
    phone: '(44) 99999-0004',
    branch: 'Filial 34 – Gran. Jari',
    role: UserRole.seller,
    avatarInitials: 'RS',
    createdAt: DateTime(2022, 2, 8),
    totalBarters: 2,
    totalSacks: 900,
  ),
  UserModel(
    id: 'u005',
    name: 'Maria Oliveira',
    email: 'maria.oliveira@barter.com.br',
    phone: '(44) 99999-0005',
    branch: 'Filial 24 – Gran. Oliveira',
    role: UserRole.seller,
    avatarInitials: 'MO',
    createdAt: DateTime(2022, 9, 1),
    totalBarters: 1,
    totalSacks: 250,
  ),
  UserModel(
    id: 'u006',
    name: 'Lucas Barros',
    email: 'lucas.barros@barter.com.br',
    phone: '(44) 99999-0006',
    branch: 'Filial 18 – Gran. São Joa.',
    role: UserRole.seller,
    avatarInitials: 'LB',
    createdAt: DateTime(2023, 1, 15),
    totalBarters: 1,
    totalSacks: 400,
  ),
];

/// Produtores (clientes) que o vendedor designa em cada permuta. Não logam no
/// app — são selecionados na criação da permuta. Cada produtor pertence à
/// CARTEIRA de um vendedor ([ProducerModel.sellerId]): o vendedor só enxerga
/// os seus; o admin enxerga todos.
final List<ProducerModel> mockProducers = [
  ProducerModel(
    id: 'p001',
    name: 'Antônio Carvalho',
    sellerId: 'u002', // carteira de João Silva
    document: 'CPF 123.456.789-00',
    phone: '(44) 99800-1001',
    farmName: 'Fazenda Boa Vista',
    city: 'Maringá/PR',
    areaHa: 120,
    avatarInitials: 'AC',
    createdAt: DateTime(2021, 2, 10),
  ),
  ProducerModel(
    id: 'p002',
    name: 'Helena Prado',
    sellerId: 'u003', // carteira de Ana Paula Ferreira
    document: 'CPF 234.567.890-11',
    phone: '(44) 99800-1002',
    farmName: 'Sítio das Águas',
    city: 'Sarandi/PR',
    areaHa: 45,
    avatarInitials: 'HP',
    createdAt: DateTime(2021, 5, 18),
  ),
  ProducerModel(
    id: 'p003',
    name: 'Joaquim Tavares',
    sellerId: 'u004', // carteira de Roberto Souza
    document: 'CNPJ 12.345.678/0001-90',
    phone: '(44) 99800-1003',
    farmName: 'Fazenda Santa Rita',
    city: 'Mandaguari/PR',
    areaHa: 320,
    avatarInitials: 'JT',
    createdAt: DateTime(2020, 11, 3),
  ),
  ProducerModel(
    id: 'p004',
    name: 'Cláudia Nunes',
    sellerId: 'u003', // carteira de Ana Paula Ferreira
    document: 'CPF 345.678.901-22',
    phone: '(44) 99800-1004',
    farmName: 'Fazenda Recanto',
    city: 'Marialva/PR',
    areaHa: 80,
    avatarInitials: 'CN',
    createdAt: DateTime(2022, 3, 21),
  ),
  ProducerModel(
    id: 'p005',
    name: 'Sebastião Ramos',
    sellerId: 'u002', // carteira de João Silva
    document: 'CPF 456.789.012-33',
    phone: '(44) 99800-1005',
    farmName: 'Sítio Bela Vista',
    city: 'Paiçandu/PR',
    areaHa: 60,
    avatarInitials: 'SR',
    createdAt: DateTime(2022, 8, 9),
  ),
  ProducerModel(
    id: 'p006',
    name: 'Vanessa Lopes',
    sellerId: 'u006', // carteira de Lucas Barros
    document: 'CNPJ 23.456.789/0001-01',
    phone: '(44) 99800-1006',
    farmName: 'Fazenda Três Irmãos',
    city: 'Floresta/PR',
    areaHa: 210,
    avatarInitials: 'VL',
    createdAt: DateTime(2023, 1, 30),
  ),
  ProducerModel(
    id: 'p007',
    name: 'Osmar Dutra',
    sellerId: 'u005', // carteira de Maria Oliveira
    document: 'CPF 567.890.123-44',
    phone: '(44) 99800-1007',
    farmName: 'Fazenda Alto da Serra',
    city: 'Campo Mourão/PR',
    areaHa: 150,
    avatarInitials: 'OD',
    createdAt: DateTime(2022, 6, 14),
  ),
];

/// Busca um produtor pelo id (null se não encontrado).
ProducerModel? producerById(String id) {
  for (final p in mockProducers) {
    if (p.id == id) return p;
  }
  return null;
}

/// Carteira de produtores visível para um usuário. Regra de acesso central:
/// vendedor enxerga apenas os produtores da própria carteira; admin (sellerId
/// null) enxerga todos. Toda listagem de produtores do app deve passar por
/// aqui — é o ponto que o backend substituirá por um filtro no servidor.
List<ProducerModel> producersForSeller(String? sellerId) {
  if (sellerId == null) return List.of(mockProducers);
  return mockProducers.where((p) => p.sellerId == sellerId).toList();
}

/// Busca um vendedor pelo id (null se não encontrado). Usado para exibir o
/// dono da carteira de um produtor nas telas do admin.
UserModel? sellerById(String id) {
  for (final s in mockSellers) {
    if (s.id == id) return s;
  }
  return null;
}

/// Grãos com que o produtor pode PAGAR a permuta (entregues na colheita).
/// O [currentPrice] é o valor de referência (R$) por saca definido pelo admin.
List<ProductModel> mockGrains = [
  ProductModel(
    id: 'g001',
    name: 'Soja',
    unit: 'saca 60kg',
    currentPrice: 148.50,
    type: ProductType.grain,
    priceHistory: [
      PriceHistoryEntry(price: 142.00, changedAt: DateTime(2025, 12, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 144.50, changedAt: DateTime(2026, 1, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 145.00, changedAt: DateTime(2026, 2, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 147.20, changedAt: DateTime(2026, 3, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 146.80, changedAt: DateTime(2026, 4, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 149.30, changedAt: DateTime(2026, 5, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 148.50, changedAt: DateTime(2026, 6, 5), changedBy: 'Carlos Mendes'),
    ],
  ),
  ProductModel(
    id: 'g002',
    name: 'Milho',
    unit: 'saca 60kg',
    currentPrice: 62.30,
    type: ProductType.grain,
    priceHistory: [
      PriceHistoryEntry(price: 58.00, changedAt: DateTime(2025, 12, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 59.50, changedAt: DateTime(2026, 1, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 60.00, changedAt: DateTime(2026, 2, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 61.20, changedAt: DateTime(2026, 3, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 63.00, changedAt: DateTime(2026, 4, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 62.80, changedAt: DateTime(2026, 5, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 62.30, changedAt: DateTime(2026, 6, 5), changedBy: 'Carlos Mendes'),
    ],
  ),
  ProductModel(
    id: 'g003',
    name: 'Trigo',
    unit: 'saca 60kg',
    currentPrice: 85.00,
    type: ProductType.grain,
    priceHistory: [
      PriceHistoryEntry(price: 80.00, changedAt: DateTime(2025, 12, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 81.50, changedAt: DateTime(2026, 1, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 82.50, changedAt: DateTime(2026, 2, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 84.00, changedAt: DateTime(2026, 3, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 83.20, changedAt: DateTime(2026, 4, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 86.10, changedAt: DateTime(2026, 5, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 85.00, changedAt: DateTime(2026, 6, 5), changedBy: 'Carlos Mendes'),
    ],
  ),
  ProductModel(
    id: 'g004',
    name: 'Aveia',
    unit: 'saca 40kg',
    currentPrice: 45.80,
    type: ProductType.grain,
    priceHistory: [
      PriceHistoryEntry(price: 43.00, changedAt: DateTime(2025, 12, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 43.80, changedAt: DateTime(2026, 1, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 44.50, changedAt: DateTime(2026, 2, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 45.20, changedAt: DateTime(2026, 3, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 44.90, changedAt: DateTime(2026, 4, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 46.10, changedAt: DateTime(2026, 5, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 45.80, changedAt: DateTime(2026, 6, 5), changedBy: 'Carlos Mendes'),
    ],
  ),
];

/// "Pastas" de insumos. Cada insumo pode pertencer a uma; a pasta pode carregar
/// uma regra de mínimo (% do total ou R$/ha) que trava o envio da permuta. O
/// admin edita o percentual vigente conforme o período (ex.: 2% numa semana,
/// 3% na outra).
List<InputCategoryModel> mockCategories = [
  const InputCategoryModel(
    id: 'c001',
    name: 'Fertilizantes',
    ruleType: CategoryRuleType.percentOfTotal,
    ruleValue: 30,
  ),
  const InputCategoryModel(
    id: 'c002',
    name: 'Defensivos',
    ruleType: CategoryRuleType.percentOfTotal,
    ruleValue: 10,
  ),
  const InputCategoryModel(
    id: 'c003',
    name: 'Sementes',
  ),
];

/// Busca uma categoria pelo id (null se não encontrada ou id null).
InputCategoryModel? categoryById(String? id) {
  if (id == null) return null;
  for (final c in mockCategories) {
    if (c.id == id) return c;
  }
  return null;
}

/// Insumos que o produtor RETIRA; o custo deles define quantas sacas ele entrega.
List<ProductModel> mockInputs = [
  ProductModel(
    id: 'i001',
    name: 'Fertilizante NPK 04-14-08',
    unit: 'saco 50kg',
    currentPrice: 115.00,
    type: ProductType.input,
    requiredPerHa: 0.4,
    categoryId: 'c001',
    priceHistory: [
      PriceHistoryEntry(price: 108.00, changedAt: DateTime(2025, 12, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 110.50, changedAt: DateTime(2026, 1, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 112.00, changedAt: DateTime(2026, 2, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 113.50, changedAt: DateTime(2026, 3, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 116.20, changedAt: DateTime(2026, 4, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 114.30, changedAt: DateTime(2026, 5, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 115.00, changedAt: DateTime(2026, 6, 5), changedBy: 'Carlos Mendes'),
    ],
  ),
  ProductModel(
    id: 'i002',
    name: 'Herbicida Glifosato 480g/L',
    unit: 'litro',
    currentPrice: 18.90,
    type: ProductType.input,
    requiredPerHa: 2.5,
    categoryId: 'c002',
    priceHistory: [
      PriceHistoryEntry(price: 20.50, changedAt: DateTime(2025, 12, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 20.10, changedAt: DateTime(2026, 1, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 19.50, changedAt: DateTime(2026, 2, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 19.10, changedAt: DateTime(2026, 3, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 18.40, changedAt: DateTime(2026, 4, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 18.70, changedAt: DateTime(2026, 5, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 18.90, changedAt: DateTime(2026, 6, 5), changedBy: 'Carlos Mendes'),
    ],
  ),
  ProductModel(
    id: 'i003',
    name: 'Inseticida Lambda-cialotrina',
    unit: 'litro',
    currentPrice: 42.00,
    type: ProductType.input,
    requiredPerHa: 0.15,
    categoryId: 'c002',
    priceHistory: [
      PriceHistoryEntry(price: 39.00, changedAt: DateTime(2025, 12, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 39.80, changedAt: DateTime(2026, 1, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 40.50, changedAt: DateTime(2026, 2, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 41.20, changedAt: DateTime(2026, 3, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 42.50, changedAt: DateTime(2026, 4, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 41.60, changedAt: DateTime(2026, 5, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 42.00, changedAt: DateTime(2026, 6, 5), changedBy: 'Carlos Mendes'),
    ],
  ),
  ProductModel(
    id: 'i004',
    name: 'Fungicida Azoxistrobina',
    unit: 'litro',
    currentPrice: 87.50,
    type: ProductType.input,
    categoryId: 'c002',
    priceHistory: [
      PriceHistoryEntry(price: 82.00, changedAt: DateTime(2025, 12, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 83.50, changedAt: DateTime(2026, 1, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 85.00, changedAt: DateTime(2026, 2, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 86.20, changedAt: DateTime(2026, 3, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 88.10, changedAt: DateTime(2026, 4, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 86.90, changedAt: DateTime(2026, 5, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 87.50, changedAt: DateTime(2026, 6, 5), changedBy: 'Carlos Mendes'),
    ],
  ),
  ProductModel(
    id: 'i005',
    name: 'Semente Soja RR – TMG 7062',
    unit: 'saco 40kg',
    currentPrice: 320.00,
    type: ProductType.input,
    categoryId: 'c003',
    priceHistory: [
      PriceHistoryEntry(price: 300.00, changedAt: DateTime(2025, 12, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 305.00, changedAt: DateTime(2026, 1, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 310.00, changedAt: DateTime(2026, 2, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 312.00, changedAt: DateTime(2026, 3, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 318.00, changedAt: DateTime(2026, 4, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 322.00, changedAt: DateTime(2026, 5, 5), changedBy: 'Carlos Mendes'),
      PriceHistoryEntry(price: 320.00, changedAt: DateTime(2026, 6, 5), changedBy: 'Carlos Mendes'),
    ],
  ),
];

/// Permutas: cada uma tem INSUMOS retirados (definem o custo) e UM grão de
/// pagamento, cuja quantidade de sacas é calculada para cobrir esse custo.
List<BarterModel> mockBarters = [
  // 300 fertilizante + 150 glifosato (R$ 37.335) → 251,4 sc soja
  BarterModel(
    id: 'PRM-2026-001',
    sellerId: 'u002',
    sellerName: 'João Silva',
    sellerBranch: 'Filial 02 – Gran. Santa T.',
    producerId: 'p001',
    producerName: 'Antônio Carvalho',
    status: BarterStatus.approved,
    createdAt: DateTime(2026, 1, 10, 9, 30),
    updatedAt: DateTime(2026, 1, 11, 14, 0),
    adminNote: 'Permuta aprovada. Entrega dos grãos confirmada no armazém.',
    reviewedBy: 'Carlos Mendes',
    grains: const [
      BarterItem(productId: 'g001', productName: 'Soja', unit: 'saca 60kg', quantity: 251.4142, unitValue: 148.50),
    ],
    inputs: const [
      BarterItem(productId: 'i001', productName: 'Fertilizante NPK 04-14-08', unit: 'saco 50kg', quantity: 300, unitValue: 115.00),
      BarterItem(productId: 'i002', productName: 'Herbicida Glifosato 480g/L', unit: 'litro', quantity: 150, unitValue: 18.90),
    ],
  ),
  // 50 semente + 80 fungicida (R$ 23.000) → 154,9 sc soja
  BarterModel(
    id: 'PRM-2026-002',
    sellerId: 'u003',
    sellerName: 'Ana Paula Ferreira',
    sellerBranch: 'Filial 04 – Gran. Inharap.',
    producerId: 'p002',
    producerName: 'Helena Prado',
    status: BarterStatus.pending,
    createdAt: DateTime(2026, 4, 22, 11, 15),
    grains: const [
      BarterItem(productId: 'g001', productName: 'Soja', unit: 'saca 60kg', quantity: 154.8822, unitValue: 148.50),
    ],
    inputs: const [
      BarterItem(productId: 'i005', productName: 'Semente Soja RR – TMG 7062', unit: 'saco 40kg', quantity: 50, unitValue: 320.00),
      BarterItem(productId: 'i004', productName: 'Fungicida Azoxistrobina', unit: 'litro', quantity: 80, unitValue: 87.50),
    ],
  ),
  // 150 fertilizante (R$ 17.250) → 276,9 sc milho — negada por estoque
  BarterModel(
    id: 'PRM-2026-003',
    sellerId: 'u004',
    sellerName: 'Roberto Souza',
    sellerBranch: 'Filial 34 – Gran. Jari',
    producerId: 'p003',
    producerName: 'Joaquim Tavares',
    status: BarterStatus.denied,
    createdAt: DateTime(2026, 2, 5, 8, 0),
    updatedAt: DateTime(2026, 2, 6, 10, 30),
    adminNote: 'Estoque de fertilizante indisponível nesta filial para o período solicitado.',
    reviewedBy: 'Carlos Mendes',
    grains: const [
      BarterItem(productId: 'g002', productName: 'Milho', unit: 'saca 60kg', quantity: 276.8861, unitValue: 62.30),
    ],
    inputs: const [
      BarterItem(productId: 'i001', productName: 'Fertilizante NPK 04-14-08', unit: 'saco 50kg', quantity: 150, unitValue: 115.00),
    ],
  ),
  // 400 fertilizante + 200 glifosato + 40 fungicida (R$ 53.280) → 358,8 sc soja
  BarterModel(
    id: 'PRM-2026-004',
    sellerId: 'u003',
    sellerName: 'Ana Paula Ferreira',
    sellerBranch: 'Filial 04 – Gran. Inharap.',
    producerId: 'p004',
    producerName: 'Cláudia Nunes',
    status: BarterStatus.approved,
    createdAt: DateTime(2026, 3, 1, 10, 0),
    updatedAt: DateTime(2026, 3, 2, 9, 0),
    adminNote: 'Aprovada.',
    reviewedBy: 'Carlos Mendes',
    grains: const [
      BarterItem(productId: 'g001', productName: 'Soja', unit: 'saca 60kg', quantity: 358.7879, unitValue: 148.50),
    ],
    inputs: const [
      BarterItem(productId: 'i001', productName: 'Fertilizante NPK 04-14-08', unit: 'saco 50kg', quantity: 400, unitValue: 115.00),
      BarterItem(productId: 'i002', productName: 'Herbicida Glifosato 480g/L', unit: 'litro', quantity: 200, unitValue: 18.90),
      BarterItem(productId: 'i004', productName: 'Fungicida Azoxistrobina', unit: 'litro', quantity: 40, unitValue: 87.50),
    ],
  ),
  // 50 semente + 100 fungicida (R$ 24.750) → 166,7 sc soja
  BarterModel(
    id: 'PRM-2026-005',
    sellerId: 'u002',
    sellerName: 'João Silva',
    sellerBranch: 'Filial 02 – Gran. Santa T.',
    producerId: 'p005',
    producerName: 'Sebastião Ramos',
    status: BarterStatus.pending,
    createdAt: DateTime(2026, 5, 8, 14, 20),
    grains: const [
      BarterItem(productId: 'g001', productName: 'Soja', unit: 'saca 60kg', quantity: 166.6667, unitValue: 148.50),
    ],
    inputs: const [
      BarterItem(productId: 'i005', productName: 'Semente Soja RR – TMG 7062', unit: 'saco 40kg', quantity: 50, unitValue: 320.00),
      BarterItem(productId: 'i004', productName: 'Fungicida Azoxistrobina', unit: 'litro', quantity: 100, unitValue: 87.50),
    ],
  ),
  // 200 lambda + 100 fertilizante (R$ 19.900) → 134 sc soja
  BarterModel(
    id: 'PRM-2026-006',
    sellerId: 'u005',
    sellerName: 'Maria Oliveira',
    sellerBranch: 'Filial 24 – Gran. Oliveira',
    producerId: 'p007',
    producerName: 'Osmar Dutra',
    status: BarterStatus.approved,
    createdAt: DateTime(2026, 4, 10, 9, 0),
    updatedAt: DateTime(2026, 4, 11, 11, 0),
    adminNote: 'Aprovada com prioridade.',
    reviewedBy: 'Carlos Mendes',
    grains: const [
      BarterItem(productId: 'g001', productName: 'Soja', unit: 'saca 60kg', quantity: 134.0068, unitValue: 148.50),
    ],
    inputs: const [
      BarterItem(productId: 'i003', productName: 'Inseticida Lambda-cialotrina', unit: 'litro', quantity: 200, unitValue: 42.00),
      BarterItem(productId: 'i001', productName: 'Fertilizante NPK 04-14-08', unit: 'saco 50kg', quantity: 100, unitValue: 115.00),
    ],
  ),
  // 100 fertilizante + 200 glifosato (R$ 15.280) → 245,3 sc milho
  BarterModel(
    id: 'PRM-2026-007',
    sellerId: 'u006',
    sellerName: 'Lucas Barros',
    sellerBranch: 'Filial 18 – Gran. São Joa.',
    producerId: 'p006',
    producerName: 'Vanessa Lopes',
    status: BarterStatus.pending,
    createdAt: DateTime(2026, 5, 11, 16, 0),
    grains: const [
      BarterItem(productId: 'g002', productName: 'Milho', unit: 'saca 60kg', quantity: 245.2649, unitValue: 62.30),
    ],
    inputs: const [
      BarterItem(productId: 'i001', productName: 'Fertilizante NPK 04-14-08', unit: 'saco 50kg', quantity: 100, unitValue: 115.00),
      BarterItem(productId: 'i002', productName: 'Herbicida Glifosato 480g/L', unit: 'litro', quantity: 200, unitValue: 18.90),
    ],
  ),
  // 500 glifosato + 60 fungicida (R$ 14.700) → 172,9 sc trigo
  BarterModel(
    id: 'PRM-2026-008',
    sellerId: 'u004',
    sellerName: 'Roberto Souza',
    sellerBranch: 'Filial 34 – Gran. Jari',
    producerId: 'p003',
    producerName: 'Joaquim Tavares',
    status: BarterStatus.approved,
    createdAt: DateTime(2026, 3, 20, 10, 45),
    updatedAt: DateTime(2026, 3, 21, 8, 30),
    adminNote: 'Aprovada.',
    reviewedBy: 'Carlos Mendes',
    grains: const [
      BarterItem(productId: 'g003', productName: 'Trigo', unit: 'saca 60kg', quantity: 172.9412, unitValue: 85.00),
    ],
    inputs: const [
      BarterItem(productId: 'i002', productName: 'Herbicida Glifosato 480g/L', unit: 'litro', quantity: 500, unitValue: 18.90),
      BarterItem(productId: 'i004', productName: 'Fungicida Azoxistrobina', unit: 'litro', quantity: 60, unitValue: 87.50),
    ],
  ),
];
