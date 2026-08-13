import 'package:flutter_test/flutter_test.dart';
import 'package:barter_app/models/models.dart';

/// O parse do JSON da API é o ponto em que uma mudança no servidor chega ao
/// app já instalado no aparelho de alguém. Um campo novo é inofensivo; um
/// VALOR novo num campo que o app converte para enum não é — e era aí que a
/// lista inteira parava de carregar.
void main() {
  Map<String, dynamic> barterJson({String status = 'pending'}) => {
        'code': 'PRM-2026-001',
        'consultantId': 2,
        'consultantName': 'João Silva',
        'consultantBranch': 'Filial 02',
        'producerId': 1,
        'producerName': 'Antônio Carvalho',
        'status': status,
        'createdAt': '2026-01-10T00:00:00.000Z',
        'items': [
          {
            'kind': 'grain',
            'productId': 1,
            'productName': 'Soja',
            'unit': 'saca 60kg',
            'quantity': 80.4444,
            'unitValue': 148.5,
          },
          {
            'kind': 'input',
            'productId': 5,
            'productName': 'NPK',
            'unit': 'saco 50kg',
            'quantity': 48,
            'unitValue': 115.0,
          },
        ],
      };

  group('BarterModel', () {
    test('separa itens por tipo e lê os status conhecidos', () {
      final barter = BarterModel.fromJson(barterJson(status: 'approved'));
      expect(barter.status, BarterStatus.approved);
      expect(barter.grains, hasLength(1));
      expect(barter.inputs, hasLength(1));
      expect(barter.inputCost, closeTo(5520.0, 0.001));
      expect(barter.referenceGrainName, 'Soja');
    });

    /// Antes, `BarterStatus.values.byName` LANÇAVA aqui — e como o parse
    /// acontece dentro de um `map` sobre a lista inteira, um único registro
    /// com status desconhecido derrubava TODAS as permutas da tela.
    test('status desconhecido não derruba o parse da lista', () {
      expect(
        () => [barterJson(status: 'cancelled'), barterJson()].map(BarterModel.fromJson).toList(),
        returnsNormally,
      );
      final barter = BarterModel.fromJson(barterJson(status: 'cancelled'));
      expect(barter.status, BarterStatus.pending);
      expect(barter.id, 'PRM-2026-001');
    });
  });

  group('InputCategoryModel', () {
    test('lê as regras conhecidas', () {
      final category = InputCategoryModel.fromJson(
        {'id': 1, 'name': 'Fertilizantes', 'ruleType': 'percentOfTotal', 'ruleValue': 30},
      );
      expect(category.ruleType, CategoryRuleType.percentOfTotal);
      expect(category.hasRule, isTrue);
    });

    test('regra desconhecida vira "sem exigência" em vez de exceção', () {
      final category = InputCategoryModel.fromJson(
        {'id': 9, 'name': 'Nova Regra', 'ruleType': 'porVolume', 'ruleValue': 5},
      );
      expect(category.ruleType, CategoryRuleType.none);
      expect(category.hasRule, isFalse);
    });
  });

  /// A senha de primeira entrada chega junto com o cadastro, numa resposta só,
  /// e é a única vez que ela existe em texto puro.
  group('ProvisionedConsultant', () {
    test('lê o cadastro e a senha provisória da mesma resposta', () {
      final provisioned = ProvisionedConsultant.fromJson({
        'id': 7,
        'fullName': 'Nova Consultora',
        'email': 'nova@barter.com.br',
        'role': 'consultant',
        'branch': 'Filial 03',
        'createdAt': '2026-08-13T10:00:00.000Z',
        'initials': 'NC',
        'mustChangePassword': true,
        'provisionalPassword': 'K7NP-4TQX',
      });

      expect(provisioned.provisionalPassword, 'K7NP-4TQX');
      expect(provisioned.consultant.name, 'Nova Consultora');
      expect(provisioned.consultant.mustChangePassword, isTrue);
      expect(provisioned.consultant.role, UserRole.consultant);
    });
  });
}
