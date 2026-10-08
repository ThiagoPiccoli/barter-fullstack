import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/back_office_main_screen.dart';
import 'package:agrobarter_app/screens/team_analysis_screen.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// A ANÁLISE DO GERENTE: os consultores do time lado a lado, e cada um aberto.
///
/// Os números são os de `dashboard_stats` (testados lá); o que estes casos
/// seguram é a tela — quem ganha a aba, e que a comparação e a abertura
/// funcionam com o que o servidor manda.
void main() {
  UserModel staff(UserRole role, List<String> capabilities) => UserModel(
        id: '7',
        name: 'Beatriz Nogueira',
        email: 'beatriz@agrobarter.com.br',
        role: role,
        phone: '',
        branch: 'Matriz',
        avatarInitials: 'BN',
        createdAt: DateTime(2024, 1, 1),
        capabilities: capabilities.toSet(),
      );

  final gerente = staff(UserRole.manager, [
    Capability.bartersReadTeam,
    Capability.bartersOpinion,
    Capability.pricesRead,
  ]);

  BarterModel barter(
    String code,
    String status, {
    required int consultantId,
    required String consultant,
    required double sacks,
    required double area,
  }) =>
      BarterModel.fromJson({
        'code': code,
        'consultantId': consultantId,
        'consultantName': consultant,
        'consultantBranch': 'Filial 02',
        'producerId': 1,
        'producerName': 'Antônio Carvalho',
        'status': status,
        'managerId': 7,
        'managerName': 'Beatriz Nogueira',
        'plantedAreaHa': area,
        'sacksPerHa': sacks / area,
        'createdAt': DateTime(2026, 3, 1).toUtc().toIso8601String(),
        'consultantSentAt': DateTime(2026, 3, 2).toUtc().toIso8601String(),
        'managerReviewedAt': DateTime(2026, 3, 4).toUtc().toIso8601String(),
        'items': [
          {
            'kind': 'grain',
            'productId': 1,
            'productName': 'Soja',
            'unit': 'saca 60kg',
            'quantity': sacks,
            'unitValue': 150.0,
          },
        ],
      });

  Future<void> abrir(WidgetTester tester, Widget tela) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.theme, home: tela));
    await tester.pumpAndSettle();
  }

  setUp(() {
    AppData.currentUser = gerente;
    AppData.barters = [
      barter('PRM-2026-001', 'approved', consultantId: 2, consultant: 'João Silva', sacks: 1200, area: 100),
      barter('PRM-2026-002', 'pending', consultantId: 2, consultant: 'João Silva', sacks: 500, area: 50),
      barter('PRM-2026-003', 'approved', consultantId: 3, consultant: 'Ana Souza', sacks: 900, area: 300),
    ];
  });

  tearDown(() {
    AppData.barters = [];
    AppData.currentUser = null;
  });

  testWidgets('o gerente, que tem time, ganha a aba', (tester) async {
    await abrir(tester, BackOfficeMainScreen(user: gerente));
    expect(find.text('Análise'), findsWidgets);
  });

  testWidgets('quem não tem time não ganha a aba', (tester) async {
    final faturista = staff(UserRole.biller, [
      Capability.bartersInvoice,
      Capability.bartersReadInvoicing,
      Capability.pricesRead,
    ]);
    AppData.currentUser = faturista;
    await abrir(tester, BackOfficeMainScreen(user: faturista));
    expect(find.text('Análise'), findsNothing);
  });

  testWidgets('os consultores se comparam pelo número escolhido, e cada um abre', (tester) async {
    await abrir(tester, TeamAnalysisTab(user: gerente));

    // Por sacas (a ordem inicial): o João fechou 1.200, a Ana 900.
    expect(
      tester.getTopLeft(find.text('João Silva')).dy,
      lessThan(tester.getTopLeft(find.text('Ana Souza')).dy),
    );
    // O investimento de cada um: 12 sc/ha no João, 3 na Ana.
    expect(find.text('12,00 sc/ha'), findsOneWidget);
    expect(find.text('3,00 sc/ha'), findsOneWidget);

    // Por área, a Ana passa à frente (300 ha contra 100).
    await tester.tap(find.text('Área').first);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Ana Souza')).dy,
      lessThan(tester.getTopLeft(find.text('João Silva')).dy),
    );

    await tester.tap(find.text('João Silva'));
    await tester.pumpAndSettle();
    expect(find.byType(ConsultantAnalysisScreen), findsOneWidget);
    expect(find.text('Tempo nas Etapas'), findsOneWidget);
    // O parecer do João levou 2 dias (do envio, dia 2, ao parecer, dia 4).
    expect(find.text('Parecer (gerente)'), findsOneWidget);
    expect(find.text('2 dias'), findsWidgets);
  });
}
