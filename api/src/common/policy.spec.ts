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
    ]) {
      expect(rolesWith(capability)).toEqual([ROLE.admin]);
    }
  });

  /**
   * O ADMIN NÃO DECIDE PERMUTA — e este é o teste que segura isso.
   *
   * `bartersReview` era dele, e a lista acima é justamente onde ela estava. Sair
   * dali não é detalhe de arrumação: quem administra o acesso não pode ser
   * também quem decide o negócio, porque aí é a mesma pessoa concedendo o poder
   * e usando-o. Devolvê-la ao admin um dia — de propósito ou por engano ao mexer
   * na tabela — quebra aqui.
   */
  it('decidir permuta é só do comitê; o admin administra e não decide', () => {
    expect(rolesWith(CAPABILITY.bartersReview)).toEqual([ROLE.committee]);
    expect(can({ role: ROLE.admin }, CAPABILITY.bartersReview)).toBe(false);
  });

  /** Faturar é do faturista, e é a única coisa que ele escreve. */
  it('faturar é só do faturista', () => {
    expect(rolesWith(CAPABILITY.bartersInvoice)).toEqual([ROLE.biller]);
  });

  /**
   * LER a cédula e PREENCHER a cédula são duas perguntas.
   *
   * O admin ganhou a segunda via do documento — ele já enxerga a operação
   * inteira e já responde pelo timbre dela, e pedir a outra pessoa uma cópia do
   * papel que ele administra não fazia sentido. O que ele NÃO ganhou é o ato:
   * preencher a cédula continua com quem apura a matrícula do imóvel, e faturar
   * continua sendo do faturista.
   *
   * Este teste é o que segura as duas metades separadas. Dar `bartersInvoice`
   * ao admin — que era o atalho óbvio para o mesmo pedido — quebra aqui.
   */
  it('a cédula tem três mãos: o consultor preenche, o emissor emite, o admin lê', () => {
    // LER é de quem preenche, de quem emite e de quem administra. São três
    // perguntas diferentes sobre o mesmo documento, e a mesma porta responde às
    // três.
    expect(rolesWith(CAPABILITY.bartersCprRead).sort()).toEqual(
      [ROLE.admin, ROLE.emitter, ROLE.consultant].sort(),
    );

    // ESCREVER é só do consultor — é ele quem tem a matrícula da lavoura, o
    // nome do cônjuge e o SCR. O faturista PERDEU isso, e é aqui que a perda
    // fica travada: devolvê-la a ele quebra este teste.
    expect(rolesWith(CAPABILITY.bartersCprFill)).toEqual([ROLE.consultant]);
    expect(can({ role: ROLE.biller }, CAPABILITY.bartersCprFill)).toBe(false);
    expect(can({ role: ROLE.biller }, CAPABILITY.bartersCprRead)).toBe(false);

    // EMITIR é só do emissor, e ele não escreve o que confere: quem confere o
    // próprio texto não está conferindo nada.
    expect(rolesWith(CAPABILITY.bartersCprIssue)).toEqual([ROLE.emitter]);
    expect(can({ role: ROLE.emitter }, CAPABILITY.bartersCprFill)).toBe(false);
    expect(can({ role: ROLE.consultant }, CAPABILITY.bartersCprIssue)).toBe(false);

    // O ADMIN lê e não age: nem fatura, nem emite.
    expect(can({ role: ROLE.admin }, CAPABILITY.bartersCprRead)).toBe(true);
    expect(can({ role: ROLE.admin }, CAPABILITY.bartersInvoice)).toBe(false);
    expect(can({ role: ROLE.admin }, CAPABILITY.bartersCprIssue)).toBe(false);

    // E não vazou para quem não tem nada com o documento.
    expect(can({ role: ROLE.committee }, CAPABILITY.bartersCprRead)).toBe(false);
    expect(can({ role: ROLE.manager }, CAPABILITY.bartersCprRead)).toBe(false);
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
   * CADA POSTO DA LINHA ESCREVE UMA COISA SÓ — e é isto que faz a etapa ter
   * dono.
   *
   * Comitê e faturista eram só leitura enquanto as etapas deles não existiam.
   * Agora existem, e o que este teste guarda é o TAMANHO do que cada um ganhou:
   * o comitê decide (e não fatura), o faturista fatura (e não decide). Um papel
   * que acumulasse os dois seria a mesma pessoa aprovando e emitindo a nota, que
   * é exatamente a separação que a linha de produção existe para manter.
   *
   * `pricesRead` continua sendo leitura: a retaguarda avalia negociação, e
   * negociação sem R$ não se avalia. Quem fica de fora dela é só o consultor —
   * ver o comentário de `pricesRead` em policy.ts.
   */
  it('o comitê decide e não fatura; o faturista fatura e não decide', () => {
    expect([...ROLE_CAPABILITIES[ROLE.committee]].sort()).toEqual(
      [
        CAPABILITY.bartersReadAll,
        CAPABILITY.producersReadAll,
        CAPABILITY.bartersReview,
        CAPABILITY.pricesRead,
        CAPABILITY.bartersInvestmentPerHa,
      ].sort(),
    );
    expect(can({ role: ROLE.committee }, CAPABILITY.bartersInvoice)).toBe(false);

    // O FATURISTA FATURA, E É SÓ ISSO. Ele ENCOLHEU nesta versão, e o encolhimento
    // é a decisão: a cédula saiu das mãos dele (preencher foi para o consultor,
    // emitir para o emissor) e `creditorManage` foi junto com o documento —
    // o timbre segue quem emite o papel, não quem emite a nota.
    expect([...ROLE_CAPABILITIES[ROLE.biller]].sort()).toEqual(
      [
        CAPABILITY.bartersReadInvoicing,
        CAPABILITY.producersReadAll,
        CAPABILITY.bartersInvoice,
        CAPABILITY.pricesRead,
        CAPABILITY.bartersInvestmentPerHa,
      ].sort(),
    );
    expect(can({ role: ROLE.biller }, CAPABILITY.bartersReview)).toBe(false);

    // `creditorManage` é a ÚNICA capacidade que um posto da linha divide com o
    // admin, e ela é do EMISSOR: a credora é o timbre dos documentos que ele
    // leva a registro (razão social, CNPJ, endereço, foro da CPR), não uma
    // decisão de negócio nem uma concessão de acesso. Quem percebe o CNPJ com um
    // dígito trocado é quem confere o título, e mandá-lo abrir chamado com o
    // admin para corrigir o próprio timbre trocaria um campo de texto por um
    // processo.
    expect(rolesWith(CAPABILITY.creditorManage).sort()).toEqual([ROLE.admin, ROLE.emitter].sort());
    expect(can({ role: ROLE.biller }, CAPABILITY.creditorManage)).toBe(false);
    expect(can({ role: ROLE.committee }, CAPABILITY.creditorManage)).toBe(false);
    expect(can({ role: ROLE.manager }, CAPABILITY.creditorManage)).toBe(false);
    expect(can({ role: ROLE.consultant }, CAPABILITY.creditorManage)).toBe(false);
  });

  /**
   * O EMISSOR — o posto que a cédula ganhou, e o mais estreito da retaguarda.
   *
   * Ele enxerga um degrau adiante do faturista (`bartersReadIssuance`), confere
   * e emite o título (`bartersCprIssue`) e responde pelo timbre dele
   * (`creditorManage`). O que ele NÃO faz é escrever a cédula: quem confere o
   * próprio texto não está conferindo nada.
   */
  it('o emissor emite o título e não escreve o que confere', () => {
    expect([...ROLE_CAPABILITIES[ROLE.emitter]].sort()).toEqual(
      [
        CAPABILITY.producersReadAll,
        CAPABILITY.bartersReadIssuance,
        CAPABILITY.bartersCprIssue,
        CAPABILITY.bartersCprRead,
        CAPABILITY.creditorManage,
        CAPABILITY.pricesRead,
        CAPABILITY.bartersInvestmentPerHa,
      ].sort(),
    );
    expect(can({ role: ROLE.emitter }, CAPABILITY.bartersCprFill)).toBe(false);
    expect(can({ role: ROLE.emitter }, CAPABILITY.bartersInvoice)).toBe(false);
    expect(can({ role: ROLE.emitter }, CAPABILITY.bartersReview)).toBe(false);
  });

  /**
   * O ESCOPO DA EMISSÃO é do emissor e de mais ninguém — e ele NÃO acumula com
   * o do faturamento, pelo mesmo motivo do escopo de time do gerente: um papel
   * com os dois enxergaria mais do que o próprio trecho da linha.
   */
  it('o escopo da emissão é do emissor, e não se acumula com o do faturamento', () => {
    expect(rolesWith(CAPABILITY.bartersReadIssuance)).toEqual([ROLE.emitter]);
    expect(can({ role: ROLE.emitter }, CAPABILITY.bartersReadInvoicing)).toBe(false);
    expect(can({ role: ROLE.emitter }, CAPABILITY.bartersReadAll)).toBe(false);
    expect(can({ role: ROLE.biller }, CAPABILITY.bartersReadIssuance)).toBe(false);
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
      [ROLE.admin, ROLE.manager, ROLE.committee, ROLE.biller, ROLE.emitter].sort(),
    );
    expect(can({ role: ROLE.consultant }, CAPABILITY.pricesRead)).toBe(false);
  });

  /**
   * O INVESTIMENTO POR HECTARE (sc/ha) é de quem COMPARA permutas.
   *
   * O recorte não é o mesmo de `pricesRead`, e a diferença é o gerente: ele vê
   * R$ (avalia a negociação do time dele) e não vê sc/ha — para ele a permuta é
   * uma, e uma régua de comparação sem com quem comparar é ruído na tela. Quem
   * a tem são os três que olham a operação de cima: admin, comitê e faturista.
   */
  it('o sc/ha é de quem compara permutas — o gerente e o consultor não o veem', () => {
    expect(rolesWith(CAPABILITY.bartersInvestmentPerHa).sort()).toEqual(
      [ROLE.admin, ROLE.committee, ROLE.biller, ROLE.emitter].sort(),
    );
    expect(can({ role: ROLE.manager }, CAPABILITY.bartersInvestmentPerHa)).toBe(false);
    expect(can({ role: ROLE.consultant }, CAPABILITY.bartersInvestmentPerHa)).toBe(false);
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

  /**
   * QUEM ACOMPANHA A OPERAÇÃO INTEIRA são o admin e o comitê — e o faturista
   * NÃO.
   *
   * Ele já teve `bartersReadAll`, e o custo disso aparecia na tela dele: a fila
   * do gerente, a mesa do comitê e as permutas negadas, tudo na conta de quem
   * não participa de nenhuma dessas etapas. O comitê fica com o alcance largo
   * de propósito — ler o que está no gerente é ler a própria fila de amanhã.
   */
  it('acompanham a operação inteira o admin e o comitê; o faturista, só o que chegou nele', () => {
    expect(rolesWith(CAPABILITY.bartersReadAll)).toEqual([ROLE.admin, ROLE.committee]);
    expect(rolesWith(CAPABILITY.bartersReadInvoicing)).toEqual([ROLE.biller]);
    expect(can({ role: ROLE.biller }, CAPABILITY.bartersReadAll)).toBe(false);
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
