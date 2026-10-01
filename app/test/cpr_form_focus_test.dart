import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/cpr_form_screen.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// O FOCO na mesa da cédula.
///
/// Os campos das lavouras e dos avalistas levavam na chave o próprio texto
/// (`value.hashCode`): cada letra trocava a chave, o Flutter recriava o campo,
/// e quem digitava precisava clicar de novo a cada caractere. O que este teste
/// guarda é a digitação de verdade — uma letra por vez, sem tocar no campo
/// entre elas —, e não o `enterText` de uma vez só, que passaria com o defeito.
///
/// E guarda também o motivo de a chave existir: remover a primeira lavoura não
/// pode deixar o texto dela aparecendo na que sobrou.
void main() {
  const code = 'BRT-1';

  /// A mesa como o servidor a devolve: duas lavouras (uma com proprietário) e
  /// um avalista, tudo em branco — o estado de quem volta da visita à fazenda.
  Map<String, dynamic> mesa({List<Map<String, dynamic>>? areas}) => {
        'data': {
          'cpr': {
            'areas': areas ??
                [
                  {
                    'owners': [
                      {'name': '', 'document': ''}
                    ]
                  },
                  <String, dynamic>{},
                ],
            'guarantors': [<String, dynamic>{}],
          },
          'known': {'barterCode': code, 'emitterName': 'Joaquim Tavares'},
          'creditor': <String, dynamic>{},
          'pledge': <String, dynamic>{},
        },
      };

  BarterModel permuta() => BarterModel(
        id: code,
        consultantId: '2',
        consultantName: 'João Silva',
        consultantBranch: 'Filial 02',
        producerId: '10',
        producerName: 'Joaquim Tavares',
        status: BarterStatus.invoiced,
        createdAt: DateTime(2026, 3, 1),
        managerId: '7',
        grains: const [],
        inputs: const [],
      );

  setUp(() {
    // O CONSULTOR: é quem escreve na cédula. Sem `cprFill` a tela abre só
    // para leitura, e os campos que este arquivo mede nem aceitam texto.
    AppData.currentUser = UserModel(
      id: '2',
      name: 'João Silva',
      email: 'joao@agrobarter.com.br',
      role: UserRole.consultant,
      phone: '',
      branch: 'Filial 02',
      unitId: '1',
      avatarInitials: 'JS',
      createdAt: DateTime(2024, 1, 1),
      mustChangePassword: false,
      capabilities: const {Capability.bartersCprFill},
    );
  });

  tearDown(() => AppData.currentUser = null);

  /// Abre a tela com a API respondendo [resposta]. O `runWithClient` vale para
  /// tudo o que a tela pedir enquanto o [corpo] roda — inclusive o `_load` do
  /// `initState`.
  Future<void> naTela(
    WidgetTester tester,
    Future<void> Function() corpo, {
    Map<String, dynamic>? resposta,
  }) async {
    // Tela alta o bastante para a `ListView` construir o formulário inteiro:
    // as lavouras e os avalistas ficam no fim, fora do viewport padrão.
    tester.view.physicalSize = const Size(1000, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cliente = MockClient((request) async {
      if (request.method == 'GET' && request.url.path.endsWith('/barters/$code/cpr')) {
        return http.Response(jsonEncode(resposta ?? mesa()), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('{"message":"rota inesperada no teste"}', 404);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.theme,
        home: CprFormScreen(barter: permuta()),
      ));
      await tester.pumpAndSettle();
      await corpo();
    }, () => cliente);
  }

  EditableText editavel(WidgetTester tester, Finder campo) => tester.widget<EditableText>(
        find.descendant(of: campo, matching: find.byType(EditableText)),
      );

  /// Digita [texto] UMA LETRA POR VEZ, com um único toque no começo — como a
  /// pessoa digita. Depois de cada letra a tela redesenha, e o campo precisa
  /// continuar com o foco e com tudo o que já foi digitado.
  Future<void> digitar(WidgetTester tester, Finder campo, String texto) async {
    await tester.tap(campo);
    await tester.pump();
    expect(editavel(tester, campo).focusNode.hasFocus, isTrue);

    var digitado = '';
    for (final letra in texto.split('')) {
      digitado += letra;
      tester.testTextInput.enterText(digitado);
      await tester.pump();
      expect(editavel(tester, campo).focusNode.hasFocus, isTrue,
          reason: 'o campo perdeu o foco depois de "$digitado"');
    }
    expect(editavel(tester, campo).controller.text, texto);
  }

  Finder campo(String rotulo) => find.widgetWithText(TextFormField, rotulo);

  testWidgets('a lavoura aceita várias letras seguidas sem perder o foco', (tester) async {
    await naTela(tester, () async {
      await digitar(tester, campo('Localidade').first, 'Sítio Boa Vista');
      await digitar(tester, campo('Matrícula').first, '12.345');
      await digitar(tester, campo('Comarca do registro').first, 'Maringá');
    });
  });

  testWidgets('a área em hectares guarda o que foi digitado, vírgula inclusive',
      (tester) async {
    // O caso em que o texto do campo e o valor guardado divergem: "12," vale
    // 12, e redesenhar o campo a partir do número comeria a vírgula.
    await naTela(tester, () async {
      await digitar(tester, campo('Área (ha)').first, '12,5');
    });
  });

  testWidgets('o proprietário da lavoura aceita várias letras seguidas', (tester) async {
    await naTela(tester, () async {
      await digitar(tester, campo('CPF/CNPJ'), '123.456.789-00');
    });
  });

  testWidgets('o avalista aceita várias letras seguidas', (tester) async {
    await naTela(tester, () async {
      await digitar(tester, campo('CPF'), '987.654.321-00');
      // O estado civil faz o bloco do cônjuge aparecer no meio da digitação —
      // e o campo em que se digita não pode ir embora junto.
      await digitar(tester, campo('Estado civil').last, 'casado');
      expect(find.text('CÔNJUGE DO AVALISTA'), findsOneWidget);
    });
  });

  testWidgets('remover a primeira lavoura não deixa o texto dela na segunda',
      (tester) async {
    await naTela(
      tester,
      () async {
        expect(find.text('Sítio A'), findsOneWidget);
        expect(find.text('Sítio B'), findsOneWidget);

        await tester.tap(find.byTooltip('Remover lavoura').first);
        await tester.pumpAndSettle();

        expect(find.text('Sítio A'), findsNothing);
        expect(editavel(tester, campo('Localidade')).controller.text, 'Sítio B');
      },
      resposta: mesa(areas: [
        {'locality': 'Sítio A'},
        {'locality': 'Sítio B'},
      ]),
    );
  });
}
