import { INSURANCE_CHOICE, choiceInsures, insuranceChoiceFor } from './insurance-policy';

/**
 * A política de seguro da versão × o que o consultor pediu.
 *
 * O que estes testes protegem é a recusa da CONTRADIÇÃO: um "com seguro" numa
 * versão sem seguro, atendido em silêncio, sairia sem a linha que o consultor
 * prometeu ao produtor.
 */
describe('Política de seguro da versão', () => {
  it('obrigatório: a permuta leva, diga o consultor o que disser — menos "não"', () => {
    expect(insuranceChoiceFor('required', undefined)).toEqual({ choice: 'required' });
    expect(insuranceChoiceFor('required', true)).toEqual({ choice: 'required' });
    expect(insuranceChoiceFor('required', false)).toHaveProperty('refusal');
  });

  it('opcional: o consultor decide, e o silêncio é recusa', () => {
    expect(insuranceChoiceFor('optional', true)).toEqual({ choice: 'accepted' });
    expect(insuranceChoiceFor('optional', false)).toEqual({ choice: 'declined' });
    expect(insuranceChoiceFor('optional', undefined)).toEqual({ choice: 'declined' });
  });

  it('sem seguro: pedir seguro é recusado', () => {
    expect(insuranceChoiceFor('none', undefined)).toEqual({ choice: 'none' });
    expect(insuranceChoiceFor('none', false)).toEqual({ choice: 'none' });
    expect(insuranceChoiceFor('none', true)).toHaveProperty('refusal');
  });

  it('só obrigatório e aceito levam a linha do seguro', () => {
    expect(choiceInsures(INSURANCE_CHOICE.required)).toBe(true);
    expect(choiceInsures(INSURANCE_CHOICE.accepted)).toBe(true);
    expect(choiceInsures(INSURANCE_CHOICE.declined)).toBe(false);
    expect(choiceInsures(INSURANCE_CHOICE.none)).toBe(false);
  });
});
