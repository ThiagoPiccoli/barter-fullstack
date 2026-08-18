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

  it('o admin é o único que gerencia usuários, unidades, catálogo, produtores e auditoria', () => {
    for (const capability of [
      CAPABILITY.usersManage,
      CAPABILITY.unitsManage,
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
   * A ETAPA DO GERENTE é dele e de mais ninguém.
   *
   * O parecer técnico não é uma segunda aprovação: é o responsável pela unidade
   * dizendo o que pensa da negociação que vai ser retirada lá. Dar isso ao
   * admin "porque ele pode tudo" esvaziaria a etapa — ele passaria a opinar
   * sobre praças que não conhece, e a permuta seguiria sem nunca ter passado
   * pela unidade.
   */
  it('o parecer técnico é só do gerente — nem o admin dá parecer', () => {
    expect(rolesWith(CAPABILITY.bartersOpinion)).toEqual([ROLE.manager]);
  });

  /**
   * Comitê e faturista ENXERGAM a operação e não escrevem nada. Quando a etapa
   * de cada um for definida, este teste é o que vai obrigar a decisão a ser
   * explícita — ele quebra no momento em que alguém der escrita a um deles. Foi
   * exatamente o que aconteceu com o gerente, que saiu daqui ao ganhar o
   * parecer e passou a ter o próprio caso, abaixo.
   *
   * `pricesRead` entrou na lista e continua sendo leitura: a retaguarda avalia
   * negociação, e negociação sem R$ não se avalia. Quem fica de fora dela é só o
   * consultor — ver o comentário de `pricesRead` em policy.ts.
   */
  it('comitê e faturista seguem em leitura, sem nenhuma escrita', () => {
    for (const role of [ROLE.committee, ROLE.biller]) {
      expect([...ROLE_CAPABILITIES[role]].sort()).toEqual(
        [CAPABILITY.bartersReadAll, CAPABILITY.producersReadAll, CAPABILITY.pricesRead].sort(),
      );
    }
  });

  it('o gerente enxerga o TIME dele e escreve UMA coisa: o parecer', () => {
    expect([...ROLE_CAPABILITIES[ROLE.manager]].sort()).toEqual(
      [
        CAPABILITY.bartersReadTeam,
        CAPABILITY.producersReadAll,
        CAPABILITY.bartersOpinion,
        CAPABILITY.pricesRead,
      ].sort(),
    );
  });

  /**
   * A LENTE DE VALOR, na tabela: quem vê R$ é a retaguarda inteira, e o
   * consultor não. Não é preferência de tela — é o que decide se a tabela do
   * fornecedor sai pela API e vai parar gravada no aparelho dele.
   */
  it('o consultor é o único papel sem acesso a valores', () => {
    expect(rolesWith(CAPABILITY.pricesRead).sort()).toEqual(
      [ROLE.admin, ROLE.manager, ROLE.committee, ROLE.biller].sort(),
    );
    expect(can({ role: ROLE.consultant }, CAPABILITY.pricesRead)).toBe(false);
  });

  /**
   * O escopo de time é do gerente e de mais ninguém — e, principalmente, ele
   * NÃO acumula com o de tudo. Um papel com as duas capacidades enxergaria a
   * operação inteira, que é o oposto do que este escopo existe para dar.
   */
  it('só o gerente tem escopo de time, e ele não enxerga tudo', () => {
    expect(rolesWith(CAPABILITY.bartersReadTeam)).toEqual([ROLE.manager]);
    expect(can({ role: ROLE.manager }, CAPABILITY.bartersReadAll)).toBe(false);
  });

  it('quem acompanha a operação inteira são admin, comitê e faturista', () => {
    expect(rolesWith(CAPABILITY.bartersReadAll)).toEqual([ROLE.admin, ROLE.committee, ROLE.biller]);
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
