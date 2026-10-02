import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/barter_program_screen.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// O LANÇAMENTO DO BARTER, do lado do admin — uma safra por cultura.
///
/// O que estes testes guardam é a forma da tela: cada cultura aberta é uma
/// ficha que se escolhe, a escolhida mostra a versão vigente DELA (e só dela),
/// a safra sem versão convida a publicar, e a safra encerrada pode ser reaberta.
void main() {
  BarterVersionModel versao({
    required String id,
    required String code,
    required String seasonId,
    required String seasonName,
    required String grain,
    required double price,
    InsurancePolicy insurance = InsurancePolicy.none,
  }) => BarterVersionModel(
    id: id,
    code: code,
    slug: code.replaceAll('/', ''),
    number: 2,
    seasonId: seasonId,
    seasonCode: code.split('.').first,
    seasonName: seasonName,
    grainId: '1',
    grainName: grain,
    grainUnit: 'saca 60kg',
    grainPrice: price,
    estimatedYield: 60,
    insurancePolicy: insurance,
    status: 'active',
    isOpen: true,
    startsAt: DateTime(2026, 1, 8),
    prices: const [],
  );

  final soja = versao(
    id: '2',
    code: 'SOJA26/27.02',
    seasonId: '3',
    seasonName: 'Soja 26/27',
    grain: 'Soja',
    price: 148.5,
    insurance: InsurancePolicy.optional,
  );

  SeasonModel safra({
    required String id,
    required String code,
    required String name,
    required String status,
    List<BarterVersionModel> versions = const [],
  }) => SeasonModel(
    id: id,
    code: code,
    slug: code.replaceAll('/', ''),
    name: name,
    grainName: name.split(' ').first,
    startYear: 2026,
    endYear: 2027,
    status: status,
    insurancePolicy: InsurancePolicy.required,
    openedAt: DateTime(2026, 1, 5),
    versions: versions,
  );

  setUp(() {
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
      mustChangePassword: false,
      capabilities: const {Capability.pricesRead},
    );
    AppData.seasons = [
      safra(id: '3', code: 'SOJA26/27', name: 'Soja 26/27', status: 'open', versions: [soja]),
      safra(id: '4', code: 'MILHO2027', name: 'Milho 2027', status: 'open'),
      safra(id: '1', code: 'TRIGO25/26', name: 'Trigo 25/26', status: 'closed'),
    ];
    AppData.currentVersions = [soja];
  });

  tearDown(() {
    AppData.currentUser = null;
    AppData.seasons = [];
    AppData.currentVersions = [];
  });

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: Scaffold(body: BarterProgramTab(onChanged: () {})),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('cada cultura aberta é uma ficha, e a primeira abre na versão dela', (tester) async {
    await abrir(tester);

    expect(find.widgetWithText(ChoiceChip, 'Soja 26/27'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Milho 2027'), findsOneWidget);
    // A versão vigente da soja, com o seguro DELA e o padrão da safra.
    // No cartão da vigente e no histórico da safra.
    expect(find.text('SOJA26/27.02'), findsNWidgets(2));
    expect(find.text('Encerrar versão'), findsOneWidget);
    expect(find.text('Nesta versão (SOJA26/27.02)'), findsOneWidget);
    expect(find.textContaining('Encerrar safra Soja 26/27'), findsOneWidget);
  });

  testWidgets('a safra sem versão convida a publicar a primeira', (tester) async {
    await abrir(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Milho 2027'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Milho 2027: nenhum'), findsOneWidget);
    expect(find.text('Publicar versão'), findsOneWidget);
    // E a versão da soja não aparece emprestada na tela do milho.
    expect(find.text('SOJA26/27.02'), findsNothing);
  });

  testWidgets('a safra encerrada aparece com a opção de reabrir', (tester) async {
    await abrir(tester);

    expect(find.text('Trigo 25/26'), findsOneWidget);
    expect(find.text('Reabrir'), findsOneWidget);
  });
}
