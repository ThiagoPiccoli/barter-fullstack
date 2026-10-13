import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/services/work_post.dart';

/// A SEGURADORA vista do lado do app: a mesa dela entre a decisão do comitê e o
/// faturista, só para as permutas com seguro.
///
/// O que estes testes travam é a leitura do JSON — o estado novo, a apólice e a
/// pergunta "passa pela seguradora?", que vem pronta do servidor — e as filas
/// que dependem dela: a permuta esperando a apólice é da seguradora, e ainda
/// não é do faturista.
void main() {
  Map<String, dynamic> barterJson({
    String status = 'awaitingPolicy',
    bool insured = true,
    Map<String, dynamic>? policy,
  }) =>
      {
        'code': 'PRM-2026-021',
        'consultantName': 'Ana Ferreira',
        'producerName': 'Helena Prado',
        'status': status,
        'createdAt': '2026-04-22T00:00:00.000Z',
        'items': const [],
        'insuranceChoice': insured ? 'required' : 'none',
        'insured': insured,
        ...?policy,
      };

  const apolice = {
    'insurancePolicyNumber': 'AP-2026-778.412',
    'insurancePolicyFile': {
      'id': 41,
      'fileName': 'apolice.pdf',
      'contentType': 'application/pdf',
      'size': 4096,
      'uploadedBy': 'Sílvia Moreira',
      'uploadedAt': '2026-04-25T00:00:00.000Z',
    },
    'insuredBy': 'Sílvia Moreira',
    'insuredAt': '2026-04-25T00:00:00.000Z',
    'insuranceNote': 'Cobertura de granizo e seca.',
  };

  group('a permuta na mesa da seguradora', () {
    test('o estado novo é lido, e não cai no padrão de "no comitê"', () {
      final barter = BarterModel.fromJson(barterJson());
      expect(barter.status, BarterStatus.awaitingPolicy);
      expect(barter.insured, isTrue);
      expect(barter.awaitsPolicy, isTrue);
      expect(barter.awaitsInvoice, isFalse);
      expect(barter.hasPolicy, isFalse);
      expect(barter.insurancePolicyFile, isNull);
    });

    /// A RESSALVA continua sendo ressalva enquanto a permuta está com a
    /// seguradora — e continua sendo uma aprovação para os painéis.
    test('a aprovada com ressalva espera a apólice e continua com ressalva', () {
      final barter =
          BarterModel.fromJson(barterJson(status: 'awaitingPolicyWithConditions'));
      expect(barter.status, BarterStatus.awaitingPolicyWithConditions);
      expect(barter.awaitsPolicy, isTrue);
      expect(barter.hasConditions, isTrue);
      expect(barter.wasApproved, isTrue);
    });

    test('a apólice informada chega com o número, o documento e quem informou', () {
      final barter = BarterModel.fromJson(barterJson(status: 'approved', policy: apolice));
      expect(barter.awaitsPolicy, isFalse);
      expect(barter.awaitsInvoice, isTrue);
      expect(barter.hasPolicy, isTrue);
      expect(barter.insurancePolicyNumber, 'AP-2026-778.412');
      expect(barter.insurancePolicyFile!.fileName, 'apolice.pdf');
      expect(barter.insuredBy, 'Sílvia Moreira');
      expect(barter.insuredAt, isNotNull);
      expect(barter.insuranceNote, 'Cobertura de granizo e seca.');
    });

    test('a permuta sem seguro não passa pela seguradora', () {
      final barter = BarterModel.fromJson(barterJson(status: 'approved', insured: false));
      expect(barter.insured, isFalse);
      expect(barter.hasPolicy, isFalse);
    });

    /// O SEGURO saiu das exigências do comitê: a lista só tem avalista e
    /// hipoteca, mesmo que um servidor antigo ainda mande a caixa.
    test('o seguro não é mais exigência do comitê', () {
      final barter = BarterModel.fromJson({
        ...barterJson(status: 'awaitingRequirements'),
        'requiresGuarantor': true,
        'requiresInsurance': true,
      });
      expect(barter.requirements, ['Avalista']);
    });
  });

  group('rótulos e filas', () {
    test('os dois estados têm rótulo local', () {
      expect(barterStatusLabel(BarterStatus.awaitingPolicy), 'Aprovada, aguardando a apólice');
      expect(
        barterStatusLabel(BarterStatus.awaitingPolicyWithConditions),
        'Aprovada com ressalva, aguardando a apólice',
      );
    });

    test('a fila da seguradora é a das aprovadas esperando a apólice', () {
      final barters = [
        BarterModel.fromJson(barterJson()),
        BarterModel.fromJson(barterJson(status: 'approved', policy: apolice)),
      ];
      expect(queueOf(WorkPost.insurer, barters).map((b) => b.status), [
        BarterStatus.awaitingPolicy,
      ]);
      expect(queueOf(WorkPost.biller, barters).map((b) => b.status), [
        BarterStatus.approved,
      ]);
    });
  });
}
