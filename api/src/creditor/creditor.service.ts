import { Injectable } from '@nestjs/common';
import type { Creditor, User } from '@prisma/client';
import { AUDIT_ACTION, AuditService } from '../audit/audit.service';
import { EMPTY_CREDITOR } from '../common/creditor';
import { PrismaService } from '../prisma/prisma.service';
import { CreditorDto } from './dto/creditor.dto';

/** A linha única. Ver o comentário do modelo: uma instalação, uma credora. */
const THE_ROW = 1;

/**
 * O CADASTRO DA CREDORA — a empresa que recebe o grão, como os documentos a
 * nomeiam.
 *
 * O service mais simples do backend, e isso é uma afirmação sobre o domínio: a
 * credora é um timbre. Ela não tem estado, não participa de fluxo e não decide
 * nada — se um dia ela ganhar uma regra, é sinal de que o modelo mudou, e não
 * de que faltava um campo.
 *
 * Ele é escrito por DOIS papéis (admin e faturista, ver `creditorManage`), e é
 * por isso que a linha guarda `updatedBy`: com dois donos, "quem mudou o CNPJ?"
 * é uma pergunta que aparece.
 */
@Injectable()
export class CreditorService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  /**
   * A credora cadastrada — ou o vazio, quando ninguém a cadastrou ainda.
   *
   * NUNCA 404. A ausência do cadastro é o estado inicial de toda instalação
   * nova, e não um erro: a tela precisa abrir com o formulário em branco, e a
   * cédula precisa saber dizer que a pendência existe. Devolver "não
   * encontrado" transformaria o primeiro dia de uso numa tela de erro.
   */
  async get(): Promise<Creditor> {
    return (await this.prisma.creditor.findUnique({ where: { id: THE_ROW } })) ?? EMPTY_CREDITOR;
  }

  /**
   * Grava o cadastro — `upsert`, porque a primeira gravação é a que o cria.
   *
   * Campo ausente vira VAZIO, e aqui isso é diferente da cédula de propósito: o
   * rascunho da cédula é preenchido aos pedaços por quem tem uma parte dos
   * dados, enquanto este é um formulário curto, mostrado inteiro, que a pessoa
   * lê de cima a baixo antes de salvar. Preservar o ausente aqui tornaria
   * impossível APAGAR um foro eleito que deixou de valer.
   */
  async save(actor: User, dto: CreditorDto): Promise<Creditor> {
    const data = {
      name: (dto.name ?? '').trim(),
      cnpj: (dto.cnpj ?? '').trim(),
      address: (dto.address ?? '').trim(),
      addressNumber: (dto.addressNumber ?? '').trim(),
      city: (dto.city ?? '').trim(),
      forum: (dto.forum ?? '').trim(),
      updatedBy: actor.fullName,
    };

    const saved = await this.prisma.creditor.upsert({
      where: { id: THE_ROW },
      create: { id: THE_ROW, ...data },
      update: data,
    });

    // Entra na trilha pelo mesmo critério dos atos que decidem dinheiro: este
    // cadastro é a parte da CPR que identifica QUEM cobra. Um CNPJ trocado aqui
    // vale para todas as cédulas emitidas dali em diante, e a linha do tempo da
    // permuta não alcança isto — ela é do registro, e a credora é global.
    await this.audit.record({
      actor,
      action: AUDIT_ACTION.creditorUpdated,
      targetType: 'creditor',
      targetId: saved.id,
      targetLabel: saved.name || '(sem razão social)',
      detail: `CNPJ ${saved.cnpj || 'não informado'}, ${saved.city || 'cidade não informada'}`,
    });
    return saved;
  }
}
