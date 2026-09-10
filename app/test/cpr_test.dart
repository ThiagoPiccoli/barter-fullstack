import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/models/models.dart';

/// A CÉDULA no app: o que o servidor manda, o que a tela devolve, e o que ela
/// abre quando ainda não há cédula nenhuma.
///
/// O app NÃO decide o que a cédula exige — quem escreve `gaps` é a API. O que
/// se prova aqui é o transporte: que nada se perde na ida e na volta, e que o
/// ponto de partida da tela é o certo em cada um dos três casos (rascunho
/// gravado, sugestão, nada).
void main() {
  Map<String, dynamic> deskJson({
    Map<String, dynamic>? cpr,
    Map<String, dynamic>? suggestion,
    List<String> gaps = const [],
    List<String> creditorGaps = const [],
    bool complete = false,
  }) =>
      {
        'cpr': cpr,
        'known': {
          'barterCode': 'PRM-2026-014',
          'emitterName': 'João da Silva',
          'emitterDocument': 'CPF 123.456.789-00',
          'grainName': 'Soja',
          'sacks': 440,
          'quantityKg': 26400,
          'sackPrice': 128.5,
          'totalValue': 56540,
          'versionCode': 'S2026.02',
        },
        'creditor': {
          'name': 'Cooperativa Exemplo Ltda.',
          'cnpj': '00.000.000/0001-00',
          'address': 'Avenida das Indústrias',
          'addressNumber': '1500',
          'city': 'Maringá/PR',
          'forum': 'Maringá/PR',
        },
        'creditorGaps': creditorGaps,
        'gaps': gaps,
        'complete': complete,
        'suggestion': suggestion ?? const {},
      };

  test('o que a permuta já sabe chega pronto — o app não recalcula nada', () {
    final desk = CprDesk.fromJson(deskJson());

    expect(desk.known.sacks, 440);
    // 440 × 60 e 440 × 128,50, contados pelo servidor. O app não repete a conta:
    // duas contas para o mesmo número é uma que diverge.
    expect(desk.known.quantityKg, 26400);
    expect(desk.known.totalValue, 56540);
    expect(desk.creditor.forum, 'Maringá/PR');
  });

  /// A tela abre com o RASCUNHO quando ele existe; com a SUGESTÃO quando não
  /// existe; e vazia quando não há nenhum dos dois. A data de emissão de uma
  /// cédula que ainda não existe é hoje.
  group('o ponto de partida da tela', () {
    test('rascunho gravado vence tudo', () {
      final desk = CprDesk.fromJson(deskJson(
        cpr: {'number': 'CPR-2026-014', 'emitterRg': '10.234.567-8', 'filledBy': 'Patrícia Lemos'},
        suggestion: {'emitterRg': '99.999.999-9'},
      ));

      expect(desk.startingPoint.number, 'CPR-2026-014');
      expect(desk.startingPoint.emitterRg, '10.234.567-8');
      expect(desk.startingPoint.filledBy, 'Patrícia Lemos');
    });

    test('sem rascunho, a sugestão preenche os campos', () {
      final desk = CprDesk.fromJson(deskJson(suggestion: {
        'emitterRg': '10.234.567-8',
        'emitterMaritalStatus': 'casado',
        'areas': [
          {
            'locality': 'Água Boa',
            'registryNumber': '12.345',
            'owners': [
              {'name': 'Antônio Pereira', 'document': '111.222.333-44'}
            ],
          }
        ],
      }));

      expect(desk.cpr, isNull);
      expect(desk.startingPoint.emitterRg, '10.234.567-8');
      expect(desk.startingPoint.areas.single.registryNumber, '12.345');
      expect(desk.startingPoint.areas.single.owners.single.name, 'Antônio Pereira');
      // Emissão é hoje: é a resposta certa quase sempre, e editável nas outras.
      expect(desk.startingPoint.issuedAt, isNotNull);
    });

    test('sem rascunho e sem sugestão, a cédula abre vazia — menos o peso da saca', () {
      final desk = CprDesk.fromJson(deskJson());

      expect(desk.suggestion, isNull);
      expect(desk.startingPoint.number, '');
      expect(desk.startingPoint.areas, isEmpty);
      // 60 kg é o padrão do mercado. Zero aqui viraria uma cédula prometendo
      // zero quilo de grão.
      expect(desk.startingPoint.sackWeightKg, 60);
    });
  });

  /// O corpo do `PUT` vai INTEIRO — a tela devolve o formulário todo, e é o
  /// servidor que trata campo ausente como "mantém o que está gravado".
  ///
  /// A asserção é sobre o MAPA INTEIRO, e não sobre uma lista de campos
  /// escolhidos a dedo, e essa diferença é a correção de um defeito real:
  /// `spouseRg` estava no construtor, no `toJson` e no `copyWith`, e faltava só
  /// no `fromJson`. Este teste existia e passava — ele conferia os oito campos
  /// que alguém lembrou de escrever, e o nono se perdia em silêncio.
  ///
  /// E "perder" era o menor dos efeitos. A tela reabria o campo VAZIO e o
  /// salvamento seguinte mandava `''` por cima do que estava guardado: um campo
  /// que se envia e não se lê APAGA o próprio dado na gravação seguinte. Com o
  /// mapa inteiro, o campo novo que alguém esquecer de ler falha aqui, sem
  /// depender de ninguém lembrar de acrescentar a linha da asserção.
  test('a ida e a volta não perdem campo nenhum', () {
    const draft = CprDraft(
      number: 'CPR-2026-014',
      emitterNationality: 'brasileiro',
      emitterMaritalStatus: 'casado',
      emitterProfession: 'produtor rural',
      emitterRg: '10.234.567-8',
      emitterAddress: 'Rua das Acácias',
      emitterAddressNumber: '320',
      emitterCity: 'Maringá/PR',
      emitterCoopId: '4471',
      emitterCnh: '01234567890',
      emitterFatherName: 'José da Silva',
      emitterMotherName: 'Ana da Silva',
      emitterEmail: 'joao@exemplo.com.br',
      deliveryPlace: 'Filial 02 — Gran. Santa Tecla',
      mortgages: 'Hipoteca de 1º grau junto ao Banco X.',
      spouseName: 'Maria da Silva',
      spouseNationality: 'brasileira',
      spouseProfession: 'do lar',
      spouseDocument: '987.654.321-00',
      spouseRg: '9.876.543-2',
      sackWeightKg: 50,
      cultivar: 'BMX Ativa RR',
      maxMoisture: 14,
      maxImpurities: 1,
      oilContent: 18,
      invoiceNumber: '55123',
      duplicateNumber: '55123-A',
      insurancePolicy: 'AP-99887',
      guarantors: [
        CprGuarantor(
          name: 'Carlos Avalista',
          document: '222.333.444-55',
          rg: '5.555.555-5',
          maritalStatus: 'casado',
          spouseName: 'Rita Avalista',
          spouseRg: '6.666.666-6',
        ),
      ],
      areas: [
        CprArea(
          locality: 'Água Boa',
          city: 'Doutor Camargo/PR',
          areaHa: 45.5,
          withinLargerArea: true,
          registryNumber: '12.345',
          registryBook: '2-RG',
          registryDistrict: 'Maringá/PR',
          owners: [CprOwner(name: 'Antônio Pereira', document: '111.222.333-44')],
        ),
      ],
    );

    final round = CprDraft.fromJson(draft.toJson());

    // O mapa inteiro, campo a campo — nenhum se perde na leitura.
    expect(round.toJson(), draft.toJson());

    // E o que mais importa dito por extenso: o RG do cônjuge sobrevive à volta,
    // e por isso a gravação seguinte não o apaga.
    expect(round.spouseRg, '9.876.543-2');
    expect(round.guarantors.single.spouseRg, '6.666.666-6');
    expect(round.areas.single.owners.single.document, '111.222.333-44');
  });

  test('o texto vai aparado — espaço sobrando não entra em título de crédito', () {
    const draft = CprDraft(number: '  CPR-2026-014  ', emitterRg: ' 10.234.567-8 ');
    final json = draft.toJson();

    expect(json['number'], 'CPR-2026-014');
    expect(json['emitterRg'], '10.234.567-8');
  });

  /// ESPELHO de `requiresSpouse`, em `api/src/barters/cpr.ts`. Aqui ele só
  /// mostra ou esconde o bloco na tela; quem COBRA o preenchimento continua
  /// sendo o servidor, na lista de pendências.
  test('o bloco do cônjuge segue o estado civil, que é texto livre', () {
    bool needs(String status) => CprDraft(emitterMaritalStatus: status).needsSpouse;

    expect(needs('Casado'), isTrue);
    expect(needs('CASADA'), isTrue);
    expect(needs('casado(a)'), isTrue);
    expect(needs('união estável'), isTrue);
    expect(needs('solteiro'), isFalse);
    expect(needs('divorciada'), isFalse);
    expect(needs(''), isFalse);
  });

  /// As duas listas de pendência são SEPARADAS porque quem resolve cada uma é
  /// outra pessoa: a do faturista, ali mesmo; a da credora, quem administra o
  /// servidor.
  test('a pendência da credora não se mistura com a do faturista', () {
    final desk = CprDesk.fromJson(deskJson(
      gaps: ['RG do emitente'],
      creditorGaps: ['CNPJ da credora (CREDITOR_CNPJ)'],
    ));

    expect(desk.gaps, ['RG do emitente']);
    expect(desk.creditorGaps, ['CNPJ da credora (CREDITOR_CNPJ)']);
    expect(desk.complete, isFalse);
  });
}
