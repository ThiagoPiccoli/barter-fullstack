import type { Creditor } from '@prisma/client';

/**
 * A CREDORA — a empresa que recebe o grão, do ponto de vista dos documentos.
 *
 * A CPR nomeia as duas partes: o EMITENTE (o produtor, que varia a cada cédula)
 * e a CREDORA (a empresa, sempre a mesma). Ela aparece em quatro cláusulas do
 * modelo — a qualificação (II), a promessa de entrega, o local de entrega (V-d)
 * e o foro (XX) —, e nas três primeiras é o MESMO texto, palavra por palavra.
 *
 * Por isso ela NÃO é campo de formulário da cédula, e sim CADASTRO: um lugar só,
 * escrito uma vez, mantido pelo admin e pelo faturista (ver `creditorManage` em
 * policy.ts). Este arquivo é a parte PURA disso — o que falta e como o foro
 * resolve o vazio —, sem I/O; quem lê e grava a linha é `creditor/`.
 *
 * Ela já morou no AMBIENTE (`CREDITOR_*`), e saiu de lá: corrigir um dígito do
 * CNPJ virava deploy, e quem percebe o erro — o faturista, montando a cédula —
 * não tinha como resolvê-lo. Dado de operação mora onde a operação alcança.
 */
export const EMPTY_CREDITOR: Creditor = {
  id: 1,
  name: '',
  cnpj: '',
  address: '',
  addressNumber: '',
  city: '',
  forum: '',
  updatedAt: new Date(0),
  updatedBy: '',
};

/**
 * O FORO que vale de fato: o eleito, ou a comarca da sede.
 *
 * O vazio não é lacuna — é o caso normal. Eleger o foro da própria sede é o que
 * quase toda credora faz, e obrigar a redigitar a mesma cidade num segundo campo
 * só cria a chance de os dois discordarem.
 */
export function forumOf(creditor: Creditor): string {
  return creditor.forum.trim() || creditor.city;
}

/**
 * O que falta no cadastro para uma cédula sair completa.
 *
 * A CPR não é recusada por causa disto — o faturista pode preencher a parte dele
 * hoje e a credora ser cadastrada amanhã. A lista sobe junto com os dados para a
 * tela poder dizer o que é o quê, e ela é SEPARADA da lista de pendências da
 * cédula: somadas, o faturista procuraria um campo de CNPJ dentro do formulário
 * da cédula, onde ele não existe.
 */
export function creditorGaps(creditor: Creditor): string[] {
  // Só os campos de TEXTO entram na chave: `forum` fica de fora porque o vazio
  // dele significa "a comarca da sede" (ver `forumOf`), e `updatedAt`/`updatedBy`
  // são rastro, não conteúdo do documento. O tipo é estreitado para as chaves de
  // string de propósito — sem isso, acrescentar uma data ao modelo faria esta
  // lista aceitá-la e compará-la como texto.
  type TextField = 'name' | 'cnpj' | 'address' | 'addressNumber' | 'city';
  const required: [TextField, string][] = [
    ['name', 'razão social'],
    ['cnpj', 'CNPJ'],
    ['address', 'logradouro da sede'],
    ['addressNumber', 'número do endereço'],
    ['city', 'cidade/UF'],
  ];
  return required.filter(([field]) => !creditor[field].trim()).map(([, label]) => label);
}
