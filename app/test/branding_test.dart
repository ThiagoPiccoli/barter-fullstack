import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/branding/active_brand.dart';
import 'package:agrobarter_app/branding/brand_wordmark.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// Percorre a árvore de spans e devolve a cor aplicada a [text].
Color? _colorOf(WidgetTester tester, String text) {
  Color? found;
  void walk(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text == text) found = span.style?.color;
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    walk(rich.text);
  }
  return found;
}

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  final id = brand.identity;

  group('BrandWordmark', () {
    testWidgets('quebra o nome em duas cores sobre a cor institucional',
        (tester) async {
      await _pump(tester, const BrandWordmark());

      final prefix = _colorOf(tester, id.wordmarkPrefix);
      final suffix = _colorOf(tester, id.wordmarkSuffix);

      expect(prefix, AppColors.primaryAccent);
      expect(suffix, AppColors.onPrimary);
      // A assinatura da marca é justamente as duas metades não coincidirem.
      expect(prefix, isNot(suffix));
    });

    testWidgets('troca para o acento escurecido sobre superfície clara',
        (tester) async {
      await _pump(tester, const BrandWordmark(tone: BrandTone.onSurface));

      final prefix = _colorOf(tester, id.wordmarkPrefix);
      final suffix = _colorOf(tester, id.wordmarkSuffix);

      // O acento vivo não tem contraste sobre branco; sobre claro o logotipo
      // cai para a variante escurecida sem perder a leitura de duas cores.
      expect(prefix, AppColors.accentOnLight);
      expect(suffix, AppColors.primary);
      expect(prefix, isNot(suffix));
    });

    testWidgets('mostra a assinatura da marca, e a esconde quando pedido',
        (tester) async {
      await _pump(tester, const BrandWordmark());
      expect(find.text(id.tagline), findsOneWidget);

      await _pump(tester, const BrandWordmark(showTagline: false));
      expect(find.text(id.tagline), findsNothing);
    });
  });

  group('tema', () {
    test('deriva as cores da marca ativa, sem valores próprios', () {
      final scheme = AppTheme.theme.colorScheme;
      expect(scheme.primary, brand.palette.primary);
      expect(scheme.secondary, brand.palette.primaryAccent);
      expect(AppTheme.theme.scaffoldBackgroundColor, brand.palette.background);
      expect(AppTheme.theme.appBarTheme.backgroundColor, brand.palette.primary);
    });

    test('a fachada AppColors só encaminha para a paleta da marca', () {
      expect(AppColors.primary, brand.palette.primary);
      expect(AppColors.grain, brand.palette.grain);
      expect(AppColors.input, brand.palette.input);
      expect(AppColors.onPrimarySubtle, brand.palette.onPrimarySubtle);
    });

    test('a série de gráficos é cíclica, então todo grão ganha cor', () {
      final series = brand.palette.dataSeries;
      expect(series, isNotEmpty);
      expect(AppColors.series(0), series.first);
      // Um grão além do fim da lista volta ao início em vez de estourar.
      expect(AppColors.series(series.length), series.first);
      expect(AppColors.series(series.length + 1), series[1]);
    });
  });
}
