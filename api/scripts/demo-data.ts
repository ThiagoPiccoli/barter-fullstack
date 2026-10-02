/**
 * DADOS DE DEMONSTRAÇÃO, por cima do seed — para mostrar o app inteiro.
 *
 * O seed (`npm run db:seed`) traz o dataset base: a soja 26/27 e o milho 2027
 * abertos, o trigo e o milho 25/26 encerrados, e uma permuta em cada posto da
 * esteira até o faturamento. Este script acrescenta o que o seed não mostra,
 * e o faz PELA API, com o usuário de cada papel — cada permuta nasce, anda e
 * congela os números pelas mesmas regras do app, e a trilha de auditoria e a
 * linha do tempo saem como sairiam de verdade:
 *
 * - a CANOLA 2027 (anual, seguro obrigatório) com permutas do rascunho à CPR
 *   emitida;
 * - permutas do MILHO 2027 com o seguro opcional ACEITO e RECUSADO;
 * - o TRIGO 2027 com uma versão que se ENCERROU SOZINHA ao bater a meta e a
 *   versão seguinte, com outra meta, já vendendo;
 * - a AVEIA 2026 encerrada — a que pode ser REABERTA na demonstração;
 * - a esteira inteira da CPR: emitida, assinada e registrada.
 *
 * Uso (com a API no ar, sobre um banco recém-semeado):
 *
 *     npm run db:seed
 *     API_URL=http://localhost:3333 npx ts-node scripts/demo-data.ts
 */

import { SEED_PASSWORD } from '../prisma/seed-data';

const BASE = `${process.env.API_URL ?? 'http://localhost:3333'}/api/v1`;

const EMAIL = {
  admin: 'admin@agrobarter.com.br',
  joao: 'joao.silva@agrobarter.com.br',
  ana: 'ana.ferreira@agrobarter.com.br',
  roberto: 'roberto.souza@agrobarter.com.br',
  maria: 'maria.oliveira@agrobarter.com.br',
  lucas: 'lucas.barros@agrobarter.com.br',
  beatriz: 'gerente@agrobarter.com.br',
  gustavo: 'gerente.sul@agrobarter.com.br',
  comite: 'comite@agrobarter.com.br',
  faturista: 'faturista@agrobarter.com.br',
  emissor: 'emissor@agrobarter.com.br',
} as const;

type Who = keyof typeof EMAIL;
type Json = Record<string, unknown>;

/** O gerente de cada consultor — quem dá o parecer. */
const MANAGER_OF: Partial<Record<Who, Who>> = {
  joao: 'beatriz',
  ana: 'beatriz',
  roberto: 'gustavo',
  maria: 'gustavo',
  lucas: 'gustavo',
};

const tokens = new Map<Who, string>();

