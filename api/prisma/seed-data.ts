import { Prisma, PrismaClient } from '@prisma/client';
import { hashPassword } from '../src/auth/password.util';
import { ROLE, type Role } from '../src/common/roles';
import { documentDigitsOf } from '../src/producers/document';
import { TAX_REGIME, taxRateOf, type TaxRegime } from '../src/barters/tax-regime';
import { normalizeName } from '../src/seasons/product-name';

/**
 * A senha de todas as contas de demonstração.
 *
 * Era `123456` — que é, literalmente, o primeiro item da lista de senhas
 * proibidas em src/auth/password-policy.ts. Um sistema que cria contas com uma
 * senha que ele próprio recusaria é uma contradição, e ela não era só estética:
 * o dataset só é bloqueado por `NODE_ENV === 'production'`, então um ambiente
 * de homologação que esquecesse essa variável nascia com contas administrativas
 * abertas na senha mais tentada do mundo.
 *
 * A daqui passa na mesma política das outras: dez caracteres, variedade
 * suficiente, fora da lista, sem sequência de teclado e sem conter o nome do
 * sistema nem o de nenhum usuário do dataset.
 */
export const SEED_PASSWORD = 'demo-2026-agro';

/**
 * Dataset de demonstração — reproduz o mock original do app (mesmos números
 * das permutas PRM-2026-001..008). Senha de todos os usuários: SEED_PASSWORD.
 *
 * Usado pelo `prisma db seed` e pelos testes e2e (reset por spec), por isso
 * apaga tudo antes de inserir.
 */
