import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'active_brand.dart';

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

/// Logotipo da marca ativa: monograma + assinatura bicolor.
///
/// A quebra de cor entre `wordmarkPrefix` e `wordmarkSuffix` é a assinatura da
/// marca — em `agroBarter`, `agro` sai no acento e `Barter` no tom de conteúdo.
/// Nada aqui é literal: outro cliente troca as duas palavras e as cores no seu
/// arquivo de marca e o logotipo se redesenha.
class BrandWordmark extends StatelessWidget {
  /// Lado do quadrado do monograma. Todo o resto escala a partir daqui.
  final double size;

  /// Mostra o nome ao lado do monograma. Desligue em espaços apertados.
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

  /// O ladrilho inverte com o fundo, e o monograma inverte junto — é isso que
  /// mantém a leitura de duas cores nas duas situações.
  Color get _tileColor => _onDark ? AppColors.onPrimary : AppColors.primary;
  Color get _tilePrefixColor =>
      _onDark ? AppColors.accentOnLight : AppColors.primaryAccent;
  Color get _tileSuffixColor =>
      _onDark ? AppColors.primary : AppColors.onPrimary;

  @override
  Widget build(BuildContext context) {
    final id = brand.identity;
    // O monograma quebra na primeira letra, espelhando a quebra do nome.
    final mono = id.monogram;
    final monoHead = mono.isEmpty ? '' : mono.substring(0, 1);
    final monoTail = mono.length > 1 ? mono.substring(1) : '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _tileColor,
            borderRadius: AppShape.logoTile,
          ),
          child: Center(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: monoHead,
                  style: TextStyle(color: _tilePrefixColor),
                ),
                TextSpan(
                  text: monoTail,
                  style: TextStyle(color: _tileSuffixColor),
                ),
              ]),
              style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                height: 1,
              ),
            ),
          ),
        ),
        if (showLettering) ...[
          SizedBox(width: size * 0.25),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(children: [
                  // O prefixo pesa menos: a cor já marca a divisão, e o peso
                  // menor evita que o nome vire dois blocos concorrentes.
                  TextSpan(
                    text: id.wordmarkPrefix,
                    style: TextStyle(
                      color: _prefixColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: id.wordmarkSuffix,
                    style: TextStyle(
                      color: _suffixColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ]),
                style: TextStyle(
                  fontSize: size * 0.46,
                  letterSpacing: -0.2,
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
