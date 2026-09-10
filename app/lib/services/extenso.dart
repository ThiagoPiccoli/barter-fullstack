/// NÚMEROS POR EXTENSO, em português — a parte da cédula que ninguém digita.
///
/// A CPR escreve cada número duas vezes: o algarismo e o extenso ("367
/// (trezentos e sessenta e sete) sacas"). A duplicação é proposital e antiga —
/// ela existe para que um dígito rasurado ou trocado não mude silenciosamente
/// quanto se deve.
///
/// E é exatamente por isso que o extenso é DERIVADO aqui, e não um campo de
/// formulário: o modelo que originou esta implementação trazia *"367
/// (quatrocentos e quarenta) sacas"*, com o algarismo e o extenso discordando.
/// Duas caixas de texto lado a lado são duas oportunidades de errar; uma caixa
/// e uma função são uma.
///
/// O que ele NÃO faz: arredondar. Quem decide a precisão é quem chama — a
/// cédula imprime o algarismo e o extenso do MESMO número já arredondado, e um
/// arredondamento escondido aqui faria os dois discordarem de novo, agora por
/// dentro.
library;

const _unidades = [
  'zero',
  'um',
  'dois',
  'três',
  'quatro',
  'cinco',
  'seis',
  'sete',
  'oito',
  'nove',
  'dez',
  'onze',
  'doze',
  'treze',
  'catorze',
  'quinze',
  'dezesseis',
  'dezessete',
  'dezoito',
  'dezenove',
];

const _dezenas = [
  '',
  '',
  'vinte',
  'trinta',
  'quarenta',
  'cinquenta',
  'sessenta',
  'setenta',
  'oitenta',
  'noventa',
];

const _centenas = [
  '',
  'cento',
  'duzentos',
  'trezentos',
  'quatrocentos',
  'quinhentos',
  'seiscentos',
  'setecentos',
  'oitocentos',
  'novecentos',
];

/// As escalas, no singular e no plural. Vai até bilhão porque é o teto honesto:
/// acima disso a cédula estaria em outro ramo de negócio, e um extenso errado
/// numa casa que ninguém revisa é pior do que a recusa de escrevê-lo.
const _escalas = [
  ('', ''),
  ('mil', 'mil'),
  ('milhão', 'milhões'),
  ('bilhão', 'bilhões'),
];

/// Um grupo de até três algarismos (1..999) por extenso.
String _grupo(int n) {
  if (n == 100) return 'cem'; // "cento" só existe acompanhado
  final partes = <String>[];

  final centena = n ~/ 100;
  final resto = n % 100;
  if (centena > 0) partes.add(_centenas[centena]);

  if (resto > 0) {
    if (resto < 20) {
      partes.add(_unidades[resto]);
    } else {
      final dezena = resto ~/ 10;
      final unidade = resto % 10;
      partes.add(unidade == 0 ? _dezenas[dezena] : '${_dezenas[dezena]} e ${_unidades[unidade]}');
    }
  }
  return partes.join(' e ');
}

/// Um inteiro não negativo por extenso: `440` → "quatrocentos e quarenta".
///
/// A pontuação entre os grupos segue o uso brasileiro, e ela não é enfeite:
/// "mil e duzentos" e "mil, duzentos e trinta" separam de propósito o caso em
/// que o último grupo é redondo do caso em que ele continua. A regra é que o
/// último conector vira " e " quando o grupo final é menor que cem ou é uma
/// centena exata — nos demais, vírgula.
String extensoInteiro(int valor) {
  if (valor < 0) return 'menos ${extensoInteiro(-valor)}';
  if (valor == 0) return 'zero';

  // Grupos de três, do menos significativo para o mais.
  final grupos = <int>[];
  var restante = valor;
  while (restante > 0) {
    grupos.add(restante % 1000);
    restante ~/= 1000;
  }
  if (grupos.length > _escalas.length) return '$valor'; // fora do alcance honesto

  final partes = <String>[];
  for (var i = grupos.length - 1; i >= 0; i--) {
    final grupo = grupos[i];
    if (grupo == 0) continue;
    final (singular, plural) = _escalas[i];
    // "mil" não leva "um" na frente: é "mil e duzentos", nunca "um mil".
    final texto = i == 1 && grupo == 1 ? 'mil' : '${_grupo(grupo)}${singular.isEmpty ? '' : ' ${grupo == 1 ? singular : plural}'}';
    partes.add(texto);
  }

  if (partes.length == 1) return partes.first;

  // O ÚLTIMO grupo não vazio decide o conector — e é o último que importa
  // porque é ele que diz ao leitor se o número acabou ali. "um milhão e
  // quinhentos mil" (grupo redondo) contra "mil, duzentos e trinta" (grupo que
  // continua): a vírgula avisa que vem mais.
  final ultimo = grupos.firstWhere((g) => g != 0);
  final conector = ultimo < 100 || ultimo % 100 == 0 ? ' e ' : ', ';
  return '${partes.sublist(0, partes.length - 1).join(', ')}$conector${partes.last}';
}

