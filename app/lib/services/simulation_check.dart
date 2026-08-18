import '../models/barter_simulation.dart';
import '../models/models.dart';
import 'barter_math.dart';

/// Como terminou o envio de uma simulação. São TRÊS desfechos, e não dois:
/// além de registrada e recusada existe o incerto — o envio cuja resposta se
/// perdeu, em que ninguém pode afirmar se a permuta entrou. Espremer o incerto
/// dentro de "falhou" é o que faria o consultor tocar "Enviar" de novo e criar
/// uma permuta duplicada. Ver `AppData.sendSimulation`.
class SendResult {
  /// A permuta registrada, quando existe uma.
  final BarterModel? barter;

  /// A permuta já estava no servidor: o que se perdeu foi só a resposta do
  /// envio anterior. Vale contar isso ao consultor — ele viu um erro antes.
  final bool reconciled;

  /// A recusa do servidor, em pt-BR e pronta para exibir.
  final String? refusal;

  /// Não deu para saber se a permuta entrou. A simulação FICA, e a tela manda
  /// conferir a lista antes de reenviar.
  final String? uncertainReason;

  const SendResult._({
    this.barter,
    this.reconciled = false,
    this.refusal,
    this.uncertainReason,
  });

  factory SendResult.sent(BarterModel barter, {bool reconciled = false}) =>
      SendResult._(barter: barter, reconciled: reconciled);

  factory SendResult.refused(String message) => SendResult._(refusal: message);

  factory SendResult.uncertain(String message) =>
      SendResult._(uncertainReason: message);

  bool get isSent => barter != null;
  bool get isUncertain => uncertainReason != null;
}

/// O que aconteceu com uma simulação entre montar e enviar.
///
/// Uma simulação pode ficar dias parada no aparelho, e nesse tempo o Barter pode
/// ter virado, o produtor pode ter saído da carteira e a unidade pode ter sido
/// desativada. Esta é a conferência que roda ANTES do `POST`, com os dados
/// recém-baixados — e o motivo dela é simples: o consultor combinou um número de
/// sacas com o produtor, e ele não pode descobrir pelo comprovante que o número
/// registrado foi outro.
///
/// A conferência é sobre o RESULTADO, não sobre a causa. Trocar a versão do
/// Barter é de longe o motivo mais comum de a conta mudar, mas quem decide se há
/// algo a avisar é a comparação das sacas: qualquer caminho que mude o número
/// cai na mesma pergunta ao consultor, e nenhum passa despercebido por não ter
/// sido previsto aqui.
class SimulationCheck {
  /// Por que esta simulação NÃO pode ser enviada agora, ou null se pode.
  ///
  /// São as condições que o servidor recusaria de todo jeito. Descobri-las aqui
  /// não é desconfiança do servidor: é dizer ao consultor o que houve, em vez de
  /// gastar o envio para receber um 422 com a mesma informação.
  final String? blocker;

  /// A simulação REFEITA na tabela vigente: mesmos produtos e quantidades, sacas
  /// recalculadas, `versionCode` do Barter de agora.
  ///
  /// É ela que vai para o envio e é ela que substitui a simulação guardada — o
  /// consultor pediu para permutar estes insumos, e é no Barter de hoje que isso
  /// acontece.
  final BarterSimulation rebuilt;

  /// Insumos que a simulação tinha e que o Barter vigente não precifica.
  ///
  /// Não dá para refazê-los: sem valor acordado nesta gestão, o insumo
  /// simplesmente não é permutável — o servidor recusa a permuta inteira por
  /// causa dele. Aparecem por nome para o consultor decidir o que fazer.
  final List<SimulationItem> dropped;

  /// A versão em que a simulação foi montada, quando ela não é mais a vigente.
  final String? previousVersionCode;

  /// As sacas que a simulação mostrava ANTES desta conferência — o número que o
  /// consultor combinou com o produtor.
  final double simulatedSacks;

