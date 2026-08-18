import {
  IsEmail,
  IsInt,
  IsOptional,
  IsPositive,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';
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

  /**
   * A UNIDADE em que a pessoa trabalha.
   *
   * Era `branch`, texto livre. Virou escolha de cadastro porque unidade deixou
   * de ser rótulo e passou a ter dono: é ela que diz quem responde pelo quê. O
   * campo `branch` continua saindo no JSON, escrito a partir daqui.
   */
  @IsInt()
  @IsPositive()
  unitId!: number;

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

/**
 * O cadastro do CONSULTOR — o único papel com campo próprio até aqui.
 *
 * É o encaixe que o comentário do `CreateUserDto` previa: quando um papel
 * precisa de um campo que os outros não têm, ele estende o DTO comum e só o
 * controller dele troca a assinatura. `POST /billers` continua sem saber que
 * gerente existe.
 */
export class CreateConsultantDto extends CreateUserDto {
  /**
   * O GERENTE deste consultor — obrigatório, e não por rigor de formulário.
   *
   * É a ele que as permutas do consultor são enviadas, e é ele quem escreve o
   * parecer técnico. Um consultor sem gerente registraria permutas que nascem
   * numa fila de ninguém: sem erro, sem alarme e sem a quem cobrar. Exigir aqui
   * transforma isso num cadastro que não se conclui, em vez de num problema que
   * só aparece semanas depois.
   */
  @IsInt()
  @IsPositive()
  managerId!: number;
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

  @IsInt()
  @IsPositive()
  unitId!: number;
}

/** A edição do consultor troca o gerente — ver [CreateConsultantDto]. */
export class UpdateConsultantDto extends UpdateUserDto {
  @IsInt()
  @IsPositive()
  managerId!: number;
}