export async function seedDatabase(prisma: PrismaClient): Promise<void> {
  // Ordem respeita os FKs (filhos primeiro).
  await prisma.cprAreaOwner.deleteMany();
  await prisma.cprArea.deleteMany();
  await prisma.cprGuarantor.deleteMany();
  await prisma.barterCpr.deleteMany();
  await prisma.creditor.deleteMany();
  await prisma.barterItem.deleteMany();
  await prisma.barterEvent.deleteMany();
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
  // Usuário antes de unidade: o usuário aponta a lotação dele, e o FK é
  // SetNull. A ordem segue a mesma regra da lista acima — filhos primeiro.
  await prisma.user.deleteMany();
  await prisma.unit.deleteMany();

  const at = (year: number, month: number, day: number, hour = 0, minute = 0) =>
    new Date(Date.UTC(year, month - 1, day, hour, minute));

  const password = await hashPassword(SEED_PASSWORD);

  /* ── A credora ────────────────────────────────────────────────────── */
  // A empresa que recebe o grão, como a CPR a nomeia. Ela existe no dataset
  // porque sem ela a tela da cédula abriria com uma pendência de configuração
  // em toda demonstração — e a pendência é justamente o que se quer mostrar
  // resolvido. Em produção, quem a cadastra é o admin ou o faturista.
  await prisma.creditor.create({
    data: {
      id: 1,
      name: 'agroBarter Cooperativa Agroindustrial Ltda.',
      cnpj: '12.345.678/0001-90',
      address: 'Avenida Colombo',
      addressNumber: '4750',
      city: 'Maringá/PR',
      // Foro em branco de propósito: é o caso comum (elege-se a comarca da
      // sede), e é ele que exercita a regra do `forumOf`.
      forum: '',
      updatedBy: 'Dataset de demonstração',
    },
  });

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
  const beatriz = await mkUser({
    fullName: 'Beatriz Nogueira',
    email: 'gerente@agrobarter.com.br',
    role: ROLE.manager,
    phone: '(44) 99999-0010',
    branch: 'Matriz',
    createdAt: at(2020, 2, 3),
  });
  // O comitê DECIDE e o faturista FATURA — os dois últimos postos da linha —,
  // então os dois assinam permutas do dataset e precisam de nome aqui.
  //
  // O COMITÊ não é uma pessoa: é uma reunião, e o cadastro é do ÓRGÃO (ver
  // `isSingleAccount` em common/roles.ts). Por isso o nome é institucional e há
  // UM só no dataset — a decisão sai assinada pelo colegiado, que é quem a toma.
  const comite = await mkUser({
    fullName: 'Comitê de Permutas',
    email: 'comite@agrobarter.com.br',
    role: ROLE.committee,
    phone: '(44) 99999-0011',
    branch: 'Matriz',
    createdAt: at(2020, 2, 3),
  });
  const patricia = await mkUser({
    fullName: 'Patrícia Lemos',
    email: 'faturista@agrobarter.com.br',
    role: ROLE.biller,
    phone: '(44) 99999-0012',
    branch: 'Matriz',
    createdAt: at(2020, 2, 3),
  });

  /**
   * O SEGUNDO gerente existe para o dataset mostrar a regra, não só o caminho
   * feliz: cada gerente recebe as permutas do PRÓPRIO time, e a permuta de um
   * consultor não aparece para o gerente do outro. Com um gerente só, "cada um
   * vê a sua fila" e "todo mundo vê tudo" produzem exatamente a mesma tela.
   *
   * Vem por último pelo mesmo motivo dos três acima: não deslocar os ids 7, 8 e
   * 9, que os testes de provisionamento fixam.
   */
  const gustavo = await mkUser({
    fullName: 'Gustavo Ramires',
    email: 'gerente.sul@agrobarter.com.br',
    role: ROLE.manager,
    phone: '(44) 99999-0013',
    branch: 'Filial 34 – Gran. Jari',
    createdAt: at(2021, 8, 16),
  });

  /* ── Unidades de retirada ─────────────────────────────────────────── */
  //
  // Elas nascem dos textos que estavam em `branch`: o cadastro de unidade é a
  // formalização daquele campo livre. São LOCAIS — não têm dono e não decidem
  // nada do fluxo; quem analisa a permuta é o gerente de quem a registrou.
  const mkUnit = (name: string, city: string) =>
    prisma.unit.create({ data: { name, nameKey: normalizeName(name), city } });

  const matriz = await mkUnit('Matriz', 'Maringá/PR');
  const filial02 = await mkUnit('Filial 02 – Gran. Santa T.', 'Sarandi/PR');
  const filial04 = await mkUnit('Filial 04 – Gran. Inharap.', 'Maringá/PR');
  const filial18 = await mkUnit('Filial 18 – Gran. São Joa.', 'Paiçandu/PR');
  const filial24 = await mkUnit('Filial 24 – Gran. Oliveira', 'Marialva/PR');
  const filial34 = await mkUnit('Filial 34 – Gran. Jari', 'Mandaguari/PR');

  // A lotação e o gerente de cada um, num segundo passo porque as unidades só
  // existem agora. `branch` continua sendo o NOME da unidade — quem o escreve
  // na aplicação é o user-provisioning.service.ts, pelo mesmo caminho.
  //
  // Os dois times: Beatriz responde por João e Ana; Gustavo, por Roberto, Maria
  // e Lucas. Repare que a lotação NÃO acompanha o time — Roberto é da Filial 34
  // e Ana da Filial 04, e isso não tem relação com quem os gerencia.
  const lotar = (
    user: { id: number },
    unit: { id: number; name: string },
    manager?: { id: number },
  ) =>
    prisma.user.update({
      where: { id: user.id },
      data: { unitId: unit.id, branch: unit.name, managerId: manager?.id ?? null },
    });

  const managerOfConsultant = new Map<number, typeof beatriz>([
    [joao.id, beatriz],
    [ana.id, beatriz],
    [roberto.id, gustavo],
    [maria.id, gustavo],
    [lucas.id, gustavo],
  ]);

  await lotar(admin, matriz);
  await lotar(joao, filial02, beatriz);
  await lotar(ana, filial04, beatriz);
  await lotar(roberto, filial34, gustavo);
  await lotar(maria, filial24, gustavo);
  await lotar(lucas, filial18, gustavo);
  await lotar(beatriz, matriz);
  await lotar(gustavo, filial34);
  await lotar(comite, matriz);
  await lotar(patricia, matriz);

  /* ── Carteiras de produtores ──────────────────────────────────────── */
  // `documentDigits` (a forma canônica que garante a unicidade) é derivada
  // aqui para o dataset não precisar repetir o documento duas vezes.
  //
  // `consultants` é LISTA: o mesmo produtor pode ser atendido por mais de um
  // consultor (ver ProducerConsultant no schema). Joaquim Tavares, abaixo, é o
  // caso do dataset — a região de Mandaguari é dividida entre Roberto e João, e
  // os dois atendem o mesmo cliente.
  type ProducerSeed = Omit<
    Prisma.ProducerUncheckedCreateInput,
    'documentDigits' | 'consultants'
  > & { consultants: number[] };

  const mkProducer = ({ consultants, ...data }: ProducerSeed) =>
    prisma.producer.create({
      data: {
        ...data,
        documentDigits: documentDigitsOf(data.document),
        // O vínculo nasce junto com o produtor, e por isso com a data dele: no
        // dataset o compartilhamento é parte da história, não algo feito hoje.
        consultants: {
          create: consultants.map((consultantId) => ({
            consultantId,
            assignedAt: data.createdAt as Date,
          })),
        },
      },
    });

  const antonio = await mkProducer({
    name: 'Antônio Carvalho',
    consultants: [joao.id],
    document: 'CPF 123.456.789-00',
    phone: '(44) 99800-1001',
    farmName: 'Fazenda Boa Vista',
    city: 'Maringá/PR',
    areaHa: 120,
    createdAt: at(2021, 2, 10),
  });
  const helena = await mkProducer({
    name: 'Helena Prado',
    consultants: [ana.id],
    document: 'CPF 234.567.890-11',
    phone: '(44) 99800-1002',
    farmName: 'Sítio das Águas',
    city: 'Sarandi/PR',
    areaHa: 45,
    createdAt: at(2021, 5, 18),
  });
  // O produtor COMPARTILHADO do dataset: Mandaguari é região dividida, e
  // Roberto e João atendem os dois a Fazenda Santa Rita. É o caso que existe
  // para as telas mostrarem uma carteira com mais de um nome — e para os testes
  // separarem "vejo o meu" de "vejo só o meu".
  const joaquim = await mkProducer({
    name: 'Joaquim Tavares',
    consultants: [roberto.id, joao.id],
    document: 'CNPJ 12.345.678/0001-90',
    phone: '(44) 99800-1003',
    farmName: 'Fazenda Santa Rita',
    city: 'Mandaguari/PR',
    areaHa: 320,
    createdAt: at(2020, 11, 3),
  });
  const claudia = await mkProducer({
    name: 'Cláudia Nunes',
    consultants: [ana.id],
    document: 'CPF 345.678.901-22',
    phone: '(44) 99800-1004',
    farmName: 'Fazenda Recanto',
    city: 'Marialva/PR',
    areaHa: 80,
    createdAt: at(2022, 3, 21),
  });
  const sebastiao = await mkProducer({
    name: 'Sebastião Ramos',
    consultants: [joao.id],
    document: 'CPF 456.789.012-33',
    phone: '(44) 99800-1005',
    farmName: 'Sítio Bela Vista',
    city: 'Paiçandu/PR',
    areaHa: 60,
    createdAt: at(2022, 8, 9),
  });
  const vanessa = await mkProducer({
    name: 'Vanessa Lopes',
    consultants: [lucas.id],
    document: 'CNPJ 23.456.789/0001-01',
    phone: '(44) 99800-1006',
    farmName: 'Fazenda Três Irmãos',
    city: 'Floresta/PR',
    areaHa: 210,
    createdAt: at(2023, 1, 30),
  });
  const osmar = await mkProducer({
    name: 'Osmar Dutra',
    consultants: [maria.id],
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

  /* ── Permutas históricas (mesmos números do mock) ─────────────────── */
  //
  // Toda permuta tem uma UNIDADE de retirada e foi endereçada ao gerente do
  // consultor que a registrou. Todas já passaram pelo parecer dele — menos
  // duas, deixadas em `sentToManager` de propósito: são as filas de Beatriz
  // (PRM-2026-005, do João) e de Gustavo (PRM-2026-007, do Lucas), e sem elas a
  // tela do gerente abriria vazia no dataset de demonstração.
  //
  // O dataset cobre a LINHA INTEIRA pelo mesmo motivo: uma em cada posto, para
  // nenhuma tela do fluxo abrir vazia — um rascunho na mão do João
  // (PRM-2026-009), duas no gerente, uma no comitê (PRM-2026-002), três
  // aprovadas esperando o faturista (uma delas COM RESSALVA, a PRM-2026-006),
  // uma negada e uma já faturada.
  const barters = [
    {
      code: 'PRM-2026-001',
      consultantNote:
        'Cliente de cinco safras, nunca atrasou entrega. A área está toda plantada e a lavoura vem bem.',
      version: sojaV2,
      consultant: joao,
      producer: antonio,
      // A mais antiga do dataset já andou a linha inteira: parecer, decisão do
      // comitê e faturamento. É a única `invoiced` — sem ela, o painel do
      // faturista não teria nada faturado para mostrar, só a fila.
      status: 'invoiced',
      createdAt: at(2026, 1, 10, 9, 30),
      managerNote:
        'Volume compatível com a área declarada e com o histórico do produtor. ' +
        'Estoque de NPK e glifosato disponível na unidade para o período.',
      managerReviewedAt: at(2026, 1, 10, 16, 45),
      reviewedAt: at(2026, 1, 11, 14, 0),
      reviewNote: 'Permuta aprovada. Entrega dos grãos confirmada no armazém.',
      invoicedAt: at(2026, 1, 12, 10, 15),
      invoiceNote: 'Faturada em nota única, retirada agendada com o produtor.',
      items: [
        grainItem(soja, 251.4142, 148.5),
        inputItem(npk, 300, 115.0),
        inputItem(glifosato, 150, 18.9),
      ],
    },
    {
      code: 'PRM-2026-002',
      consultantNote:
        'Produtora organizada, entrega sempre no prazo combinado. Pediu a semente com antecedência por causa do plantio cedo.',
      version: sojaV2,
      consultant: ana,
      producer: helena,
      status: 'pending',
      createdAt: at(2026, 4, 22, 11, 15),
      managerNote:
        'Produtora com bom histórico de entrega. Semente e fungicida em estoque; ' +
        'a retirada da semente precisa ser agendada com uma semana de antecedência.',
      managerReviewedAt: at(2026, 4, 23, 9, 10),
      items: [
        grainItem(soja, 154.8822, 148.5),
        inputItem(semente, 50, 320.0),
        inputItem(fungicida, 80, 87.5),
      ],
    },
    {
      code: 'PRM-2026-003',
      consultantNote:
        'Bom pagador, mas o volume que ele pediu depende de a carga chegar antes da janela dele. Registrei como veio para o gerente avaliar o estoque.',
      version: milhoVersion,
      consultant: roberto,
      producer: joaquim,
      status: 'denied',
      createdAt: at(2026, 2, 5, 8, 0),
      managerNote:
        'Não temos fertilizante para esse volume no período pedido — a próxima carga ' +
        'chega depois da janela de plantio dele. Sugiro reprogramar ou dividir a retirada.',
      managerReviewedAt: at(2026, 2, 5, 17, 20),
      reviewedAt: at(2026, 2, 6, 10, 30),
      reviewNote: 'Estoque de fertilizante indisponível nesta filial para o período solicitado.',
      items: [grainItem(milho, 276.8861, 62.3), inputItem(npk, 150, 115.0)],
    },
    {
      code: 'PRM-2026-004',
      consultantNote:
        'Área pequena e bem cuidada. Ela já permutou nas duas últimas safras e liquidou tudo em grão.',
      version: sojaV2,
      consultant: ana,
      producer: claudia,
      status: 'approved',
      createdAt: at(2026, 3, 1, 10, 0),
      managerNote:
        'Mix bem distribuído e coerente com os 80 ha da propriedade. Sem restrição ' +
        'de estoque na unidade.',
      managerReviewedAt: at(2026, 3, 1, 15, 30),
      reviewedAt: at(2026, 3, 2, 9, 0),
      reviewNote: 'Aprovada.',
      items: [
        grainItem(soja, 358.7879, 148.5),
        inputItem(npk, 400, 115.0),
        inputItem(glifosato, 200, 18.9),
        inputItem(fungicida, 40, 87.5),
      ],
    },
    {
      code: 'PRM-2026-005',
      consultantNote:
        'Primeira permuta dele conosco. Área própria, sem arrendamento, e a referência da revenda vizinha é boa.',
      version: sojaV2,
      consultant: joao,
      producer: sebastiao,
      // Na mesa da Beatriz, esperando o parecer da Filial 02.
      status: 'sentToManager',
      createdAt: at(2026, 5, 8, 14, 20),
      items: [
        grainItem(soja, 166.6667, 148.5),
        inputItem(semente, 50, 320.0),
        inputItem(fungicida, 100, 87.5),
      ],
    },
    {
      code: 'PRM-2026-006',
      consultantNote:
        'Cliente antigo da unidade, retira tudo de uma vez. Sem pendência financeira aberta.',
      version: sojaV2,
      consultant: maria,
      producer: osmar,
      // A ÚNICA aprovada COM RESSALVA do dataset, e ela existe para a tela do
      // comitê e a do faturista mostrarem o terceiro desfecho da decisão. Sem
      // ela, o selo e a exigência só apareceriam depois de alguém aprovar com
      // ressalva na demonstração — e o mais provável é que ninguém descobrisse
      // que dá.
      status: 'approvedWithConditions',
      createdAt: at(2026, 4, 10, 9, 0),
      managerNote:
        'Retirada do inseticida já separada. Produtor é cliente antigo da unidade e ' +
        'costuma retirar tudo de uma vez — reservei doca para o dia 15.',
      managerReviewedAt: at(2026, 4, 10, 14, 5),
      reviewedAt: at(2026, 4, 11, 11, 0),
      // A RESSALVA é o texto da decisão, e é obrigatória neste desfecho: ela diz
      // o que precisa ser providenciado antes de a entrega ser cobrada.
      reviewNote:
        'Aprovada com ressalva: exigir seguro agrícola da área e aval do cônjuge ' +
        'antes da retirada. Confirmar a apólice com o produtor.',
      items: [
        grainItem(soja, 134.0068, 148.5),
        inputItem(lambda, 200, 42.0),
        inputItem(npk, 100, 115.0),
      ],
    },
    {
      code: 'PRM-2026-007',
      consultantNote:
        'Produtora nova na carteira, área arrendada em três talhões. Sugiro olhar a garantia com cuidado.',
      version: milhoVersion,
      consultant: lucas,
      producer: vanessa,
      // Na mesa do Gustavo, esperando o parecer da Filial 18.
      status: 'sentToManager',
      createdAt: at(2026, 5, 11, 16, 0),
      items: [
        grainItem(milho, 245.2649, 62.3),
        inputItem(npk, 100, 115.0),
        inputItem(glifosato, 200, 18.9),
      ],
    },
    {
      code: 'PRM-2026-008',
      consultantNote:
        'Mesmo produtor da PRM-2026-003, agora no trigo. Os dois talhões em pousio explicam o volume de glifosato.',
      version: trigoVersion,
      consultant: roberto,
      producer: joaquim,
      status: 'approved',
      createdAt: at(2026, 3, 20, 10, 45),
      managerNote:
        'Volume de glifosato alto para a área, mas o produtor já explicou: dois talhões ' +
        'em pousio entram agora. Estoque comporta.',
      managerReviewedAt: at(2026, 3, 20, 17, 0),
      reviewedAt: at(2026, 3, 21, 8, 30),
      reviewNote: 'Aprovada.',
      items: [
        grainItem(trigo, 172.9412, 85.0),
        inputItem(glifosato, 500, 18.9),
        inputItem(fungicida, 60, 87.5),
      ],
    },
    {
      code: 'PRM-2026-009',
      consultantNote: '',
      version: sojaV2,
      consultant: joao,
      producer: antonio,
      // O RASCUNHO do dataset: montada e ainda na mão do João, sem parecer
      // escrito e sem gerente endereçado. Ela existe pelo mesmo motivo das duas
      // em `sentToManager` — a tela do consultor precisa ter o que mostrar no
      // estado novo —, e é a única permuta do dataset que NENHUMA tela da
      // retaguarda enxerga (ver `scopeFor`).
      status: 'draft',
      createdAt: at(2026, 5, 14, 8, 40),
      // 60×115 + 400×18,9 + 18×42 = R$ 15.216,00 → 102,4646 sacas de soja. Os
      // três insumos com exigência por hectare estão nos mínimos dos 120 ha do
      // Antônio, como estariam se ela tivesse passado pelo servidor.
      items: [
        grainItem(soja, 102.4646, 148.5),
        inputItem(npk, 60, 115.0),
        inputItem(glifosato, 400, 18.9),
        inputItem(lambda, 18, 42.0),
      ],
    },
  ];

  // Onde cada permuta é retirada. O padrão é a unidade do próprio consultor,
  // que é o caso comum — menos a do Roberto para o Joaquim, retirada na Matriz
  // de propósito: é o dataset mostrando que a retirada é combinada com o
  // produtor e não tem relação nenhuma com quem analisa a permuta.
  const unitOfConsultant = new Map([
    [joao.id, filial02],
    [ana.id, filial04],
    [roberto.id, filial34],
    [maria.id, filial24],
    [lucas.id, filial18],
  ]);
  const pickupOverride = new Map([['PRM-2026-008', matriz]]);

  // A FORMA de recolhimento escolhida no fechamento de cada permuta. O padrão é
  // a comercialização; estas duas fecharam sobre a FOLHA, e existem para o
  // dataset mostrar as duas alíquotas — uma de produtor CPF (fica só o Senar de
  // 0,20%) e outra de CNPJ (0,25%). Sem elas, toda permuta sairia com o mesmo
  // percentual e a linha de imposto passaria por certa mostrando sempre o mesmo
  // número.
  const taxRegimeOverride = new Map<string, TaxRegime>([
    // Cláudia Nunes, CPF: sobra o Senar de 0,20%.
    ['PRM-2026-004', TAX_REGIME.folha],
    // Vanessa Lopes, CNPJ: sobra o Senar de 0,25%.
    ['PRM-2026-007', TAX_REGIME.folha],
  ]);

  for (const entry of barters) {
    const homeUnit = unitOfConsultant.get(entry.consultant.id)!;
    const unit = pickupOverride.get(entry.code) ?? homeUnit;
    // O destinatário é o gerente do CONSULTOR — a mesma regra que o
    // BartersService impõe, aqui só reproduzida para o dataset.
    const manager = managerOfConsultant.get(entry.consultant.id)!;
    const taxRegime = taxRegimeOverride.get(entry.code) ?? TAX_REGIME.comercializacao;

    await prisma.barter.create({
      data: {
        code: entry.code,
        versionId: entry.version.id,
        versionCode: entry.version.code,
        consultantId: entry.consultant.id,
        consultantName: entry.consultant.fullName,
        consultantBranch: homeUnit.name,
        producerId: entry.producer.id,
        producerName: entry.producer.name,
        // A ÁREA congelada no registro — o denominador do investimento por
        // hectare. Sai do cadastro do produtor, que é de onde o service a copia.
        producerAreaHa: entry.producer.areaHa,
        unitId: unit.id,
        unitName: unit.name,
        status: entry.status,
        // O PARECER DO CONSULTOR e o encaminhamento. O rascunho é o único sem os
        // dois: ele ainda não foi escrito nem enviado, que é o que rascunho é.
        consultantNote: entry.consultantNote || null,
        consultantSentAt: entry.status === 'draft' ? null : entry.createdAt,
        // A mesma conta do BartersService: a forma escolhida no fechamento e a
        // alíquota que ela produziu para este produtor.
        taxRegime,
        taxRate: taxRateOf(taxRegime, documentDigitsOf(entry.producer.document)),
        // O destinatário existe desde o ENCAMINHAMENTO; o parecer só nas que já
        // passaram pela etapa. As duas em `sentToManager` estão endereçadas e
        // sem nota; o rascunho não está endereçado a ninguém.
        managerId: entry.status === 'draft' ? null : manager.id,
        managerName: entry.status === 'draft' ? null : manager.fullName,
        managerNote: entry.managerNote ?? null,
        managerReviewedAt: entry.managerReviewedAt ?? null,
        // Quem decide é o COMITÊ. Era o admin quando o dataset foi escrito, e a
        // assinatura mudou junto com a regra: uma demonstração em que o admin
        // aprova ensinaria errado o fluxo que o sistema passou a ter.
        reviewNote: entry.reviewNote ?? null,
        reviewedBy: entry.reviewedAt ? comite.fullName : null,
        reviewedById: entry.reviewedAt ? comite.id : null,
        reviewedAt: entry.reviewedAt ?? null,
        invoiceNote: entry.invoiceNote ?? null,
        invoicedBy: entry.invoicedAt ? patricia.fullName : null,
        invoicedById: entry.invoicedAt ? patricia.id : null,
        invoicedAt: entry.invoicedAt ?? null,
        createdAt: entry.createdAt,
        items: { create: entry.items },
        events: { create: timelineOf(entry) },
      },
    });
  }

  /* ── A cédula pronta ──────────────────────────────────────────────── */
  //
  // UMA cédula completa no dataset, na PRM-2026-001 — a única já faturada, e
  // por isso a que abre direto no botão "Cédula de Produto Rural" sem passar
  // pelo faturamento. É o documento pronto para ser gerado: abrir a permuta e
  // exportar o DOCX/PDF, sem digitar nada antes.
  //
  // Ela existe porque a tela da cédula tem dois estados muito diferentes — o
  // formulário vazio (que as outras permutas já mostram) e o documento fechado
  // — e o segundo não aparecia em demonstração nenhuma: chegar até ele custava
  // uns quarenta campos digitados à mão, e ninguém faz isso duas vezes.
  //
  // TODO CAMPO QUE `cprGaps()` COBRA está preenchido, e é isso que faz
  // `complete` vir `true` (a credora, que é a outra metade da conta, já está
  // cadastrada mais acima). O Antônio é CASADO de propósito: é o que aciona o
  // bloco de anuência do cônjuge, que fica vazio na maioria das cédulas e por
  // isso é justamente o que ninguém vê antes de precisar dele.
  const faturada = await prisma.barter.findUniqueOrThrow({
    where: { code: 'PRM-2026-001' },
  });
  await prisma.barterCpr.create({
    data: {
      barterId: faturada.id,
      number: 'CPR-2026-014',
      // Emitida no dia do faturamento e vencendo na colheita — que é o que a
      // CPR é: a promessa de entregar o grão que ainda está na lavoura.
      //
      // O VENCIMENTO é gravado ao MEIO-DIA UTC, e a hora não é enfeite: ele é
      // uma data de calendário que sai impressa ("IV – VENCIMENTO: 30/06/2026"),
      // e o app a lê em hora local. À meia-noite UTC, que é o que `at()` dá por
      // omissão, o documento saía com 29/06 para quem está no Brasil — um dia a
      // menos num prazo de entrega, dentro de um título executável. Meio-dia
      // deixa a data certa de UTC-11 a UTC+11. O app não tem esse problema: ele
      // grava o que o calendário devolve em hora local; quem precisa da hora é
      // este dataset, que escreve UTC direto.
      issuedAt: at(2026, 1, 12, 10, 30),
      dueDate: at(2026, 6, 30, 12),

      emitterNationality: 'brasileiro',
      emitterMaritalStatus: 'casado',
      emitterProfession: 'produtor rural',
      emitterRg: '5.482.109-3 SSP/PR',
      emitterAddress: 'Estrada da Boa Vista',
      emitterAddressNumber: 'km 12',
      emitterCity: 'Maringá/PR',
      emitterCoopId: '4471',
      // Coletados e não impressos: nenhuma cláusula do modelo os usa, e por
      // isso `cprGaps()` não os cobra. Estão aqui para a tela mostrar o bloco
      // da proposta preenchido como ele fica na vida real.
      emitterCnh: '02938475610',
      emitterFatherName: 'Sebastião Carvalho',
      emitterMotherName: 'Therezinha Moraes Carvalho',
      emitterEmail: 'antonio.carvalho@exemplo.com.br',

      // O local da entrega é a unidade de retirada dele — o caso comum, e o
      // que a tela sugere. Ele SAI no documento (cláusula V, "d").
      deliveryPlace: 'Filial 02 – Gran. Santa T.',
      mortgages: 'Hipoteca de 1º grau sobre a matrícula 18.442, junto ao Banco do Brasil S.A.',

      spouseName: 'Marta Regina Carvalho',
      spouseNationality: 'brasileira',
      spouseProfession: 'produtora rural',
      spouseDocument: '321.654.987-00',
      spouseRg: '6.115.884-0 SSP/PR',

      // O padrão da soja: 60 kg por saca, 14% de umidade, 1% de impurezas e
      // 18% de teor de óleo. São os números do modelo recebido.
      sackWeightKg: 60,
      cultivar: 'BMX Ativa RR',
      maxMoisture: 14,
      maxImpurities: 1,
      oilContent: 18,

      invoiceNumber: '55.318',
      duplicateNumber: '55.318-A',
      // Com apólice, para a alínea "j" da cláusula XVIII aparecer no documento:
      // ela só existe quando há seguro, e uma cédula sem seguro não a imprime.
      insurancePolicy: 'AP-2026-778.412',

      filledBy: patricia.fullName,
      filledById: patricia.id,

      // DUAS lavouras, e não uma: a cláusula VI as enumera ("(i)… e (ii)…"), e
      // com uma só o documento nunca mostra a conjunção nem a segunda
      // matrícula. A segunda é ARRENDADA — o dono do imóvel não é o emitente,
      // que é o caso comum e a razão de o modelo nomear os dois separadamente.
      areas: {
        create: [
          {
            position: 0,
            locality: 'Gleba Ribeirão Morangueiro',
            city: 'Maringá/PR',
            areaHa: 78.5,
            withinLargerArea: false,
            registryNumber: '18.442',
            registryBook: '2-RG',
            registryDistrict: 'Maringá/PR',
            owners: {
              create: [
                { position: 0, name: 'Antônio Carvalho', document: '123.456.789-00' },
                { position: 1, name: 'Marta Regina Carvalho', document: '321.654.987-00' },
              ],
            },
          },
          {
            position: 1,
            locality: 'Gleba Patrimônio Ivaí',
            city: 'Doutor Camargo/PR',
            // 45,05 ha de propósito: o zero à esquerda do bloco decimal é o
            // caso em que o extenso e o algarismo já discordaram, e agora ele
            // sai impresso em toda geração do documento — "quarenta e cinco
            // vírgula zero cinco hectares". Ver `extensoDecimal`, no app.
            areaHa: 45.05,
            withinLargerArea: true,
            registryNumber: '7.309',
            registryBook: '2-RG',
            registryDistrict: 'Floresta/PR',
            owners: {
              create: [{ position: 0, name: 'Espólio de Idalina Perotto', document: '456.789.123-00' }],
            },
          },
        ],
      },

      // Um AVALISTA — coletado pela proposta e ainda não impresso (o modelo não
      // tem cláusula de aval). Está aqui para o bloco mais longo do formulário
      // abrir preenchido pelo menos uma vez.
      guarantors: {
        create: [
          {
            position: 0,
            name: 'Nelson Carvalho',
            document: '987.654.321-00',
            rg: '4.220.876-5 SSP/PR',
            cnh: '01827364590',
            nationality: 'brasileiro',
            profession: 'comerciante',
            maritalStatus: 'casado',
            fatherName: 'Sebastião Carvalho',
            motherName: 'Therezinha Moraes Carvalho',
            email: 'nelson.carvalho@exemplo.com.br',
            address: 'Rua Néo Alves Martins',
            addressNumber: '2887',
            city: 'Maringá/PR',
            spouseName: 'Cláudia Bianchi Carvalho',
            spouseDocument: '654.321.987-00',
            spouseRg: '7.881.230-4 SSP/PR',
            spouseNationality: 'brasileira',
            spouseProfession: 'advogada',
          },
        ],
      },
    },
  });

  /**
   * A LINHA DO TEMPO de uma permuta do dataset, montada a partir dos marcos que
   * a entrada declara.
   *
   * Ela é derivada, e não escrita à mão em cada permuta, de propósito: uma
   * história inventada linha a linha teria como divergir dos campos da própria
   * permuta — um parecer no histórico que não está em `managerNote`, uma decisão
   * com data diferente de `reviewedAt` — e a demonstração passaria a mostrar uma
   * inconsistência que o sistema real não produz. Aqui as duas coisas saem da
   * mesma fonte, como saem no BartersService.
   */
  function timelineOf(entry: (typeof barters)[number]) {
    const manager = managerOfConsultant.get(entry.consultant.id)!;
    const steps: Prisma.BarterEventCreateWithoutBarterInput[] = [
      {
        action: 'register',
        fromStatus: null,
        toStatus: 'draft',
        actorId: entry.consultant.id,
        actorName: entry.consultant.fullName,
        actorRole: ROLE.consultant,
        at: entry.createdAt,
      },
    ];

    // O ENCAMINHAMENTO é o segundo passo, e leva o parecer do consultor junto —
    // é ele que tira a permuta da mesa dela. Mesma data do registro no dataset:
    // as permutas de demonstração foram montadas e mandadas no mesmo ato, que é
    // o caso comum de quem já vem da conversa com o produtor.
    if (entry.status !== 'draft') {
      steps.push({
        action: 'forward',
        fromStatus: 'draft',
        toStatus: 'sentToManager',
        actorId: entry.consultant.id,
        actorName: entry.consultant.fullName,
        actorRole: ROLE.consultant,
        note: entry.consultantNote || null,
        at: entry.createdAt,
      });
    }

    if (entry.managerReviewedAt) {
      steps.push({
        action: 'opinion',
        fromStatus: 'sentToManager',
        toStatus: 'pending',
        actorId: manager.id,
        actorName: manager.fullName,
        actorRole: ROLE.manager,
        note: entry.managerNote ?? null,
        at: entry.managerReviewedAt,
      });
    }

    if (entry.reviewedAt) {
      steps.push({
        action: 'review',
        fromStatus: 'pending',
        // A decisão foi APROVAR, aprovar COM RESSALVA ou NEGAR — e ela é lida do
        // estado, menos em `invoiced`: esse veio depois, do faturista, e lê-lo
        // aqui faria o comitê parecer ter faturado.
        toStatus: entry.status === 'invoiced' ? 'approved' : entry.status,
        actorId: comite.id,
        actorName: comite.fullName,
        actorRole: ROLE.committee,
        note: entry.reviewNote ?? null,
        at: entry.reviewedAt,
      });
    }

    if (entry.invoicedAt) {
      steps.push({
        action: 'invoice',
        fromStatus: 'approved',
        toStatus: 'invoiced',
        actorId: patricia.id,
        actorName: patricia.fullName,
        actorRole: ROLE.biller,
        note: entry.invoiceNote ?? null,
        at: entry.invoicedAt,
      });
    }

    return steps;
  }
}
