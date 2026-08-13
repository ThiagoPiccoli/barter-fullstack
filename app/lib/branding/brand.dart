import 'package:flutter/material.dart';

/// Contrato de marca do aplicativo.
///
/// Tudo que muda de um cliente para outro — cores, nome, assinatura visual e
/// vocabulário — vive aqui dentro. Nenhuma tela conhece um hex ou um nome
/// comercial: elas leem `AppColors` (que deriva de [BrandPalette]) e
/// `brand.copy` / `brand.identity`.
///
/// Para reskinnar o app para uma nova empresa, veja `lib/branding/README.md`.

/// Paleta completa da marca.
///
/// A regra de ouro: **toda cor visível no app sai daqui**. Se você precisar de
/// um tom novo em uma tela, adicione um campo nesta classe em vez de escrever
/// um `Color(0x...)` solto — senão o próximo cliente herda a cor do anterior.
@immutable
class BrandPalette {
  /// Cor institucional. Domina app bar, botões e fundos de destaque.
  final Color primary;

  /// Um passo mais claro que [primary]. Fecha o gradiente dos cabeçalhos.
  final Color primaryMedium;

  /// Variante clara para estados sutis (ícones sobre fundo claro, realces).
  final Color primaryLight;

  /// Cor de destaque/energia da marca. É ela que colore o prefixo do logotipo.
  final Color primaryAccent;

  /// Fundo tênue derivado da primária, para chips e cartões selecionados.
  final Color primarySurface;

  /// Variante do acento legível sobre fundo claro (contraste AA em texto).
  ///
  /// Acentos vivos (lima, âmbar) costumam falhar em contraste sobre branco;
  /// este é o tom que o logotipo usa quando está sobre superfície clara.
  final Color accentOnLight;

  /// Fundo geral das telas.
  final Color background;

  /// Superfície de cartões e campos.
  final Color surface;

  /// Conteúdo sobre [surface]/[background], do mais forte ao mais fraco.
  final Color textDark;
  final Color textMedium;
  final Color textLight;

  /// Conteúdo sobre [primary] (cabeçalhos, app bar, tela de login).
  ///
  /// Separar estes tons dos `Color(0xAAFFFFFF)` espalhados pelo código é o que
  /// permite a uma marca de fundo claro continuar legível.
  final Color onPrimary;

  /// Texto secundário sobre a primária (~80% de [onPrimary]).
  final Color onPrimaryMuted;

  /// Texto terciário / legendas sobre a primária (~65%).
  final Color onPrimarySubtle;

  /// Traços e ícones decorativos sobre a primária (~33%).
  final Color onPrimaryFaint;

  /// Preenchimento de blocos translúcidos sobre a primária (~12%).
  final Color onPrimaryOverlay;

  /// Estados de uma permuta, e seus fundos correspondentes.
  final Color approved;
  final Color pending;
  final Color denied;
  final Color approvedBg;
  final Color pendingBg;
  final Color deniedBg;

  /// Separadores e bordas de campo.
  final Color divider;

  /// Borda mais tênue, usada em campos de formulário em repouso.
  final Color borderSubtle;

  /// Sombra dos cartões.
  final Color cardShadow;

  /// Fundo neutro para elementos desabilitados.
  final Color disabledBg;

  /// Conteúdo de elementos desabilitados.
  final Color disabledFg;

  /// As duas pontas do negócio: o insumo retirado (que define o custo) e o
  /// grão de pagamento (que cobre esse custo). São cores semânticas, não
  /// decorativas — mantenha-as distinguíveis entre si e da [primary].
  final Color grain;
  final Color grainBg;
  final Color input;
  final Color inputBg;

  /// Cor do saldo/fechamento de conta nos resumos.
  final Color balance;

  /// Série categórica para gráficos (sacas por grão, etc.).
  ///
  /// Ordenada: o gráfico consome do índice 0 em diante e repete se acabar.
  final List<Color> dataSeries;

  const BrandPalette({
    required this.primary,
    required this.primaryMedium,
    required this.primaryLight,
    required this.primaryAccent,
    required this.primarySurface,
    required this.accentOnLight,
    required this.background,
    required this.surface,
    required this.textDark,
    required this.textMedium,
    required this.textLight,
    required this.onPrimary,
    required this.onPrimaryMuted,
    required this.onPrimarySubtle,
    required this.onPrimaryFaint,
    required this.onPrimaryOverlay,
    required this.approved,
    required this.pending,
    required this.denied,
    required this.approvedBg,
    required this.pendingBg,
    required this.deniedBg,
    required this.divider,
    required this.borderSubtle,
    required this.cardShadow,
    required this.disabledBg,
    required this.disabledFg,
    required this.grain,
    required this.grainBg,
    required this.input,
    required this.inputBg,
    required this.balance,
    required this.dataSeries,
  });

