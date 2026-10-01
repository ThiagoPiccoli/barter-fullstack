import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/consultant_profile_screen.dart';
import 'package:agrobarter_app/screens/consultants_screen.dart';
import 'package:agrobarter_app/screens/staff_profile_screen.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// O PERFIL da retaguarda — gerente, comitê, faturista, emissor e admin — que a
/// aba de cadastros abre ao tocar no cartão, como já fazia com o consultor.
void main() {
  UserModel pessoa(String id, String nome, UserRole papel,
          {String managerId = '', String unidade = 'Matriz'}) =>
      UserModel(
        id: id,
        name: nome,
        email: '$id@agrobarter.com.br',
        role: papel,
        phone: '',
        branch: unidade,
        unitId: '1',
        managerId: managerId,
        avatarInitials: nome.substring(0, 2).toUpperCase(),
        createdAt: DateTime(2024, 1, 1),
        mustChangePassword: false,
      );

  final beatriz = pessoa('7', 'Beatriz Nogueira', UserRole.manager);
  final gustavo = pessoa('10', 'Gustavo Ramires', UserRole.manager);

  setUp(() {
    AppData.managers = [beatriz, gustavo];
    AppData.consultants = [
      pessoa('2', 'João Silva', UserRole.consultant, managerId: '7', unidade: 'Filial 02'),
      pessoa('3', 'Ana Paula Ferreira', UserRole.consultant, managerId: '7', unidade: 'Filial 04'),
      pessoa('4', 'Roberto Souza', UserRole.consultant, managerId: '10', unidade: 'Filial 34'),
    ];
  });

  tearDown(() {
    AppData.managers = [];
    AppData.consultants = [];
    AppData.admins = [];
    AppData.currentUser = null;
  });

  Future<void> abrir(WidgetTester tester, Widget tela) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.theme, home: tela));
    await tester.pumpAndSettle();
  }

  testWidgets('tocar no gerente abre o perfil dele, não a edição', (tester) async {
    await abrir(tester, const ConsultantsScreen());
    await tester.tap(find.text('Gerentes'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Beatriz Nogueira'));
    await tester.pumpAndSettle();

    expect(find.byType(StaffProfileScreen), findsOneWidget);
    expect(find.text('Gerente: Beatriz'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });

  testWidgets('o perfil do gerente mostra o time dele, e só ele', (tester) async {
    await abrir(tester, StaffProfileScreen(user: beatriz, role: UserRole.manager));

    expect(find.text('Consultores do time (2)'), findsOneWidget);
    expect(find.text('João Silva'), findsOneWidget);
    expect(find.text('Ana Paula Ferreira'), findsOneWidget);
    expect(find.text('Roberto Souza'), findsNothing);
    expect(find.text('Excluir gerente'), findsOneWidget);
  });

  testWidgets('o consultor do time abre o perfil dele', (tester) async {
    await abrir(tester, StaffProfileScreen(user: beatriz, role: UserRole.manager));

    await tester.tap(find.text('João Silva'));
    await tester.pumpAndSettle();

    expect(find.byType(ConsultantProfileScreen), findsOneWidget);
  });

  testWidgets('gerente sem time diz que está vazio', (tester) async {
    AppData.consultants = [];
    await abrir(tester, StaffProfileScreen(user: beatriz, role: UserRole.manager));

    expect(find.text('Consultores do time (0)'), findsOneWidget);
    expect(find.text('Nenhum consultor no time ainda'), findsOneWidget);
  });

  /// A PRÓPRIA CONTA não redefine a senha nem se exclui por aqui: a senha dela
  /// se troca por "Alterar senha", e o servidor recusa excluí-la.
  testWidgets('a própria conta de admin não tem senha nem exclusão', (tester) async {
    final eu = pessoa('1', 'Carlos Mendes', UserRole.admin);
    AppData.currentUser = eu;
    await abrir(tester, StaffProfileScreen(user: eu, role: UserRole.admin));

    expect(find.text('Administrador • você'), findsOneWidget);
    expect(find.text('Redefinir senha'), findsNothing);
    expect(find.textContaining('Excluir'), findsNothing);
  });

  testWidgets('outro admin redefine e exclui', (tester) async {
    AppData.currentUser = pessoa('1', 'Carlos Mendes', UserRole.admin);
    await abrir(
      tester,
      StaffProfileScreen(user: pessoa('12', 'Outra Admin', UserRole.admin), role: UserRole.admin),
    );

    expect(find.text('Redefinir senha'), findsOneWidget);
    expect(find.text('Excluir administrador'), findsOneWidget);
  });
}
