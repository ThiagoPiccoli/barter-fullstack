import 'package:flutter_test/flutter_test.dart';
import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/barter_simulation.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/services/simulation_check.dart';

/// A simulação é a ÚNICA cópia do trabalho que o consultor fez sem sinal: ela
/// não existe no servidor, e não há de onde recuperá-la se o app a perder. E é
/// dela que sai a permuta de verdade — o número que o consultor combinou com o
/// produtor precisa ser o que vai ser registrado, ou ele precisa ser avisado de
/// que mudou.
///
/// Os testes daqui cercam as duas coisas: as maneiras de perder a simulação, e
/// as maneiras de ela virar permuta com uma conta que ninguém combinou.
void main() {
  UserModel consultant(String id) => UserModel(
        id: id,
        name: 'Consultor $id',
        email: 'c$id@coop.test',
        phone: '',
        branch: 'Filial 02',
        role: UserRole.consultant,
        avatarInitials: 'C$id',
        createdAt: DateTime(2026, 1, 1),
      );

  BarterSimulation simulation({
    String id = 'sim-1',
    String consultantId = '2',
    String versionCode = 'S2026.02',
    List<SimulationItem>? items,
    double simulatedSacks = 80,
    TaxRegime taxRegime = TaxRegime.comercializacao,
    DateTime? updatedAt,
  }) =>
      BarterSimulation(
        id: id,
        consultantId: consultantId,
        producerId: '10',
        producerName: 'Antônio Carvalho',
        unitId: '3',
        unitName: 'Filial 02 – Gran. Santa T.',
        versionCode: versionCode,
        items: items ??
            const [
              SimulationItem(
                  productId: '5', productName: 'NPK', unit: 'saco 50kg', quantity: 48),
              SimulationItem(
                  productId: '9', productName: 'Glifosato', unit: 'litro', quantity: 20),
            ],
        simulatedSacks: simulatedSacks,
        grainName: 'Soja',
        taxRegime: taxRegime,
        createdAt: DateTime(2026, 3, 1),
        updatedAt: updatedAt ?? DateTime(2026, 3, 2),
      );

  /// Uma versão do Barter com a tabela que os testes pedirem.
  BarterVersionModel version({
    String code = 'S2026.02',
    bool isOpen = true,
    double grainPrice = 100,
    Map<String, double> prices = const {'5': 100.0, '9': 50.0},
  }) =>
      BarterVersionModel(
        id: 'v1',
        code: code,
        number: 2,
        seasonCode: 'S2026',
        seasonName: 'Safra 2026',
        grainId: '1',
        grainName: 'Soja',
        grainUnit: 'saca 60kg',
        grainPrice: grainPrice,
        status: isOpen ? 'open' : 'closed',
        isOpen: isOpen,
        startsAt: DateTime(2026, 2, 1),
        prices: [
          for (final entry in prices.entries)
            VersionPriceModel(
              productId: entry.key,
              productName: 'Produto ${entry.key}',
              unit: 'un',
              price: entry.value,
            ),
        ],
      );

  setUp(() {
    AppData.simulations = [];
    AppData.currentUser = consultant('2');
  });

  tearDown(() {
    AppData.simulations = [];
    AppData.currentUser = null;
  });

  group('BarterSimulation', () {
    test('sobrevive à ida e volta do JSON', () {
      final restored = BarterSimulation.fromJson(simulation().toJson());

      expect(restored.id, 'sim-1');
      expect(restored.consultantId, '2');
      expect(restored.producerName, 'Antônio Carvalho');
      expect(restored.unitId, '3');
      expect(restored.versionCode, 'S2026.02');
      expect(restored.simulatedSacks, 80);
      expect(restored.grainName, 'Soja');
      expect(restored.items.map((i) => i.productName), ['NPK', 'Glifosato']);
      expect(restored.inputQuantities, {'5': 48.0, '9': 20.0});
    });

    /// A FORMA de recolher o Funrural é escolhida no fechamento e viaja com a
    /// simulação até o envio: entre uma coisa e outra o aparelho pode ficar
    /// guardado por semanas, e refazer a escolha na hora de mandar seria pedir
    /// ao consultor que lembrasse do que combinou na fazenda.
    test('a forma de recolhimento escolhida no fechamento sobrevive ao aparelho', () {
      final restored =
          BarterSimulation.fromJson(simulation(taxRegime: TaxRegime.folha).toJson());

      expect(restored.taxRegime, TaxRegime.folha);
      // E ela continua sendo a mesma quando a simulação é reescrita.
      expect(restored.copyWith(simulatedSacks: 90).taxRegime, TaxRegime.folha);
    });

    test('abre uma simulação salva por uma versão anterior do app', () {
      // Campos que ainda não existiam, e números gravados como texto: ela
      // continua abrindo, porque carrega o trabalho de uma tarde.
      final restored = BarterSimulation.fromJson({
        'id': 'sim-antiga',
        'consultantId': 2,
        'producerId': 10,
        'items': [
          {'productId': 5, 'quantity': '48'},
        ],
      });

      expect(restored.id, 'sim-antiga');
      expect(restored.consultantId, '2');
      expect(restored.producerName, '');
      expect(restored.versionCode, '');
      expect(restored.simulatedSacks, 0);
      expect(restored.inputQuantities, {'5': 48.0});
    });

    test('descarta itens que não são insumo escolhido', () {
      final restored = BarterSimulation.fromJson({
        'id': 'sim-1',
        'items': [
          {'productId': '5', 'quantity': 48},
          {'productId': '9', 'quantity': 0},
          {'productId': '11', 'quantity': -3},
          {'productId': '12', 'quantity': 'abc'},
          {'productId': '', 'quantity': 10},
        ],
      });

      // Zero, negativo, ilegível e sem id não são escolha — e um deles chegando
      // ao payload faria o servidor recusar a permuta inteira no envio.
      expect(restored.inputQuantities, {'5': 48.0});
      expect(restored.inputCount, 1);
    });

    test('gera ids locais distintos', () {
      final ids = {for (var i = 0; i < 50; i++) BarterSimulation.newId()};
      expect(ids.length, 50);
    });
  });

  group('AppData.mySimulations', () {
    test('mostra só as simulações do consultor logado', () {
      AppData.simulations = [
        simulation(id: 'minha', consultantId: '2'),
        simulation(id: 'do-colega', consultantId: '7'),
      ];

      // O aparelho é compartilhado em algumas praças. Enviar a simulação de um
      // colega registraria a permuta em nome de quem clicou, e o servidor não
      // teria como perceber a troca.
      expect(AppData.mySimulations.map((s) => s.id), ['minha']);
    });

    test('ordena da mais recente para a mais antiga', () {
      AppData.simulations = [
        simulation(id: 'velha', updatedAt: DateTime(2026, 3, 1)),
        simulation(id: 'nova', updatedAt: DateTime(2026, 3, 10)),
        simulation(id: 'media', updatedAt: DateTime(2026, 3, 5)),
      ];

      expect(AppData.mySimulations.map((s) => s.id), ['nova', 'media', 'velha']);
    });

    test('fica vazia sem ninguém logado', () {
      AppData.simulations = [simulation()];
      AppData.currentUser = null;

      expect(AppData.mySimulations, isEmpty);
    });
  });

  group('AppData.saveSimulation', () {
    test('reescreve a simulação de mesmo id em vez de duplicá-la', () async {
      await AppData.saveSimulation(simulation(simulatedSacks: 80));
      await AppData.saveSimulation(simulation(simulatedSacks: 95));

      // É o segundo "Salvar" da mesma permuta. Sem isto, a lista encheria de
      // cópias da mesma negociação e o consultor encaminharia a errada.
      expect(AppData.mySimulations, hasLength(1));
      expect(AppData.mySimulations.single.simulatedSacks, 95);
    });

    test('mantém a simulação em memória mesmo quando o aparelho recusa gravar',
        () async {
      // Sem plugin de cofre (o caso deste teste), a gravação falha e o retorno
      // diz isso — mas a permuta montada continua utilizável na sessão aberta,
      // que é o que ainda dá para salvar do trabalho do consultor.
      final persisted = await AppData.saveSimulation(simulation());

      expect(persisted, isFalse);
      expect(AppData.mySimulations, hasLength(1));
    });

    test('deleteSimulation tira só a simulação pedida', () async {
      await AppData.saveSimulation(simulation(id: 'a'));
      await AppData.saveSimulation(simulation(id: 'b'));

      await AppData.deleteSimulation('a');

      expect(AppData.mySimulations.map((s) => s.id), ['b']);
    });
  });

  group('checkSimulation — o que mudou entre montar e enviar', () {
    SimulationCheck check(
      BarterSimulation sim, {
      BarterVersionModel? v,
      bool producerInWallet = true,
      bool unitExists = true,
    }) =>
        checkSimulation(sim,
            version: v ?? version(),
            producerInWallet: producerInWallet,
            unitExists: unitExists);

    test('nada mudou: envia sem interromper', () {
      // 48 × 100 + 20 × 50 = 5.800; a 100 a saca, 58 sacas.
      final result = check(simulation(simulatedSacks: 58));

      expect(result.blocker, isNull);
      expect(result.canSend, isTrue);
      expect(result.needsReview, isFalse);
      expect(result.currentSacks, 58);
    });

    test('Barter fechado trava o envio e diz que a simulação está guardada', () {
      final result = check(simulation(), v: version(isOpen: false));

      expect(result.canSend, isFalse);
      expect(result.blocker, contains('fechado'));
      expect(result.blocker, contains('continua guardada'));
    });

    test('sem Barter nenhum também trava', () {
      final result = checkSimulation(simulation(),
          version: null, producerInWallet: true, unitExists: true);

      expect(result.blocker, isNotNull);
    });

    test('produtor fora da carteira trava antes de gastar o envio', () {
      // O servidor recusaria com 403; dizer aqui poupa a viagem e explica o que
      // houve, em vez de devolver "sem permissão".
      final result = check(simulation(), producerInWallet: false);

      expect(result.canSend, isFalse);
      expect(result.blocker, contains('Antônio Carvalho'));
      expect(result.blocker, contains('carteira'));
    });

    test('unidade desativada trava e manda escolher outra', () {
      final result = check(simulation(), unitExists: false);

      expect(result.canSend, isFalse);
      expect(result.blocker, contains('escolha outra'));
    });

    test('Barter novo: refaz com os mesmos insumos na tabela vigente', () {
      // A simulação foi montada no S2026.02 e ficou parada. O Barter virou e os
      // valores subiram: os insumos são os mesmos, mas cobri-los custa mais
      // sacas — e é isso que o consultor precisa ver antes de encaminhar.
      final result = check(
        simulation(versionCode: 'S2026.02', simulatedSacks: 58),
        v: version(code: 'S2026.03', prices: const {'5': 120.0, '9': 60.0}),
      );

      expect(result.versionChanged, isTrue);
      expect(result.previousVersionCode, 'S2026.02');
      expect(result.rebuilt.versionCode, 'S2026.03');
      // 48 × 120 + 20 × 60 = 6.960 → 69,6 sacas.
      expect(result.currentSacks, closeTo(69.6, 0.001));
      expect(result.sacksChanged, isTrue);
      expect(result.needsReview, isTrue);
      // Refazer não é bloquear: a permuta continua enviável, com o número novo.
      expect(result.canSend, isTrue);
      expect(result.rebuilt.items.map((i) => i.productId), ['5', '9']);
    });

    test('mesma versão com valor corrigido também acusa a diferença', () {
      // O admin pode corrigir um valor DENTRO da versão vigente, inclusive a
      // cotação da saca. O código da versão continua o mesmo — por isso a
      // conferência é sobre as SACAS, e não sobre o código.
      final result = check(
        simulation(simulatedSacks: 58),
        v: version(grainPrice: 80),
      );

      expect(result.versionChanged, isFalse);
      expect(result.currentSacks, closeTo(72.5, 0.001));
      expect(result.sacksChanged, isTrue);
      expect(result.needsReview, isTrue);
    });

    test('diferença invisível na tela não interrompe o envio', () {
      // Abaixo da tolerância os dois números aparecem iguais; alarmar sobre o
      // que ninguém enxerga ensinaria o consultor a confirmar sem ler.
      final result = check(simulation(simulatedSacks: 58.02));

      expect(result.sacksChanged, isFalse);
      expect(result.needsReview, isFalse);
    });

    test('insumo fora da tabela nova aparece por nome e trava o envio', () {
      // Sem valor acordado nesta gestão o insumo não é permutável, e o servidor
      // recusaria a permuta inteira por causa dele.
      final result = check(
        simulation(versionCode: 'S2026.02'),
        v: version(code: 'S2026.03', prices: const {'5': 100.0}),
      );

      expect(result.dropped.map((i) => i.productName), ['Glifosato']);
      expect(result.canSend, isFalse);
      expect(result.needsReview, isTrue);
      // O insumo derrubado CONTINUA na simulação refeita — `copyWith` não mexe
      // nos itens —, e é por isso que a trava tem de existir: as sacas foram
      // recalculadas sem ele, então enviar registraria um total que não o cobre.
      expect(result.rebuilt.items.map((i) => i.productName), contains('Glifosato'));
    });

    test('a trava do insumo derrubado sai por nome e diz o que fazer', () {
      // `stopReason` é a porta que o envio consulta. Enquanto ela não existia, o
      // envio olhava só `blocker` e a permuta passava daqui para tomar um 422.
      final result = check(
        simulation(versionCode: 'S2026.02'),
        v: version(code: 'S2026.03', prices: const {'5': 100.0}),
      );

      expect(result.blocker, isNull);
      expect(result.stopReason, contains('Glifosato'));
      expect(result.stopReason, contains('S2026.03'));
      expect(result.stopReason, contains('Abra a simulação'));
    });

    test('sem insumo derrubado a porta do envio fica aberta', () {
      final result = check(simulation(versionCode: 'S2026.02'), v: version(code: 'S2026.03'));

      expect(result.dropped, isEmpty);
      expect(result.stopReason, isNull);
      expect(result.canSend, isTrue);
    });

    test('o Barter fechado continua respondendo pela mesma porta', () {
      // `stopReason` soma as duas famílias de recusa: quem já parava por
      // `blocker` não pode ter passado a escapar.
      final result = check(simulation(), v: version(isOpen: false));

      expect(result.stopReason, equals(result.blocker));
      expect(result.stopReason, isNotNull);
    });

    test('a simulação refeita preserva id, dono e produtor', () {
      final result = check(
        simulation(id: 'sim-7', versionCode: 'S2026.01', taxRegime: TaxRegime.folha),
        v: version(code: 'S2026.03'),
      );

      // Refazer a conta com a tabela nova não desfaz a escolha de imposto: ela
      // é do fechamento, não da tabela de valores.
      expect(result.rebuilt.taxRegime, TaxRegime.folha);

      // Refazer é atualizar a MESMA simulação, não criar outra: o id que a lista
      // usa para reescrever e apagar precisa continuar o mesmo.
      expect(result.rebuilt.id, 'sim-7');
      expect(result.rebuilt.consultantId, '2');
      expect(result.rebuilt.producerId, '10');
      expect(result.rebuilt.createdAt, DateTime(2026, 3, 1));
    });
  });
}
