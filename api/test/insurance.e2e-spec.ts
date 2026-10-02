import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import {
  ADMIN,
  COMITE,
  GERENTE,
  JOAO,
  UNIT,
  createTestApp,
  fillCpr,
  loginAs,
  resetDb,
} from './utils';

/**
 * O SEGURO DO PRODUTOR — uma POLÍTICA por versão da cultura (obrigatório,
 * opcional ou sem seguro) e precificado pelo MUNICÍPIO.
 *
 * A regra inteira cabe em três frases, e é isto que estas provas travam:
 *
 * 1. **a política é do admin, na versão do Barter** — e, quando ela é opcional,
 *    quem decide a permuta é o consultor com o produtor;
 * 2. **quanto custa é do lugar** — área plantada × taxa do município, porque
 *    o que a seguradora cota é o risco da praça (chuva, granizo, seca);
 * 3. **é custo, e custo vira saca** — o seguro entra na conta como qualquer
 *    coisa que a empresa adianta, e sai na colheita junto com os insumos.
 *
 * E a quarta, que não é regra mas é a diferença entre um sistema que funciona e
 * um que mente: a taxa é CONGELADA no registro. Recotar a praça amanhã não
 * reescreve o que o consultor combinou com o produtor hoje.
 */
describe('Seguro do produtor (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });
  beforeEach(() => resetDb(app));
  afterAll(() => app.close());

  const asUser = async (email: string) => `Bearer ${await loginAs(app, email)}`;

  /** O Barter vigente da soja no dataset — é nele que uma permuta nova de soja cai. */
  const VERSAO = 'SOJA2627.02';

  /**
   * Antônio Carvalho, em Maringá/PR, carteira do João, com 120 ha de soja. Os insumos são os
   * mínimos por hectare, e custam R$ 11.946,00 — ver `validPayload` em
   * barters.e2e-spec.ts, de onde este payload é a cópia deliberada: os dois
   * testes precisam registrar a MESMA permuta para que a diferença entre eles
   * seja só o seguro.
   */
  const payload = {
    producerId: 1,
    unitId: UNIT.filial02,
    seasonId: 3, // Soja 26/27
    plantedAreaHa: 120,
    inputs: [
      { productId: 5, quantity: 48 },
      { productId: 6, quantity: 300 },
      { productId: 7, quantity: 18 },
    ],
  };

  /** A política de seguro do Barter vigente da soja — o ato do admin. */
  const ligarSeguro = async (policy = 'required') =>
    request(app.getHttpServer())
      .put(`/api/v1/barter-versions/${VERSAO}/insurance`)
      .set('Authorization', await asUser(ADMIN))
      .send({ policy });

  const registrar = async (extra: object = {}) =>
    request(app.getHttpServer())
      .post('/api/v1/barters')
      .set('Authorization', await asUser(JOAO))
      .send({ ...payload, ...extra });

  /**
   * ENCAMINHA o rascunho ao gerente — o preâmbulo de todo caso que precisa ler a
   * permuta pelos olhos da RETAGUARDA.
   *
   * Ele existe aqui por causa de uma regra que não é do seguro: rascunho é DO
   * DONO (ver `scopeFor`), e nem o admin o enxerga. Como a taxa em R$ só
   * atravessa a lente de quem vê valores, conferir o número congelado exige
   * tirar a permuta da mesa do consultor primeiro. A cédula vai junto porque é
   * pré-requisito do encaminhamento.
   */
  const encaminhar = async (code: string) => {
    const auth = await asUser(JOAO);
    await fillCpr(app, auth, code);
    return request(app.getHttpServer())
      .post(`/api/v1/barters/${code}/forward`)
      .set('Authorization', auth)
      .send({ note: 'Cliente antigo, pagou as três últimas safras em dia.' });
  };

  /** A permuta como a retaguarda a lê — com os valores em R$. */
  const comoAdmin = async (code: string) =>
    request(app.getHttpServer())
      .get(`/api/v1/barters/${code}`)
      .set('Authorization', await asUser(ADMIN));

  /* ── A base por município ──────────────────────────────────────────── */

  describe('a base de seguros por município', () => {
    it('o admin cadastra uma praça, e ela passa a valer pela forma canônica', async () => {
      const criada = await request(app.getHttpServer())
        .post('/api/v1/insurance-rates')
        .set('Authorization', await asUser(ADMIN))
        .send({ city: 'Cianorte/PR', valuePerHa: 90, note: 'Praça nova' });

      expect(criada.status).toBe(201);
      expect(criada.body.data).toMatchObject({ city: 'Cianorte/PR', valuePerHa: 90 });

      // A MESMA praça escrita de outro jeito é a mesma praça: sobre o texto
      // cru, "cianorte / pr" entraria como uma segunda linha com um segundo
      // preço, e a permuta encontraria uma delas por acaso de digitação.
      const repetida = await request(app.getHttpServer())
        .post('/api/v1/insurance-rates')
        .set('Authorization', await asUser(ADMIN))
        .send({ city: 'cianorte / pr', valuePerHa: 120 });

      expect(repetida.status).toBe(422);
      expect(repetida.body.message).toContain('Cianorte/PR');
    });

    /**
     * Zero não é seguro de graça: é linha pela metade. Aceito, ele produziria
     * permutas com uma linha de seguro que não cobra nada — pior do que a praça
     * ausente, que ao menos recusa o registro dizendo o que falta.
     */
    it('praça a R$ 0,00 é recusada', async () => {
      const resposta = await request(app.getHttpServer())
        .post('/api/v1/insurance-rates')
        .set('Authorization', await asUser(ADMIN))
        .send({ city: 'Cianorte/PR', valuePerHa: 0 });

      expect(resposta.status).toBe(422);
      expect(resposta.body.message).toContain('maior que zero');
    });

    /**
     * O CONSULTOR LÊ A BASE, e lê na moeda dele.
     *
     * Ele precisa saber quanto o seguro vai custar ao cliente ANTES de fechar a
     * permuta — e R$ não atravessa a lente dele (ver `ValueLens`). O que chega é
     * `sacksPerHa` na cultura da versão em que ele monta a permuta: 85,00 ÷
     * 148,50 = 0,5723 sacas de soja por hectare.
     */
    it('o consultor lê a base em sacas, e a retaguarda em R$', async () => {
      const doConsultor = await request(app.getHttpServer())
        .get(`/api/v1/insurance-rates?version=${VERSAO}`)
        .set('Authorization', await asUser(JOAO));

      expect(doConsultor.status).toBe(200);
      const maringa = doConsultor.body.data.find(
        (rate: { city: string }) => rate.city === 'Maringá/PR',
      );
      expect(maringa.valuePerHa).toBeUndefined();
      expect(maringa.sacksPerHa).toBeCloseTo(85 / 148.5, 6);

      const doAdmin = await request(app.getHttpServer())
        .get('/api/v1/insurance-rates')
        .set('Authorization', await asUser(ADMIN));
      expect(
        doAdmin.body.data.find((rate: { city: string }) => rate.city === 'Maringá/PR').valuePerHa,
      ).toBe(85);
    });

    /**
     * O CASO DA PLANILHA REAL: ela vem toda de um estado só e sem UF
     * ("TUPANCIRETÃ"), enquanto o cadastro do produtor tem "Maringá/PR".
     *
     * A permuta precisa achar a praça mesmo assim — do contrário, a carga de
     * 400 municípios entraria na base e nenhuma delas valeria para produtor
     * nenhum. Aqui a praça de Maringá é recadastrada SEM a UF, e o registro
     * continua cotando o seguro.
     */
    it('a praça sem UF casa com o produtor cadastrado com UF', async () => {
      const base = await request(app.getHttpServer())
        .get('/api/v1/insurance-rates')
        .set('Authorization', await asUser(ADMIN));
      const maringa = base.body.data.find((rate: { city: string }) => rate.city === 'Maringá/PR');

      // A praça volta como a seguradora a escreve: sem estado e em caixa alta.
      const renomeada = await request(app.getHttpServer())
        .put(`/api/v1/insurance-rates/${maringa.id}`)
        .set('Authorization', await asUser(ADMIN))
        .send({ city: 'MARINGÁ', valuePerHa: 85 });
      expect(renomeada.status).toBe(200);

      await ligarSeguro();
      const resposta = await registrar();

      expect(resposta.status).toBe(201);
      const seguro = resposta.body.data.items.find(
        (item: { insurance: boolean }) => item.insurance,
      );
      expect(seguro.quantity).toBe(120);
      // E a praça gravada na permuta é a da BASE, como o admin a escreveu.
      expect(resposta.body.data.insuranceCity).toBe('MARINGÁ');
    });

    /**
     * A outra ponta da mesma regra: duas linhas para o mesmo município (uma com
     * UF e outra sem) fariam a permuta encontrar duas taxas. O cadastro recusa
     * a segunda antes de a ambiguidade existir.
     */
    it('recusa a mesma praça cadastrada de novo sem a UF', async () => {
      const resposta = await request(app.getHttpServer())
        .post('/api/v1/insurance-rates')
        .set('Authorization', await asUser(ADMIN))
        .send({ city: 'MARINGÁ', valuePerHa: 91 });

      expect(resposta.status).toBe(422);
      expect(resposta.body.message).toContain('Maringá/PR');
    });

    it('quem não administra a base não escreve nela', async () => {
      for (const email of [JOAO, GERENTE, COMITE]) {
        const resposta = await request(app.getHttpServer())
          .post('/api/v1/insurance-rates')
          .set('Authorization', await asUser(email))
          .send({ city: 'Cianorte/PR', valuePerHa: 90 });
        expect(resposta.status).toBe(403);
      }
    });
  });

  /* ── O seguro dentro da permuta ────────────────────────────────────── */

  describe('a permuta de um Barter com seguro', () => {
    /**
     * A PROVA CENTRAL: a linha nasce da área do produtor e da taxa da praça
     * dele, e o custo dela entra nas sacas.
     *
     * Antônio tem 120 ha em Maringá/PR, que está na base a R$ 85,00/ha:
     *
     *     seguro = 120 × 85,00 = R$ 10.200,00
     *     custo  = 11.946,00 (insumos) + 10.200,00 = R$ 22.146,00
     *     sacas  = 22.146,00 ÷ 148,50 = 149,1313
     *
     * Sem seguro, a mesma permuta paga 80,4444 sacas (ver barters.e2e-spec.ts).
     */
    it('nasce com a linha do seguro, e as sacas pagam o custo inteiro', async () => {
      expect((await ligarSeguro()).status).toBe(200);

      const resposta = await registrar();
      expect(resposta.status).toBe(201);

      const barter = resposta.body.data;
      const seguro = barter.items.find((item: { insurance: boolean }) => item.insurance);
      expect(seguro).toMatchObject({
        kind: 'input',
        productName: 'Seguro agrícola — Maringá/PR',
        unit: 'ha',
        quantity: 120,
        productId: null,
      });

      const grao = barter.items.find((item: { kind: string }) => item.kind === 'grain');
      expect(grao.quantity).toBe(149.1313);

      // A PRAÇA e a TAXA congeladas na permuta. O valor por hectare é R$, e por
      // isso não atravessa a lente do consultor — a praça atravessa, porque ela
      // é o que explica a linha.
      expect(barter.insuranceCity).toBe('Maringá/PR');
      expect(barter.insuranceRatePerHa).toBeUndefined();

      expect((await encaminhar(barter.code as string)).status).toBe(200);
      const daRetaguarda = await comoAdmin(barter.code as string);
      expect(daRetaguarda.body.data.insuranceRatePerHa).toBe(85);
      expect(
        daRetaguarda.body.data.items.find((item: { insurance: boolean }) => item.insurance)
          .unitValue,
      ).toBe(85);
    });

    /**
     * O SEGURO NÃO ENTRA NAS RÉGUAS DAS CLASSES, e é por isso que esta permuta
     * continua passando: os insumos dela são exatamente os mínimos.
     *
     * Contado no total que mede as pastas, ligar o seguro derrubaria de uma vez
     * todas as permutas da praça que cumpriam os mínimos no dia anterior — sem
     * que nenhum consultor tivesse mudado um item sequer.
     */
    it('não mexe nos mínimos por classe nem nos por hectare', async () => {
      await ligarSeguro();
      expect((await registrar()).status).toBe(201);
    });

    /**
     * A PRAÇA SEM TAXA recusa o REGISTRO — e a frase diz qual praça e onde se
     * resolve.
     *
     * A recusa é aqui porque aqui ela é grátis: a permuta não existe, ninguém
     * retirou nada, e quem resolve é o admin numa linha de cadastro. Deixar a
     * permuta nascer sem a linha seria descobrir semanas depois que ela está sem
     * seguro numa safra que tem seguro — com o insumo já na fazenda.
     */
    it('praça fora da base recusa o registro, nomeando o município', async () => {
      await ligarSeguro();

      const base = await request(app.getHttpServer())
        .get('/api/v1/insurance-rates')
        .set('Authorization', await asUser(ADMIN));
      const maringa = base.body.data.find((rate: { city: string }) => rate.city === 'Maringá/PR');
      const removida = await request(app.getHttpServer())
        .delete(`/api/v1/insurance-rates/${maringa.id}`)
        .set('Authorization', await asUser(ADMIN));
      expect(removida.status).toBe(204);

      const resposta = await registrar();
      expect(resposta.status).toBe(422);
      expect(resposta.body.message).toContain('Maringá/PR');
      expect(resposta.body.message).toContain('base de seguros por município');
    });

    /**
     * A TAXA É SNAPSHOT — o mesmo que já vale para a alíquota do imposto, para a
     * área do produtor e para as duas taxas do penhor.
     *
     * Recotar a praça é rotina (a seguradora recota, a diretoria revê), e uma
     * permuta já registrada que passasse a custar mais sacas por causa disso
     * estaria mudando o que o consultor combinou com o produtor — sem que nada
     * nela tivesse mudado.
     */
    it('a taxa fica congelada: recotar a praça não reescreve a permuta', async () => {
      await ligarSeguro();
      const criada = await registrar();
      const code = criada.body.data.code as string;

      const base = await request(app.getHttpServer())
        .get('/api/v1/insurance-rates')
        .set('Authorization', await asUser(ADMIN));
      const maringa = base.body.data.find((rate: { city: string }) => rate.city === 'Maringá/PR');
      await request(app.getHttpServer())
        .put(`/api/v1/insurance-rates/${maringa.id}`)
        .set('Authorization', await asUser(ADMIN))
        .send({ city: 'Maringá/PR', valuePerHa: 200 });

      expect((await encaminhar(code)).status).toBe(200);
      const depois = await comoAdmin(code);
      expect(depois.body.data.insuranceRatePerHa).toBe(85);
      expect(
        depois.body.data.items.find((item: { insurance: boolean }) => item.insurance).unitValue,
      ).toBe(85);
    });

    /**
     * A REMONTAGEM DO RASCUNHO refaz a permuta inteira — e o seguro volta com a
     * taxa DA PERMUTA, não com a de hoje.
     *
     * Sem isto, a linha sumiria na primeira correção de quantidade (ela não está
     * na lista que o consultor manda) ou voltaria reprecificada pela cotação
     * nova, num rascunho que o produtor já viu.
     */
    it('a remontagem do rascunho preserva o seguro, pela taxa congelada', async () => {
      await ligarSeguro();
      const criada = await registrar();
      const code = criada.body.data.code as string;

      const base = await request(app.getHttpServer())
        .get('/api/v1/insurance-rates')
        .set('Authorization', await asUser(ADMIN));
      const maringa = base.body.data.find((rate: { city: string }) => rate.city === 'Maringá/PR');
      await request(app.getHttpServer())
        .put(`/api/v1/insurance-rates/${maringa.id}`)
        .set('Authorization', await asUser(ADMIN))
        .send({ city: 'Maringá/PR', valuePerHa: 200 });

      const remontada = await request(app.getHttpServer())
        .put(`/api/v1/barters/${code}/inputs`)
        .set('Authorization', await asUser(JOAO))
        .send({ inputs: payload.inputs });

      expect(remontada.status).toBe(200);
      const seguro = remontada.body.data.items.find(
        (item: { insurance: boolean }) => item.insurance,
      );
      expect(seguro.quantity).toBe(120);
      expect(
        remontada.body.data.items.find((i: { kind: string }) => i.kind === 'grain').quantity,
      ).toBe(149.1313);
    });

    /**
     * DESLIGAR o seguro vale para as PRÓXIMAS. As permutas que já nasceram com
     * ele continuam com ele — a taxa está congelada nelas, e o que foi acordado
     * não se reescreve.
     */
    it('desligar o seguro não mexe no que já foi registrado', async () => {
      await ligarSeguro();
      const comSeguro = await registrar();
      const code = comSeguro.body.data.code as string;

      expect((await ligarSeguro('none')).status).toBe(200);

      expect((await encaminhar(code)).status).toBe(200);
      const depois = await comoAdmin(code);
      expect(depois.body.data.insuranceRatePerHa).toBe(85);

      // E a permuta NOVA nasce sem linha nenhuma de seguro.
      const semSeguro = await registrar();
      expect(semSeguro.status).toBe(201);
      expect(
        semSeguro.body.data.items.filter((item: { insurance: boolean }) => item.insurance),
      ).toEqual([]);
      expect(semSeguro.body.data.insuranceCity).toBe('');
    });
  });

  /* ── O Barter sem seguro ───────────────────────────────────────────── */

  /**
   * O PADRÃO É NÃO TER. O dataset de demonstração tem a base cadastrada e o
   * Barter vigente da soja SEM seguro — e é assim que a permuta nasce enquanto
   * ninguém mudar a política.
   */
  it('sem o seguro ligado, a permuta não ganha linha nenhuma', async () => {
    const resposta = await registrar();

    expect(resposta.status).toBe(201);
    expect(resposta.body.data.items.filter((i: { insurance: boolean }) => i.insurance)).toEqual([]);
    expect(
      resposta.body.data.items.find((i: { kind: string }) => i.kind === 'grain').quantity,
    ).toBe(80.4444);
    expect(resposta.body.data.insuranceCity).toBe('');
  });

  it('só quem gere o Barter muda o seguro do lançamento', async () => {
    for (const email of [JOAO, GERENTE, COMITE]) {
      const resposta = await request(app.getHttpServer())
        .put(`/api/v1/barter-versions/${VERSAO}/insurance`)
        .set('Authorization', await asUser(email))
        .send({ policy: 'required' });
      expect(resposta.status).toBe(403);
    }
  });

  it('política que não existe é recusada', async () => {
    expect((await ligarSeguro('talvez')).status).toBe(422);
  });

  /**
   * O SEGURO É DA VERSÃO, e ela chega inteira ao app: é por este campo que a
   * tela do consultor sabe se mostra a linha, o interruptor ou nada.
   */
  it('a versão vigente diz a política de seguro', async () => {
    const soja = async () =>
      (
        await request(app.getHttpServer())
          .get('/api/v1/barter-versions/current')
          .set('Authorization', await asUser(JOAO))
      ).body.data.find((version: { slug: string }) => version.slug === VERSAO);

    expect((await soja()).insurancePolicy).toBe('none');
    await ligarSeguro();
    expect((await soja()).insurancePolicy).toBe('required');
  });

  /* ── O seguro de cada permuta: obrigatório, opcional, sem ─────────── */

  describe('a escolha que fica gravada na permuta', () => {
    it('obrigatório: a permuta leva, e não dá para recusar', async () => {
      await ligarSeguro('required');

      const leva = await registrar();
      expect(leva.status).toBe(201);
      expect(leva.body.data.insuranceChoice).toBe('required');

      const recusa = await registrar({ insurance: false });
      expect(recusa.status).toBe(422);
      expect(recusa.body.message).toContain('obrigatório');
    });

    /**
     * OPCIONAL: o consultor decide com o produtor. A RECUSA fica gravada — é
     * informação de risco que o comitê precisa ler, e "sem seguro" deixou de
     * ter uma história só.
     */
    it('opcional: o produtor aceita ou recusa, e a escolha fica gravada', async () => {
      await ligarSeguro('optional');

      const aceita = await registrar({ insurance: true });
      expect(aceita.status).toBe(201);
      expect(aceita.body.data.insuranceChoice).toBe('accepted');
      expect(aceita.body.data.items.some((i: { insurance: boolean }) => i.insurance)).toBe(true);

      const recusa = await registrar({ insurance: false });
      expect(recusa.status).toBe(201);
      expect(recusa.body.data.insuranceChoice).toBe('declined');
      expect(recusa.body.data.items.some((i: { insurance: boolean }) => i.insurance)).toBe(false);

      // Calado é recusa: custo não entra numa permuta sem alguém dizer que entra.
      const calado = await registrar();
      expect(calado.body.data.insuranceChoice).toBe('declined');
    });

    it('sem seguro: pedir seguro é recusado', async () => {
      const resposta = await registrar({ insurance: true });
      expect(resposta.status).toBe(422);
      expect(resposta.body.message).toContain('não oferece seguro');
    });

    /** O seguro é sobre a ÁREA PLANTADA da permuta, e não a fazenda inteira. */
    it('o seguro cobre a área plantada informada', async () => {
      await ligarSeguro('required');
      const resposta = await registrar({ plantedAreaHa: 60 });

      expect(resposta.status).toBe(201);
      expect(
        resposta.body.data.items.find((i: { insurance: boolean }) => i.insurance).quantity,
      ).toBe(60);
      expect(resposta.body.data.plantedAreaHa).toBe(60);
    });

    /**
     * No RASCUNHO, a escolha do opcional se refaz: o produtor muda de ideia na
     * conversa, e o consultor remonta a permuta com ou sem a linha.
     */
    it('no rascunho, o opcional se liga e desliga', async () => {
      await ligarSeguro('optional');
      const criada = await registrar({ insurance: false });
      const code = criada.body.data.code as string;

      const comSeguro = await request(app.getHttpServer())
        .put(`/api/v1/barters/${code}/inputs`)
        .set('Authorization', await asUser(JOAO))
        .send({ inputs: payload.inputs, insurance: true });
      expect(comSeguro.status).toBe(200);
      expect(comSeguro.body.data.insuranceChoice).toBe('accepted');
      expect(comSeguro.body.data.insuranceCity).toBe('Maringá/PR');

      const semSeguro = await request(app.getHttpServer())
        .put(`/api/v1/barters/${code}/inputs`)
        .set('Authorization', await asUser(JOAO))
        .send({ inputs: payload.inputs, insurance: false });
      expect(semSeguro.body.data.insuranceChoice).toBe('declined');
      expect(semSeguro.body.data.insuranceCity).toBe('');
    });

    /**
     * Cada cultura tem a sua política: mudar a da soja não toca no milho
     * safrinha, que no dataset oferece o seguro como opcional.
     */
    it('a política é de cada versão — a soja não mexe no milho', async () => {
      await ligarSeguro('required');
      const atuais = await request(app.getHttpServer())
        .get('/api/v1/barter-versions/current')
        .set('Authorization', await asUser(JOAO));
      const milho = atuais.body.data.find((v: { slug: string }) => v.slug === 'MILHO2027.01');
      expect(milho.insurancePolicy).toBe('optional');
    });
  });
});
