import { seasonCode, seasonName, slugOf, versionCode, yearsLabel } from './season-code';

describe('Códigos da safra da cultura', () => {
  it('a cultura que cruza o ano sai como 26/27; a anual, como 2027', () => {
    expect(yearsLabel(2026, 2027)).toBe('26/27');
    expect(yearsLabel(2027, 2027)).toBe('2027');
    expect(yearsLabel(2099, 2100)).toBe('99/00');
  });

  it('o código é o grão sem acento nem espaço, com os anos', () => {
    expect(seasonCode('Soja', 2026, 2027)).toBe('SOJA26/27');
    expect(seasonCode('Canola', 2027, 2027)).toBe('CANOLA2027');
    expect(seasonCode('Milho Safrinha', 2027, 2027)).toBe('MILHOSAFRINHA2027');
    expect(seasonCode('Feijão', 2026, 2027)).toBe('FEIJAO26/27');
  });

  it('o nome é o que as pessoas leem', () => {
    expect(seasonName('Soja', 2026, 2027)).toBe('Soja 26/27');
    expect(seasonName(' Canola ', 2027, 2027)).toBe('Canola 2027');
  });

  it('a versão numera a safra, e o slug tira a barra para a URL', () => {
    const code = versionCode('SOJA26/27', 2);
    expect(code).toBe('SOJA26/27.02');
    expect(slugOf(code)).toBe('SOJA2627.02');
    expect(slugOf('CANOLA2027.01')).toBe('CANOLA2027.01');
  });
});
