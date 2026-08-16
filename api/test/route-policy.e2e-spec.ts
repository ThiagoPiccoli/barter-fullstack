import { RequestMethod, type INestApplication } from '@nestjs/common';
import { METHOD_METADATA, PATH_METADATA } from '@nestjs/common/constants';
import { DiscoveryModule, DiscoveryService, MetadataScanner } from '@nestjs/core';
import { Test } from '@nestjs/testing';
import {
  ANY_ROLE_KEY,
  IS_PUBLIC_KEY,
  REQUIRED_CAPABILITIES_KEY,
  ROLES_KEY,
} from '../src/common/decorators';
import { AppModule } from '../src/app.module';

/**
 * O INVENTÁRIO DE ROTAS.
 *
 * Percorre a árvore de controllers que o Nest realmente registrou e lê a
 * política de acesso de cada handler. Duas coisas são travadas aqui:
 *
 * 1. nenhuma rota fica sem política declarada;
 * 2. a política de cada rota é EXATAMENTE a da tabela abaixo.
 *
 * O item 2 é o que dá o alarme. Rota nova, ou mudança de quem pode chamar uma
 * já existente, quebra este teste até alguém escrever a linha correspondente —
 * ou seja, até alguém tomar a decisão de acesso conscientemente, em vez de
 * herdá-la de um decorator copiado do arquivo ao lado.
 *
 * Ele existe porque o modo de falha anterior era silencioso: acrescentar um
 * endpoint e esquecer a linha de acesso não produzia erro nenhum — a rota
 * nascia aberta e funcionava.
 */
