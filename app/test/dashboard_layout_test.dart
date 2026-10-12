import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/admin_main_screen.dart';
import 'package:agrobarter_app/screens/back_office_main_screen.dart';
import 'package:agrobarter_app/screens/consultant_main_screen.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// OS PAINÉIS CABEM — no telefone e no monitor, para todo papel.
///
/// O topo de cada painel virou uma grade de cartões com listas dentro (os
/// maiores insumos, as safras, as fases), e cartão lado a lado com conteúdo de
/// altura diferente é onde o layout quebra: um texto que não cabe, uma linha
/// que estoura. Os números estão testados em `dashboard_stats_test`; aqui o que
/// se segura é que cada painel se desenha inteiro, sem erro de layout, nas duas
/// larguras.
///
/// COM A FONTE DE VERDADE. A fonte padrão dos testes desenha toda letra como um
/// quadrado de 1em — o dobro da largura média da Roboto —, e com ela qualquer
/// linha de texto do app "estoura" a 390px. Medir largura com ela é medir
/// outra tela; por isso o teste carrega a Roboto do SDK (e a fonte da marca).
Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    final fonts = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    await _loadFont('Roboto', [
      for (final w in ['Regular', 'Medium', 'Bold', 'Black']) '$fonts/Roboto-$w.ttf',
    ]);
    await _loadFont('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
    await _loadFont('BricolageGrotesque', ['assets/fonts/BricolageGrotesque-Bold.ttf']);
  });

  UserModel user(UserRole role, List<String> capabilities) => UserModel(
        id: '7',
        name: 'Carlos Mendes',
        email: 'carlos@agrobarter.com.br',
        role: role,
        phone: '',
        branch: 'Matriz',
        avatarInitials: 'CM',
        createdAt: DateTime(2024, 1, 1),
        capabilities: capabilities.toSet(),
      );

  var seq = 0;
  BarterModel barter(String status, {String season = 'Soja 26/27', String producer = 'Antônio Carvalho'}) {
    seq++;
    return BarterModel.fromJson({
      'code': 'PRM-2026-${seq.toString().padLeft(3, '0')}',
      'cprNumber': 'CPR-2026-${seq.toString().padLeft(3, '0')}',
      'consultantId': seq.isEven ? 2 : 3,
      'consultantName': seq.isEven ? 'João Silva' : 'Ana Souza com um nome bem comprido',
      'consultantBranch': seq.isEven ? 'Filial 02' : 'Filial 34 – Granja Santa Terezinha',
      'producerId': seq % 3,
      'producerName': producer,
      'status': status,
      'seasonId': season.hashCode.toString(),
      'seasonName': season,
      'managerId': 7,
      'managerName': 'Beatriz Nogueira',
      'plantedAreaHa': 120.0 + seq,
      'sacksPerHa': 2.1,
      'insured': true,
      'insuranceCity': 'Maringá/PR',
      if (status.startsWith('cpr') || status == 'invoiced' || status == 'approved')
        'insurancePolicyNumber': 'AP-$seq',
      'createdAt': DateTime(2026, 9, 1).toUtc().toIso8601String(),
      'consultantSentAt': DateTime(2026, 9, 2).toUtc().toIso8601String(),
      'managerReviewedAt': DateTime(2026, 9, 4).toUtc().toIso8601String(),
      'reviewedAt': DateTime(2026, 9, 8).toUtc().toIso8601String(),
      'reviewedBy': 'Comitê',
      'insuredAt': DateTime(2026, 9, 10).toUtc().toIso8601String(),
      'invoicedAt': DateTime(2026, 9, 12).toUtc().toIso8601String(),
      'items': [
        {
          'kind': 'grain',
          'productId': 1,
          'productName': season.startsWith('Milho') ? 'Milho' : 'Soja',
          'unit': 'saca 60kg',
          'quantity': 250.0 + seq,
          'unitValue': 148.5,
        },
        {
          'kind': 'input',
          'productId': 5,
          'productName': 'Fertilizante NPK 04-14-08 de nome comprido',
          'unit': 'saco 50kg',
          'quantity': 48.0,
          'unitValue': 115.0,
        },
      ],
    });
  }

  List<BarterModel> operation() => [
        barter('sentToManager'),
        barter('pending', season: 'Milho 2027'),
        barter('awaitingPolicy', producer: 'Fazenda Três Irmãos Agropecuária Ltda'),
        barter('approved'),
        barter('approvedWithConditions', season: 'Milho 2027'),
        barter('invoiced'),
        barter('cprIssued', season: 'Milho 2027'),
        barter('cprSigned'),
        barter('cprRegistered'),
        barter('denied'),
        barter('draft'),
      ];

  tearDown(() {
    AppData.barters = [];
    AppData.currentUser = null;
  });

  final screens = <String, Widget Function()>{
    'admin': () => AdminMainScreen(admin: AppData.currentUser!),
    'consultor': () => ConsultantMainScreen(consultant: AppData.currentUser!),
    'gerente': () => BackOfficeMainScreen(user: AppData.currentUser!),
    'comitê': () => BackOfficeMainScreen(user: AppData.currentUser!),
    'seguradora': () => BackOfficeMainScreen(user: AppData.currentUser!),
    'faturista': () => BackOfficeMainScreen(user: AppData.currentUser!),
    'emissor': () => BackOfficeMainScreen(user: AppData.currentUser!),
  };

  final users = <String, UserModel Function()>{
    'admin': () => user(UserRole.admin, [
          Capability.bartersReview,
          Capability.bartersReadAll,
          Capability.pricesRead,
        ]),
    'consultor': () => user(UserRole.consultant, [Capability.bartersRegister]),
    'gerente': () => user(UserRole.manager, [
          Capability.bartersReadTeam,
          Capability.bartersOpinion,
          Capability.pricesRead,
        ]),
    'comitê': () => user(UserRole.committee, [
          Capability.bartersReview,
          Capability.bartersReadAll,
          Capability.pricesRead,
        ]),
    'seguradora': () => user(UserRole.insurer, [
          Capability.bartersInsure,
          Capability.bartersReadInsurance,
          Capability.pricesRead,
        ]),
    'faturista': () => user(UserRole.biller, [
          Capability.bartersInvoice,
          Capability.bartersReadInvoicing,
          Capability.pricesRead,
        ]),
    'emissor': () => user(UserRole.emitter, [
          Capability.bartersCprIssue,
          Capability.bartersReadIssuance,
          Capability.bartersCprRead,
          Capability.pricesRead,
        ]),
  };

  for (final role in screens.keys) {
    for (final size in const [Size(390, 2400), Size(1400, 2400)]) {
      testWidgets('o painel do $role se desenha inteiro em ${size.width.toInt()}px', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        AppData.currentUser = users[role]!();
        AppData.barters = operation();

        await tester.pumpWidget(MaterialApp(theme: AppTheme.theme, home: screens[role]!()));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  }
}
