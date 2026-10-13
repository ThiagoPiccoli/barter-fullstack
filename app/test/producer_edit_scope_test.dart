import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/edit_forms.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// O CADASTRO DO PRODUTOR TEM DOIS DONOS, e a tela diz qual é qual.
///
/// O CONSULTOR cadastra o cliente novo e gere todos os dados dos clientes
/// dele: quem visita a fazenda é quem sabe que o telefone mudou, que o
/// produtor fez a opção pela folha e que o CPF saiu com um dígito trocado.
///
/// A ÁREA não está mais aqui: ela é a área plantada de cada permuta, por
/// cultura — e o cadastro diz isso a quem procurar o campo.
///
/// O que ele NÃO alcança é a CARTEIRA — quem atende quem é decisão de quem
/// administra. Ela fica VISÍVEL e travada, e no cadastro novo mostra o nome
/// dele: o produtor que ele cadastra é dele.
///
/// Quem recusa de verdade é o servidor (`ownerOnCreate` e `assertEditable`, na
/// API). Estes testes guardam a tradução da regra na tela.
void main() {
  UserModel pessoa({
    required String id,
    required String nome,
    required UserRole papel,
    required Set<String> capacidades,
  }) => UserModel(
    id: id,
    name: nome,
    email: '$id@agrobarter.com.br',
    role: papel,
    phone: '',
    branch: 'Filial 02',
    unitId: '1',
    avatarInitials: 'XX',
    createdAt: DateTime(2024, 1, 1),
    mustChangePassword: false,
    capabilities: capacidades,
  );

  UserModel consultor() => pessoa(
    id: '2',
    nome: 'João Silva',
    papel: UserRole.consultant,
    capacidades: const {Capability.producersRegister, Capability.producersEdit},
  );

  UserModel admin() => pessoa(
    id: '1',
    nome: 'Admin',
    papel: UserRole.admin,
    capacidades: const {
      Capability.producersManage,
      Capability.producersRegister,
      Capability.producersEdit,
    },
  );

  ProducerModel produtor() => ProducerModel(
    id: '10',
    name: 'Antônio Carvalho',
    consultantId: '2',
    document: 'CPF 123.456.789-00',
    phone: '(44) 99999-0000',
    farmName: 'Fazenda Boa Vista',
    city: 'Maringá/PR',
    avatarInitials: 'AC',
    createdAt: DateTime(2020, 1, 1),
  );

  setUp(() {
    AppData.consultants = [consultor()];
  });

  tearDown(() {
    AppData.consultants = [];
    AppData.currentUser = null;
  });

  /// Tela alta o bastante para o formulário inteiro caber sem rolagem — a
  /// mesma razão do teste da carteira: o que está fora do viewport nem é
  /// construído, e o teste falharia por não achar o que não foi desenhado.
  Future<void> abrir(WidgetTester tester, UserModel quem, {ProducerModel? p}) async {
    AppData.currentUser = quem;
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: EditProducerScreen(producer: p),
    ));
    await tester.pumpAndSettle();
  }

  /// Um campo é EDITÁVEL quando existe uma caixa de texto com aquele rótulo.
  Finder campo(String rotulo) => find.widgetWithText(TextFormField, rotulo);

  /// O regime de Funrural é editável quando as opções estão na tela.
  Finder regimes() => find.byType(RadioListTile<TaxRegime>);

  testWidgets('o consultor edita todos os dados do cliente dele', (tester) async {
    await abrir(tester, consultor(), p: produtor());

    for (final rotulo in [
      'Nome',
      'Documento (CPF/CNPJ)',
      'Telefone',
      'Propriedade',
      'Município/UF',
    ]) {
      expect(campo(rotulo), findsOneWidget, reason: rotulo);
    }
    expect(regimes(), findsNWidgets(TaxRegime.values.length));
    // A área saiu do cadastro, e a tela diz onde ela foi parar.
    expect(campo('Área cultivável (ha)'), findsNothing);
    expect(find.textContaining('área plantada é informada em cada permuta'), findsOneWidget);
  });

  /// A CARTEIRA aparece travada — com o nome à vista, porque saber quem atende
  /// o cliente continua sendo informação.
  testWidgets('só a carteira fica travada para ele', (tester) async {
    await abrir(tester, consultor(), p: produtor());

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('João Silva'), findsOneWidget);
    expect(find.textContaining('definido pelo administrador'), findsOneWidget);
  });

  /// O CADASTRO DO CONSULTOR nasce na carteira dele. O nome vem da sessão, e
  /// não da lista de consultores — que é do admin e pode nem ter sido
  /// carregada para ele.
  testWidgets('no cadastro novo, a carteira já é a dele', (tester) async {
    AppData.consultants = [];
    await abrir(tester, consultor());

    expect(find.text('Novo Produtor'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('João Silva'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(campo('Documento (CPF/CNPJ)'), findsOneWidget);
    expect(regimes(), findsNWidgets(TaxRegime.values.length));
  });

  testWidgets('o admin escolhe a carteira', (tester) async {
    await abrir(tester, admin(), p: produtor());

    expect(campo('Documento (CPF/CNPJ)'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });
}
