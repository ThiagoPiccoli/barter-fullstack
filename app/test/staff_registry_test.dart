import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/consultants_screen.dart';
import 'package:agrobarter_app/screens/edit_forms.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// A ABA DE CADASTROS do admin, nos dois papéis que ela passou a administrar: o
/// FATURISTA (uma pessoa, várias) e o COMITÊ (um órgão, um cadastro só).
///
/// A diferença entre os dois é o que estes testes existem para segurar. O comitê
/// é uma REUNIÃO: não se cadastra um integrante por vez, não há lista e não há
/// exclusão — e a tela precisa dizer isso sozinha, porque quem abre o formulário
/// não vai ler o comentário do controller.
void main() {
  UserModel staff(String id, String nome, UserRole role) => UserModel(
        id: id,
        name: nome,
        email: '$id@agrobarter.com.br',
        role: role,
        phone: '',
        branch: 'Matriz',
        unitId: '1',
        avatarInitials: 'XX',
        createdAt: DateTime(2024, 1, 1),
      );

  setUp(() {
    AppData.units = [
      UnitModel(
        id: '1',
        name: 'Matriz',
        city: 'Maringá/PR',
        avatarInitials: 'MA',
        createdAt: DateTime(2020, 1, 1),
      ),
    ];
  });

  tearDown(() {
    AppData.units = [];
    AppData.billers = [];
    AppData.committee = null;
    AppData.barters = [];
  });

  /// Tela larga: com seis segmentos, o padrão de 800×600 deixaria os últimos
  /// fora do viewport da faixa rolável, e o teste falharia por não alcançar o
  /// que ele quer medir.
  Future<void> abrir(WidgetTester tester, Widget tela) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.theme, home: tela));
    await tester.pumpAndSettle();
  }

  group('cadastros — comitê', () {
    testWidgets('sem cadastro, a tela diz o que falta e oferece criá-lo', (tester) async {
      await abrir(tester, const ConsultantsScreen());
      await tester.tap(find.text('Comitê'));
      await tester.pumpAndSettle();

      expect(find.text('O comitê ainda não tem cadastro'), findsOneWidget);
      // O convite existe DUAS vezes de propósito: no cartão e no botão de ação.
      expect(find.widgetWithText(FloatingActionButton, 'Cadastrar comitê'), findsOneWidget);
    });

    testWidgets('com cadastro, some o botão de criar — ele é um só', (tester) async {
      AppData.committee = staff('8', 'Comitê de Permutas', UserRole.committee);
      await abrir(tester, const ConsultantsScreen());
      await tester.tap(find.text('Comitê'));
      await tester.pumpAndSettle();

      expect(find.text('Comitê de Permutas'), findsOneWidget);
      expect(find.text('O comitê ainda não tem cadastro'), findsNothing);
      // Não há "novo comitê": um botão que só levaria a um 422 é pior do que
      // botão nenhum.
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('o formulário do comitê pede o nome do ÓRGÃO, e não exclui', (tester) async {
      await abrir(
        tester,
        EditStaffScreen(
          user: staff('8', 'Comitê de Permutas', UserRole.committee),
          role: UserRole.committee,
        ),
      );

      expect(find.text('Editar Comitê'), findsOneWidget);
      // "Nome do comitê", e não "Nome": o que se escreve aqui assina cada
      // decisão, e o rótulo evita o cadastro nascer com o nome de quem preencheu.
      expect(find.text('Nome do comitê'), findsOneWidget);
      expect(find.text('E-mail de acesso do comitê'), findsOneWidget);

      // A senha se redefine (a composição da reunião muda); o cadastro não se
      // exclui — sem ele nenhuma permuta é decidida.
      expect(find.text('Redefinir senha'), findsOneWidget);
      expect(find.textContaining('Excluir'), findsNothing);
    });

    testWidgets('o formulário novo abre como cadastro, não como pessoa', (tester) async {
      await abrir(tester, const EditStaffScreen(role: UserRole.committee));

      expect(find.text('Cadastrar Comitê'), findsOneWidget);
      expect(find.textContaining('REUNIÃO'), findsOneWidget);
      // Comitê não tem gerente — o campo é só do consultor.
      expect(find.text('Gerente responsável'), findsNothing);
    });
  });

  group('cadastros — faturistas', () {
    testWidgets('a lista mostra os faturistas cadastrados', (tester) async {
      AppData.billers = [
        staff('9', 'Patrícia Lemos', UserRole.biller),
        staff('12', 'Marcos Vieira', UserRole.biller),
      ];
      await abrir(tester, const ConsultantsScreen());
      await tester.tap(find.text('Faturistas'));
      await tester.pumpAndSettle();

      expect(find.text('Patrícia Lemos'), findsOneWidget);
      expect(find.text('Marcos Vieira'), findsOneWidget);
      expect(find.text('2 faturista(s)'), findsOneWidget);
      expect(find.widgetWithText(FloatingActionButton, 'Novo faturista'), findsOneWidget);
    });

    /// O faturista é PESSOA: são vários, e cada um sai sem travar nada — o que
    /// ele faturou guarda o nome dele no próprio registro.
    testWidgets('o formulário do faturista exclui, e não pergunta gerente', (tester) async {
      await abrir(
        tester,
        EditStaffScreen(user: staff('9', 'Patrícia Lemos', UserRole.biller), role: UserRole.biller),
      );

      expect(find.text('Editar Faturista'), findsOneWidget);
      expect(find.text('Excluir faturista'), findsOneWidget);
      expect(find.text('Gerente responsável'), findsNothing);
    });
  });
}
