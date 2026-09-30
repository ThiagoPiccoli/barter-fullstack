import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'active_brand.dart';
import 'brand_mark.dart';

/// Família do logotipo, empacotada em `assets/fonts` (ver pubspec).
const String brandWordmarkFont = 'BricolageGrotesque';

/// Sobre qual fundo o logotipo está sendo desenhado.
///
/// O logotipo é bicolor nos dois casos — o que muda é qual par de cores dá
/// contraste. Sobre a cor institucional o acento vivo brilha; sobre superfície
/// clara ele precisa cair para a variante escurecida.
enum BrandTone {
  /// Sobre a cor institucional: app bar, cabeçalhos, login.
  onPrimary,

  /// Sobre fundo claro: cartões, folhas de impressão, diálogos.
  onSurface,
}

/// Logotipo da marca ativa: símbolo (vagem + espiga) + assinatura bicolor.
///
/// A quebra de cor entre `wordmarkPrefix` e `wordmarkSuffix` é a assinatura da
/// marca — em `agroBarter`, `agro` sai no acento e `Barter` no tom de conteúdo.
/// Nada aqui é literal: outro cliente troca as duas palavras e as cores no seu
/// arquivo de marca e o logotipo se redesenha.
class BrandWordmark extends StatelessWidget {
  /// Altura do símbolo. Todo o resto escala a partir daqui.
  final double size;

  /// Mostra o nome ao lado do símbolo. Desligue em espaços apertados.
  final bool showLettering;

  /// Mostra a assinatura sob o nome.
  final bool showTagline;

  final BrandTone tone;

  const BrandWordmark({
    super.key,
    this.size = 40,
    this.showLettering = true,
    this.showTagline = true,
    this.tone = BrandTone.onPrimary,
  });

  bool get _onDark => tone == BrandTone.onPrimary;

  /// Cor do prefixo: o acento vivo sobre fundo escuro, o escurecido sobre claro.
  Color get _prefixColor =>
      _onDark ? AppColors.primaryAccent : AppColors.accentOnLight;

  /// Cor do sufixo: sempre o tom de maior contraste com o fundo.
  Color get _suffixColor => _onDark ? AppColors.onPrimary : AppColors.primary;

  Color get _taglineColor =>
      _onDark ? AppColors.onPrimaryMuted : AppColors.textMedium;

  /// A vagem inverte com o fundo; a espiga fica sempre no dourado da marca.
  Color get _podColor => _onDark ? AppColors.onPrimary : AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final id = brand.identity;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(
          height: size,
          podColor: _podColor,
          wheatColor: AppColors.primaryAccent,
        ),
        if (showLettering) ...[
          SizedBox(width: size * 0.17),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(children: [
                  // As duas metades têm o mesmo peso: é só a cor que divide,
                  // como no desenho oficial.
                  TextSpan(
                    text: id.wordmarkPrefix,
                    style: TextStyle(color: _prefixColor),
                  ),
                  TextSpan(
                    text: id.wordmarkSuffix,
                    style: TextStyle(color: _suffixColor),
                  ),
                ]),
                // Proporções do SVG oficial: corpo de 56 para um símbolo de 75,
                // espaçamento de -3,5% do corpo.
                style: TextStyle(
                  fontFamily: brandWordmarkFont,
                  fontSize: size * 0.62,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -size * 0.62 * 0.035,
                  height: 1.1,
                ),
              ),
              if (showTagline)
                Text(
                  brand.identity.tagline,
                  style: TextStyle(
                    color: _taglineColor,
                    fontSize: size * 0.2,
                    letterSpacing: 0.4,
                    height: 1.3,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