describe('Política de acesso de TODAS as rotas (e2e)', () => {
  let app: INestApplication;
  let routes: { route: string; policy: string }[];

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule, DiscoveryModule],
    }).compile();
    app = moduleRef.createNestApplication({ logger: false, bodyParser: false });
    await app.init();
    routes = collectRoutes(app);
  });

  afterAll(() => app.close());

  /**
   * Lê a política de um handler: o metadado do método vence o da classe, que é
   * a mesma precedência que o AccessGuard aplica em produção. Se lesse
   * diferente, o inventário atestaria uma coisa e o servidor faria outra.
   */
  const policyOf = (handler: object, controller: object): string => {
    const read = <T>(key: string): T | undefined =>
      (Reflect.getMetadata(key, handler) as T) ?? (Reflect.getMetadata(key, controller) as T);

    if (read<boolean>(IS_PUBLIC_KEY)) return 'public';
    const capabilities = read<string[]>(REQUIRED_CAPABILITIES_KEY);
    if (capabilities?.length) return `capability:${[...capabilities].sort().join('+')}`;
    const roles = read<string[]>(ROLES_KEY);
    if (roles?.length) return `role:${[...roles].sort().join('+')}`;
    if (read<boolean>(ANY_ROLE_KEY)) return 'any-authenticated';
    return 'SEM POLÍTICA';
  };

  function collectRoutes(instance: INestApplication) {
    const discovery = instance.get(DiscoveryService);
    const scanner = new MetadataScanner();
    const found: { route: string; policy: string }[] = [];

    for (const wrapper of discovery.getControllers()) {
      const { instance: controller, metatype } = wrapper;
      if (!controller || !metatype) continue;
      const prototype = Object.getPrototypeOf(controller) as object;
      const base = (Reflect.getMetadata(PATH_METADATA, metatype) as string) ?? '';

      for (const name of scanner.getAllMethodNames(prototype)) {
        const handler = (prototype as Record<string, object>)[name];
        const method = Reflect.getMetadata(METHOD_METADATA, handler) as number | undefined;
        if (method === undefined) continue; // não é rota

        const suffix = (Reflect.getMetadata(PATH_METADATA, handler) as string) ?? '';
        const path = [base, suffix].filter((part) => part && part !== '/').join('/');
        found.push({
          route: `${RequestMethod[method]} /${path}`,
          policy: policyOf(handler, metatype),
        });
      }
    }
    return found.sort((a, b) => a.route.localeCompare(b.route));
  }

  it('o inventário enxerga as rotas de verdade (rede de segurança do próprio teste)', () => {
    // Se a introspecção quebrar numa versão futura do Nest, ela devolveria uma
    // lista vazia — e um teste que não vê rota nenhuma passaria feliz enquanto
    // atestava exatamente nada.
    expect(routes.length).toBeGreaterThan(20);
    expect(routes.map((r) => r.route)).toContain('POST /barters');
  });

  it('nenhuma rota fica sem política de acesso declarada', () => {
    const semPolitica = routes.filter((r) => r.policy === 'SEM POLÍTICA').map((r) => r.route);
    expect(semPolitica).toEqual([]);
  });

  it('a política de cada rota é a esperada', () => {
    expect(routes).toEqual(
      [
        // Sessão — qualquer autenticado, seja qual for o papel.
        { route: 'GET /me', policy: 'any-authenticated' },
        { route: 'POST /auth/login', policy: 'public' },
        { route: 'POST /auth/logout', policy: 'any-authenticated' },
        { route: 'POST /auth/password', policy: 'any-authenticated' },

        // Sinal de vida e sonda de saúde, as duas fora do prefixo e as duas
        // públicas: sonda não carrega credencial.
        { route: 'GET /', policy: 'public' },
        { route: 'GET /health', policy: 'public' },

        // Trilha de auditoria.
        { route: 'GET /audit-logs', policy: 'capability:audit.read' },

        // Permutas — leitura escopada pelo service; escrita por capacidade.
        { route: 'GET /barters', policy: 'any-authenticated' },
        { route: 'GET /barters/:code', policy: 'any-authenticated' },
        { route: 'POST /barters', policy: 'capability:barters.register' },
        { route: 'POST /barters/:code/review', policy: 'capability:barters.review' },

        // Lançamento do Barter — safra e versões são do admin. A exceção é a
        // versão VIGENTE: o consultor precisa dela para saber se há Barter
        // aberto e para a prévia das sacas.
        { route: 'GET /barter-versions/current', policy: 'any-authenticated' },
        { route: 'GET /barter-versions/:code', policy: 'capability:barter.manage' },
        { route: 'POST /barter-versions/:code/close', policy: 'capability:barter.manage' },
        {
          route: 'PUT /barter-versions/:code/prices/:productId',
          policy: 'capability:barter.manage',
        },
        { route: 'GET /seasons', policy: 'capability:barter.manage' },
        { route: 'POST /seasons', policy: 'capability:barter.manage' },
        { route: 'POST /seasons/:code/close', policy: 'capability:barter.manage' },
        { route: 'POST /seasons/:code/versions', policy: 'capability:barter.manage' },
        { route: 'POST /seasons/:code/versions/import', policy: 'capability:barter.manage' },

        // Catálogo — leitura comum, gestão do admin.
        // Classes: a lista é FIXA (vem da migration), então só há leitura e o
        // ajuste da regra de mínimo. Não existe POST nem DELETE — e é isso que
        // este inventário trava.
        { route: 'GET /classes', policy: 'any-authenticated' },
        { route: 'PUT /classes/:id/rule', policy: 'capability:catalog.manage' },
        { route: 'DELETE /products/:id', policy: 'capability:catalog.manage' },
        { route: 'GET /products', policy: 'any-authenticated' },
        { route: 'GET /products/:id', policy: 'any-authenticated' },
        { route: 'POST /products', policy: 'capability:catalog.manage' },
        { route: 'PUT /products/:id', policy: 'capability:catalog.manage' },
        // Sem rota de preço no catálogo: valor é da versão do Barter.

        // Produtores — leitura escopada pelo service; cadastro do admin.
        { route: 'DELETE /producers/:id', policy: 'capability:producers.manage' },
        { route: 'GET /producers', policy: 'any-authenticated' },
        { route: 'GET /producers/:id', policy: 'any-authenticated' },
        { route: 'POST /producers', policy: 'capability:producers.manage' },
        { route: 'PUT /producers/:id', policy: 'capability:producers.manage' },

        // Usuários — uma rota por papel, todas sob a mesma capacidade.
        { route: 'DELETE /billers/:id', policy: 'capability:users.manage' },
        { route: 'GET /billers', policy: 'capability:users.manage' },
        { route: 'POST /billers', policy: 'capability:users.manage' },
        { route: 'POST /billers/:id/reset-password', policy: 'capability:users.manage' },
        { route: 'PUT /billers/:id', policy: 'capability:users.manage' },
        { route: 'DELETE /committee-members/:id', policy: 'capability:users.manage' },
        { route: 'GET /committee-members', policy: 'capability:users.manage' },
        { route: 'POST /committee-members', policy: 'capability:users.manage' },
        { route: 'POST /committee-members/:id/reset-password', policy: 'capability:users.manage' },
        { route: 'PUT /committee-members/:id', policy: 'capability:users.manage' },
        { route: 'DELETE /consultants/:id', policy: 'capability:users.manage' },
        { route: 'GET /consultants', policy: 'capability:users.manage' },
        { route: 'POST /consultants', policy: 'capability:users.manage' },
        { route: 'POST /consultants/:id/reset-password', policy: 'capability:users.manage' },
        { route: 'PUT /consultants/:id', policy: 'capability:users.manage' },
        { route: 'DELETE /managers/:id', policy: 'capability:users.manage' },
        { route: 'GET /managers', policy: 'capability:users.manage' },
        { route: 'POST /managers', policy: 'capability:users.manage' },
        { route: 'POST /managers/:id/reset-password', policy: 'capability:users.manage' },
        { route: 'PUT /managers/:id', policy: 'capability:users.manage' },
      ].sort((a, b) => a.route.localeCompare(b.route)),
    );
  });
});
