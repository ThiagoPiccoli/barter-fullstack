import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/edit_forms.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// O campo de CARTEIRA do cadastro de produtor — marcação múltipla, porque
/// consultores dividem região e atendem o mesmo cliente.
///
/// O que este teste guarda é a regra que a tela precisa impor sozinha: pelo
/// menos um consultor marcado. Ela também vive no servidor (o DTO recusa lista
/// vazia), mas quem descobre isso primeiro é quem está preenchendo o formulário
/// — e um 422 depois de digitar sete campos é a pior hora de descobrir.
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

  ProducerModel produtor(List<String> consultantIds) => ProducerModel(
        id: '3',
        name: 'Joaquim Tavares',
        consultantIds: consultantIds,
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
  });

  tearDown(() => AppData.consultants = []);

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

  Checkbox caixaDe(WidgetTester tester, String nome) => tester.widget<Checkbox>(
        find.descendant(
          of: find.widgetWithText(CheckboxListTile, nome),
          matching: find.byType(Checkbox),
        ),
      );

  testWidgets('o produtor compartilhado abre com os dois consultores marcados',
      (tester) async {
    await abrir(tester, produtor(['2', '4']));

    expect(caixaDe(tester, 'João Silva').value, isTrue);
    expect(caixaDe(tester, 'Roberto Souza').value, isTrue);
    expect(caixaDe(tester, 'Ana Paula Ferreira').value, isFalse);
    expect(find.text('2 marcado(s)'), findsOneWidget);
  });

  testWidgets('marcar outro consultor compartilha o produtor com ele', (tester) async {
    await abrir(tester, produtor(['2']));
    expect(find.text('1 marcado(s)'), findsOneWidget);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Roberto Souza'));
    await tester.pumpAndSettle();

    expect(caixaDe(tester, 'João Silva').value, isTrue);
    expect(caixaDe(tester, 'Roberto Souza').value, isTrue);
    expect(find.text('2 marcado(s)'), findsOneWidget);
  });

  /// Sem nenhum marcado o formulário PARA aqui: não chega a chamar a API, que
  /// é o que faz este teste rodar sem servidor nenhum no ar.
  testWidgets('desmarcar todos acusa antes de salvar', (tester) async {
    await abrir(tester, produtor(['2', '4']));

    for (final nome in ['João Silva', 'Roberto Souza']) {
      await tester.tap(find.widgetWithText(CheckboxListTile, nome));
      await tester.pumpAndSettle();
    }

    // Acusa no ato de desmarcar o último — e não só quando alguém tenta salvar.
    final erro = find.text('Marque pelo menos um consultor para atender este produtor');
    expect(erro, findsOneWidget);

    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();
    expect(erro, findsOneWidget);
  });

  testWidgets('produtor novo começa sem ninguém marcado', (tester) async {
    await abrir(tester, null);

    for (final nome in ['João Silva', 'Roberto Souza', 'Ana Paula Ferreira']) {
      expect(caixaDe(tester, nome).value, isFalse);
    }
    expect(find.textContaining('marcado(s)'), findsNothing);
    expect(find.text('Cadastrar'), findsOneWidget);
  });

  /// Consultor excluído já não tem vínculo no servidor. Mostrá-lo marcado
  /// prometeria salvar algo que a API recusaria — e o admin só descobriria ao
  /// tentar.
  testWidgets('id de consultor que não existe mais não abre marcado', (tester) async {
    await abrir(tester, produtor(['2', '999']));

    expect(caixaDe(tester, 'João Silva').value, isTrue);
    expect(find.text('1 marcado(s)'), findsOneWidget);
  });
}
