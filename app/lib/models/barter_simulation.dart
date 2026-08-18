import '../services/tax_regime.dart';

/// Um insumo dentro de uma simulação, com o nome congelado.
///
/// O nome e a unidade são SNAPSHOT porque a simulação precisa se explicar sem
/// rede: o catálogo do `AppData` é hidratado da API no login, e sem ele a lista
/// mostraria uma coluna de ids. O que vai no envio é só `productId` e
/// `quantity` — o resto o servidor regrava a partir do cadastro dele.
class SimulationItem {
  final String productId;
  final String productName;
  final String unit;
  final double quantity;

  const SimulationItem({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.quantity,
  });

  SimulationItem copyWith({double? quantity}) => SimulationItem(
        productId: productId,
        productName: productName,
        unit: unit,
        quantity: quantity ?? this.quantity,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'unit': unit,
        'quantity': quantity,
      };

  factory SimulationItem.fromJson(Map<String, dynamic> json) => SimulationItem(
        productId: '${json['productId'] ?? ''}',
        productName: '${json['productName'] ?? ''}',
        unit: '${json['unit'] ?? ''}',
        quantity: BarterSimulation.toQuantity(json['quantity']),
      );
}

/// Uma permuta SIMULADA e guardada no aparelho — o carrinho do consultor.
///
/// Toda permuta passa por aqui. O consultor monta a simulação na fazenda, onde
/// pode não haver sinal, e ela fica gravada no aparelho: montar e guardar não
/// falam com o servidor em momento algum. Só o ENVIO fala — e é ele que checa se
/// o serviço responde, se o Barter continua aberto e se a conta ainda é a que
/// foi simulada.
///
/// ## Simulação não é permuta, e a diferença é o ponto
///
/// Nada aqui vale como acordo. Os números que ela mostra são os do dia em que
/// foi montada — daí o nome [simulatedSacks] — e o que vale é o que o servidor
/// devolve no envio, calculado com a tabela daquele instante.
///
/// Guardar o número simulado não é redundância: é o que permite PERCEBER que a
/// conta mudou entre montar e enviar. Uma simulação parada por semanas atravessa
/// a troca de versão do Barter, e nesse caso ela é refeita com os mesmos
/// produtos na tabela vigente — o consultor vê o número novo antes de mandar,
/// em vez de descobrir pelo comprovante. Ver `SimulationCheck`.
class BarterSimulation {
  /// Id LOCAL, gerado no aparelho. Não é o `PRM-AAAA-NNN`: esse é público, e
  /// quem o reserva é o servidor, no envio. Uma simulação não tem código de
  /// permuta porque ainda não é uma permuta.
  final String id;

  /// A quem esta simulação pertence. O aparelho pode ser compartilhado (ou
  /// passar de mão), e a simulação de um consultor não é assunto do próximo a
  /// logar — nem poderia ser enviada por ele, já que a permuta nasce em nome de
  /// quem a registra.
  final String consultantId;

  final String producerId;
  final String producerName;
  final String unitId;
  final String unitName;

  /// A versão do Barter em que a simulação foi montada. É o que diz, no envio,
  /// se ela atravessou uma troca de Barter — e o que a tela mostra ao explicar
  /// por que o número mudou.
  final String versionCode;

  /// Os insumos simulados, com nome congelado para a lista funcionar sem rede.
  final List<SimulationItem> items;

  /// As sacas que a simulação mostrou, com a tabela do dia em que foi montada.
  /// É o número que o consultor falou para o produtor — e a referência contra a
  /// qual o envio confere se a conta mudou.
  final double simulatedSacks;

  /// O grão em que a simulação foi paga, para o cartão dizer "sc de soja" sem
  /// depender do catálogo carregado.
  final String grainName;

  /// COMO o Funrural desta entrega vai ser recolhido — a escolha do fechamento,
  /// entre a comercialização e a folha de pagamento. Ver
  /// `services/tax_regime.dart`.
  ///
  /// Fica na simulação porque é lá que a escolha é feita: o consultor fecha a
  /// conta com o produtor na fazenda, e essa decisão precisa sobreviver ao
  /// aparelho ficar guardado até o envio. Quem grava a alíquota que ela produz é
  /// o servidor, no envio.
  final TaxRegime taxRegime;

