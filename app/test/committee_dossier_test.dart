import 'package:flutter_test/flutter_test.dart';
import 'package:agrobarter_app/models/models.dart';

/// A MESA DO COMITÊ vista do lado do app: o dossiê e as exigências.
///
/// O que estes testes travam é a leitura de DUAS AUSÊNCIAS que significam
/// coisas diferentes, e que um `?? []` apagaria:
///
/// - `creditFiles` NÃO VEIO: quem está lendo não pode abrir o dossiê. A tela
///   não desenha a seção — porque uma lista vazia diria "o comitê não apurou
///   nada", e o consultor concluiria que a permuta dele foi decidida no escuro;
/// - `creditFiles` veio VAZIO: quem lê alcança o dossiê, e ele está vazio de
///   verdade. Aí a tela cobra os documentos antes da decisão.
void main() {
  Map<String, dynamic> barterJson({
    List<Map<String, dynamic>>? creditFiles,
    bool withRequirements = false,
    String status = 'pending',
    List<Map<String, dynamic>>? events,
  }) => {
        'code': 'PRM-2026-002',
        'consultantName': 'Ana Ferreira',
        'producerName': 'Helena Prado',
        'status': status,
        'createdAt': '2026-04-22T00:00:00.000Z',
        'items': const [],
        'creditFiles': ?creditFiles,
        'events': ?events,
        'consultantId': 5,
        if (withRequirements) ...{
          'requiresGuarantor': true,
          'requiresCollateral': true,
        },
      };

  Map<String, dynamic> creditFile({String kind = 'serasa'}) => {
        'id': 7,
        'kind': kind,
        'kindLabel': kind == 'serasa' ? 'Consulta ao Serasa' : 'Endividamento na cooperativa',
        'note': 'Consulta de 20/04, sem restrições.',
        'attachedBy': 'Comitê de Permutas',
        'attachedAt': '2026-04-23T00:00:00.000Z',
        'file': {
          'id': 12,
          'fileName': 'serasa.pdf',
          'contentType': 'application/pdf',
          'size': 2048,
          'uploadedBy': 'Comitê de Permutas',
          'uploadedAt': '2026-04-23T00:00:00.000Z',
        },
      };

  group('O dossiê da análise de crédito', () {
    test('quem pode ler recebe a lista, com o tipo já por extenso', () {
      final barter = BarterModel.fromJson(barterJson(creditFiles: [creditFile()]));

      expect(barter.creditFiles, hasLength(1));
      final read = barter.creditFiles!.single;
      expect(read.kind, 'serasa');
      // O RÓTULO vem resolvido do servidor: o app não mantém uma segunda cópia
      // do vocabulário para sair de sincronia com ele.
      expect(read.kindLabel, 'Consulta ao Serasa');
      expect(read.attachedBy, 'Comitê de Permutas');
      expect(read.file?.fileName, 'serasa.pdf');
      expect(read.file?.sizeLabel, '2 KB');
    });

    /// A diferença que decide se a seção aparece na tela.
    test('campo ausente é "não posso ler"; vazio é "não há peça"', () {
      expect(BarterModel.fromJson(barterJson()).creditFiles, isNull);
      expect(BarterModel.fromJson(barterJson(creditFiles: [])).creditFiles, isEmpty);
    });

    test('os três tipos que a tela oferece são os do servidor', () {
      expect(creditFileKinds.keys.toList(), ['serasa', 'indebtedness', 'other']);
      expect(creditFileKinds['indebtedness'], 'Endividamento na cooperativa');
    });
  });

  group('As exigências do comitê', () {
    /// Elas chegam a TODO MUNDO que enxerga a permuta, e não só a quem decidiu:
    /// são trabalho para outra pessoa — o consultor as leva ao produtor, o
    /// emissor descobre que aquele título espera um avalista.
    test('vêm como campos, e a lista sai na ordem da reunião', () {
      final barter = BarterModel.fromJson(barterJson(withRequirements: true));

      expect(barter.requiresGuarantor, isTrue);
      expect(barter.requiresCollateral, isTrue);
      // `requiresCollateral` é a HIPOTECA: o rótulo mudou, a coluna ficou.
      expect(barter.requirements, ['Avalista', 'Hipoteca']);
    });

    /// Sem exigência marcada, a lista é vazia — o que vale tanto para a
    /// aprovação limpa quanto para a permuta que ninguém decidiu ainda.
    test('sem exigência, a lista é vazia', () {
      expect(BarterModel.fromJson(barterJson()).requirements, isEmpty);
    });
  });

  /// O DESVIO DAS EXIGÊNCIAS: o comitê pede avalista, hipoteca ou seguro ANTES
  /// de decidir, e a permuta volta ao consultor. Cumpridas, ela volta direto ao
  /// comitê, sem passar de novo pelo gerente.
  group('A permuta devolvida com exigências', () {
    Map<String, dynamic> evento(String action, String to, String at, {String? note}) => {
          'action': action,
          'fromStatus': 'pending',
          'toStatus': to,
          'actorName': 'Comitê de Permutas',
          'actorRole': 'committee',
          'actorRoleLabel': 'Comitê',
          'note': note,
          'at': at,
        };

    test('o estado novo é lido, e a permuta está com o consultor', () {
      final barter = BarterModel.fromJson(
        barterJson(status: 'awaitingRequirements', withRequirements: true),
      );

      expect(barter.status, BarterStatus.awaitingRequirements);
      expect(barter.awaitsRequirements, isTrue);
      expect(barter.awaitsCommittee, isFalse);
      expect(barter.statusLabel, 'Exigências do comitê, com o consultor');
      // Só o DONO da permuta tem o botão de devolver.
      expect(barter.awaitsRequirementsFrom('5'), isTrue);
      expect(barter.awaitsRequirementsFrom('6'), isFalse);
      // E ela ainda aceita pedido de produto: não foi decidida.
      expect(barter.canRequestProductBy('5'), isTrue);
    });

    /// O QUAL do pedido mora na linha do tempo — o pedido não é decisão, e não
    /// escreve nos campos dela. Vale o pedido MAIS RECENTE.
    test('o texto do pedido é o do último evento de exigência', () {
      final barter = BarterModel.fromJson(barterJson(
        status: 'awaitingRequirements',
        events: [
          evento('require', 'awaitingRequirements', '2026-04-24T10:00:00.000Z',
              note: 'Aval do irmão.\nExigências: Avalista.'),
          evento('fulfill', 'pending', '2026-04-25T10:00:00.000Z'),
          evento('require', 'awaitingRequirements', '2026-04-26T10:00:00.000Z',
              note: 'Agora a apólice.\nExigências: Seguro.'),
        ],
      ));

      expect(barter.requirementsNote, 'Agora a apólice.\nExigências: Seguro.');
      expect(barter.reviewNote, isNull);
    });

    test('sem pedido nenhum, não há texto de exigência', () {
      expect(BarterModel.fromJson(barterJson()).requirementsNote, isNull);
    });

    test('a linha do tempo nomeia a ida e a volta', () {
      final ida = BarterEventModel.fromJson(
          evento('require', 'awaitingRequirements', '2026-04-24T10:00:00.000Z'));
      final volta = BarterEventModel.fromJson(
          evento('fulfill', 'pending', '2026-04-25T10:00:00.000Z'));

      expect(ida.title, 'Exigências do comitê: voltou ao consultor');
      expect(volta.title, 'Exigências cumpridas: voltou ao comitê');
    });
  });

  /// O AVISO ao gerente — a frase vem pronta do servidor.
  group('Os avisos', () {
    test('o aviso traz a permuta, a frase e a hora', () {
      final notice = NoticeModel.fromJson({
        'id': 3,
        'barterCode': 'PRM-2026-002',
        'message': 'A permuta PRM-2026-002, de Ana Ferreira, voltou ao consultor.',
        'createdAt': '2026-04-24T10:00:00.000Z',
        'readAt': null,
      });

      expect(notice.id, 3);
      expect(notice.barterCode, 'PRM-2026-002');
      expect(notice.message, contains('voltou ao consultor'));
      expect(notice.createdAt.toUtc(), DateTime.utc(2026, 4, 24, 10));
    });
  });
}
