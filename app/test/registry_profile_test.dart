import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/consultants_screen.dart';
import 'package:agrobarter_app/screens/insurance_rate_profile_screen.dart';
import 'package:agrobarter_app/screens/unit_profile_screen.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// Os perfis de UNIDADE e de PRAÇA DE SEGURO — a mesma porta dos cadastros de
/// gente: tocar no cartão abre o que o cadastro é, e a edição fica no lápis.
void main() {
  UserModel pessoa(String id, String nome, UserRole papel, String unitId) => UserModel(
        id: id,
        name: nome,
        email: '$id@agrobarter.com.br',
        role: papel,
        phone: '',
        branch: '',
        unitId: unitId,
        avatarInitials: nome.substring(0, 2).toUpperCase(),
        createdAt: DateTime(2024, 1, 1),
        mustChangePassword: false,
      );

  ProducerModel produtor(String id, String nome, String cidade) => ProducerModel(
        id: id,
        name: nome,
        consultantId: '2',
        document: 'CPF 123.456.789-0$id',
        phone: '',
        farmName: 'Fazenda $nome',
        city: cidade,
        avatarInitials: nome.substring(0, 2).toUpperCase(),
        createdAt: DateTime(2020, 1, 1),
      );

  final filial34 =
      UnitModel(id: '6', name: 'Filial 34', city: 'Mandaguari/PR', createdAt: DateTime(2024, 3, 1));
  const maringa = InsuranceRateModel(id: '1', city: 'Maringá/PR', valuePerHa: 50);

  setUp(() {
    AppData.units = [filial34];
    AppData.consultants = [
      pessoa('4', 'Roberto Souza', UserRole.consultant, '6'),
      pessoa('2', 'João Silva', UserRole.consultant, '2'),
    ];
    AppData.managers = [pessoa('10', 'Gustavo Ramires', UserRole.manager, '6')];
    AppData.insuranceRates = [maringa];
    AppData.producers = [
      produtor('1', 'Antônio Carvalho', 'Maringá/PR'),
      produtor('2', 'Helena Prado', 'Sarandi/PR'),
    ];
  });

  tearDown(() {
    AppData.units = [];
    AppData.consultants = [];
    AppData.managers = [];
    AppData.insuranceRates = [];
    AppData.producers = [];
  });

  Future<void> abrir(WidgetTester tester, Widget tela) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.theme, home: tela));
    await tester.pumpAndSettle();
  }

  group('unidade', () {
    testWidgets('tocar na unidade abre o perfil dela, não a edição', (tester) async {
      await abrir(tester, const ConsultantsScreen());
      await tester.tap(find.text('Unidades'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filial 34'));
      await tester.pumpAndSettle();

      expect(find.byType(UnitProfileScreen), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('o perfil mostra o gerente e quem está lotado nela', (tester) async {
      await abrir(tester, UnitProfileScreen(unit: filial34));

      expect(find.text('Pessoas lotadas (2)'), findsOneWidget);
      expect(find.text('Roberto Souza'), findsOneWidget);
      expect(find.text('João Silva'), findsNothing);
      // O gerente aparece no cadastro da unidade e na lista de lotados.
      expect(find.text('Gustavo Ramires'), findsNWidgets(2));
      expect(find.text('Excluir unidade'), findsOneWidget);
    });

    /// Excluir não tem trava no servidor: quem estava lotado fica sem unidade.
    /// O diálogo diz quantos, antes.
    testWidgets('excluir avisa quantas pessoas ficam sem unidade', (tester) async {
      await abrir(tester, UnitProfileScreen(unit: filial34));

      await tester.tap(find.text('Excluir unidade'));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 pessoa(s) lotada(s) aqui ficam sem unidade'), findsOneWidget);
    });
  });

  group('praça de seguro', () {
    testWidgets('tocar na praça abre o perfil dela, não a edição', (tester) async {
      await abrir(tester, const ConsultantsScreen());
      await tester.tap(find.text('Seguros'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Maringá/PR'));
      await tester.pumpAndSettle();

      expect(find.byType(InsuranceRateProfileScreen), findsOneWidget);
    });

    /// O CUSTO por produtor saiu daqui junto com a área do cadastro: ele é de
    /// cada permuta, sobre a área plantada dela.
    testWidgets('o perfil mostra os produtores da praça', (tester) async {
      await abrir(tester, const InsuranceRateProfileScreen(rate: maringa));

      expect(find.text('Produtores nesta praça (1)'), findsOneWidget);
      expect(find.text('Antônio Carvalho'), findsOneWidget);
      expect(find.text('Helena Prado'), findsNothing);
    });

    testWidgets('excluir avisa que os produtores da praça ficam sem taxa', (tester) async {
      await abrir(tester, const InsuranceRateProfileScreen(rate: maringa));

      await tester.tap(find.text('Excluir praça'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 produtor(es) desta praça ficam sem taxa'), findsOneWidget);
    });
  });
}
