import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/invoicing_screen.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// O COMPROVANTE NA MESA DO FATURISTA.
///
/// O PDF da permuta só se tirava do detalhe, e o faturista, que fatura de
/// dentro da tela de faturamento, tinha de sair dela para buscá-lo. O botão é
/// o mesmo `BarterPdf` do detalhe; o que este arquivo prende é que ele está
/// lá e que gera o documento de uma permuta aprovada.
void main() {
  const printing = MethodChannel('net.nfet.printing');

  BarterModel aprovada() => BarterModel.fromJson({
        'code': 'PRM-2026-001',
        'versionCode': 'S2026.02',
        'consultantId': 2,
        'consultantName': 'João Silva',
        'consultantBranch': 'Filial 02',
        'producerId': 1,
        'producerName': 'Antônio Carvalho',
        'unitId': 2,
        'unitName': 'Filial 02 – Gran. Santa T.',
        'status': 'approved',
        'createdAt': '2026-01-10T00:00:00.000Z',
        'items': [
          {
            'kind': 'grain',
            'productId': 1,
            'productName': 'Soja',
            'unit': 'saca 60kg',
            'quantity': 251.4142,
            'unitValue': 148.5,
          },
          {
            'kind': 'input',
            'productId': 5,
            'productName': 'NPK',
            'unit': 'saco 50kg',
            'quantity': 300.0,
            'unitValue': 115.0,
          },
        ],
      });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(printing, null);
  });

  testWidgets('o faturista gera o PDF da permuta aprovada', (tester) async {
    // A folha de compartilhamento é nativa: o teste fica no lugar dela e
    // guarda o que chegou.
    Map<Object?, Object?>? compartilhado;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(printing, (call) async {
      if (call.method == 'sharePdf') {
        compartilhado = call.arguments as Map<Object?, Object?>;
        return 1;
      }
      return null;
    });

    final barter = aprovada();
    expect(barter.awaitsInvoice, isTrue);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: InvoicingScreen(barter: barter, onInvoiced: (_) {}),
    ));

    final botao = find.byTooltip('Comprovante da permuta');
    expect(botao, findsOneWidget);

    // A montagem do PDF é trabalho de verdade, fora do relógio falso do teste.
    await tester.runAsync(() async {
      await tester.tap(botao);
      for (var i = 0; i < 100 && compartilhado == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    expect(compartilhado, isNotNull, reason: 'o PDF não chegou à folha de compartilhamento');
    expect(compartilhado!['name'], 'permuta-prm-2026-001.pdf');
    final bytes = compartilhado!['doc'] as Uint8List;
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(find.textContaining('Não foi possível gerar o PDF'), findsNothing);
  });
}
