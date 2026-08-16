import type { User } from '@prisma/client';

/**
 * A TRAVA POR CONTA — quantas senhas erradas seguidas ela aceita, por quanto
 * tempo descansa, e o que a destranca.
 *
 * Isto existe porque o limite por IP protege o SERVIDOR, não a CONTA: dez
 * tentativas por minuto por IP viram muitas por minuto quando saem de muitos
 * IPs, e a conta do admin é alvo conhecido de qualquer um que veja a tela de
 * login.
 *
 * A TROCA que este desenho aceita, dita por inteiro: quem souber o e-mail de
 * alguém consegue manter a conta trancada errando senha de propósito. É por
 * isso que a trava é de QUINZE MINUTOS e não de "até o admin liberar" — o
 * incômodo passa sozinho, o ataque de adivinhação não sobrevive a ele, e a
 * redefinição de senha continua sendo a saída imediata. Uma trava permanente
 * trocaria o roubo de conta por uma negação de serviço confiável, o que é um
 * péssimo negócio.
 *
 * POR QUE ESTE ARQUIVO EXISTE, e não duas constantes dentro do AuthService: a
 * trava é escrita em um lugar (o login que erra) e apagada em QUATRO (o login
 * que acerta, a troca da própria senha, o reset pelo admin e o reset pela linha
 * de comando). Enquanto o que apaga era um par de campos digitado à mão, três
 * desses quatro caminhos simplesmente esqueciam de apagar — e a conta seguia
 * trancada depois de receber uma senha nova, que é o oposto do que um reset
 * promete.
 */
export const MAX_FAILED_ATTEMPTS = 10;
export const LOCK_MINUTES = 15;

/**
 * O estado "esta conta não tem histórico de erro": contador zerado e trava
 * removida.
 *
 * É o que TODO caminho que prova a identidade do titular precisa gravar —
 * acertar a senha, trocá-la sabendo a atual, ou receber uma nova de quem tem
 * poder para isso. Sem isso o reset entrega uma senha que não entra, e o
 * contador herdado tranca a conta no primeiro engano ao digitá-la.
 */
export const CLEARED_LOCKOUT: { failedLoginAttempts: number; lockedUntil: Date | null } = {
  failedLoginAttempts: 0,
  lockedUntil: null,
};

/** Até quando a conta descansa, contado a partir de agora. */
export function lockExpiryFrom(now: Date = new Date()): Date {
  return new Date(now.getTime() + LOCK_MINUTES * 60 * 1000);
}

/** A conta está de castigo neste instante? */
export function isLocked(user: Pick<User, 'lockedUntil'>, now: Date = new Date()): boolean {
  return user.lockedUntil !== null && user.lockedUntil.getTime() > now.getTime();
}
