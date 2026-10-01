import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrobarter_app/branding/brand_mark.dart';
import 'package:agrobarter_app/services/nav_rail_preference.dart';
import 'package:agrobarter_app/widgets/adaptive_layout.dart';

void main() {
  late Map<String, String> cofre;

  setUp(() {
    cofre = {};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(cofre);
    NavRailPreference.reset();
  });

  Future<void> pumpScaffold(WidgetTester tester, {double width = 1400}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: AdaptiveNavScaffold(
        selectedIndex: 0,
        onSelect: (_) {},
        body: Scaffold(appBar: AppBar(title: const Text('Dashboard')), body: const SizedBox()),
        destinations: const [
          AdaptiveDestination(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Início'),
          AdaptiveDestination(icon: Icons.swap_horiz, activeIcon: Icons.swap_horiz, label: 'Permutas'),
        ],
      ),
    ));
  }

  bool labelVisible(WidgetTester tester, String label) =>
      find.text(label).hitTestable().evaluate().isNotEmpty;

  testWidgets('recolhe para só os ícones, com o nome em tooltip, e grava', (tester) async {
    await pumpScaffold(tester);
    expect(labelVisible(tester, 'Permutas'), isTrue);
    expect(find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Permutas'), findsNothing);

    await tester.tap(find.byTooltip('Recolher menu'));
    await tester.pumpAndSettle();

    expect(labelVisible(tester, 'Permutas'), isFalse);
    expect(find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Permutas'), findsWidgets);
    expect(find.byTooltip('Expandir menu'), findsOneWidget);
    expect(cofre['barter.nav_rail_collapsed'], 'true');

    await tester.tap(find.byTooltip('Expandir menu'));
    await tester.pumpAndSettle();

    expect(labelVisible(tester, 'Permutas'), isTrue);
    expect(cofre['barter.nav_rail_collapsed'], 'false');
  });

  testWidgets('abre já recolhida quando foi assim que ficou', (tester) async {
    cofre['barter.nav_rail_collapsed'] = 'true';
    await NavRailPreference.load();
    await pumpScaffold(tester);

    expect(labelVisible(tester, 'Permutas'), isFalse);
    expect(find.byTooltip('Expandir menu'), findsOneWidget);
  });

  testWidgets('entre os cortes, recolher também tira o nome de baixo do ícone', (tester) async {
    await pumpScaffold(tester, width: 1000);
    expect(labelVisible(tester, 'Permutas'), isTrue);

    await tester.tap(find.byTooltip('Recolher menu'));
    await tester.pumpAndSettle();

    expect(labelVisible(tester, 'Permutas'), isFalse);
    expect(find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Permutas'), findsWidgets);
  });

  testWidgets('a seta mora na barra de título, colada na coluna', (tester) async {
    await pumpScaffold(tester);
    final seta = tester.getRect(find.byTooltip('Recolher menu'));
    final barra = tester.getRect(find.byType(AppBar));

    expect(barra.contains(seta.center), isTrue);
    expect(seta.left - barra.left, lessThan(16));
  });

  testWidgets('fechada, a marca fica no eixo dos ícones', (tester) async {
    await pumpScaffold(tester);
    await tester.tap(find.byTooltip('Recolher menu'));
    await tester.pumpAndSettle();

    final marca = tester.getCenter(find.byType(BrandMark));
    final icone = tester.getCenter(find.byIcon(Icons.home));
    expect(marca.dx, moreOrLessEquals(icone.dx, epsilon: 0.5));
  });
}
