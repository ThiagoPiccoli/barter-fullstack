import { IsIn, IsNumber, Min } from 'class-validator';

/**
 * A REGRA de mínimo de uma classe — a única coisa dela que se altera.
 *
 * O nome e a lista não entram aqui de propósito: classe é vocabulário do
 * negócio, criado na migration. O que muda de safra para safra é o quanto do
 * custo da permuta precisa passar por aquela classe.
 */
export class ClassRuleDto {
  @IsIn(['none', 'percentOfTotal', 'valuePerHa'])
  ruleType!: 'none' | 'percentOfTotal' | 'valuePerHa';

  @IsNumber()
  @Min(0)
  ruleValue!: number;
}
