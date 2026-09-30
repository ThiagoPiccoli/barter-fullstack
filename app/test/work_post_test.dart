import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/services/work_post.dart';

/// O POSTO DE CADA UM NA LINHA — a regra, sem a tela.
///
/// Ela morava dentro de uma classe privada do painel da retaguarda, misturada
/// com cor, ícone e texto de botão. O que estes casos guardam é o que a mistura
/// escondia: o posto sai da CAPACIDADE (e não do nome do papel), cada fila é a
/// do seu dono, e a etapa que cada um acompanha é a VIZINHA dele — nunca uma
/// que ele não possa abrir.
void main() {
  UserModel pessoa(Set<String> capacidades, {String id = '7'}) => UserModel(
        id: id,
        name: 'Fulano',
        email: 'fulano@agrobarter.com.br',
        role: UserRole.manager,
        phone: '',
        branch: 'Filial 02',
        unitId: '1',
        avatarInitials: 'FL',
        createdAt: DateTime(2024, 1, 1),
        mustChangePassword: false,
        capabilities: capacidades,
      );

  BarterModel barter(String id, BarterStatus status, {String managerId = '7'}) => BarterModel(
        id: id,
        consultantId: '2',
        consultantName: 'João Silva',
        consultantBranch: 'Filial 02',
        producerId: '10',
        producerName: 'Antônio Carvalho',
        status: status,
        createdAt: DateTime(2026, 3, 1),
        managerId: managerId,
        grains: const [],
        inputs: const [],
      );

  group('quem ocupa cada posto', () {
    test('o posto sai da capacidade, e não do nome do papel', () {
      expect(workPostOf(pessoa({Capability.bartersOpinion})), WorkPost.manager);
      expect(workPostOf(pessoa({Capability.bartersReview})), WorkPost.committee);
      expect(workPostOf(pessoa({Capability.bartersInvoice})), WorkPost.biller);
      expect(workPostOf(pessoa({Capability.bartersCprIssue})), WorkPost.emitter);
    });

    test('quem não age na linha não tem posto', () {
      expect(workPostOf(pessoa({Capability.producersManage, Capability.pricesRead})), isNull);
      expect(workPostOf(pessoa(const {})), isNull);
      expect(workPostsOf(pessoa(const {})), isEmpty);
    });

    /// O ADMIN ocupa os quatro postos, na ordem da linha.
    test('quem tem as quatro capacidades ocupa os quatro postos', () {
      final todos = pessoa({
        Capability.bartersOpinion,
        Capability.bartersReview,
        Capability.bartersInvoice,
        Capability.bartersCprIssue,
      });
      expect(workPostsOf(todos), [
        WorkPost.manager,
        WorkPost.committee,
        WorkPost.biller,
        WorkPost.emitter,
      ]);
    });

    /// Acumulando capacidades, vale a etapa MAIS CEDO da linha: o trabalho que
    /// ela segura é o que trava a esteira antes.
    test('quem acumula capacidades aparece no posto mais cedo', () {
      expect(
        workPostOf(pessoa({Capability.bartersOpinion, Capability.bartersReview})),
        WorkPost.manager,
      );
    });
  });

  group('a fila de cada posto', () {
    final barters = [
      barter('gerente-meu', BarterStatus.sentToManager),
      barter('gerente-de-outro', BarterStatus.sentToManager, managerId: '99'),
      barter('comite', BarterStatus.pending),
      barter('a-faturar', BarterStatus.approved),
      barter('faturada', BarterStatus.invoiced),
      barter('emitida', BarterStatus.cprIssued),
      barter('registrada', BarterStatus.cprRegistered),
    ];

    /// A DO GERENTE É A ÚNICA COM DESTINATÁRIO: o parecer é dele, e a permuta de
    /// outro time não é assunto dele.
    test('a do gerente traz só as endereçadas a ele', () {
      final fila = queueOf(WorkPost.manager, barters, managerId: '7');
      expect(fila.map((b) => b.id), ['gerente-meu']);
    });

    /// Sem destinatário, é a fila de TODOS os gerentes — a do admin.
    test('sem gerente, a fila do parecer traz todas as que esperam parecer', () {
      final fila = queueOf(WorkPost.manager, barters, managerId: null);
      expect(fila.map((b) => b.id), ['gerente-meu', 'gerente-de-outro']);
    });

    test('a do comitê e a do faturista são o ESTADO da permuta', () {
      expect(queueOf(WorkPost.committee, barters).map((b) => b.id), ['comite']);
      expect(queueOf(WorkPost.biller, barters).map((b) => b.id), ['a-faturar']);
    });

    /// A DO EMISSOR TEM OS TRÊS DEGRAUS da cédula: emitir, assinar e registrar
    /// acontecem em dias diferentes, e uma fila com só "a emitir" esconderia as
    /// cédulas assinadas paradas esperando cartório.
    test('a do emissor cobre o trecho inteiro da cédula', () {
      final fila = queueOf(WorkPost.emitter, barters).map((b) => b.id);
      expect(fila, containsAll(['faturada', 'emitida']));
      // A REGISTRADA saiu: ela acabou, e fila é o que espera alguém.
      expect(fila, isNot(contains('registrada')));
    });
  });

  group('a etapa vizinha', () {
    /// Quem empurra a permuta adiante acompanha a SEGUINTE; quem é fim de linha
    /// acompanha o que já concluiu. O COMITÊ é o único que olha para TRÁS — o
    /// que está no gerente é a fila que vai cair na mesa dele.
    test('cada posto acompanha a etapa vizinha dele', () {
      expect(followStatusOf(WorkPost.manager), BarterStatus.pending);
      expect(followStatusOf(WorkPost.committee), BarterStatus.sentToManager);
      expect(followStatusOf(WorkPost.biller), BarterStatus.invoiced);
      expect(followStatusOf(WorkPost.emitter), BarterStatus.cprRegistered);
    });

    test('o segundo número do painel conta a etapa vizinha', () {
      final barters = [
        barter('a', BarterStatus.pending),
        barter('b', BarterStatus.pending),
        barter('c', BarterStatus.invoiced),
      ];

      expect(followCountOf(WorkPost.manager, barters), 2);
      expect(followCountOf(WorkPost.biller, barters), 1);
    });
  });
}
