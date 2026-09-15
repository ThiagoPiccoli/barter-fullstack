import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/barter_detail_screen.dart';
import 'package:agrobarter_app/screens/barters_screen.dart';
import 'package:agrobarter_app/services/barter_pdf.dart';
import 'package:agrobarter_app/theme/app_theme.dart';
import 'package:agrobarter_app/widgets/common_widgets.dart';

/// O INVESTIMENTO POR HECTARE (sc/ha) NA TELA.
///
/// O número já vinha certo da API — o que faltava era ele APARECER, e é isso que
/// este arquivo prende. Um campo novo no JSON e uma linha nova num `Column` não
/// se cobrem sozinhos: as duas metades podem estar certas e a tela continuar sem
/// mostrar nada, que foi exatamente o que aconteceu.
void main() {
  Map<String, dynamic> barterJson({
    Object? areaHa = 120,
    Object? sacksPerHa = 2.0951183,
  }) =>
      {
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
        'managerId': 7,
        'managerName': 'Beatriz Nogueira',
        'createdAt': '2026-01-10T00:00:00.000Z',
        // O `?` é o "só se não for nulo": um campo AUSENTE é o que o servidor
        // manda a quem não pode compará-lo, e é diferente de um campo nulo (a
        // permuta sem área). Os dois casos são testados abaixo.
        'producerAreaHa': ?areaHa,
        'sacksPerHa': ?sacksPerHa,
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
      };

  Future<void> abrir(WidgetTester tester, BarterModel barter) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: BarterDetailScreen(barter: barter, isAdmin: true),
    ));
    await tester.pump();
  }

  tearDown(() {
    AppData.barters = [];
    AppData.currentUser = null;
  });

  testWidgets('o detalhe mostra o investimento por hectare com a área', (tester) async {
    await abrir(tester, BarterModel.fromJson(barterJson()));

    // Em DOIS lugares, e de propósito: no painel do topo (a terceira leitura do
    // negócio, ao lado do custo e das sacas) e na ficha de informações, junto da
    // área que o produz.
    //
    // 251,4142 sacas ÷ 120 ha = 2,0951… → duas casas, que é a precisão em que
    // esta régua é lida: a diferença entre 2,09 e 2,1 muda a comparação entre
    // duas permutas, e é para comparar que ela existe.
    expect(find.textContaining('2,10 sc/ha'), findsNWidgets(2));
    expect(find.text('Investimento'), findsNWidgets(2));
    expect(find.textContaining('120 ha'), findsNWidgets(2));
  });

  /// Ele SOME para quem não pode compará-lo — o servidor nem manda o campo.
  testWidgets('sem a capacidade, a linha não aparece', (tester) async {
    await abrir(
      tester,
      BarterModel.fromJson(barterJson(areaHa: null, sacksPerHa: null)),
    );

    expect(find.text('Investimento'), findsNothing);
  });

  /// Permuta anterior ao campo de área: `null` no lugar da divisão que não dá
  /// para fazer. A linha some em vez de mostrar "0 sc/ha", que seria uma
  /// afirmação — e falsa.
  testWidgets('sem área registrada, não inventa um número', (tester) async {
    await abrir(tester, BarterModel.fromJson(barterJson(areaHa: 0, sacksPerHa: null)));

    expect(find.text('Investimento'), findsNothing);
  });

  /// A LISTA é onde a régua serve para alguma coisa: no detalhe há uma permuta
  /// só na tela, e uma régua sem régua ao lado não compara nada. Este caso é o
  /// que faltava — o número existia no JSON e no detalhe, e a tela por onde se
  /// olha a operação inteira não o mostrava.
  testWidgets('a lista de permutas mostra o investimento de cada uma', (tester) async {
    AppData.currentUser = UserModel(
      id: '1',
      name: 'Carlos Mendes',
      email: 'admin@agrobarter.com.br',
      role: UserRole.admin,
      phone: '',
      branch: 'Matriz',
      unitId: '1',
      avatarInitials: 'CM',
      createdAt: DateTime(2024, 1, 1),
      capabilities: const {Capability.pricesRead},
    );
    AppData.barters = [
      BarterModel.fromJson(barterJson()),
      BarterModel.fromJson(barterJson(areaHa: 320, sacksPerHa: 0.5404412)
        ..['code'] = 'PRM-2026-008'),
    ];

    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: const BartersScreen(isAdmin: true, consultantId: null),
    ));
    await tester.pumpAndSettle();

    // As duas permutas, cada uma com a SUA régua — é a comparação lado a lado
    // que a métrica existe para permitir.
    expect(find.text('2,10 sc/ha'), findsOneWidget);
    expect(find.text('0,54 sc/ha'), findsOneWidget);
  });

  /// O cartão do PAINEL leva a mesma régua: é lá que se olha várias permutas de
  /// uma vez sem abrir nenhuma.
  testWidgets('o cartão do painel leva o investimento na linha de baixo', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: Scaffold(
        body: MiniBarterCard(barter: BarterModel.fromJson(barterJson()), isAdmin: true),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('2,10 sc/ha'), findsOneWidget);
  });

  /// E ele some do cartão de quem não o recebe — o consultor.
  testWidgets('o cartão do painel do consultor não mostra a régua', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: Scaffold(
        body: MiniBarterCard(
          barter: BarterModel.fromJson(barterJson(areaHa: null, sacksPerHa: null)),
          isAdmin: false,
        ),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('sc/ha'), findsNothing);
  });

  /// O COMPROVANTE também leva a régua.
  ///
  /// O texto do PDF sai comprimido (FlateDecode), então o teste INFLA os streams
  /// antes de procurar — ler os bytes crus acharia zero ocorrências de qualquer
  /// palavra, inclusive das que já estão lá, e o teste passaria a atestar nada.
  ///
  /// O texto sai PALAVRA A PALAVRA (cada `[(palavra)]TJ` é um operador), então a
  /// extração as junta com espaço: procurar "2,10 sc/ha" nos operadores crus
  /// não acharia nada, mesmo com as três palavras impressas uma ao lado da
  /// outra.
  String textoDoPdf(List<int> bytes) {
    final buffer = StringBuffer();
    final raw = String.fromCharCodes(bytes.map((b) => b & 0xFF));
    var at = 0;
    while (true) {
      final start = raw.indexOf('stream', at);
      if (start < 0) break;
      final end = raw.indexOf('endstream', start);
      if (end < 0) break;
      // Pula o "stream" e a quebra de linha que vem depois dele.
      var from = start + 'stream'.length;
      while (from < end && (raw.codeUnitAt(from) == 13 || raw.codeUnitAt(from) == 10)) {
        from++;
      }
      try {
        final conteudo = latin1.decode(
          ZLibDecoder().convert(bytes.sublist(from, end)),
          allowInvalid: true,
        );
        for (final palavra in RegExp(r'\[\((.*?)\)\]TJ').allMatches(conteudo)) {
          buffer.write('${palavra.group(1)} ');
        }
      } catch (_) {
        // Stream que não é texto (imagem, fonte): segue para o próximo.
      }
      at = end + 1;
    }
    return buffer.toString();
  }

  test('o comprovante em PDF traz o investimento por hectare', () async {
    final bytes = await BarterPdf.build(
      BarterModel.fromJson(barterJson()),
      showValues: true,
    );

    final texto = textoDoPdf(bytes);
    // A rede de segurança do próprio teste: se a extração falhar, ela acha
    // "INVESTIMENTO" em lugar nenhum — e passaria a atestar exatamente nada.
    expect(texto, contains('PRM-2026-001'));
    // Ele mora no QUADRO DO TOTAL, em destaque, e não mais como uma linha de
    // cadastro ao lado da área: é a régua que compara esta permuta com
    // qualquer outra, e o lugar dela é junto do número que ela mede.
    expect(texto, contains('INVESTIMENTO NA LAVOURA'));
    expect(texto, contains('2,10 sc/ha'));
    // Sem a área ao lado: ela já está impressa no bloco do produtor, e repetida
    // aqui competia com o número que este quadro existe para destacar.
    expect(texto, isNot(contains('2,10 sc/ha (120 ha)')));
  });

  /// E some do comprovante de quem não o recebe — o do consultor.
  test('o comprovante do consultor não traz a régua', () async {
    final bytes = await BarterPdf.build(
      BarterModel.fromJson(barterJson(areaHa: null, sacksPerHa: null)),
      showValues: false,
    );

    final texto = textoDoPdf(bytes);
    expect(texto, contains('PRM-2026-001'));
    expect(texto, isNot(contains('sc/ha')));
  });
}
