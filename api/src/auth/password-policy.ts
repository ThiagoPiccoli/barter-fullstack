import {
  registerDecorator,
  type ValidationArguments,
  type ValidationOptions,
} from 'class-validator';

/**
 * O QUE CONTA COMO SENHA ACEITÁVEL — a resposta em um lugar só.
 *
 * Antes disto a regra era `@MinLength(6)`, repetida em dois DTOs e uma terceira
 * vez, com outro número, dentro do script de emergência. Seis caracteres é o
 * piso de um sistema que não decide nada; este aqui aprova permuta e redefine
 * acesso de outras contas.
 *
 * O desenho segue o NIST SP 800-63B (§5.1.1.2), e o que ele diz é menos óbvio
 * do que parece:
 *
 * - COMPRIMENTO é o que importa. Dez caracteres, e nenhuma exigência de
 *   maiúscula, número ou símbolo. Regras de composição não produzem senha
 *   forte, produzem `Senha@123` — a mesma senha de sempre com o imposto pago —
 *   e empurram todo mundo para o papelzinho embaixo do teclado.
 * - LISTA DE BLOQUEIO é o que sobra de valor. Senha que já apareceu em
 *   vazamento não é fraca por ser curta, é fraca por ser conhecida, e nenhuma
 *   regra de formato pega isso.
 * - CONTEXTO conta: o nome de quem escolhe, o e-mail e o nome do serviço são
 *   as primeiras tentativas de quem ataca uma conta específica.
 *
 * O que fica de fora, e é o próximo passo: conferir contra a base do "Have I
 * Been Pwned" (k-anonymity, só os cinco primeiros dígitos do SHA-1 saem daqui).
 * Não entrou agora porque significa dar acesso de saída à internet para a API e
 * decidir o que fazer quando o serviço estiver fora do ar — uma decisão de
 * operação, não de código. A lista abaixo cobre o que aparece no topo de todo
 * vazamento; ela não substitui aquela.
 */

/** Piso de comprimento. Acima do mínimo do NIST (8) por ser sistema de dinheiro. */
export const MIN_PASSWORD_LENGTH = 10;

/**
 * Teto. Existe para o scrypt não virar porta de negação de serviço: derivar a
 * chave de uma senha de 10 KB custa o mesmo que derivar dez mil senhas.
 */
export const MAX_PASSWORD_LENGTH = 64;

/**
 * As que não podem passar. Topo dos vazamentos conhecidos, as variações em
 * português e as palavras do próprio produto — `agrobarter2026` é a primeira
 * coisa que alguém tenta contra este sistema, e ela passaria por qualquer
 * regra de comprimento.
 */
const BLOCKLIST = new Set([
  '123456',
  '1234567',
  '12345678',
  '123456789',
  '1234567890',
  '123456789010',
  'password',
  'password1',
  'password123',
  'qwerty',
  'qwerty123',
  'qwertyuiop',
  'abc123',
  'iloveyou',
  'admin',
  'admin123',
  'administrador',
  'letmein',
  'welcome',
  'monkey',
  'dragon',
  'senha',
  'senha123',
  'senha1234',
  'minhasenha',
  'mudar123',
  'trocar123',
  'brasil',
  'brasil123',
  'flamengo',
  'corinthians',
  'agrobarter',
  'agrobarter123',
  'agrobarter2026',
  'barter',
  'barter123',
  'permuta',
  'permuta123',
  'cooperativa',
]);

/** Palavras do próprio serviço: senha que as contenha é chute de primeira rodada. */
const PRODUCT_WORDS = ['agrobarter', 'barter', 'permuta', 'safra'];

/** Sem acento, sem caixa — `Senha` e `sênha` são a mesma tentativa. */
function normalize(value: string): string {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();
}

/**
 * Quantos caracteres DIFERENTES uma senha precisa ter.
 *
 * O comprimento sozinho é enganado por repetição: `aaaaaaaaaa` e `ababababab`
 * têm dez caracteres e a força de um ou dois. Cinco distintos passa longe de
 * qualquer senha escrita por gente e derruba a fileira inteira das que se
 * digitam sem pensar.
 */
const MIN_DISTINCT_CHARACTERS = 5;