  final DateTime createdAt;
  final DateTime updatedAt;

  const BarterSimulation({
    required this.id,
    required this.consultantId,
    required this.producerId,
    required this.producerName,
    required this.unitId,
    required this.unitName,
    required this.versionCode,
    required this.items,
    required this.simulatedSacks,
    this.grainName = '',
    this.taxRegime = TaxRegime.comercializacao,
    required this.createdAt,
    required this.updatedAt,
  });

  BarterSimulation copyWith({
    String? versionCode,
    List<SimulationItem>? items,
    double? simulatedSacks,
    String? grainName,
    TaxRegime? taxRegime,
    DateTime? updatedAt,
  }) =>
      BarterSimulation(
        id: id,
        consultantId: consultantId,
        producerId: producerId,
        producerName: producerName,
        unitId: unitId,
        unitName: unitName,
        versionCode: versionCode ?? this.versionCode,
        items: items ?? this.items,
        simulatedSacks: simulatedSacks ?? this.simulatedSacks,
        grainName: grainName ?? this.grainName,
        taxRegime: taxRegime ?? this.taxRegime,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// O payload do envio: só id e quantidade. Nome, unidade e preço são do
  /// servidor — ele os regrava a partir do cadastro e da tabela da versão.
  Map<String, double> get inputQuantities => {
        for (final item in items) item.productId: item.quantity,
      };

  int get inputCount => items.length;

  /// Um id local novo. O relógio em microssegundos basta porque o único
  /// concorrente é o próprio consultor tocando "Salvar" — não há duas fontes
  /// gerando ids para esta lista, e ela nunca sai deste aparelho.
  static String newId() =>
      'sim-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'consultantId': consultantId,
        'producerId': producerId,
        'producerName': producerName,
        'unitId': unitId,
        'unitName': unitName,
        'versionCode': versionCode,
        'items': [for (final item in items) item.toJson()],
        'simulatedSacks': simulatedSacks,
        'grainName': grainName,
        'taxRegime': taxRegime.apiValue,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Lê uma simulação gravada por uma versão ANTERIOR do app.
  ///
  /// Tolerante de propósito, e mais do que o parse da API: aqui o dado é do
  /// próprio consultor, foi montado offline e pode ser a única cópia do trabalho
  /// de uma tarde. Campo que sumiu vira vazio, número gravado como texto é
  /// convertido — e a simulação continua abrindo. Só falta de `id` derruba a
  /// linha (ver `SimulationStorage.load`): sem ele não há o que reescrever nem
  /// apagar.
  factory BarterSimulation.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = <SimulationItem>[];
    if (rawItems is List) {
      for (final row in rawItems) {
        if (row is! Map) continue;
        final item = SimulationItem.fromJson(Map<String, dynamic>.from(row));
        // Quantidade zerada, negativa ou ilegível não é insumo escolhido — e uma
        // delas chegando ao payload faria o servidor recusar a permuta inteira.
        if (item.productId.isNotEmpty && item.quantity > 0) items.add(item);
      }
    }
    return BarterSimulation(
      id: json['id'] as String,
      consultantId: '${json['consultantId'] ?? ''}',
      producerId: '${json['producerId'] ?? ''}',
      producerName: '${json['producerName'] ?? ''}',
      unitId: '${json['unitId'] ?? ''}',
      unitName: '${json['unitName'] ?? ''}',
      versionCode: '${json['versionCode'] ?? ''}',
      items: items,
      simulatedSacks: toQuantity(json['simulatedSacks']),
      grainName: '${json['grainName'] ?? ''}',
      // Simulação montada por uma versão anterior do app não tem o campo: cai
      // na comercialização, que é o que vale para quem não fez a opção formal
      // pela folha.
      taxRegime: taxRegimeFrom(json['taxRegime']),
      createdAt: _toDate(json['createdAt']),
      updatedAt: _toDate(json['updatedAt']),
    );
  }

  static double toQuantity(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0;
    return 0;
  }

  static DateTime _toDate(dynamic v) =>
      v is String ? (DateTime.tryParse(v) ?? DateTime.now()) : DateTime.now();
}
