import 'package:flutter_test/flutter_test.dart';
import 'package:agrobarter_app/services/offline_cache.dart';

/// O pacote gravado no aparelho é o que permite montar uma permuta sem sinal —
/// e ele atravessa o mesmo `fromJson` da API, de propósito, para que o offline
/// nunca calcule diferente do online.
///
/// Os testes daqui cercam a serialização e, principalmente, o que acontece com
/// um pacote estragado: um catálogo pela metade não pode virar uma permuta com
/// um número de sacas que nunca existiu.
void main() {
  Map<String, dynamic> row(String id) => {'id': id, 'name': 'Item $id'};

  OfflinePackage package({
    Map<String, dynamic>? version,
    List<Map<String, dynamic>>? products,
  }) =>
      OfflinePackage(
        savedAt: DateTime(2026, 8, 18, 14, 32),
        user: {'id': 2, 'email': 'ana@coop.test', 'fullName': 'Ana Ferreira'},
        version: version ?? {'code': 'S2026.02', 'grainPrice': 100},
        products: products ?? [row('5'), row('9')],
        classes: [row('c1')],
        producers: [row('10')],
        units: [row('3')],
      );

  group('OfflinePackage', () {
    test('sobrevive à ida e volta do JSON', () {
      final restored = OfflinePackage.fromJson(package().toJson());

      expect(restored.savedAt, DateTime(2026, 8, 18, 14, 32));
      expect(restored.user!['fullName'], 'Ana Ferreira');
      expect(restored.version!['code'], 'S2026.02');
      expect(restored.products.map((p) => p['id']), ['5', '9']);
      expect(restored.classes, hasLength(1));
      expect(restored.producers, hasLength(1));
      expect(restored.units, hasLength(1));
    });

    test('guarda o JSON como veio da API, sem reescrevê-lo', () {
      // O ponto do cache cru: o que sai daqui é idêntico ao que a API mandou, e
      // os dois caminhos atravessam o mesmo parser. Um `toJson` próprio daria
      // uma segunda gramática ao mesmo dado — e o dia em que ela divergisse
      // seria o dia em que a permuta offline sairia com outro número.
      final original = {
        'code': 'S2026.02',
        'grainPrice': 148.5,
        'prices': [
          {'productId': 5, 'price': 115.0},
        ],
      };
      final restored = OfflinePackage.fromJson(package(version: original).toJson());

      expect(restored.version, original);
    });

    test('versão nula é resposta legítima: não há Barter aberto', () {
      final semBarter = OfflinePackage(
        savedAt: DateTime(2026, 8, 18),
        user: null,
        version: null,
        products: [row('5')],
        classes: const [],
        producers: const [],
        units: const [],
      );
      final restored = OfflinePackage.fromJson(semBarter.toJson());

      // Diferente de nunca ter sincronizado — quem separa as duas é o
      // `lastSyncAt`, que só existe depois de um pacote bem-sucedido.
      expect(restored.version, isNull);
      expect(restored.savedAt, isNotNull);
    });

    test('linhas que não são objeto são descartadas, e o resto fica', () {
      final restored = OfflinePackage.fromJson({
        'savedAt': DateTime(2026, 8, 18).toIso8601String(),
        'products': [
          {'id': '5'},
          'lixo',
          42,
          {'id': '9'},
        ],
      });

      expect(restored.products.map((p) => p['id']), ['5', '9']);
    });

    test('pacote sem listas abre vazio em vez de estourar', () {
      final restored = OfflinePackage.fromJson({'savedAt': 'não é data'});

      expect(restored.products, isEmpty);
      expect(restored.classes, isEmpty);
      expect(restored.producers, isEmpty);
      expect(restored.units, isEmpty);
      expect(restored.user, isNull);
      expect(restored.savedAt, isNotNull);
    });
  });

  group('OfflineCache', () {
    test('sem cofre disponível, load devolve null em vez de lançar', () async {
      // É o caso deste teste (sem plugin) e o do desktop sem entitlement: o app
      // precisa cair no login, não quebrar na tela de abertura.
      expect(await OfflineCache.load(), isNull);
    });

    test('sem cofre disponível, save avisa que não gravou', () async {
      expect(await OfflineCache.save(package()), isFalse);
    });

    test('clear não lança quando não há o que apagar', () async {
      await expectLater(OfflineCache.clear(), completes);
    });
  });
}
