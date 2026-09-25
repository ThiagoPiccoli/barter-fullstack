import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/edit_forms.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// O CADASTRO DO PRODUTOR TEM DOIS DONOS, e a tela diz qual é qual.
///
/// O CONSULTOR passou a gerir os dados do cliente dele: quem visita a fazenda é
/// quem sabe que o telefone mudou, que a propriedade está com o nome errado e
/// que o cliente passou a plantar noutro município. Enquanto isso foi só do
/// admin, corrigir um telefone virava um chamado — e o cadastro envelhecia em
/// silêncio, que é pior do que ficar errado com alguém sabendo.
///
/// O que ele NÃO alcança é o outro lado da mesma regra: a identidade do cadastro
/// (o documento), as duas réguas que medem toda permuta dele (a área cultivável
/// e o regime de Funrural) e a carteira — quem atende quem é decisão de quem
/// administra. Os quatro ficam VISÍVEIS e travados, porque esconder um campo que
/// ele acabou de conferir na fazenda o faria procurar o que sumiu.
///
/// Quem recusa de verdade é o servidor (`assertEditable`, na API). Estes testes
/// guardam a tradução da regra na tela.
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
    capacidades: const {Capability.producersEdit},
  );

  UserModel admin() => pessoa(
    id: '1',
    nome: 'Admin',
    papel: UserRole.admin,
    capacidades: const {Capability.producersManage, Capability.producersEdit},
  );

  ProducerModel produtor() => ProducerModel(
    id: '10',
    name: 'Antônio Carvalho',
    consultantIds: const ['2'],
    document: 'CPF 123.456.789-00',
    phone: '(44) 99999-0000',
    farmName: 'Fazenda Boa Vista',
    city: 'Maringá/PR',
    areaHa: 120,
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
  Future<void> abrir(WidgetTester tester, UserModel quem) async {
    AppData.currentUser = quem;
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: EditProducerScreen(producer: produtor()),
    ));
    await tester.pumpAndSettle();
  }

  /// Um campo é EDITÁVEL quando existe uma caixa de texto com aquele rótulo.
  Finder campo(String rotulo) => find.widgetWithText(TextFormField, rotulo);

  testWidgets('o consultor edita contato e endereço do cliente dele', (tester) async {
    await abrir(tester, consultor());

    expect(campo('Nome'), findsOneWidget);
    expect(campo('Telefone'), findsOneWidget);
    expect(campo('Propriedade'), findsOneWidget);
    expect(campo('Município/UF'), findsOneWidget);
  });

  /// Os quatro campos do ADMIN aparecem travados — com o valor à vista, porque
  /// a área cultivável que o consultor acabou de conferir continua sendo a
  /// informação que ele foi buscar ali.
  testWidgets('documento, área, Funrural e carteira ficam travados para ele', (tester) async {
    await abrir(tester, consultor());

    expect(campo('Documento (CPF/CNPJ)'), findsNothing);
    expect(campo('Área cultivável (ha)'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);

    // Travado não é escondido: o valor continua na tela, com o cadeado.
    expect(find.text('CPF 123.456.789-00'), findsOneWidget);
    expect(find.text('120 ha'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(4));
  });

  /// E a tela DIZ a quem pedir: uma trava que não explica manda o consultor
  /// concluir que o app está quebrado.
  testWidgets('a tela diz que os quatro são do administrador', (tester) async {
    await abrir(tester, consultor());

    expect(find.textContaining('alterados pelo administrador'), findsOneWidget);
  });

  testWidgets('o admin continua alcançando os quatro', (tester) async {
    await abrir(tester, admin());

    expect(campo('Documento (CPF/CNPJ)'), findsOneWidget);
    expect(campo('Área cultivável (ha)'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsWidgets);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });
}
