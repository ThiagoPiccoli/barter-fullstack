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
    List<String> consultantGaps = const [],
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
          // O VENCIMENTO e as NOTAS chegam entre o que ninguém digita: o
          // primeiro é da SAFRA (ele muda conforme a cultura) e as segundas são
          // do FATURAMENTO. Os dois eram campos do formulário, preenchidos por
          // quem não tinha a informação.
          'dueDate': '2026-06-30T12:00:00.000Z',
          'seasonName': 'Soja 2026',
          'invoices': [
            {'number': '55.318', 'series': '1', 'duplicateNumber': '55.318-A'},
          ],
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
        'consultantGaps': consultantGaps,
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

  /// As listas de pendência são SEPARADAS porque quem resolve cada uma é outra
  /// pessoa: a do consultor, ali mesmo; a da credora, quem administra o
  /// servidor.
  test('a pendência da credora não se mistura com a do consultor', () {
    final desk = CprDesk.fromJson(deskJson(
      gaps: ['RG do emitente'],
      creditorGaps: ['CNPJ da credora (CREDITOR_CNPJ)'],
    ));

    expect(desk.gaps, ['RG do emitente']);
    expect(desk.creditorGaps, ['CNPJ da credora (CREDITOR_CNPJ)']);
    expect(desk.complete, isFalse);
  });

  /// O QUE TRAVA O ENCAMINHAMENTO é um RECORTE de `gaps`, e chega pronto do
  /// servidor.
  ///
  /// A separação é o que faz o aviso do detalhe não mandar o consultor procurar
  /// o número da CPR (do emissor) e a nota fiscal (do faturista) num formulário
  /// onde nenhum dos dois existe — e o `readyToForward` do app é a mesma
  /// pergunta que o portão do `forward` responde na API.
  group('o que trava o encaminhamento', () {
    test('vem separado da lista inteira', () {
      final desk = CprDesk.fromJson(deskJson(
        gaps: ['RG do emitente', 'número da CPR', 'nota fiscal do faturamento'],
        consultantGaps: ['RG do emitente'],
      ));

      expect(desk.consultantGaps, ['RG do emitente']);
      expect(desk.readyToForward, isFalse);
    });

    test('cédula sem pendência do consultor libera a permuta, mesmo incompleta', () {
      // O caso REAL do rascunho pronto: falta o número da CPR e a nota, que são
      // de outros postos e só existem semanas depois. A permuta anda assim
      // mesmo — esperar por elas para encaminhar travaria a esteira inteira.
      final desk = CprDesk.fromJson(deskJson(
        gaps: ['número da CPR', 'nota fiscal do faturamento'],
      ));

      expect(desk.readyToForward, isTrue);
      expect(desk.complete, isFalse);
    });

    test('servidor antigo, sem o campo: nada trava', () {
      // Uma versão da API anterior a este campo não deve travar o botão do app
      // instalado — o portão de verdade é o do servidor, e ele recusa de lá.
      final json = deskJson()..remove('consultantGaps');

      expect(CprDesk.fromJson(json).readyToForward, isTrue);
    });
  });

  /// OS DOIS DOCUMENTOS QUE VOLTAM DE FORA — a cédula assinada e a via
  /// carimbada pelo registro.
  ///
  /// Eles chegam dentro da CÉDULA (são anexos dela), enquanto as DATAS dos dois
  /// atos chegam na permuta. O que se prova aqui é só o transporte: perder
  /// qualquer um dos dois na leitura faria a tela dizer que o papel não está
  /// anexado — sobre uma permuta cujo papel está anexado.
  group('os documentos que voltaram de fora', () {
    Map<String, dynamic> file(String name) => {
          'id': 9,
          'fileName': name,
          'contentType': 'application/pdf',
          'size': 120_000,
          'uploadedBy': 'Renata Bicudo',
          'uploadedAt': '2026-03-14T11:00:00.000Z',
        };

    test('a cédula assinada e a via registrada chegam com o rascunho', () {
      final desk = CprDesk.fromJson(deskJson(cpr: {
        'number': 'CPR-2026-014',
        'signedFile': file('cpr-assinada.pdf'),
        'registryFile': file('via-registrada.pdf'),
      }));

      expect(desk.cpr!.signedFile!.fileName, 'cpr-assinada.pdf');
      expect(desk.cpr!.registryFile!.fileName, 'via-registrada.pdf');
      expect(desk.cpr!.signedFile!.sizeLabel, isNotEmpty);
    });

    test('cédula sem os anexos não inventa nenhum', () {
      final desk = CprDesk.fromJson(deskJson(cpr: {'number': 'CPR-2026-014'}));

      expect(desk.cpr!.signedFile, isNull);
      expect(desk.cpr!.registryFile, isNull);
    });

    /// O `copyWith` do formulário NÃO pode perdê-los: quem digita um campo do
    /// padrão do grão não está removendo o papel assinado da cédula. É a mesma
    /// regra do SCR, e ela já esteve errada uma vez.
    test('digitar no formulário não apaga os anexos', () {
      final desk = CprDesk.fromJson(deskJson(cpr: {
        'number': 'CPR-2026-014',
        'signedFile': file('cpr-assinada.pdf'),
      }));

      final editado = desk.cpr!.copyWith(cultivar: 'BMX Ativa RR');

      expect(editado.cultivar, 'BMX Ativa RR');
      expect(editado.signedFile!.fileName, 'cpr-assinada.pdf');
    });
  });

  _notasEEmissao();
}
/// AS NOTAS DO FATURAMENTO e a EMISSÃO da cédula, do lado do app.
///
/// As duas coisas nasceram da mesma correção: o faturista deixou de preencher a
/// cédula e passou a anexar as notas, e o EMISSOR apareceu para conferir e
/// emitir o título. O que se prova aqui é o transporte — o app não decide nada
/// disso, e cada engano na leitura do JSON é um estado errado numa tela.
void _notasEEmissao() {
  Map<String, dynamic> barterJson(
    String status, {
    List<Map<String, dynamic>> invoices = const [],
    Map<String, dynamic> extra = const {},
  }) =>
      {
        'code': 'PRM-2026-001',
        'consultantId': 2,
        'consultantName': 'João Silva',
        'producerName': 'Antônio Carvalho',
        'status': status,
        'createdAt': '2026-01-10T09:30:00.000Z',
        'items': const [],
        'invoices': invoices,
        ...extra,
      };

  group('as notas do faturamento', () {
    test('a permuta chega com as notas, e cada uma com o anexo', () {
      final barter = BarterModel.fromJson(barterJson('invoiced', invoices: [
        {
          'id': 7,
          'number': '55.318',
          'series': '1',
          'duplicateNumber': '55.318-A',
          'issuedAt': '2026-01-12T10:15:00.000Z',
          'value': 37334.0,
          'attachedBy': 'Patrícia Lemos',
          'file': {
            'id': 3,
            'fileName': 'nf-55318.pdf',
            'contentType': 'application/pdf',
            'size': 82_400,
            'uploadedBy': 'Patrícia Lemos',
            'uploadedAt': '2026-01-12T10:15:00.000Z',
          },
        },
      ]));

      expect(barter.invoices, hasLength(1));
      final nota = barter.invoices.single;
      expect(nota.label, 'NF 55.318/1');
      expect(nota.duplicateNumber, '55.318-A');
      expect(nota.value, 37334.0);
      expect(nota.file!.fileName, 'nf-55318.pdf');
      // O tamanho sai legível sem ninguém dividir nada na tela.
      expect(nota.file!.sizeLabel, '80 KB');
    });

    /// SEM SÉRIE o rótulo não sai com a barra pendurada: há praça que não usa
    /// série, e "NF 55.318/" seria ruído impresso na tela e no documento.
    test('nota sem série não ganha a barra', () {
      final barter = BarterModel.fromJson(barterJson('invoiced', invoices: [
        {'id': 7, 'number': '55.318', 'series': '', 'file': null},
      ]));
      expect(barter.invoices.single.label, 'NF 55.318');
      // SEM ARQUIVO é a nota HERDADA do campo de texto que ficava na cédula. A
      // tela a mostra como pendente em vez de escondê-la — o número existe, e a
      // prova não.
      expect(barter.invoices.single.file, isNull);
    });

    test('permuta sem notas não inventa lista', () {
      expect(BarterModel.fromJson(barterJson('approved')).invoices, isEmpty);
    });
  });

  group('o trecho da cédula', () {
    /// FATURAR DEIXOU DE SER O FIM DA LINHA. Este é o teste que trava a
    /// correção: a permuta faturada ainda deve o título, e quem está com ela é o
    /// EMISSOR.
    test('a faturada está com o emissor, e não concluída', () {
      final barter = BarterModel.fromJson(barterJson('invoiced'));
      expect(barter.isInvoiced, isTrue);
      expect(barter.awaitsCprIssue, isTrue);
      expect(barter.isCprIssued, isFalse);
      expect(barter.isCprRegistered, isFalse);
      expect(barter.statusLabel, 'Faturada, a emitir a CPR');
    });

    test('cada degrau da cédula tem o próprio estado', () {
      expect(BarterModel.fromJson(barterJson('cprIssued')).awaitsSignatures, isTrue);
      expect(BarterModel.fromJson(barterJson('cprSigned')).awaitsRegistration, isTrue);
      expect(BarterModel.fromJson(barterJson('cprRegistered')).isCprRegistered, isTrue);
    });

    /// A CÉDULA EMITIDA não se reescreve — e é [isCprIssued] que a tela lê para
    /// desligar o formulário. Ela conta os três degraus a partir da emissão,
    /// porque nenhum deles aceita escrita.
    test('emitida, assinada e registrada contam como "já saiu"', () {
      for (final status in ['cprIssued', 'cprSigned', 'cprRegistered']) {
        expect(
          BarterModel.fromJson(barterJson(status)).isCprIssued,
          isTrue,
          reason: status,
        );
      }
      expect(BarterModel.fromJson(barterJson('invoiced')).isCprIssued, isFalse);
    });

    /// O FATURAMENTO não se desfaz quando a cédula anda: [wasInvoiced] é a
    /// pergunta de quem conta o que já saiu, e ela sobrevive aos três degraus.
    /// É o mesmo raciocínio de `wasApproved` com o faturamento.
    test('o faturamento sobrevive aos degraus da cédula', () {
      for (final status in ['invoiced', 'cprIssued', 'cprSigned', 'cprRegistered']) {
        final barter = BarterModel.fromJson(barterJson(status));
        expect(barter.wasInvoiced, isTrue, reason: status);
        expect(barter.wasApproved, isTrue, reason: status);
        // E o pedido de alteração continua fechado: o que saiu para fora não se
        // corrige pela esteira.
        expect(barter.canBeChangedBy('2'), isFalse, reason: status);
      }
    });

    test('as marcas dos três atos do emissor chegam inteiras', () {
      final barter = BarterModel.fromJson(barterJson('cprRegistered', extra: {
        'cprEmittedBy': 'Renata Bicudo',
        'cprEmittedAt': '2026-01-15T14:00:00.000Z',
        'cprEmissionNote': 'Duas vias impressas.',
        'cprSignedAt': '2026-01-20T10:00:00.000Z',
        'cprSignatureNote': 'Emitente e cônjuge, presencial.',
        'cprRegisteredAt': '2026-02-02T09:00:00.000Z',
        'cprRegistryNumber': 'R-4 / 18.442',
        'cprRegistryPlace': 'CRI Maringá/PR',
      }));

      expect(barter.cprEmittedBy, 'Renata Bicudo');
      expect(barter.cprEmissionNote, contains('Duas vias'));
      expect(barter.cprSignedAt, isNotNull);
      expect(barter.cprRegistryNumber, 'R-4 / 18.442');
      expect(barter.cprRegistryPlace, 'CRI Maringá/PR');
    });

    /// Servidor mais novo que o app: um estado desconhecido cai em `pending` e a
    /// permuta continua VISÍVEL, com o rótulo certo (que vem do servidor). Era
    /// exatamente o que acontecia com `invoiced` quando ele nasceu.
    test('estado desconhecido não esconde a permuta', () {
      final barter = BarterModel.fromJson(
        barterJson('cprProtestada', extra: {'statusLabel': 'CPR protestada'}),
      );
      expect(barter.status, BarterStatus.pending);
      expect(barter.statusLabel, 'CPR protestada');
    });
  });
}
