import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/edit_forms.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// O campo de CARTEIRA do cadastro de produtor — uma lista suspensa, porque é
/// um consultor por produtor.
///
/// O que este teste guarda é a regra que a tela precisa impor sozinha: um
/// consultor escolhido. Ela também vive no servidor, mas quem descobre isso
/// primeiro é quem está preenchendo o formulário — e um 422 depois de digitar
/// sete campos é a pior hora de descobrir.
void main() {
  UserModel consultor(String id, String nome, String unidade) => UserModel(
        id: id,
        name: nome,
        email: '$id@agrobarter.com.br',
        role: UserRole.consultant,
        phone: '',
        branch: unidade,
        unitId: '1',
        managerId: '7',
        managerName: 'Beatriz Nogueira',
        avatarInitials: 'XX',
        createdAt: DateTime(2024, 1, 1),
        mustChangePassword: false,
      );

  ProducerModel produtor(String? consultantId) => ProducerModel(
        id: '3',
        name: 'Joaquim Tavares',
        consultantId: consultantId,
        document: 'CNPJ 12.345.678/0001-90',
        phone: '',
        farmName: 'Fazenda Santa Rita',
        city: 'Mandaguari/PR',
        areaHa: 320,
        avatarInitials: 'JT',
        createdAt: DateTime(2020, 11, 3),
      );

  setUp(() {
    AppData.consultants = [
      consultor('2', 'João Silva', 'Filial 02'),
      consultor('4', 'Roberto Souza', 'Filial 34'),
      consultor('3', 'Ana Paula Ferreira', 'Filial 04'),
    ];
    // A CARTEIRA é campo do ADMIN: quem atende quem é decisão de quem
    // administra, e o consultor que a escrevesse poderia se remover do próprio
    // cliente. Sem este usuário, a tela desenha a versão do consultor — e o
    // campo que este arquivo inteiro mede não existe nela.
    AppData.currentUser = UserModel(
      id: '1',
      name: 'Admin',
      email: 'admin@agrobarter.com.br',
      role: UserRole.admin,
      phone: '',
      branch: 'Matriz',
      unitId: '1',
      avatarInitials: 'AD',
      createdAt: DateTime(2024, 1, 1),
      mustChangePassword: false,
      capabilities: const {Capability.producersManage, Capability.producersEdit},
    );
  });

  tearDown(() {
    AppData.consultants = [];
    AppData.currentUser = null;
  });

  /// Tela alta o bastante para o formulário inteiro caber sem rolagem. O padrão
  /// de 800×600 deixa o botão de salvar fora do viewport, e a `ListView` nem
  /// chega a construí-lo — o teste falharia por não achar o botão, que não é o
  /// que ele quer medir.
  Future<void> abrir(WidgetTester tester, ProducerModel? p) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: EditProducerScreen(producer: p),
    ));
    await tester.pumpAndSettle();
  }

  /// O valor que a lista suspensa está mostrando agora.
  String? escolhido(WidgetTester tester) => tester
      .state<FormFieldState<String>>(find.byType(DropdownButtonFormField<String>))
      .value;

  Future<void> escolher(WidgetTester tester, String nome) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    // O menu aberto desenha o item por cima do campo; o último achado é o do
    // menu.
    await tester.tap(find.textContaining(nome, findRichText: true).last);
    await tester.pumpAndSettle();
  }

  testWidgets('o produtor abre com o consultor dele escolhido', (tester) async {
    await abrir(tester, produtor('4'));

    expect(escolhido(tester), '4');
    expect(find.textContaining('Roberto Souza', findRichText: true), findsOneWidget);
  });

  testWidgets('trocar o consultor é escolher outro na lista', (tester) async {
    await abrir(tester, produtor('2'));
    expect(escolhido(tester), '2');

    await escolher(tester, 'Roberto Souza');

    expect(escolhido(tester), '4');
  });

  testWidgets('a lista oferece todos os consultores, com a unidade de cada um',
      (tester) async {
    await abrir(tester, produtor('2'));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    for (final nome in ['João Silva', 'Roberto Souza', 'Ana Paula Ferreira']) {
      expect(find.textContaining(nome, findRichText: true), findsWidgets);
    }
    expect(find.textContaining('Filial 34', findRichText: true), findsOneWidget);
  });

  /// Sem consultor o formulário PARA aqui: não chega a chamar a API, que é o
  /// que faz este teste rodar sem servidor nenhum no ar.
  testWidgets('produtor novo começa sem consultor, e salvar assim acusa', (tester) async {
    await abrir(tester, null);
    expect(escolhido(tester), isNull);
    expect(find.text('Cadastrar'), findsOneWidget);

    await tester.tap(find.text('Cadastrar'));
    await tester.pumpAndSettle();
    expect(find.text('Escolha o consultor que atende este produtor'), findsOneWidget);
  });

  /// O produtor cujo consultor foi excluído espera realocação: o campo abre
  /// vazio, pedindo um consultor, em vez de mostrar um id que não está na lista.
  testWidgets('consultor que não existe mais não abre escolhido', (tester) async {
    await abrir(tester, produtor('999'));

    expect(escolhido(tester), isNull);
  });
}
