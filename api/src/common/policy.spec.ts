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
   * O ADMIN TEM TODAS AS CAPACIDADES — é o responsável final pelo sistema, e
   * isso inclui decidir permuta ao lado do comitê.
   */
  it('decidir permuta é do comitê, e o admin também decide', () => {
    expect(rolesWith(CAPABILITY.bartersReview).sort()).toEqual([ROLE.admin, ROLE.committee].sort());
    expect(can({ role: ROLE.admin }, CAPABILITY.bartersReview)).toBe(true);
  });

  /**
   * A APÓLICE é da seguradora (e do admin), e é a ÚNICA coisa que ela escreve.
   * Ela enxerga só o trecho dela da linha — e só o que tem seguro, recorte que
   * mora no service (ver `bartersReadInsurance`).
   */
  it('a seguradora informa a apólice, e só isso', () => {
    expect(rolesWith(CAPABILITY.bartersInsure).sort()).toEqual([ROLE.admin, ROLE.insurer].sort());
    expect(rolesWith(CAPABILITY.bartersReadInsurance).sort()).toEqual(
      [ROLE.admin, ROLE.insurer].sort(),
    );
    expect([...ROLE_CAPABILITIES[ROLE.insurer]].sort()).toEqual(
      [
        CAPABILITY.producersReadAll,
        CAPABILITY.bartersReadInsurance,
        CAPABILITY.bartersInsure,
        CAPABILITY.pricesRead,
      ].sort(),
    );
    // Não decide, não fatura, não mexe na cédula e não enxerga a operação inteira.
    for (const capability of [
      CAPABILITY.bartersReview,
      CAPABILITY.bartersInvoice,
      CAPABILITY.bartersCprRead,
      CAPABILITY.bartersCprFill,
      CAPABILITY.bartersCprIssue,
      CAPABILITY.bartersReadAll,
      CAPABILITY.bartersReadInvoicing,
      CAPABILITY.insuranceManage,
    ]) {
      expect(can({ role: ROLE.insurer }, capability)).toBe(false);
    }
  });

  /** Faturar é do faturista (e do admin), e é a única coisa que o faturista escreve. */
  it('faturar é do faturista, e o admin também fatura', () => {
    expect(rolesWith(CAPABILITY.bartersInvoice).sort()).toEqual([ROLE.admin, ROLE.biller].sort());
  });

  /**
   * LER a cédula e PREENCHER a cédula são duas perguntas — e o admin responde
   * sim às duas, junto com quem preenche e quem emite, porque o admin tem
   * todas as capacidades do sistema.
   */
  it('a cédula: o consultor preenche, o emissor emite, e o admin faz as duas coisas também', () => {
    // LER é de quem preenche, de quem emite e de quem administra.
    expect(rolesWith(CAPABILITY.bartersCprRead).sort()).toEqual(
      [ROLE.admin, ROLE.emitter, ROLE.consultant].sort(),
    );

    // ESCREVER é do consultor e do admin — o faturista continua sem.
    expect(rolesWith(CAPABILITY.bartersCprFill).sort()).toEqual(
      [ROLE.admin, ROLE.consultant].sort(),
    );
    expect(can({ role: ROLE.biller }, CAPABILITY.bartersCprFill)).toBe(false);
    expect(can({ role: ROLE.biller }, CAPABILITY.bartersCprRead)).toBe(false);

    // EMITIR é do emissor e do admin; o consultor não emite o que preenche.
    expect(rolesWith(CAPABILITY.bartersCprIssue).sort()).toEqual([ROLE.admin, ROLE.emitter].sort());
    expect(can({ role: ROLE.emitter }, CAPABILITY.bartersCprFill)).toBe(false);
    expect(can({ role: ROLE.consultant }, CAPABILITY.bartersCprIssue)).toBe(false);

    // O ADMIN lê, preenche, fatura e emite — é o responsável final pelo sistema.
    expect(can({ role: ROLE.admin }, CAPABILITY.bartersCprRead)).toBe(true);
    expect(can({ role: ROLE.admin }, CAPABILITY.bartersInvoice)).toBe(true);
    expect(can({ role: ROLE.admin }, CAPABILITY.bartersCprIssue)).toBe(true);

    // E não vazou para quem não tem nada com o documento.
    expect(can({ role: ROLE.committee }, CAPABILITY.bartersCprRead)).toBe(false);
    expect(can({ role: ROLE.manager }, CAPABILITY.bartersCprRead)).toBe(false);
  });

  it('registrar permuta é do consultor, e o admin também registra', () => {
    expect(rolesWith(CAPABILITY.bartersRegister).sort()).toEqual(
      [ROLE.admin, ROLE.consultant].sort(),
    );
  });

  /**
   * A ETAPA DO GERENTE é dele — e o admin também a alcança, como responsável
   * final por todas as etapas da esteira.
   */
  it('o parecer técnico é do gerente, e o admin também pode dar parecer', () => {
    expect(rolesWith(CAPABILITY.bartersOpinion).sort()).toEqual([ROLE.admin, ROLE.manager].sort());
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
        // O DOSSIÊ é a terceira coisa que ele ganhou, e ela anda junto com a
        // decisão: ler os anexos que já estão na permuta e juntar o que se
        // apurou sobre o cliente (Serasa, endividamento interno) é parte de
        // decidir crédito, não uma atribuição nova.
        CAPABILITY.bartersCreditRead,
        CAPABILITY.bartersCreditAttach,
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
   * O ESCOPO DA EMISSÃO é do emissor — e ele NÃO acumula com o do faturamento,
   * pelo mesmo motivo do escopo de time do gerente: um papel com os dois
   * enxergaria mais do que o próprio trecho da linha. O admin é a exceção
   * deliberada: ele tem todos os escopos, porque enxerga a operação inteira.
   */
  it('o escopo da emissão é do emissor (e do admin), e não se acumula com o do faturamento entre os postos', () => {
    expect(rolesWith(CAPABILITY.bartersReadIssuance).sort()).toEqual(
      [ROLE.admin, ROLE.emitter].sort(),
    );
    expect(can({ role: ROLE.emitter }, CAPABILITY.bartersReadInvoicing)).toBe(false);
    expect(can({ role: ROLE.emitter }, CAPABILITY.bartersReadAll)).toBe(false);
    expect(can({ role: ROLE.biller }, CAPABILITY.bartersReadIssuance)).toBe(false);
  });

  /**
   * O DOSSIÊ DA ANÁLISE DE CRÉDITO — a única leitura de anexo restrita do
   * sistema.
   *
   * Nota fiscal, cédula assinada e comprovante de registro vão para quem alcança
   * a permuta; a consulta ao Serasa e o endividamento do produtor dentro da
   * cooperativa, não. A diferença é a natureza da peça: as primeiras são
   * documentos da operação, e estas são a vida financeira de um cliente,
   * colhida para uma decisão de crédito.
   *
   * E a ESCRITA é do comitê — e também do admin, como responsável final pelo
   * sistema.
   */
  it('o dossiê do comitê é lido pelo comitê e pelo admin, e escrito pelos dois', () => {
    expect(rolesWith(CAPABILITY.bartersCreditRead).sort()).toEqual(
      [ROLE.admin, ROLE.committee].sort(),
    );
    expect(rolesWith(CAPABILITY.bartersCreditAttach).sort()).toEqual(
      [ROLE.admin, ROLE.committee].sort(),
    );

    expect(can({ role: ROLE.consultant }, CAPABILITY.bartersCreditRead)).toBe(false);
    expect(can({ role: ROLE.manager }, CAPABILITY.bartersCreditRead)).toBe(false);
    expect(can({ role: ROLE.biller }, CAPABILITY.bartersCreditRead)).toBe(false);
    expect(can({ role: ROLE.emitter }, CAPABILITY.bartersCreditRead)).toBe(false);
    expect(can({ role: ROLE.admin }, CAPABILITY.bartersCreditAttach)).toBe(true);
  });

  /**
   * A BASE DE SEGUROS é do admin, e é SEPARADA da caneta do preço do Barter.
   *
   * As duas decidem quanto a permuta custa ao produtor e hoje moram na mesma
   * mão, mas são atos diferentes: publicar a tabela de valores é decisão
   * comercial da safra; manter a base de seguros é transcrever a cotação que a
   * seguradora mandou. O dia em que a segunda for do escritório de crédito, é
   * esta linha que muda.
   */
  it('a base de seguros é do admin, e ninguém mais escreve nela', () => {
    expect(rolesWith(CAPABILITY.insuranceManage)).toEqual([ROLE.admin]);
    expect(can({ role: ROLE.committee }, CAPABILITY.insuranceManage)).toBe(false);
    expect(can({ role: ROLE.consultant }, CAPABILITY.insuranceManage)).toBe(false);
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
      [ROLE.admin, ROLE.manager, ROLE.committee, ROLE.insurer, ROLE.biller, ROLE.emitter].sort(),
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
   * O escopo de time é do gerente — e, entre os postos da linha, ele NÃO
   * acumula com o de tudo (`bartersReadAll`). O admin é a exceção: ele tem os
   * dois, porque enxerga a operação inteira.
   */
  it('o escopo de time é do gerente (e do admin), e o gerente sozinho não enxerga tudo', () => {
    expect(rolesWith(CAPABILITY.bartersReadTeam).sort()).toEqual([ROLE.admin, ROLE.manager].sort());
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
    expect(rolesWith(CAPABILITY.bartersReadInvoicing).sort()).toEqual(
      [ROLE.admin, ROLE.biller].sort(),
    );
    expect(can({ role: ROLE.biller }, CAPABILITY.bartersReadAll)).toBe(false);
  });

  it('o consultor não enxerga além da própria carteira', () => {
    expect(can({ role: ROLE.consultant }, CAPABILITY.bartersReadAll)).toBe(false);
    expect(can({ role: ROLE.consultant }, CAPABILITY.producersReadAll)).toBe(false);
  });

  /**
   * CADASTRAR e EDITAR o produtor são do consultor (e do admin); definir a
   * carteira e excluir continuam só do admin. Em que carteira o produtor dele
   * nasce é regra do service, não desta tabela.
   */
  it('o consultor cadastra e edita o produtor, mas não administra a base', () => {
    expect(rolesWith(CAPABILITY.producersRegister).sort()).toEqual(
      [ROLE.admin, ROLE.consultant].sort(),
    );
    expect(rolesWith(CAPABILITY.producersEdit).sort()).toEqual(
      [ROLE.admin, ROLE.consultant].sort(),
    );
    expect(can({ role: ROLE.consultant }, CAPABILITY.producersManage)).toBe(false);
  });

  it('papel desconhecido não tem capacidade nenhuma — falha fechando', () => {
    for (const capability of CAPABILITIES) {
      expect(can({ role: 'diretor' }, capability)).toBe(false);
    }
  });
});
