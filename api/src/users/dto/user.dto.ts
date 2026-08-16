import { IsEmail, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { IsStrongPassword } from '../../auth/password-policy';

/**
 * Forma do cadastro de usuário. Vale hoje para os quatro papéis provisionáveis
 * — e note o que NÃO existe aqui: `role`. O papel vem da rota
 * (`POST /billers` cria faturista), então nem se ele fosse enviado no corpo
 * seria lido: o `whitelist` do ValidationPipe descarta campo não declarado.
 *
 * Quando um papel precisar de campo próprio (alçada em R$ do gerente, por
 * exemplo), ele ganha o seu DTO estendendo este e o controller dele troca a
 * assinatura — sem tocar nos outros três. É para isso que as rotas são
 * separadas.
 */
export class CreateUserDto {
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

  /**
   * Opcional: sem ela, o servidor sorteia a senha de primeira entrada — e é o
   * caminho preferido, porque o sorteio produz senha melhor do que a que o
   * admin escolheria digitando.
   *
   * Quando vem preenchida, vale a mesma regra de todo o resto (ver
   * password-policy.ts). Como `email` e `fullName` estão neste mesmo corpo, a
   * conferência de contexto acontece aqui mesmo: não dá para cadastrar o
   * consultor João Silva com a senha `joaosilva01`.
   */
  @IsOptional()
  @IsStrongPassword()
  password?: string;
}

/** Edição não troca senha nem papel — para isso existem rotas próprias. */
export class UpdateUserDto {
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
