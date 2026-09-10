import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/services/extenso.dart';

/// O EXTENSO da cédula. Estes testes são a razão de a função existir: o modelo
/// que originou a implementação trazia "367 (quatrocentos e quarenta) sacas" —
/// o algarismo e o extenso discordando dentro do mesmo título de crédito.
///
/// Os números aqui estão escritos à mão de propósito, como as alíquotas em
/// `tax_regime_test.dart`: eles são a língua portuguesa, não o resultado de uma
/// fórmula que dê para reconstruir do código.
void main() {
  group('inteiros', () {
    test('as unidades e a faixa irregular dos dez aos dezenove', () {
      expect(extensoInteiro(0), 'zero');
      expect(extensoInteiro(1), 'um');
      expect(extensoInteiro(9), 'nove');
      expect(extensoInteiro(10), 'dez');
      expect(extensoInteiro(14), 'catorze');
      expect(extensoInteiro(15), 'quinze');
      expect(extensoInteiro(19), 'dezenove');
    });

    test('dezenas, com e sem unidade', () {
      expect(extensoInteiro(20), 'vinte');
      expect(extensoInteiro(21), 'vinte e um');
      expect(extensoInteiro(45), 'quarenta e cinco');
      expect(extensoInteiro(90), 'noventa');
      expect(extensoInteiro(99), 'noventa e nove');
    });

    /// "cem" sozinho, "cento" acompanhado. É a irregularidade que mais aparece
    /// numa cédula, porque quase todo valor passa dos cem.
    test('cem é cem sozinho e cento acompanhado', () {
      expect(extensoInteiro(100), 'cem');
      expect(extensoInteiro(101), 'cento e um');
      expect(extensoInteiro(150), 'cento e cinquenta');
      expect(extensoInteiro(200), 'duzentos');
      expect(extensoInteiro(367), 'trezentos e sessenta e sete');
      expect(extensoInteiro(440), 'quatrocentos e quarenta');
      expect(extensoInteiro(999), 'novecentos e noventa e nove');
    });

    /// "mil" não leva "um" na frente — é "mil e duzentos", nunca "um mil".
    test('mil não vem acompanhado de um', () {
      expect(extensoInteiro(1000), 'mil');
      expect(extensoInteiro(1001), 'mil e um');
      expect(extensoInteiro(1200), 'mil e duzentos');
      expect(extensoInteiro(2000), 'dois mil');
    });

    /// A regra da pontuação entre grupos: " e " quando o último grupo é menor
    /// que cem ou é centena exata; vírgula nos demais. Ela separa "mil e
    /// duzentos" de "mil, duzentos e trinta", e não é enfeite — é o que diz ao
    /// leitor se o número acabou ali.
    test('o conector do último grupo segue o uso brasileiro', () {
      expect(extensoInteiro(1230), 'mil, duzentos e trinta');
      expect(extensoInteiro(1030), 'mil e trinta');
      expect(extensoInteiro(1100), 'mil e cem');
      expect(extensoInteiro(21500), 'vinte e um mil e quinhentos');
      expect(extensoInteiro(26400), 'vinte e seis mil e quatrocentos');
      expect(extensoInteiro(56540), 'cinquenta e seis mil, quinhentos e quarenta');
    });

    test('milhões e bilhões, no singular e no plural', () {
      expect(extensoInteiro(1000000), 'um milhão');
      expect(extensoInteiro(2000000), 'dois milhões');
      expect(extensoInteiro(1500000), 'um milhão e quinhentos mil');
      expect(extensoInteiro(1000000000), 'um bilhão');
    });
  });

  group('moeda', () {
    test('reais inteiros não ganham "e zero centavos"', () {
      expect(extensoMoeda(56540), 'cinquenta e seis mil, quinhentos e quarenta reais');
      expect(extensoMoeda(1), 'um real');
      expect(extensoMoeda(2), 'dois reais');
    });

    test('centavos entram quando existem', () {
      expect(extensoMoeda(128.5), 'cento e vinte e oito reais e cinquenta centavos');
      expect(extensoMoeda(1.01), 'um real e um centavo');
      expect(extensoMoeda(148.5), 'cento e quarenta e oito reais e cinquenta centavos');
    });

    /// Só centavos: "zero reais e cinquenta centavos" é mais confuso do que
    /// "cinquenta centavos".
    test('valor abaixo de um real é só a parte dos centavos', () {
      expect(extensoMoeda(0.5), 'cinquenta centavos');
      expect(extensoMoeda(0), 'zero reais');
    });

    /// O arredondamento é para o CENTAVO, que é a menor unidade pagável — e é o
    /// mesmo do algarismo impresso ao lado.
    test('fração de centavo é arredondada, como o algarismo ao lado', () {
      expect(extensoMoeda(10.004), 'dez reais');
      expect(extensoMoeda(10.005), 'dez reais e um centavo');
    });
  });

  group('decimais e percentuais', () {
    test('a área sai como "inteiro vírgula decimal"', () {
      expect(extensoDecimal(45.5), 'quarenta e cinco vírgula cinquenta');
      expect(extensoDecimal(120), 'cento e vinte');
      expect(extensoDecimal(80.25), 'oitenta vírgula vinte e cinco');
    });

    /// O bloco decimal é lido como o algarismo é IMPRESSO — zeros à direita
    /// inclusive. `1,50` e `1,5` são o mesmo número, mas não a mesma linha, e o
    /// extenso acompanha o que está escrito ao lado dele.
    test('o extenso lê o decimal como ele é impresso', () {
      expect(extensoDecimal(1.50), 'um vírgula cinquenta');
      expect(extensoDecimal(1.5, casas: 4), 'um vírgula cinco mil');
      // Decimal zerado não vira "vírgula zero": o número é inteiro.
      expect(extensoDecimal(2.0), 'dois');
    });

    /// OS ZEROS À ESQUERDA DO BLOCO — o caso que este arquivo existia para
    /// impedir e deixava passar.
    ///
    /// `decimal` é um inteiro, e inteiro não guarda quantas casas ocupa: o bloco
    /// `5` de `45,5` e o bloco `05` de `45,05` chegavam à escrita como o mesmo
    /// `5`. Os dois saíam "vírgula cinco" — o algarismo dizendo `45,05` e o
    /// extenso, ao lado dele, dizendo dez vezes mais. É o "367 (quatrocentos e
    /// quarenta)" de novo, agora produzido por nós, na cláusula do penhor.
    test('o zero à esquerda do bloco decimal é dito, não engolido', () {
      expect(extensoDecimal(45.05), 'quarenta e cinco vírgula zero cinco');
      expect(extensoDecimal(1234.05), 'mil, duzentos e trinta e quatro vírgula zero cinco');
      expect(extensoDecimal(0.05), 'zero vírgula zero cinco');
      expect(extensoDecimal(1.09), 'um vírgula zero nove');
      // Duas casas de zero, quando o bloco tem quatro: "1,0050".
      expect(extensoDecimal(1.005, casas: 4), 'um vírgula zero zero cinquenta');
      // E o percentual, que é a mesma escrita: 1,05% não é 1,5%.
      expect(extensoPercentual(1.05), 'um vírgula zero cinco por cento');
    });

    test('os percentuais do padrão do grão', () {
      expect(extensoPercentual(14), 'catorze por cento');
      expect(extensoPercentual(1), 'um por cento');
      expect(extensoPercentual(18), 'dezoito por cento');
      expect(extensoPercentual(1.5), 'um vírgula cinquenta por cento');
    });
  });

  /// O caso que originou tudo isto: o algarismo e o extenso do MESMO número não
  /// podem discordar. O modelo recebido trazia 367 escrito como "quatrocentos e
  /// quarenta" — dois números diferentes na mesma linha de um título executável.
  test('o algarismo e o extenso saem sempre do mesmo número', () {
    for (final n in [1, 9, 10, 14, 99, 100, 101, 367, 440, 1000, 1200, 56540]) {
      expect(extensoInteiro(n), isNot(equals('$n')),
          reason: '$n deveria virar palavra, não repetir o algarismo');
    }
    // O par que estava errado no modelo, agora impossível de divergir.
    expect(extensoInteiro(367), 'trezentos e sessenta e sete');
    expect(extensoInteiro(440), 'quatrocentos e quarenta');
  });
}