async function token(who: Who): Promise<string> {
  const cached = tokens.get(who);
  if (cached) return cached;
  const response = await fetch(`${BASE}/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: EMAIL[who], password: SEED_PASSWORD }),
  });
  const body = (await response.json()) as { data?: { token?: string } };
  if (!body.data?.token) throw new Error(`Login de ${EMAIL[who]} falhou (HTTP ${response.status})`);
  tokens.set(who, body.data.token);
  return body.data.token;
}

async function call<T = Json>(who: Who, method: string, path: string, body?: unknown): Promise<T> {
  const response = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      authorization: `Bearer ${await token(who)}`,
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return unwrap<T>(response, `${method} ${path}`);
}

/** Um PDF mínimo de mentira — a API confere o tipo e o tamanho, não o conteúdo. */
function pdf(name: string): Blob {
  return new Blob([`%PDF-1.4\n${name}\n%%EOF\n`], { type: 'application/pdf' });
}

async function upload<T = Json>(
  who: Who,
  method: string,
  path: string,
  fileName: string,
  fields: Record<string, string> = {},
): Promise<T> {
  const form = new FormData();
  for (const [key, value] of Object.entries(fields)) form.append(key, value);
  form.append('file', pdf(fileName), fileName);
  const response = await fetch(`${BASE}${path}`, {
    method,
    headers: { authorization: `Bearer ${await token(who)}` },
    body: form,
  });
  return unwrap<T>(response, `${method} ${path}`);
}

async function unwrap<T>(response: Response, label: string): Promise<T> {
  const text = await response.text();
  const body = text ? (JSON.parse(text) as { data?: T; message?: unknown }) : {};
  if (!response.ok) {
    throw new Error(`${label} → HTTP ${response.status}: ${JSON.stringify(body.message ?? body)}`);
  }
  return body.data as T;
}

/* ── Leitura do que o seed criou ──────────────────────────────────────── */

interface Product {
  id: number;
  name: string;
  type: string;
}
interface Producer {
  id: number;
  name: string;
  city: string;
}
interface Season {
  id: number;
  code: string;
  slug: string;
  name: string;
}
interface Barter {
  code: string;
  status: string;
}

const iso = (date: string) => new Date(`${date}T12:00:00.000Z`).toISOString();

async function main() {
  console.log(`Dados de demonstração em ${BASE}\n`);

  const seasons = await call<Season[]>('admin', 'GET', '/seasons');
  if (seasons.some((season) => season.code === 'CANOLA2027')) {
    throw new Error(
      'A demonstração já foi aplicada neste banco. Rode `npm run db:seed` antes de repetir.',
    );
  }

  const products = await call<Product[]>('admin', 'GET', '/products?limit=200');
  const product = (name: string) => {
    const found = products.find((p) => p.name.toLowerCase().startsWith(name.toLowerCase()));
    if (!found) throw new Error(`Produto "${name}" não está no catálogo`);
    return found;
  };
  const npk = product('Fertilizante NPK');
  const glifosato = product('Herbicida Glifosato');
  const lambda = product('Inseticida Lambda');
  const fungicida = product('Fungicida Azoxistrobina');
  const semente = product('Semente Soja');

  const units = await call<{ id: number; name: string }[]>('admin', 'GET', '/units');
  const unit = (prefix: string) => units.find((u) => u.name.startsWith(prefix))!.id;

  /** Uma tabela de insumos com os preços de referência × um fator da cultura. */
  const table = (factor: number) =>
    [
      [npk, 115],
      [glifosato, 18.9],
      [lambda, 42],
      [fungicida, 87.5],
      [semente, 320],
    ].map(([p, price]) => ({
      productId: (p as Product).id,
      price: Math.round((price as number) * factor * 100) / 100,
    }));

  /* ── Safras e versões ────────────────────────────────────────────────── */

  // A CANOLA: o grão não existe no catálogo do seed — nasce aqui, como o admin
  // o cadastraria. Safra anual, de inverno, com seguro OBRIGATÓRIO.
  const canola = await call<Product>('admin', 'POST', '/products', {
    name: 'Canola',
    unit: 'saca 60kg',
    type: 'grain',
    currentPrice: 112,
  });
  await call('admin', 'POST', '/seasons', {
    grainId: canola.id,
    startYear: 2027,
    endYear: 2027,
    insurancePolicy: 'required',
  });
  await call('admin', 'POST', '/seasons/CANOLA2027/versions', {
    grainPrice: 112,
    estimatedYield: 35,
    cprDueDate: iso('2027-11-20'),
    insurancePolicy: 'required',
    targetSales: 450000,
    targetSacks: 4000,
    targetBarters: 20,
    note: 'Tabela de abertura da canola de inverno.',
    prices: table(1.02),
  });
  console.log('  ok  Canola 2027 aberta, CANOLA2027.01 publicada (seguro obrigatório)');

  // O TRIGO 2027: a primeira versão é um lote promocional que ENCERRA AO BATER
  // A META — uma permuta aprovada, e ela fecha sozinha.
  const trigo = product('Trigo');
  await call('admin', 'POST', '/seasons', {
    grainId: trigo.id,
    startYear: 2027,
    endYear: 2027,
    insurancePolicy: 'none',
  });
  await call('admin', 'POST', '/seasons/TRIGO2027/versions', {
    grainPrice: 86,
    estimatedYield: 55,
    cprDueDate: iso('2027-10-30'),
    targetBarters: 1,
    closeOnGoal: true,
    note: 'Lote promocional: encerra na primeira aprovação.',
    prices: table(0.95),
  });
  console.log('  ok  Trigo 2027 aberta, TRIGO2027.01 publicada (encerra ao bater meta)');

  // A AVEIA 2026: publicada e ENCERRADA — é a safra que o admin pode reabrir na
  // demonstração (nenhuma outra safra de aveia está aberta).
  await call('admin', 'POST', '/seasons', {
    grainId: product('Aveia').id,
    startYear: 2026,
    endYear: 2026,
    insurancePolicy: 'none',
  });
  await call('admin', 'POST', '/seasons/AVEIA2026/versions', {
    grainPrice: 52,
    estimatedYield: 50,
    cprDueDate: iso('2026-12-15'),
    note: 'Aveia de cobertura.',
    prices: table(0.9),
  });
  await call('admin', 'POST', '/seasons/AVEIA2026/close');
  console.log('  ok  Aveia 2026 publicada e encerrada (pode ser reaberta)');

  // A SOJA 26/27 vence na colheita de 2027 — o seed a trouxe com a data da
  // safra anterior. É o acerto de termos que o admin faz sem republicar.
  await call('admin', 'PUT', '/barter-versions/SOJA2627.02/terms', {
    cprDueDate: iso('2027-04-30'),
  });
  console.log('  ok  SOJA26/27.02 com o vencimento da CPR em 30/04/2027');

  /* ── Permutas ────────────────────────────────────────────────────────── */

  const allSeasons = await call<Season[]>('admin', 'GET', '/seasons');
  const seasonId = (code: string) => allSeasons.find((s) => s.code === code)!.id;

  const producersOf = new Map<Who, Producer[]>();
  const producer = async (who: Who, name: string) => {
    if (!producersOf.has(who)) {
      producersOf.set(who, await call<Producer[]>(who, 'GET', '/producers?limit=200'));
    }
    const found = producersOf.get(who)!.find((p) => p.name === name);
    if (!found) throw new Error(`${name} não está na carteira de ${EMAIL[who]}`);
    return found;
  };

  type Stop =
    | 'draft'
    | 'sentToManager'
    | 'pending'
    | 'approved'
    | 'approvedWithConditions'
    | 'invoiced'
    | 'cprIssued'
    | 'cprSigned'
    | 'cprRegistered';
  const ORDER: Stop[] = [
    'draft',
    'sentToManager',
    'pending',
    'approved',
    'invoiced',
    'cprIssued',
    'cprSigned',
    'cprRegistered',
  ];
  const reaches = (stop: Stop, step: Stop) =>
    ORDER.indexOf(stop === 'approvedWithConditions' ? 'approved' : stop) >= ORDER.indexOf(step);

  let cprNumber = 30;
  let registry = 21000;

  /** A CÉDULA preenchida pelo consultor — o que o encaminhamento exige. */
  const fillCpr = async (who: Who, code: string, p: Producer, area: number) => {
    await call(who, 'PUT', `/barters/${code}/cpr`, {
      emitterNationality: 'brasileiro',
      emitterMaritalStatus: 'casado',
      emitterProfession: 'produtor rural',
      emitterRg: `${10 + (registry % 80)}.234.567-8`,
      spouseName: 'Maria das Graças Silva',
      spouseDocument: '222.333.444-55',
      spouseNationality: 'brasileira',
      spouseProfession: 'produtora rural',
      emitterAddress: 'Estrada Rural',
      emitterAddressNumber: `km ${registry % 40}`,
      emitterCity: p.city,
      deliveryPlace: 'Unidade de recebimento da cooperativa',
      cultivar: 'Cultivar recomendada da região',
      maxMoisture: 14,
      maxImpurities: 1,
      oilContent: 18,
      areas: [
        {
          locality: 'Sede da fazenda',
          city: p.city,
          // Metade da área plantada em penhor: cobre a garantia exigida e não
          // passa da lavoura informada.
          areaHa: Math.round(area * 0.5 * 100) / 100,
          registryNumber: String(registry++),
          registryBook: '2-RG',
          registryDistrict: p.city,
          owners: [{ name: p.name, document: '111.222.333-44' }],
        },
      ],
    });
    await upload(who, 'PUT', `/barters/${code}/cpr/scr`, 'scr.pdf');
  };

  interface Spec {
    who: Who;
    producer: string;
    season: string;
    area: number;
    unit: string;
    stop: Stop;
    insurance?: boolean;
    withFungicide?: boolean;
    note: string;
    managerNote?: string;
    reviewNote?: string;
  }

  const created: { code: string; label: string }[] = [];

  const run = async (spec: Spec) => {
    const p = await producer(spec.who, spec.producer);
    // OS MÍNIMOS por hectare da área plantada: NPK 0,4, glifosato 2,5 e
    // lambda 0,15 por ha — com folga, para a régua das classes passar.
    const inputs = [
      { productId: npk.id, quantity: Math.ceil(spec.area * 0.45) },
      { productId: glifosato.id, quantity: Math.ceil(spec.area * 2.5) },
      { productId: lambda.id, quantity: Math.ceil(spec.area * 0.15 * 100) / 100 },
      ...(spec.withFungicide
        ? [{ productId: fungicida.id, quantity: Math.ceil(spec.area * 0.3) }]
        : []),
    ];
    const barter = await call<Barter>(spec.who, 'POST', '/barters', {
      producerId: p.id,
      seasonId: seasonId(spec.season),
      plantedAreaHa: spec.area,
      unitId: unit(spec.unit),
      inputs,
      ...(spec.insurance === undefined ? {} : { insurance: spec.insurance }),
      note: spec.note,
    });
    const code = barter.code;

    if (reaches(spec.stop, 'sentToManager')) {
      await fillCpr(spec.who, code, p, spec.area);
      await call(spec.who, 'POST', `/barters/${code}/forward`, { note: spec.note });
    }
    if (reaches(spec.stop, 'pending')) {
      await call(MANAGER_OF[spec.who]!, 'POST', `/barters/${code}/opinion`, {
        note: spec.managerNote ?? 'Área conferida, estoque disponível na unidade de retirada.',
      });
    }
    if (reaches(spec.stop, 'approved')) {
      const withConditions = spec.stop === 'approvedWithConditions';
      await call('comite', 'POST', `/barters/${code}/review`, {
        status: withConditions ? 'approvedWithConditions' : 'approved',
        ...(spec.reviewNote || withConditions
          ? { note: spec.reviewNote ?? 'Aprovada com aval do cônjuge antes da retirada.' }
          : {}),
        ...(withConditions ? { requiresGuarantor: true } : {}),
      });
    }
    if (reaches(spec.stop, 'invoiced')) {
      await upload('faturista', 'POST', `/barters/${code}/invoices`, 'nota.pdf', {
        number: `00${registry}`,
        series: '1',
        duplicateNumber: `${registry}-A`,
      });
      await call('faturista', 'POST', `/barters/${code}/invoice`, {
        note: 'Nota emitida e enviada ao produtor.',
      });
    }
    if (reaches(spec.stop, 'cprIssued')) {
      await call('emissor', 'POST', `/barters/${code}/cpr/issue`, {
        number: `CPR-2026-0${cprNumber++}`,
        note: 'Duas vias impressas.',
      });
    }
    if (reaches(spec.stop, 'cprSigned')) {
      await upload('emissor', 'POST', `/barters/${code}/cpr/signatures`, 'cpr-assinada.pdf', {
        signedAt: new Date().toISOString(),
        note: 'Assinada na unidade, com o cônjuge.',
      });
    }
    if (reaches(spec.stop, 'cprRegistered')) {
      await call('emissor', 'POST', `/barters/${code}/cpr/registration`, {
        registryNumber: `R-${registry % 9}/${registry}`,
        registryPlace: `Cartório de Registro de Imóveis de ${p.city}`,
      });
      await upload('emissor', 'PUT', `/barters/${code}/cpr/registry-file`, 'via-registrada.pdf');
    }

    const label = `${spec.season} • ${spec.producer} • ${spec.stop}`;
    created.push({ code, label });
    console.log(`  ok  ${code}  ${label}`);
    return code;
  };

  // CANOLA 2027 — seguro obrigatório, uma permuta em cada trecho da esteira.
  await run({
    who: 'joao',
    producer: 'Antônio Carvalho',
    season: 'CANOLA2027',
    area: 80,
    unit: 'Filial 02',
    stop: 'draft',
    note: 'Talhão de inverno do Antônio. Falta combinar a data de retirada.',
  });
  await run({
    who: 'ana',
    producer: 'Cláudia Nunes',
    season: 'CANOLA2027',
    area: 60,
    unit: 'Filial 04',
    stop: 'sentToManager',
    withFungicide: true,
    note: 'Primeira canola da Cláudia; a área é a mesma do trigo do ano passado.',
  });
  await run({
    who: 'roberto',
    producer: 'Joaquim Tavares',
    season: 'CANOLA2027',
    area: 150,
    unit: 'Filial 18',
    stop: 'pending',
    note: 'Cliente grande da praça, rotação soja-canola há três safras.',
  });
  await run({
    who: 'maria',
    producer: 'Osmar Dutra',
    season: 'CANOLA2027',
    area: 120,
    unit: 'Filial 24',
    stop: 'cprIssued',
    withFungicide: true,
    note: 'Retira tudo de uma vez, como na soja.',
  });

  // MILHO 2027 — seguro OPCIONAL: aceito por um, recusado por outro.
  await run({
    who: 'joao',
    producer: 'Sebastião Ramos',
    season: 'MILHO2027',
    area: 50,
    unit: 'Filial 02',
    stop: 'approved',
    insurance: true,
    note: 'Safrinha do Sebastião. Ele quis o seguro depois da seca de 2024.',
  });
  await run({
    who: 'lucas',
    producer: 'Vanessa Lopes',
    season: 'MILHO2027',
    area: 90,
    unit: 'Filial 34',
    stop: 'pending',
    insurance: false,
    note: 'A produtora recusou o seguro: já tem apólice própria da área arrendada.',
  });
  await run({
    who: 'ana',
    producer: 'Helena Prado',
    season: 'MILHO2027',
    area: 40,
    unit: 'Filial 04',
    stop: 'cprSigned',
    insurance: true,
    note: 'Milho safrinha da Helena, com seguro.',
  });

  // TRIGO 2027 — a aprovação desta permuta BATE A META do lote promocional e
  // encerra a TRIGO2027.01 sozinha.
  await run({
    who: 'maria',
    producer: 'Osmar Dutra',
    season: 'TRIGO2027',
    area: 100,
    unit: 'Filial 24',
    stop: 'approved',
    note: 'Entrou no lote promocional do trigo.',
  });
  // A segunda versão sai com outra meta — e o trigo volta a vender.
  await call('admin', 'POST', '/seasons/TRIGO2027/versions', {
    grainPrice: 88,
    estimatedYield: 55,
    cprDueDate: iso('2027-10-30'),
    targetSacks: 2500,
    targetBarters: 15,
    note: 'Tabela regular, depois do lote promocional.',
    prices: table(0.97),
  });
  console.log('  ok  TRIGO2027.02 publicada com a meta nova');
  await run({
    who: 'lucas',
    producer: 'Vanessa Lopes',
    season: 'TRIGO2027',
    area: 70,
    unit: 'Filial 34',
    stop: 'sentToManager',
    note: 'Trigo nos talhões que saem do milho.',
  });

  // SOJA 26/27 — a PRM-2026-001 do seed (faturada, cédula pronta) percorre o
  // trecho inteiro do emissor: emitida, assinada e registrada.
  await call('emissor', 'POST', '/barters/PRM-2026-001/cpr/issue', {
    note: 'Duas vias impressas.',
  });
  await upload('emissor', 'POST', '/barters/PRM-2026-001/cpr/signatures', 'cpr-assinada.pdf', {
    signedAt: new Date().toISOString(),
  });
  await call('emissor', 'POST', '/barters/PRM-2026-001/cpr/registration', {
    registryNumber: 'R-4/18.442',
    registryPlace: 'Cartório de Registro de Imóveis de Maringá/PR',
  });
  await upload('emissor', 'PUT', '/barters/PRM-2026-001/cpr/registry-file', 'via-registrada.pdf');
  console.log('  ok  PRM-2026-001  SOJA26/27 • Antônio Carvalho • cprRegistered');

  // Uma permuta de soja a mais, aprovada com ressalva — a mesa do faturista.
  await run({
    who: 'roberto',
    producer: 'Joaquim Tavares',
    season: 'SOJA26/27',
    area: 320,
    unit: 'Filial 18',
    stop: 'approvedWithConditions',
    withFungicide: true,
    note: 'Ampliação da área arrendada na soja.',
    reviewNote: 'Aprovada com aval do cônjuge e matrícula da área arrendada antes da retirada.',
  });

  const trigo01 = await call<{ status: string; closedBy: string }>(
    'admin',
    'GET',
    '/barter-versions/TRIGO2027.01',
  );
  console.log(`\n  TRIGO2027.01: ${trigo01.status} — ${trigo01.closedBy}`);
  console.log(`\nPronto: ${created.length} permuta(s) novas por cima do seed.`);
}

main().catch((error: unknown) => {
  console.error(`\nFalhou: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});