  const SimulationCheck._({
    this.blocker,
    required this.rebuilt,
    required this.simulatedSacks,
    this.dropped = const [],
    this.previousVersionCode,
  });

  /// As sacas recalculadas com a tabela vigente — o que será registrado.
  double get currentSacks => rebuilt.simulatedSacks;

  bool get canSend => blocker == null && dropped.isEmpty;

  /// O Barter virou desde que a simulação foi montada.
  bool get versionChanged => previousVersionCode != null;

  /// As sacas mudaram o bastante para o consultor precisar saber.
  ///
  /// A tolerância é a da própria EXIBIÇÃO: abaixo dela os dois números aparecem
  /// iguais na tela, e alarmar sobre uma diferença que ninguém enxerga só
  /// ensinaria o consultor a confirmar sem ler.
  bool get sacksChanged => (currentSacks - simulatedSacks).abs() >= 0.05;

  /// Vale interromper o envio para o consultor conferir?
  bool get needsReview => versionChanged || sacksChanged || dropped.isNotEmpty;
}

/// Confere uma simulação contra os dados vigentes e a refaz no Barter de hoje.
///
/// Recebe tudo de fora, e de propósito: a conferência é a parte que precisa ser
/// verdadeira sob condições que não dá para reproduzir com o app aberto — Barter
/// encerrado, insumo retirado da tabela, produtor fora da carteira. Como função
/// pura ela é testável linha a linha; quem busca os dados frescos na API é
/// `AppData.reviewSimulation`.
SimulationCheck checkSimulation(
  BarterSimulation simulation, {
  required BarterVersionModel? version,
  required bool producerInWallet,
  required bool unitExists,
}) {
  // A ordem das recusas é a ordem em que elas fazem o consultor perder tempo. O
  // Barter fechado vem primeiro porque atinge TODAS as simulações dele de uma
  // vez: não adianta mandar corrigir o produtor de uma se nenhuma vai sair hoje.
  if (version == null || !version.isOpen) {
    return _blocked(
      simulation,
      'O Barter está fechado no momento. Sua simulação continua guardada e pode '
      'ser enviada assim que o próximo for publicado.',
    );
  }
  if (!producerInWallet) {
    return _blocked(
      simulation,
      '${simulation.producerName} não está mais na sua carteira. Fale com o '
      'administrador ou monte a permuta para outro produtor.',
    );
  }
  if (!unitExists) {
    return _blocked(
      simulation,
      'A unidade de retirada ${simulation.unitName} não está mais disponível. '
      'Abra a simulação e escolha outra.',
    );
  }

  // Refaz a simulação com a TABELA DE AGORA. Os insumos e as quantidades são os
  // que o consultor escolheu — o que muda é quanto eles custam, e portanto
  // quantas sacas os cobrem.
  final priced = <PricedInput>[];
  final dropped = <SimulationItem>[];
  for (final item in simulation.items) {
    final price = version.priceOf(item.productId);
    if (price == null) {
      dropped.add(item);
      continue;
    }
    priced.add(PricedInput(
      productId: item.productId,
      quantity: item.quantity,
      unitPrice: price.price,
    ));
  }

  final sacks = sacksToCover(inputCost(priced), version.grainPrice);
  final rebuilt = simulation.copyWith(
    versionCode: version.code,
    simulatedSacks: sacks,
    grainName: version.grainName,
    updatedAt: DateTime.now(),
  );

  return SimulationCheck._(
    rebuilt: rebuilt,
    dropped: dropped,
    previousVersionCode:
        simulation.versionCode.isNotEmpty && simulation.versionCode != version.code
            ? simulation.versionCode
            : null,
    simulatedSacks: simulation.simulatedSacks,
  );
}

SimulationCheck _blocked(BarterSimulation simulation, String reason) =>
    SimulationCheck._(
      blocker: reason,
      rebuilt: simulation,
      simulatedSacks: simulation.simulatedSacks,
    );
