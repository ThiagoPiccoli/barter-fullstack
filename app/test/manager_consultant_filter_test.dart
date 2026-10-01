import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/barters_screen.dart';
import 'package:agrobarter_app/services/dashboard_stats.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// O SELETOR DE CONSULTOR na aba de permutas do gerente.
///
/// Um gerente responde por vários consultores (`User.managerId`), e a mesa dele
/// junta as permutas de todos. O seletor recorta por quem registrou, com
/// "Todos" como volta para a mesa inteira.
void main() {
  UserModel staff(UserRole role, List<String> capabilities) => UserModel(
        id: '7',
        name: 'Beatriz Nogueira',
        email: 'gerente@agrobarter.com.br',
        role: role,
        phone: '',
        branch: 'Matriz',
        unitId: '1',
        avatarInitials: 'BN',
        createdAt: DateTime(2024, 1, 1),
        capabilities: capabilities.toSet(),
      );

  BarterModel barter(String code, String consultantId, String consultantName,
          {String status = 'sentToManager', int daysAgo = 1}) =>
      BarterModel.fromJson({
        'code': code,
        'consultantId': int.parse(consultantId),
        'consultantName': consultantName,
        'consultantBranch': 'Filial 02',
        'producerId': 1,
        'producerName': 'Produtor de $consultantName',
        'unitId': 2,
        'unitName': 'Filial 02 – Gran. Santa T.',
        'status': status,
        'managerId': 7,
        'managerName': 'Beatriz Nogueira',
        'createdAt': DateTime(2026, 9, 30).subtract(Duration(days: daysAgo)).toUtc().toIso8601String(),
        'items': [
          {
            'kind': 'grain',
            'productId': 1,
            'productName': 'Soja',
            'unit': 'saca 60kg',
            'quantity': 80.0,
            'unitValue': 148.5,
          },
        ],
      });

  group('consultantsOf', () {
    test('um por consultor, em ordem de nome', () {
      final list = consultantsOf([
        barter('PRM-1', '3', 'Ana Paula Ferreira'),
        barter('PRM-2', '2', 'João Silva'),
        barter('PRM-3', '3', 'Ana Paula Ferreira'),
      ]);
      expect(list.map((c) => c.id), ['3', '2']);
      expect(list.map((c) => c.name), ['Ana Paula Ferreira', 'João Silva']);
    });

    test('o nome que vale é o da permuta mais recente', () {
      final list = consultantsOf([
        barter('PRM-1', '2', 'João S.', daysAgo: 30),
        barter('PRM-2', '2', 'João Silva', daysAgo: 1),
      ]);
      expect(list.single.name, 'João Silva');
    });
  });

  group('a aba de permutas', () {
    setUp(() {
      AppData.barters = [
        barter('PRM-2026-001', '2', 'João Silva'),
        barter('PRM-2026-002', '2', 'João Silva', status: 'pending'),
        barter('PRM-2026-003', '3', 'Ana Paula Ferreira'),
      ];
    });

    tearDown(() {
      AppData.barters = [];
      AppData.currentUser = null;
    });

    Future<void> abrir(WidgetTester tester, Widget tela, {double width = 1400}) async {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.theme, home: tela));
      await tester.pumpAndSettle();
    }

    Future<void> escolher(WidgetTester tester, String opcao) async {
      await tester.tap(find.byKey(const ValueKey('consultant-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(opcao).last);
      await tester.pumpAndSettle();
    }

    final gerente = [Capability.bartersReadTeam, Capability.bartersOpinion];

    for (final width in [1400.0, 390.0]) {
      testWidgets('o gerente recorta por consultor e volta em "Todos" (${width.toInt()}px)',
          (tester) async {
        AppData.currentUser = staff(UserRole.manager, gerente);
        await abrir(
          tester,
          const BartersScreen(isAdmin: true, consultantId: null, opinionManagerId: '7'),
          width: width,
        );

        // Abre em "Todos": a aba Todas conta as três.
        expect(find.textContaining('Todas (3)'), findsOneWidget);

        await escolher(tester, 'João Silva');
        expect(find.textContaining('Todas (2)'), findsOneWidget);
        expect(find.textContaining('No gerente (1)'), findsOneWidget);
        expect(find.textContaining('No comitê (1)'), findsOneWidget);

        await escolher(tester, 'Ana Paula Ferreira');
        expect(find.textContaining('Todas (1)'), findsOneWidget);
        expect(find.textContaining('No comitê (0)'), findsOneWidget);

        await escolher(tester, 'Todos');
        expect(find.textContaining('Todas (3)'), findsOneWidget);
      });
    }

    testWidgets('o admin não ganha o seletor', (tester) async {
      AppData.currentUser = staff(UserRole.admin, [
        Capability.usersManage,
        Capability.bartersReadAll,
        Capability.bartersReadTeam,
        Capability.bartersOpinion,
      ]);
      await abrir(tester, const BartersScreen(isAdmin: true, consultantId: null));
      expect(find.byKey(const ValueKey('consultant-selector')), findsNothing);
    });
  });
}
