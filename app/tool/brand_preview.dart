// Gera as PNGs de conferência visual da marca ativa em `docs/brand/`.
//
//     flutter test tool/brand_preview.dart --update-goldens
//
// Fica fora de `test/` de propósito: não roda na suíte padrão, porque a
// renderização de fonte varia entre máquinas e viraria um teste instável.
// Rode depois de reskinnar para ver a marca nova.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/branding/active_brand.dart';
import 'package:agrobarter_app/branding/brand_wordmark.dart';
import 'package:agrobarter_app/theme/app_theme.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/widgets/common_widgets.dart';

const _fontDir = '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final bytes = await File('$_fontDir/$f').readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Future<void> _shoot(WidgetTester tester, Widget child, Size size, String name) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  // A marca não fixa família (no aparelho o padrão é Roboto), e os estilos dos
  // widgets deixam `fontFamily` nulo. No ambiente de teste isso cai no glifo de
  // caixa, então a família precisa ser injetada em todos os pontos de herança.
  final base = AppTheme.theme;
  final theme = base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Roboto'),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto'),
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      // Sem um Material ancestral o estilo padrão é o de diagnóstico, que
      // sublinha tudo em amarelo — ruído que não existe no app real.
      home: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle.merge(
          style: const TextStyle(
            fontFamily: 'Roboto',
            decoration: TextDecoration.none,
          ),
          child: child,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../docs/brand/$name.png'));
}

void main() {
  setUpAll(() async {
    await _loadFont('Roboto', [
      'Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf',
    ]);
    await _loadFont('MaterialIcons', ['MaterialIcons-Regular.otf']);
  });

  testWidgets('logotipo nos dois fundos', (tester) async {
    await _shoot(
      tester,
      ColoredBox(
        color: AppColors.background,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28),
              width: double.infinity,
              decoration: BoxDecoration(gradient: AppColors.primaryGradient),
              child: const Center(child: BrandWordmark(size: 56)),
            ),
            const SizedBox(height: 28),
            const Center(child: BrandWordmark(size: 56, tone: BrandTone.onSurface)),
            const SizedBox(height: 28),
            Container(
              height: 56,
              color: AppColors.primary,
              child: const Center(
                  child: BrandWordmark(size: 32, showTagline: false)),
            ),
          ],
        ),
      ),
      const Size(900, 700),
      'wordmark',
    );
  });

  testWidgets('paleta da marca', (tester) async {
    Widget swatch(String name, Color c, {bool dark = false}) => Container(
          width: 150,
          height: 74,
          padding: const EdgeInsets.all(8),
          color: c,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              '$name\n#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
              style: TextStyle(
                fontSize: 10,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: dark ? AppColors.textDark : AppColors.onPrimary,
              ),
            ),
          ),
        );

    final p = brand.palette;
    await _shoot(
      tester,
      ColoredBox(
        color: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            swatch('primary', p.primary),
            swatch('primaryMedium', p.primaryMedium),
            swatch('primaryLight', p.primaryLight),
            swatch('primaryAccent', p.primaryAccent, dark: true),
            swatch('accentOnLight', p.accentOnLight),
            swatch('primarySurface', p.primarySurface, dark: true),
            swatch('background', p.background, dark: true),
            swatch('textDark', p.textDark),
            swatch('textMedium', p.textMedium),
            swatch('textLight', p.textLight),
            swatch('grain', p.grain),
            swatch('grainBg', p.grainBg, dark: true),
            swatch('input', p.input),
            swatch('inputBg', p.inputBg, dark: true),
            swatch('approved', p.approved),
            swatch('pending', p.pending),
            swatch('denied', p.denied),
            swatch('divider', p.divider, dark: true),
            for (var i = 0; i < p.dataSeries.length; i++)
              swatch('series[$i]', p.dataSeries[i]),
          ]),
        ),
      ),
      const Size(2400, 1180),
      'palette',
    );
  });

  testWidgets('componentes no tema', (tester) async {
    await _shoot(
      tester,
      Scaffold(
        appBar: AppBar(title: const BrandWordmark(size: 30, showTagline: false)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const DashboardHeader(
            greetingName: 'Carlos',
            subtitle: 'Central de Permutas • 13 ago 2026',
            icon: Icons.admin_panel_settings,
          ),
          const SizedBox(height: 16),
          const BarterBalanceBar(
            inputCost: 48200,
            referenceValue: 128.5,
            referenceGrainName: 'Soja',
            inputCount: 4,
          ),
          const SizedBox(height: 16),
          Row(children: [
            const StatusBadge(status: BarterStatus.approved),
            const SizedBox(width: 8),
            const StatusBadge(status: BarterStatus.pending),
            const SizedBox(width: 8),
            const StatusBadge(status: BarterStatus.denied),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: ElevatedButton(onPressed: () {}, child: const Text('Enviar Permuta'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: () {}, child: const Text('Cancelar'))),
          ]),
          const SizedBox(height: 16),
          const TextField(decoration: InputDecoration(labelText: 'E-mail', hintText: 'admin@agrobarter.com.br')),
        ]),
      ),
      const Size(820, 1180),
      'components',
    );
  });
}
