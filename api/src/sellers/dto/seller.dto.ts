import { IsEmail, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

/**
 * Vendedores são provisionados pelo ADMIN (não há signup público). A senha é
 * opcional na criação: sem ela, vale a senha padrão de primeira entrada.
 */
export class CreateSellerDto {
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  fullName!: string;

  @IsEmail()
  @MaxLength(254)
  email!: string;

  @IsOptional()
  @IsString()
  @MaxLength(30)
  phone?: string;

  @IsString()
  @MinLength(1)
  @MaxLength(120)
  branch!: string;

  @IsOptional()
  @IsString()
  @MinLength(6)
  @MaxLength(64)
  password?: string;
}

/** Edição não troca senha nem papel. */
export class UpdateSellerDto {
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  fullName!: string;

  @IsEmail()
  @MaxLength(254)
  email!: string;

  @IsOptional()
  @IsString()
  @MaxLength(30)
  phone?: string;

  @IsString()
  @MinLength(1)
  @MaxLength(120)
  branch!: string;
}
