import { Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import type { InsuranceRate, Prisma, User } from '@prisma/client';
import { AUDIT_ACTION, AuditService } from '../audit/audit.service';
import { PrismaService } from '../prisma/prisma.service';
import { readWorkbook } from '../seasons/version-import';
import { ImportInsuranceRatesDto, InsuranceRateDto } from './dto/insurance-rate.dto';
import { parseInsuranceSheet } from './insurance-import';
import { cityKeyOf, cityNameOf, sameCity } from './insurance-rate';

/**
 * A BASE DE SEGUROS POR MUNICÍPIO — o cadastro que responde "quanto custa
 * segurar um hectare nesta praça".
 *
 * Ela é lida por uma pergunta só, e é a da permuta: `rateFor(município do
 * produtor)`. Todo o resto deste service existe para manter essa resposta em
 * dia — a linha editada à mão quando a seguradora recota uma praça, e a
 * planilha carregada inteira quando ela recota a safra.
 *
 * O CADASTRO É DO ADMIN (`insurance.manage`) e a LEITURA é de todos: o
 * consultor precisa saber quanto o seguro vai custar ao cliente antes de fechar
 * a permuta. Quem não vê R$ recebe o valor convertido em sacas — ver o
 * serializador.
 */
@Injectable()
export class InsuranceService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  /**
   * A base inteira, em ordem alfabética.
   *
   * Sem paginação, pelo mesmo critério das unidades e das classes: a lista tem
   * teto natural (uma empresa opera em dezenas de praças, e o teto de carga é
   * de milhares) e as telas precisam dela inteira — é dela que sai a conferência
   * do admin e a prévia do consultor.
   */
  list(): Promise<InsuranceRate[]> {
    return this.prisma.insuranceRate.findMany({ orderBy: { city: 'asc' } });
  }

  async find(id: number): Promise<InsuranceRate> {
    const rate = await this.prisma.insuranceRate.findUnique({ where: { id } });
    if (!rate) throw new NotFoundException('Registro não encontrado.');
    return rate;
  }

  /**
   * A TAXA DE UMA PRAÇA — a pergunta que a permuta faz.
   *
   * `null` quando a praça não está na base, e é o chamador quem decide o que
   * isso significa: no registro de uma permuta com seguro, significa recusar
   * dizendo o que falta (ver `missingRateRefusal`); na prévia do app, significa
   * mostrar a pendência antes de o consultor montar a permuta inteira.
   *
   * A comparação é pela forma canônica, e é por isso que ela não é um
   * `findUnique` por `city`: o cadastro do produtor tem "Maringá/PR" e a base
   * pode ter "maringa / pr" — o mesmo lugar escrito por duas pessoas diferentes.
   */
  async rateFor(city: string | null | undefined): Promise<InsuranceRate | null> {
    const key = cityKeyOf(city ?? '');
    if (!key) return null;

    const exact = await this.prisma.insuranceRate.findUnique({ where: { cityKey: key } });
    if (exact) return exact;

    // SEM A UF DE UM DOS LADOS, a igualdade de texto não basta — e este é o
    // caso NORMAL, não a exceção: a planilha da seguradora é toda de um estado
    // só e traz "TUPANCIRETÃ", enquanto o cadastro do produtor traz
    // "Tupanciretã/RS", porque ali o município aparece sozinho.
    //
    // A busca é estreitada no BANCO pelo nome (o município puro ou ele seguido
    // de barra) e decidida em memória por `sameCity`, que é quem conhece a
    // regra. Sem o `startsWith`, isto seria a tabela inteira em toda permuta.
    const name = cityNameOf(key);
    const candidates = await this.prisma.insuranceRate.findMany({
      where: { OR: [{ cityKey: name }, { cityKey: { startsWith: `${name}/` } }] },
    });
    const matches = candidates.filter((rate) => sameCity(rate.city, city ?? ''));

    // DUAS praças casando é ambiguidade, e ambiguidade não se resolve no palpite
    // — "Bom Jesus" com duas UFs na base são dois riscos e dois preços. Devolver
    // `null` faz o registro recusar dizendo qual município falta, que é o que
    // manda alguém olhar a base; escolher uma delas cobraria do produtor o
    // seguro de outro estado, e ninguém veria.
    return matches.length === 1 ? matches[0] : null;
  }

  async create(actor: User, dto: InsuranceRateDto): Promise<InsuranceRate> {
    await this.ensureCityIsFree(dto.city);
    const rate = await this.prisma.insuranceRate.create({ data: this.dataOf(dto) });

    await this.audit.record({
      actor,
      action: AUDIT_ACTION.insuranceRateChanged,
      targetType: 'insuranceRate',
      targetId: rate.id,
      targetLabel: rate.city,
      detail: `cadastrada a ${money(rate.valuePerHa)}/ha`,
    });
    return rate;
  }

  async update(actor: User, id: number, dto: InsuranceRateDto): Promise<InsuranceRate> {
    const before = await this.find(id);
    await this.ensureCityIsFree(dto.city, id);
    const rate = await this.prisma.insuranceRate.update({
      where: { id },
      data: this.dataOf(dto),
    });

    await this.audit.record({
      actor,
      action: AUDIT_ACTION.insuranceRateChanged,
      targetType: 'insuranceRate',
      targetId: rate.id,
      targetLabel: rate.city,
      // O VALOR ANTERIOR vai no detalhe porque ele não fica guardado em lugar
      // nenhum: a base é cadastro vivo, e sem isto "quanto era antes?" só teria
      // resposta nas permutas que congelaram a taxa antiga.
      detail:
        before.valuePerHa === rate.valuePerHa
          ? `${money(rate.valuePerHa)}/ha`
          : `${money(before.valuePerHa)}/ha → ${money(rate.valuePerHa)}/ha`,
    });
    return rate;
  }

  /**
   * Excluir a praça NÃO mexe nas permutas dela: a taxa está congelada em cada
   * uma (ver `Barter.insuranceRatePerHa`), e o que some é a possibilidade de
   * registrar permuta NOVA naquele município enquanto o Barter levar seguro —
   * que é exatamente o que "a seguradora não cobre mais esta praça" significa.
   */
  async delete(actor: User, id: number): Promise<void> {
    const rate = await this.find(id);
    await this.prisma.insuranceRate.delete({ where: { id } });

    await this.audit.record({
      actor,
      action: AUDIT_ACTION.insuranceRateDeleted,
      targetType: 'insuranceRate',
      targetId: rate.id,
      targetLabel: rate.city,
      detail: `estava a ${money(rate.valuePerHa)}/ha`,
    });
  }

  /**
   * A CARGA DA PLANILHA — o caminho do admin quando a cotação chega com dezenas
   * de praças.
   *
   * O arquivo é lido por inteiro ANTES de qualquer gravação, e um erro de linha
   * recusa o arquivo todo (ver `parseInsuranceSheet`): meia base carregada é
   * pior do que nenhuma, porque as praças que ficaram de fora só se descobrem
   * quando um consultor esbarra nelas com o produtor na frente.
   *
   * A gravação é uma TRANSAÇÃO SÓ, pelo mesmo motivo: uma base metade nova e
   * metade velha não é um estado que alguém possa conferir. No modo `replace`,
   * o apagar e o gravar acontecem dentro dela — em nenhum instante a base fica
   * vazia para quem estiver registrando uma permuta naquele segundo.
   */
  async import(
    actor: User,
    file: { buffer: Buffer; originalname: string },
    dto: ImportInsuranceRatesDto,
  ): Promise<InsuranceImportReport> {
    let matrix: string[][];
    try {
      matrix = await readWorkbook(file.buffer);
    } catch (error) {
      throw new UnprocessableEntityException(
        error instanceof Error ? error.message : 'Não consegui ler o arquivo.',
      );
    }

    const { rows, errors, priceColumn, ignored } = parseInsuranceSheet(matrix, dto.column);
    if (errors.length > 0) {
      // As primeiras dez, e o resto contado: uma planilha com trezentos erros
      // produziria uma mensagem que ninguém lê, e as dez primeiras costumam ser
      // o mesmo erro repetido — que é o que o admin precisa ver para corrigir a
      // coluna inteira de uma vez.
      const shown = errors.slice(0, 10);
      const rest = errors.length - shown.length;
      throw new UnprocessableEntityException(
        `A planilha tem ${errors.length} problema(s):\n${shown.join('\n')}${
          rest > 0 ? `\n…e mais ${rest}.` : ''
        }`,
      );
    }

    const replace = dto.mode === 'replace';
    const data = rows.map((row) => ({
      city: row.city,
      cityKey: cityKeyOf(row.city),
      valuePerHa: row.valuePerHa,
      note: row.note,
    }));

    await this.prisma.$transaction(async (tx) => {
      if (replace) {
        await tx.insuranceRate.deleteMany({});
        await tx.insuranceRate.createMany({ data });
        return;
      }
      // MERGE: a praça que já existe recebe o valor novo, a que não existe
      // entra, e a que não está na planilha fica como estava. É `upsert` por
      // linha — e não `createMany` com `skipDuplicates` — porque atualizar É o
      // caso comum aqui: a seguradora manda a mesma lista com preços novos.
      for (const row of data) {
        await tx.insuranceRate.upsert({
          where: { cityKey: row.cityKey },
          create: row,
          update: { city: row.city, valuePerHa: row.valuePerHa, note: row.note },
        });
      }
    });

    await this.audit.record({
      actor,
      action: AUDIT_ACTION.insuranceBaseImported,
      targetType: 'insuranceRate',
      targetLabel: file.originalname,
      // A COLUNA entra na trilha junto com a contagem, e é a informação mais
      // importante da linha: a mesma planilha carregada pela coluna "SEM
      // Subvenção" em vez da "Reajuste" produz uma base inteira com outro
      // preço, e nada além disto registraria qual delas valeu naquele dia.
      detail:
        `${rows.length} município(s) pela coluna "${priceColumn!.header}", ` +
        `modo ${replace ? 'substituição da base' : 'atualização'}` +
        (ignored > 0 ? ` (${ignored} linha(s) de planilha ignorada(s))` : ''),
    });

    return {
      rates: await this.list(),
      priceColumn: priceColumn!,
      imported: rows.length,
      ignored,
    };
  }

  private dataOf(dto: InsuranceRateDto): Prisma.InsuranceRateUncheckedCreateInput {
    return {
      city: dto.city.trim(),
      cityKey: cityKeyOf(dto.city),
      valuePerHa: dto.valuePerHa,
      note: dto.note?.trim() ? dto.note.trim() : null,
    };
  }

  /**
   * O índice único é a garantia final, mas ele só sabe dizer "valor repetido".
   * Conferir antes permite a mensagem que o admin entende — e a comparação é
   * sobre a forma canônica, porque "Maringá/PR" e "maringa / pr" são a mesma
   * praça, e duas linhas para ela fariam a permuta encontrar uma das duas por
   * acaso de digitação.
   */
  private async ensureCityIsFree(city: string, ignoreId?: number): Promise<void> {
    // A conferência é por `sameCity`, e não pela chave: "TUPANCIRETÃ" e
    // "Tupanciretã/RS" são a mesma praça escrita por duas pessoas, e as duas na
    // base fariam a permuta encontrar DUAS taxas para o mesmo produtor — o que
    // `rateFor` trata como ambiguidade e recusa. É mais honesto impedir a
    // segunda linha de nascer do que explicar depois por que a praça
    // cadastrada não vale.
    const name = cityNameOf(city);
    const candidates = await this.prisma.insuranceRate.findMany({
      where: { OR: [{ cityKey: name }, { cityKey: { startsWith: `${name}/` } }] },
    });
    const existing = candidates.find((rate) => rate.id !== ignoreId && sameCity(rate.city, city));
    if (!existing) return;
    throw new UnprocessableEntityException(
      `O município "${existing.city}" já está na base de seguros`,
    );
  }
}

/**
 * O QUE A CARGA DA PLANILHA DEVOLVE — a base inteira e o que foi lido dela.
 *
 * A base inteira porque a tela que carregou é a mesma que lista o cadastro, e
 * no modo substituição essa é a única resposta honesta: o que saiu da lista
 * saiu. E o RELATÓRIO junto porque a carga tomou uma decisão em nome de quem a
 * disparou — qual das colunas de valor valeu —, e quem decide precisa ver a
 * decisão no mesmo minuto, não descobri-la na primeira permuta cara demais.
 */
export interface InsuranceImportReport {
  rates: InsuranceRate[];
  priceColumn: { id: string; label: string; header: string };
  /** Quantas praças o arquivo trouxe. */
  imported: number;
  /** Quantas linhas de enfeite foram ignoradas (ver `isPlaceholder`). */
  ignored: number;
}

/** O valor como a trilha de auditoria o escreve — em pt-BR, como no resto dela. */
const money = (value: number): string =>
  `R$ ${value.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