  /// Gradiente institucional dos cabeçalhos e blocos de resumo.
  LinearGradient get primaryGradient => LinearGradient(
        colors: [primary, primaryMedium],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Cor da série [index], repetindo do início quando a lista acaba.
  Color series(int index) => dataSeries[index % dataSeries.length];
}

/// Assinatura verbal e visual da marca.
@immutable
class BrandIdentity {
  /// Primeira metade do logotipo, pintada com o acento. Ex.: `agro`.
  final String wordmarkPrefix;

  /// Segunda metade do logotipo, pintada com o tom de conteúdo. Ex.: `Barter`.
  final String wordmarkSuffix;

  /// Monograma do ícone quadrado ao lado do logotipo. Ex.: `aB`.
  final String monogram;

  /// Assinatura sob o logotipo. Ex.: `Permuta de grãos por insumos`.
  final String tagline;

  /// Nome completo para título de janela, PDF e metadados.
  final String appTitle;

  /// Razão social / nome do detentor do copyright no rodapé.
  final String legalName;

  /// Domínio de e-mail usado nos exemplos de login.
  final String emailDomain;

  /// Como o logotipo deve ser desenhado por padrão em texto puro (PDF, título).
  String get wordmark => '$wordmarkPrefix$wordmarkSuffix';

  const BrandIdentity({
    required this.wordmarkPrefix,
    required this.wordmarkSuffix,
    required this.monogram,
    required this.tagline,
    required this.appTitle,
    required this.legalName,
    required this.emailDomain,
  });
}

/// Vocabulário do domínio.
///
/// Cooperativas diferentes chamam a mesma coisa por nomes diferentes: o que
/// aqui é "permuta" pode ser "troca" ou "barter" em outro cliente, e "consultor"
/// pode ser "vendedor" ou "RTV". Centralizar isso evita ter que caçar strings
/// em quinze telas a cada implantação.
///
/// Convenção: `x` é minúsculo para uso no meio da frase, `xTitle` é a forma de
/// título, `xPlural`/`xPluralTitle` são os plurais.
@immutable
class BrandCopy {
  final String barter;
  final String barterTitle;
  final String barterPlural;
  final String barterPluralTitle;

  final String grain;
  final String grainTitle;
  final String grainPlural;
  final String grainPluralTitle;

  final String input;
  final String inputTitle;
  final String inputPlural;
  final String inputPluralTitle;

  final String producer;
  final String producerTitle;
  final String producerPlural;
  final String producerPluralTitle;

  final String consultant;
  final String consultantTitle;
  final String consultantPlural;
  final String consultantPluralTitle;

  /// Abreviação de [consultant] usada em cartões apertados. Ex.: `Cons.`
  final String consultantShort;

  /// Unidade de entrega do grão. Ex.: `saca` / `sacas`.
  final String sack;
  final String sackPlural;

  /// Como a organização se chama ao falar com o usuário. Ex.: `cooperativa`.
  final String organization;

  const BrandCopy({
    required this.barter,
    required this.barterTitle,
    required this.barterPlural,
    required this.barterPluralTitle,
    required this.grain,
    required this.grainTitle,
    required this.grainPlural,
    required this.grainPluralTitle,
    required this.input,
    required this.inputTitle,
    required this.inputPlural,
    required this.inputPluralTitle,
    required this.producer,
    required this.producerTitle,
    required this.producerPlural,
    required this.producerPluralTitle,
    required this.consultant,
    required this.consultantTitle,
    required this.consultantPlural,
    required this.consultantPluralTitle,
    required this.consultantShort,
    required this.sack,
    required this.sackPlural,
    required this.organization,
  });
}

/// Geometria da marca: o quanto o desenho é arredondado.
///
/// Uma marca mais séria/institucional pede raios menores; uma mais jovem, raios
/// maiores. Um número aqui muda a personalidade do app inteiro.
@immutable
class BrandShape {
  final double card;
  final double button;
  final double field;
  final double chip;
  final double logoTile;

  const BrandShape({
    this.card = 12,
    this.button = 10,
    this.field = 10,
    this.chip = 20,
    this.logoTile = 8,
  });

  BorderRadius get cardRadius => BorderRadius.circular(card);
  BorderRadius get buttonRadius => BorderRadius.circular(button);
  BorderRadius get fieldRadius => BorderRadius.circular(field);
  BorderRadius get chipRadius => BorderRadius.circular(chip);
  BorderRadius get logoTileRadius => BorderRadius.circular(logoTile);
}

/// Uma marca completa: identidade + paleta + vocabulário + geometria.
@immutable
class Brand {
  final BrandIdentity identity;
  final BrandPalette palette;
  final BrandCopy copy;
  final BrandShape shape;

  /// Família tipográfica. `null` usa a fonte padrão da plataforma.
  final String? fontFamily;

  const Brand({
    required this.identity,
    required this.palette,
    required this.copy,
    this.shape = const BrandShape(),
    this.fontFamily,
  });
}