/// Um valor em reais por extenso: `56540.0` → "cinquenta e seis mil, quinhentos
/// e quarenta reais".
///
/// Os centavos entram só quando existem — "mil reais" e "mil reais e zero
/// centavos" dizem a mesma coisa, e a segunda forma chama atenção para um zero
/// que não significa nada. O arredondamento é para o CENTAVO, que é a menor
/// unidade que a moeda tem: um extenso com fração de centavo seria um valor que
/// não dá para pagar.
String extensoMoeda(double valor) {
  final centavosTotais = (valor * 100).round();
  final reais = centavosTotais ~/ 100;
  final centavos = centavosTotais % 100;

  final parteReais = '${extensoInteiro(reais)} ${reais == 1 ? 'real' : 'reais'}';
  if (centavos == 0) return parteReais;

  final parteCentavos =
      '${extensoInteiro(centavos)} ${centavos == 1 ? 'centavo' : 'centavos'}';
  // Zero reais e alguns centavos existe (um preço de fração), e aí o extenso é
  // só a parte dos centavos: "zero reais e cinquenta centavos" é mais confuso
  // do que "cinquenta centavos".
  return reais == 0 ? parteCentavos : '$parteReais e $parteCentavos';
}

/// Um decimal por extenso, na forma "inteiro vírgula decimal": `45.5` →
/// "quarenta e cinco vírgula cinco".
///
/// É a forma que a cédula usa para área e percentual, e ela é escolhida por ser
/// AMBÍGUA EM NADA: "quarenta e cinco hectares e cinquenta ares" exige do leitor
/// que ele saiba o que é um are, e "quarenta e cinco e meio" perde a precisão
/// que o algarismo ao lado tem.
///
/// [casas] é quantas casas decimais escrever, e o padrão é duas — a mesma
/// precisão com que a área e os percentuais são digitados. As casas seguem em
/// BLOCO ("cinquenta", e não "cinco zero"), que é como se lê um decimal em voz
/// alta.
///
/// O bloco é lido EXATAMENTE como o algarismo é impresso, zeros inclusive: à
/// direita, `45,50` vira "quarenta e cinco vírgula cinquenta", e não "...vírgula
/// cinco"; à esquerda, `45,05` vira "quarenta e cinco vírgula ZERO cinco". Os
/// dois seriam o mesmo número, mas não a mesma linha — e este arquivo existe
/// justamente para que o extenso e o algarismo ao lado nunca contem histórias
/// diferentes.
String extensoDecimal(double valor, {int casas = 2}) {
  final negativo = valor < 0;
  final absoluto = valor.abs();

  final fator = _potencia10(casas);
  final total = (absoluto * fator).round();
  final inteiro = total ~/ fator;
  final decimal = total % fator;

  final texto = decimal == 0
      ? extensoInteiro(inteiro)
      : '${extensoInteiro(inteiro)} vírgula ${_extensoBloco(decimal, casas)}';
  return negativo ? 'menos $texto' : texto;
}

/// O BLOCO DECIMAL por extenso — o número dele, com os zeros à esquerda ditos
/// um a um.
///
/// Os zeros são a razão desta função existir. `decimal` é um inteiro, e um
/// inteiro não guarda quantas casas ele ocupa: o bloco `5` (de `45,5`) e o
/// bloco `05` (de `45,05`) chegam aqui como o mesmo `5`. Soletrá-lo direto
/// escrevia "quarenta e cinco vírgula cinco" para os DOIS — e num título
/// executável isso é o algarismo dizendo `45,05` e o extenso dizendo dez vezes
/// mais, que é exatamente o defeito ("367 (quatrocentos e quarenta)") contra o
/// qual este arquivo inteiro foi escrito.
String _extensoBloco(int decimal, int casas) {
  final digitos = decimal.toString().padLeft(casas, '0');
  final zeros = digitos.length - digitos.replaceFirst(RegExp(r'^0+'), '').length;
  final numero = extensoInteiro(decimal);
  // "zero cinco", "zero zero cinquenta" — um "zero" por casa que o algarismo
  // mostra e o número não carrega.
  return zeros == 0 ? numero : '${List.filled(zeros, 'zero').join(' ')} $numero';
}

/// Um percentual por extenso: `14` → "catorze por cento".
String extensoPercentual(double valor, {int casas = 2}) =>
    '${extensoDecimal(valor, casas: casas)} por cento';

int _potencia10(int expoente) {
  var resultado = 1;
  for (var i = 0; i < expoente; i++) {
    resultado *= 10;
  }
  return resultado;
}
