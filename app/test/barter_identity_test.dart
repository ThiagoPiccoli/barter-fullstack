import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/theme/app_theme.dart';
import 'package:agrobarter_app/widgets/common_widgets.dart';

/// A IDENTIFICAÇÃO DA PERMUTA — o bloco que substitui o código solto em listas,
/// cartões e diálogos.
///
/// O número do investimento por hectare NÃO é conferido aqui como conta: ele vem
/// pronto do servidor (ver investment_per_ha_test.dart). O que este arquivo
/// prende é o que o bloco mostra, e o que ele esconde de quem não recebe.
void main() {
  BarterModel barter({Object? areaHa = 120, Object? sacksPerHa = 2.0951183}) =>
      BarterModel.fromJson({
        'code': 'PRM-2026-001',
        'versionCode': 'S2026.02',
        'consultantId': 2,
        'consultantName': 'João Silva',
        'consultantBranch': 'Filial 02',
        'producerId': 1,
        'producerName': 'Antônio Carvalho',
        'unitId': 2,
        'unitName': 'Filial 02',
        'status': 'approved',
        'managerId': 7,
        'createdAt': '2026-01-10T00:00:00.000Z',
        'plantedAreaHa': ?areaHa,
        'sacksPerHa': ?sacksPerHa,
        'items': [],
      });

  Future<void> show(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: Scaffold(body: child),
    ));
    await tester.pump();
  }

  testWidgets('mostra código, produtor, consultor, área e investimento', (tester) async {
    await show(tester, BarterIdentity(barter: barter()));

    expect(find.text('PRM-2026-001'), findsOneWidget);
    expect(find.text('Antônio Carvalho'), findsOneWidget);
    expect(find.text('João Silva'), findsOneWidget);
    expect(find.text('120 ha'), findsOneWidget);
    expect(find.text('2,10 sc/ha'), findsOneWidget);
  });

  /// Quem não pode comparar (consultor, gerente) não recebe os dois campos — e
  /// o bloco continua dizendo de quem é a permuta.
  testWidgets('sem área nem investimento, a linha de baixo some', (tester) async {
    await show(tester, BarterIdentity(barter: barter(areaHa: null, sacksPerHa: null)));

    expect(find.text('Antônio Carvalho'), findsOneWidget);
    expect(find.text('João Silva'), findsOneWidget);
    expect(find.textContaining(' ha'), findsNothing);
    expect(find.text('Investimento '), findsNothing);
  });

  /// Permuta anterior ao campo de área: nem "0 ha", nem "0 sc/ha".
  testWidgets('área zero não vira número', (tester) async {
    await show(tester, BarterIdentity(barter: barter(areaHa: 0, sacksPerHa: null)));

    expect(find.textContaining('ha'), findsNothing);
  });

  /// O diálogo mede a largura pelo conteúdo (IntrinsicWidth); é o lugar onde um
  /// filho flexível quebraria o layout.
  testWidgets('cabe num diálogo', (tester) async {
    await show(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [BarterIdentity(barter: barter())],
              ),
            ),
          ),
          child: const Text('abrir'),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('2,10 sc/ha'), findsOneWidget);
  });

  testWidgets('o histórico dos perfis leva a identificação', (tester) async {
    await show(tester, BarterLogItem(barter: barter(), subtitle: '2 insumo(s)'));

    expect(tester.takeException(), isNull);
    expect(find.text('Antônio Carvalho'), findsOneWidget);
    expect(find.text('2,10 sc/ha'), findsOneWidget);
  });
}
