import { CAPABILITIES, CAPABILITY, ROLE_CAPABILITIES, can, rolesWith } from './policy';
import { ROLE, ROLES } from './roles';

/**
 * A tabela de capacidades é a resposta a "o que cada papel pode". Estes testes
 * escrevem essa resposta por extenso — de modo que ampliar o poder de um papel
 * seja uma linha alterada AQUI, visível em revisão, e não um efeito colateral
 * de mexer num decorator qualquer.
 */
describe('Tabela de capacidades', () => {
  it('todo papel está na tabela', () => {
    expect(Object.keys(ROLE_CAPABILITIES).sort()).toEqual([...ROLES].sort());
  });

  it('nenhuma capacidade fica órfã (concedida a ninguém)', () => {
    const orfas = CAPABILITIES.filter((capability) => rolesWith(capability).length === 0);
    expect(orfas).toEqual([]);
  });

  it('o admin é o único que gerencia usuários, catálogo, produtores e auditoria', () => {
    for (const capability of [
      CAPABILITY.usersManage,
      CAPABILITY.catalogManage,
      CAPABILITY.producersManage,
      CAPABILITY.auditRead,
      CAPABILITY.bartersReview,
    ]) {
      expect(rolesWith(capability)).toEqual([ROLE.admin]);
    }
  });

  it('registrar permuta é só do consultor', () => {
    expect(rolesWith(CAPABILITY.bartersRegister)).toEqual([ROLE.consultant]);
  });

  /**
   * O estado combinado: gerente, comitê e faturista ENXERGAM a operação e não
   * escrevem nada. Quando o contrato entre eles for definido, este teste é o
   * que vai obrigar a decisão a ser explícita — ele quebra no momento em que
   * alguém der escrita a um deles.
   */
  it('a retaguarda nova está em leitura, sem nenhuma escrita', () => {
    for (const role of [ROLE.manager, ROLE.committee, ROLE.biller]) {
      expect([...ROLE_CAPABILITIES[role]].sort()).toEqual(
        [CAPABILITY.bartersReadAll, CAPABILITY.producersReadAll].sort(),
      );
    }
  });

  it('o consultor não enxerga além da própria carteira', () => {
    expect(can({ role: ROLE.consultant }, CAPABILITY.bartersReadAll)).toBe(false);
    expect(can({ role: ROLE.consultant }, CAPABILITY.producersReadAll)).toBe(false);
  });

  it('papel desconhecido não tem capacidade nenhuma — falha fechando', () => {
    for (const capability of CAPABILITIES) {
      expect(can({ role: 'diretor' }, capability)).toBe(false);
    }
  });
});
