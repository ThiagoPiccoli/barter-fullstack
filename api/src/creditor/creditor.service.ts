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
 * O CADASTRO era a coisa mais simples do backend, e isso era uma afirmação sobre
 * o domínio: a credora é um timbre — não tem estado, não participa de fluxo e não
 * decide nada. O comentário antigo dizia que, se ela um dia ganhasse uma REGRA,
 * seria sinal de que o modelo mudou.
 *
 * O dia chegou, e a leitura certa dele não foi mudar o modelo: foi separar as
 * duas coisas DENTRO da linha. A MARGEM DE SEGURANÇA DO PENHOR é da EMPRESA, e
 * esta é a única linha que representa a empresa — mas ela é regra, não timbre, e
 * por isso tem método próprio (`setPledgeMargin`), rota própria e capacidade
 * própria. O `save` abaixo continua escrevendo só o papel timbrado.
 *
 * A DIVISÃO EXISTE POR CAUSA DE QUEM ESCREVE. O cadastro é de DOIS papéis (admin
 * e EMISSOR, ver `creditorManage`) — o timbre segue quem leva o título a
 * registro, e quem percebe o CNPJ com um dígito trocado é ele. A margem é só do
 * ADMIN (`pledgePolicyManage`): ela decide quanta terra a empresa exige em
 * garantia de tudo o que for registrado dali em diante, e entregá-la pela porta
 * do CNPJ dava ao emissor a caneta de uma política de risco.
 *
 * `updatedBy` existe pelo mesmo motivo de sempre, e agora com mais razão: com
 * dois donos e duas naturezas, "quem mudou isto?" é pergunta que aparece.
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

  /**
   * A MARGEM DE SEGURANÇA DO PENHOR — a folga de área que a empresa exige.
   *
   * MÉTODO PRÓPRIO, e não um campo do `save` acima, porque a AUTORIDADE é outra:
   * o cadastro é do admin e do emissor (o timbre segue quem leva o papel a
   * registro); esta linha é só do admin. Enquanto ela viajou dentro do
   * `CreditorDto`, o emissor mudava a garantia de toda permuta futura pela porta
   * do CNPJ — ver `pledgePolicyManage` em policy.ts.
   *
   * O `upsert` repete o desenho do `save`: a primeira gravação de uma instalação
   * nova pode ser esta, e um `update` puro estouraria por não achar a linha.
   *
   * ELA NÃO REESCREVE PERMUTA JÁ REGISTRADA. A margem é congelada em
   * `Barter.pledgeMarginPercent` no ato do registro, então mudá-la aqui vale para
   * o que vier depois — e é por isso que a TRILHA é obrigatória, e traz o de-para
   * e a data: "desde quando passamos a exigir menos terra?" é uma pergunta que
   * só a linha do tempo responde.
   */
  async setPledgeMargin(actor: User, pledgeMarginPercent: number): Promise<Creditor> {
    const before = await this.get();
    const saved = await this.prisma.creditor.upsert({
      where: { id: THE_ROW },
      create: { id: THE_ROW, pledgeMarginPercent, updatedBy: actor.fullName },
      update: { pledgeMarginPercent, updatedBy: actor.fullName },
    });

    if (before.pledgeMarginPercent !== saved.pledgeMarginPercent) {
      await this.audit.record({
        actor,
        action: AUDIT_ACTION.creditorPledgeMarginChanged,
        targetType: 'creditor',
        targetId: saved.id,
        targetLabel: saved.name || '(sem razão social)',
        detail:
          `margem de segurança do penhor: ${before.pledgeMarginPercent}% → ` +
          `${saved.pledgeMarginPercent}% (vale para as permutas registradas a partir de agora)`,
      });
    }
    return saved;
  }
}
