import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/prices_screen.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// ONDE SE CADASTRA UM GRÃO — e por que isso virou teste.
///
/// O grão é o que o lançamento oferece como CULTURA, e a planilha do fornecedor
/// não o cria (ela traz insumos). Quem precisa dele é o admin com o formulário
/// de publicar aberto, descobrindo que o milho não está no catálogo — e o botão
/// que o cadastra vivia numa aba só, a do Histórico, que não é a aba em que ele
/// está. Um ato raro pode ficar discreto; não pode ficar escondido justamente de
/// quem o procura.
void main() {
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
      // O admin vê valores em R$ — é a lente que esta tela usa para desenhar a
      // tabela e as cotações.
      capabilities: const {Capability.pricesRead},
    );
  });

  tearDown(() {
    AppData.currentUser = null;
    AppData.seasons = [];
    AppData.currentVersions = [];
    AppData.grains = [];
    AppData.inputs = [];
  });

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.theme, home: const PricesScreen()));
    await tester.pumpAndSettle();
  }

  /// O "+" do cabeçalho vale para as CINCO abas. Ele é um só — o cabeçalho é
  /// compartilhado —, e o que mudou foi ele deixar de sumir nas três em que o
  /// admin passa o tempo.
  testWidgets('o cadastro de grão é alcançável de qualquer aba', (tester) async {
    await abrir(tester);

    for (final aba in ['Lançamento', 'Valores', 'Grãos', 'Histórico', 'Classes']) {
      await tester.tap(find.text(aba));
      await tester.pumpAndSettle();

      expect(
        find.byTooltip('Cadastrar item'),
        findsOneWidget,
        reason: 'o "+" precisa existir na aba $aba',
      );
    }
  });

  testWidgets('o menu do "+" oferece grão e insumo', (tester) async {
    await abrir(tester);

    await tester.tap(find.byTooltip('Cadastrar item'));
    await tester.pumpAndSettle();

    expect(find.text('Novo grão'), findsOneWidget);
    expect(find.text('Novo insumo'), findsOneWidget);
  });

  /// OS GRÃOS SAÍRAM DO HISTÓRICO para uma aba própria, onde mora o MODELO DA
  /// CPR de cada um. O que falta definir aparece marcado no cartão — é a
  /// pergunta desta aba.
  testWidgets('a aba de grãos mostra o modelo da CPR, e o histórico só os insumos', (tester) async {
    AppData.grains = [
      const ProductModel(
        id: '1',
        name: 'Soja',
        unit: 'saca 60kg',
        currentPrice: 148.5,
        type: ProductType.grain,
        priceHistory: [],
        cprModel: GrainCprModel(maxMoisture: 14, maxImpurities: 1, oilContent: 18),
      ),
      const ProductModel(
        id: '2',
        name: 'Milho',
        unit: 'saca 60kg',
        currentPrice: 62.3,
        type: ProductType.grain,
        priceHistory: [],
        cprModel: GrainCprModel(maxMoisture: 14, maxImpurities: 1),
      ),
    ];
    AppData.inputs = [
      const ProductModel(
        id: '5',
        name: 'Fertilizante NPK 04-14-08',
        unit: 'saco 50kg',
        currentPrice: 115,
        type: ProductType.input,
        priceHistory: [],
      ),
    ];
    await abrir(tester);

    await tester.tap(find.text('Grãos'));
    await tester.pumpAndSettle();
    expect(find.text('Saca de 60 kg · umidade 14% · impurezas 1% · óleo 18%'), findsOneWidget);
    expect(find.text('Saca de 60 kg · umidade 14% · impurezas 1% · óleo a definir'), findsOneWidget);
    expect(find.text('1 número a definir'), findsOneWidget);
    expect(find.text('Fertilizante NPK 04-14-08'), findsNothing);

    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();
    expect(find.text('Fertilizante NPK 04-14-08'), findsOneWidget);
    expect(find.text('Soja'), findsNothing);
  });
}
