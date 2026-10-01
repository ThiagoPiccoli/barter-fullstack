import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/edit_forms.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// O cadastro do GERENTE: uma unidade só por gerente. (O time dele aparece no
/// perfil — ver `staff_profile_test.dart`.)
///
/// A unicidade também vive no servidor (ver `ensureUnitHasNoOtherManager`), mas
/// quem descobre primeiro é quem está escolhendo a unidade — e é por isso que a
/// lista marca a ocupada e o campo acusa antes do envio.
void main() {
  UserModel pessoa(String id, String nome, UserRole papel, String unitId,
          {String managerId = '', String unidade = ''}) =>
      UserModel(
        id: id,
        name: nome,
        email: '$id@agrobarter.com.br',
        role: papel,
        phone: '',
        branch: unidade,
        unitId: unitId,
        managerId: managerId,
        avatarInitials: nome.substring(0, 2).toUpperCase(),
        createdAt: DateTime(2024, 1, 1),
        mustChangePassword: false,
      );

  UnitModel unidade(String id, String nome) =>
      UnitModel(id: id, name: nome, city: 'Maringá/PR', createdAt: DateTime(2024, 1, 1));

  final beatriz = pessoa('7', 'Beatriz Nogueira', UserRole.manager, '1');
  final gustavo = pessoa('10', 'Gustavo Ramires', UserRole.manager, '6');

  setUp(() {
    AppData.units = [unidade('1', 'Matriz'), unidade('2', 'Filial 02'), unidade('6', 'Filial 34')];
    AppData.managers = [beatriz, gustavo];
    AppData.consultants = [
      pessoa('2', 'João Silva', UserRole.consultant, '2', managerId: '7', unidade: 'Filial 02'),
      pessoa('3', 'Ana Paula Ferreira', UserRole.consultant, '3', managerId: '7', unidade: 'Filial 04'),
      pessoa('4', 'Roberto Souza', UserRole.consultant, '6', managerId: '10', unidade: 'Filial 34'),
    ];
  });

  tearDown(() {
    AppData.units = [];
    AppData.managers = [];
    AppData.consultants = [];
  });

  Future<void> abrir(WidgetTester tester, UserModel? gerente) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: EditStaffScreen(user: gerente, role: UserRole.manager),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> escolherUnidade(WidgetTester tester, String nome) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(nome, findRichText: true).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a lista de unidades diz qual já tem gerente — menos a dele mesmo',
      (tester) async {
    await abrir(tester, beatriz);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(find.textContaining('gerente: Gustavo Ramires', findRichText: true), findsOneWidget);
    expect(find.textContaining('gerente: Beatriz Nogueira', findRichText: true), findsNothing);
  });

  testWidgets('escolher a unidade de outro gerente acusa na hora, e salvar para aí',
      (tester) async {
    await abrir(tester, beatriz);
    await escolherUnidade(tester, 'Filial 34');

    final erro =
        find.text('Esta unidade já tem gerente: Gustavo Ramires. Cada unidade tem um gerente só');
    expect(erro, findsOneWidget);

    // A recusa é local: o formulário não chega a chamar a API, que é o que
    // faz este teste rodar sem servidor.
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();
    expect(erro, findsOneWidget);
  });

  testWidgets('unidade livre não acusa nada', (tester) async {
    await abrir(tester, beatriz);
    await escolherUnidade(tester, 'Filial 02');

    expect(find.textContaining('já tem gerente'), findsNothing);
  });
}
