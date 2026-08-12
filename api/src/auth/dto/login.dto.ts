import { IsEmail, IsString, MaxLength, MinLength } from 'class-validator';

export class LoginDto {
  @IsEmail()
  @MaxLength(254)
  email!: string;

  @IsString()
  password!: string;
}

/**
 * Troca da própria senha. O mínimo de 6 acompanha o provisionamento de
 * vendedores (CreateSellerDto) — a senha provisória do admin também respeita
 * esse piso.
 */
export class ChangePasswordDto {
  @IsString()
  currentPassword!: string;

  @IsString()
  @MinLength(6, { message: 'A nova senha precisa ter ao menos 6 caracteres' })
  @MaxLength(64)
  newPassword!: string;
}
