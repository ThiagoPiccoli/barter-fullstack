import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { User } from '@prisma/client';
import { AccessGuard } from './access.guard';
import { ANY_ROLE_KEY, IS_PUBLIC_KEY, REQUIRED_CAPABILITIES_KEY, ROLES_KEY } from './decorators';
import { CAPABILITY } from './policy';
import { ROLE } from './roles';

/**
 * O guard de autorização, com atenção ao caso que motivou reescrevê-lo: rota
 * SEM política declarada.
 *
 * No desenho anterior, ausência de decorator significava "liberado para
 * qualquer autenticado". Um endpoint novo sem a linha de acesso nascia
 * atendendo quem não devia, em silêncio. Aqui isso é uma recusa.
 */
describe('AccessGuard', () => {
  const guard = new AccessGuard(new Reflector());

  /** Monta um contexto com os metadados que o Nest teria lido dos decorators. */
  const contextWith = (metadata: Record<string, unknown>, role?: string): ExecutionContext => {
    const handler = () => undefined;
    for (const [key, value] of Object.entries(metadata)) {
      Reflect.defineMetadata(key, value, handler);
    }
    class FakeController {}
    return {
      getHandler: () => handler,
      getClass: () => FakeController,
      switchToHttp: () => ({
        getRequest: () => (role ? { user: { role } as User } : {}),
      }),
    } as unknown as ExecutionContext;
  };

  describe('rota sem política declarada', () => {
    it('é RECUSADA, mesmo para o admin', () => {
      expect(() => guard.canActivate(contextWith({}, ROLE.admin))).toThrow(ForbiddenException);
    });

    it('é recusada também sem usuário nenhum', () => {
      expect(() => guard.canActivate(contextWith({}))).toThrow(ForbiddenException);
    });
  });

  it('@Public passa sem usuário', () => {
    expect(guard.canActivate(contextWith({ [IS_PUBLIC_KEY]: true }))).toBe(true);
  });

  it('@AnyRole passa para qualquer papel', () => {
    for (const role of Object.values(ROLE)) {
      expect(guard.canActivate(contextWith({ [ANY_ROLE_KEY]: true }, role))).toBe(true);
    }
  });

  describe('@RequireCapability', () => {
    const usersManage = { [REQUIRED_CAPABILITIES_KEY]: [CAPABILITY.usersManage] };

    it('deixa passar quem tem a capacidade', () => {
      expect(guard.canActivate(contextWith(usersManage, ROLE.admin))).toBe(true);
    });

    it('barra quem não tem — e diz quem tem', () => {
      for (const role of [ROLE.manager, ROLE.committee, ROLE.biller, ROLE.consultant]) {
        expect(() => guard.canActivate(contextWith(usersManage, role))).toThrow(
          'Ação permitida apenas para: Administrador',
        );
      }
    });

    it('exige TODAS as capacidades quando há mais de uma', () => {
      const duas = {
        [REQUIRED_CAPABILITIES_KEY]: [CAPABILITY.bartersReadAll, CAPABILITY.bartersReview],
      };
      // O admin lê tudo e não decide; o faturista lê tudo e fatura, mas também
      // não decide. Uma das duas capacidades faltando basta para barrar — quem
      // passa é só quem tem as duas, que aqui é o comitê.
      expect(() => guard.canActivate(contextWith(duas, ROLE.admin))).toThrow(ForbiddenException);
      expect(() => guard.canActivate(contextWith(duas, ROLE.biller))).toThrow(ForbiddenException);
      expect(guard.canActivate(contextWith(duas, ROLE.committee))).toBe(true);
    });

    /** Papel desconhecido (banco adulterado, servidor à frente do app) não tem capacidade nenhuma. */
    it('papel fora da tabela não passa', () => {
      expect(() => guard.canActivate(contextWith(usersManage, 'superadmin'))).toThrow(
        ForbiddenException,
      );
    });
  });

  it('@Roles continua valendo para a rota que é sobre o papel em si', () => {
    const somenteConsultor = { [ROLES_KEY]: [ROLE.consultant] };
    expect(guard.canActivate(contextWith(somenteConsultor, ROLE.consultant))).toBe(true);
    expect(() => guard.canActivate(contextWith(somenteConsultor, ROLE.admin))).toThrow(
      'Ação permitida apenas para: Consultor',
    );
  });

  /**
   * A precedência importa: um controller inteiro sob @RequireCapability e um
   * método que abre exceção. Se a capacidade vencesse o metadado do método, a
   * exceção seria ignorada; se o `@AnyRole` do método vencesse sempre, um
   * controller protegido teria buracos.
   */
  it('capacidade do método vence a marca do controller', () => {
    const context = contextWith(
      { [REQUIRED_CAPABILITIES_KEY]: [CAPABILITY.usersManage] },
      ROLE.biller,
    );
    Reflect.defineMetadata(ANY_ROLE_KEY, true, context.getClass());
    expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
  });
});
