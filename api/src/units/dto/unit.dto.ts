import { IsString, MaxLength, MinLength } from 'class-validator';

/**
 * Cadastro da unidade de retirada — um lugar, e só.
 *
 * Repare no que NÃO existe aqui: um responsável. A unidade não tem dono e não
 * decide quem analisa a permuta; quem dá o parecer é o gerente do consultor que
 * a registrou. O local de retirada é combinado com o produtor e pode ser
 * qualquer um da lista.
 */
export class UnitDto {
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name!: string;

  @IsString()
  @MinLength(2)
  @MaxLength(80)
  city!: string;
}
