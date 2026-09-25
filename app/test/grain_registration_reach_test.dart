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
    AppData.currentVersion = null;
  });

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.theme, home: const PricesScreen()));
    await tester.pumpAndSettle();
  }

  /// O "+" do cabeçalho vale para as QUATRO abas. Ele é um só — o cabeçalho é
  /// compartilhado —, e o que mudou foi ele deixar de sumir nas três em que o
  /// admin passa o tempo.
  testWidgets('o cadastro de grão é alcançável de qualquer aba', (tester) async {
    await abrir(tester);

    for (final aba in ['Lançamento', 'Valores', 'Histórico', 'Classes']) {
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
}
