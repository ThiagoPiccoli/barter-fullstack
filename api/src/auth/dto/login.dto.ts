import { IsEmail, IsString, MaxLength } from 'class-validator';
import { IsStrongPassword, MAX_PASSWORD_LENGTH } from '../password-policy';

export class LoginDto {
  @IsEmail()
  @MaxLength(254)
  email!: string;

  /**
   * TETO sim, piso não — e a assimetria é de propósito.
   *
   * O piso não entra aqui porque o login não é o lugar de julgar a senha: ele
   * confere a que existe. Exigir dez caracteres para TENTAR entrar diria, a
   * quem digitasse nove, que nenhuma conta usa senha curta — e recusaria a
   * conta legada antes de ela ter a chance de ser migrada.
   *
   * O teto entra porque é a mesma razão que o fez existir na política (ver
   * MAX_PASSWORD_LENGTH): derivar a chave de uma senha enorme custa caro, e
   * esta é a ÚNICA rota anônima que chama o scrypt. Enquanto a política
   * justificava o limite pela negação de serviço e o login não o aplicava, a
   * justificativa protegia todo mundo menos a porta da rua.
   */
  @IsString()
  @MaxLength(MAX_PASSWORD_LENGTH)
  password!: string;
}

/**
 * Troca da própria senha.
 *
 * A regra do que vale como senha mora em password-policy.ts, e não aqui: ela é
 * a mesma do cadastro de usuário e do script de emergência. O que este DTO NÃO
 * consegue conferir é o contexto — a senha não pode conter o nome nem o e-mail
 * de quem a escolhe, e nenhum dos dois vem no corpo desta requisição. Quem
 * completa isso é o AuthService, que sabe de quem é a conta.
 */
export class ChangePasswordDto {
  @IsString()
  currentPassword!: string;

  @IsStrongPassword()
  newPassword!: string;
}