/**
 * As corridas de teclado e de alfabeto, do jeito que a mão as faz.
 *
 * Isto começou como "os passos entre as letras são todos +1?", que parecia
 * mais esperto e era pior: `0987654321` passava batido, porque o pulo do `0`
 * para o `9` quebra a conta logo no primeiro passo — e ninguém que escolhe
 * essa senha está pensando em aritmética. Comparar com a corrida escrita por
 * extenso pega as três famílias de uma vez (dígitos, alfabeto e as fileiras do
 * teclado), nos dois sentidos.
 */
const RUNS = ['01234567890', 'abcdefghijklmnopqrstuvwxyz', 'qwertyuiop', 'asdfghjkl', 'zxcvbnm'];

const reverse = (value: string) => [...value].reverse().join('');

/** Um caractere só, repetido, ou variedade pobre demais (`ababababab`). */
function isTooRepetitive(value: string): boolean {
  return new Set(value).size < MIN_DISTINCT_CHARACTERS;
}

/** A senha inteira é um pedaço de uma corrida de teclado ou do alfabeto? */
function isKeyboardRun(value: string): boolean {
  return RUNS.some((run) => run.includes(value) || reverse(run).includes(value));
}

/**
 * Pedaços do nome e do e-mail que não podem virar senha. Só palavras de 4
 * letras ou mais: `ana` cortaria `ana-lisa-do-campo`, que é uma senha
 * perfeitamente boa de alguém chamado Ana.
 */
function ownerWords(owner: PasswordOwner): string[] {
  const local = owner.email?.split('@')[0] ?? '';
  return [...local.split(/[^a-zA-Z0-9]+/), ...(owner.fullName ?? '').split(/\s+/)]
    .map(normalize)
    .filter((word) => word.length >= 4);
}

/** Quem está escolhendo a senha — o que ela NÃO pode conter. */
export interface PasswordOwner {
  email?: string | null;
  fullName?: string | null;
}

/**
 * O problema da senha, em uma frase pronta para exibir — ou `null` quando ela
 * serve. Devolver a mensagem (em vez de um booleano) é o que permite dizer à
 * pessoa o que corrigir: "senha inválida" faz ela tentar de novo no escuro.
 */
export function passwordProblem(password: string, owner: PasswordOwner = {}): string | null {
  if (password.length < MIN_PASSWORD_LENGTH) {
    return `A senha precisa ter ao menos ${MIN_PASSWORD_LENGTH} caracteres`;
  }
  if (password.length > MAX_PASSWORD_LENGTH) {
    return `A senha não pode passar de ${MAX_PASSWORD_LENGTH} caracteres`;
  }

  const normalized = normalize(password);

  if (BLOCKLIST.has(normalized)) {
    return 'Esta senha é conhecida demais — escolha outra que ninguém tentaria';
  }
  if (isKeyboardRun(normalized)) {
    return 'Uma sequência de teclas não protege a conta — escolha outra senha';
  }
  if (isTooRepetitive(normalized)) {
    return `A senha precisa ter ao menos ${MIN_DISTINCT_CHARACTERS} caracteres diferentes`;
  }
  if (PRODUCT_WORDS.some((word) => normalized.includes(word))) {
    return 'A senha não pode conter o nome do sistema';
  }
  if (ownerWords(owner).some((word) => normalized.includes(word))) {
    return 'A senha não pode conter o seu nome nem o seu e-mail';
  }

  return null;
}

/**
 * A mesma regra, como validação de DTO.
 *
 * Quando o objeto validado trouxer `email` e `fullName` ao lado (é o caso do
 * cadastro de usuário), eles entram na conferência de contexto. A troca da
 * própria senha não os tem no corpo — lá quem completa o contexto é o
 * AuthService, que sabe de quem é a conta.
 */
export function IsStrongPassword(options?: ValidationOptions): PropertyDecorator {
  return (target: object, propertyName: string | symbol) =>
    registerDecorator({
      name: 'isStrongPassword',
      target: target.constructor,
      propertyName: propertyName as string,
      options,
      validator: {
        validate(value: unknown, args: ValidationArguments) {
          if (typeof value !== 'string') return false;
          const sibling = args.object as PasswordOwner;
          return (
            passwordProblem(value, { email: sibling.email, fullName: sibling.fullName }) === null
          );
        },
        defaultMessage(args: ValidationArguments) {
          const value = args.value as unknown;
          if (typeof value !== 'string') return 'A senha precisa ser um texto';
          const sibling = args.object as PasswordOwner;
          return (
            passwordProblem(value, { email: sibling.email, fullName: sibling.fullName }) ??
            'Senha inválida'
          );
        },
      },
    });
}
