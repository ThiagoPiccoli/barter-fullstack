import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/services/num_input.dart';

/// A LEITURA DE NÚMERO DIGITADO, uma só para o app inteiro.
///
/// Ela existia sete vezes, uma por formulário, e em três feitios: o
/// `replaceAll(',', '.')` puro, o mesmo com o ponto de milhar removido, e um que
/// ainda limpava "R$". O mesmo texto virava três números conforme a tela — e a
/// versão que lia "1.250,00" como 1,25 era a do valor da saca, que multiplica a
/// permuta inteira.
void main() {
  group('parseNumber', () {
    test('vírgula é decimal e ponto é milhar — como o Brasil escreve', () {
      expect(parseNumber('152,50'), 152.5);
      expect(parseNumber('1.250,00'), 1250.0);
      expect(parseNumber('1.250.000,75'), 1250000.75);
    });

    /// SEM VÍRGULA, o ponto é decimal: é o que chega de um teclado numérico de
    /// celular e de qualquer valor copiado de outro sistema.
    test('sem vírgula, o ponto é decimal', () {
      expect(parseNumber('1250.5'), 1250.5);
      expect(parseNumber('60'), 60.0);
    });

    /// O RÓTULO ESCAPA para dentro do campo quando alguém cola um valor de
    /// outro lugar — e o número continua lá.
    test('unidade e moeda coladas junto não derrubam a leitura', () {
      expect(parseNumber('R\$ 1.250,00'), 1250.0);
      expect(parseNumber('120 ha'), 120.0);
      expect(parseNumber('45%'), 45.0);
    });

    /// VAZIO É `null`, E NÃO ZERO: campo em branco e "zero digitado" são
    /// respostas diferentes, e quem decide o que fazer com cada uma é o
    /// formulário. Um preço zerado que ninguém digitou é pior que um branco.
    test('vazio e ilegível devolvem null', () {
      expect(parseNumber(''), isNull);
      expect(parseNumber('   '), isNull);
      expect(parseNumber('abc'), isNull);
      expect(parseNumber('R\$'), isNull);
    });

    test('negativo sobrevive — quem recusa é a validação do campo', () {
      expect(parseNumber('-12,5'), -12.5);
    });

    test('parseNumberOr troca o vazio pelo padrão de quem chamou', () {
      expect(parseNumberOr(''), 0);
      expect(parseNumberOr('abc', fallback: 1), 1);
      expect(parseNumberOr('7,5'), 7.5);
    });
  });
}
