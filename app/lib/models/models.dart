enum UserRole { admin, seller }

class UserModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String branch;
  final UserRole role;
  final String avatarInitials;
  final DateTime createdAt;
  final int totalBarters;
  final double totalSacks;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.branch,
    required this.role,
    required this.avatarInitials,
    required this.createdAt,
    this.totalBarters = 0,
    this.totalSacks = 0,
  });
}

/// Produtor (cliente) designado a uma permuta. NÃO loga no app — é cadastrado
/// e selecionado pelo vendedor ao registrar cada permuta. É o dono dos grãos
/// que pagarão os insumos.
class ProducerModel {
  final String id;
  final String name;

  /// Vendedor dono da CARTEIRA a que este produtor pertence. Cada produtor
  /// pertence a exatamente um vendedor: o vendedor só vê (e permuta com) os
  /// produtores da própria carteira; o admin vê todas as carteiras.
  final String sellerId;

  /// CPF ou CNPJ.
  final String document;
  final String phone;

  /// Nome da propriedade (ex.: "Fazenda Boa Vista").
  final String farmName;

  /// Município/UF (ex.: "Maringá/PR").
  final String city;

  /// Área cultivável da propriedade, em hectares. É a base de cálculo das
  /// exigências mínimas de insumo: cada insumo com taxa por hectare exige, no
  /// mínimo, `taxa × areaHa` na permuta deste produtor.
  final double areaHa;
  final String avatarInitials;
  final DateTime createdAt;

  const ProducerModel({
    required this.id,
    required this.name,
    required this.sellerId,
    required this.document,
    required this.phone,
    required this.farmName,
    required this.city,
    required this.areaHa,
    required this.avatarInitials,
    required this.createdAt,
  });

  /// Localização resumida (ex.: "Fazenda Boa Vista – Maringá/PR").
  String get location => '$farmName – $city';

  /// Área formatada (ex.: "120 ha" / "85,5 ha").
  String get areaLabel {
    final s = areaHa == areaHa.roundToDouble()
        ? areaHa.toStringAsFixed(0)
        : areaHa.toStringAsFixed(1).replaceAll('.', ',');
    return '$s ha';
  }
}

/// Em uma permuta (escambo) existem dois tipos de produto: o insumo que o
/// produtor RETIRA agora (o que ele precisa para plantar) e o grão com que ele
/// PAGA esses insumos, entregue na colheita. O insumo é a origem da permuta; o
/// grão é o pagamento — e a quantidade de sacas é consequência do custo dos insumos.
enum ProductType { grain, input }

enum BarterStatus { pending, approved, denied }

/// Item de uma permuta. Serve tanto para o grão entregue quanto para o
/// insumo retirado. [unitValue] é o valor de referência (R$) por unidade no
/// momento da permuta — é o que permite converter grão em insumo.
class BarterItem {
  final String productId;
  final String productName;
  final String unit;
  final double quantity;
  final double unitValue;

  const BarterItem({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.unitValue,
  });

  /// Valor total de troca deste item (R$).
  double get total => quantity * unitValue;
}

/// Uma permuta: o produtor RETIRA os insumos de que precisa e os PAGA com um
/// único grão. Primeiro montam-se os insumos (o custo), depois calcula-se
/// quantas sacas do grão escolhido cobrem esse custo — esse é o coração do escambo.
class BarterModel {
  final String id;
  // Vendedor: usuário que registrou a permuta (loga no app).
  final String sellerId;
  final String sellerName;
  final String sellerBranch;
  // Produtor: cliente designado pelo vendedor, dono dos grãos que pagam.
  final String producerId;
  final String producerName;
  final BarterStatus status;
  final List<BarterItem> grains;
  final List<BarterItem> inputs;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? adminNote;
  final String? reviewedBy;

  const BarterModel({
    required this.id,
    required this.sellerId,
    required this.sellerName,
    required this.sellerBranch,
    required this.producerId,
    required this.producerName,
    required this.status,
    required this.grains,
    required this.inputs,
    required this.createdAt,
    this.updatedAt,
    this.adminNote,
    this.reviewedBy,
  });

  /// Custo dos insumos retirados (R$) — é o valor que a permuta precisa pagar.
  double get inputCost => inputs.fold(0.0, (sum, i) => sum + i.total);

  /// Valor pago em grãos (R$). Calculado para cobrir o custo dos insumos, então
  /// normalmente é igual a [inputCost].
  double get grainCredit => grains.fold(0.0, (sum, i) => sum + i.total);

  /// Folga do pagamento (R$): grãos pagos menos custo dos insumos. ~0 quando o
  /// pagamento cobre exatamente os insumos; nunca deveria ficar negativo.
  double get balance => grainCredit - inputCost;

  /// Total de sacas do grão de pagamento a entregar.
  double get totalGrainQty => grains.fold(0.0, (sum, i) => sum + i.quantity);

  /// Total de unidades de insumos retiradas.
  double get totalInputQty => inputs.fold(0.0, (sum, i) => sum + i.quantity);

  /// Grão de pagamento da permuta. Escolhe-se um único grão; havendo mais de um
  /// (dados legados), usa-se o de maior valor como referência. Não fica preso à soja.
  BarterItem? get dominantGrain {
    BarterItem? best;
    double bestVal = -1;
    for (final g in grains) {
      if (g.total > bestVal) {
        bestVal = g.total;
        best = g;
      }
    }
    return best;
  }

  /// Nome do grão de pagamento (ex.: "Soja"). Vazio se nenhum foi escolhido.
  String get referenceGrainName => dominantGrain?.productName ?? '';

  /// Valor (R$) de uma saca do grão de pagamento.
  double get referenceValue => dominantGrain?.unitValue ?? 0;

  /// Sacas do grão de pagamento necessárias para cobrir o custo dos insumos — o
  /// coração da permuta: "quantas sacas o produtor precisa entregar para pagar".
  double get sacksToDeliver => referenceValue > 0 ? inputCost / referenceValue : 0;

  /// Valor pago em grãos, expresso em sacas do grão de pagamento.
  double get grainCreditInSacks => referenceValue > 0 ? grainCredit / referenceValue : 0;

  /// Custo dos insumos expresso em sacas do grão de pagamento (= [sacksToDeliver]).
  double get inputCostInSacks => referenceValue > 0 ? inputCost / referenceValue : 0;

  /// Folga do pagamento expressa em sacas do grão de pagamento (~0).
  double get balanceInSacks => referenceValue > 0 ? balance / referenceValue : 0;

  String get statusLabel {
    switch (status) {
      case BarterStatus.pending:
        return 'Em Análise';
      case BarterStatus.approved:
        return 'Aprovada';
      case BarterStatus.denied:
        return 'Negada';
    }
  }
}

class ProductModel {
  final String id;
  final String name;
  final String unit;

  /// Valor de referência em R$ por unidade, definido pelo administrador.
  /// É a "taxa de câmbio" que converte o custo dos insumos em sacas de grão.
  final double currentPrice;
  final ProductType type;
  final List<PriceHistoryEntry> priceHistory;

  /// Exigência mínima do insumo por hectare, definida pelo admin (0 = sem
  /// exigência). Em uma permuta, o produtor é obrigado a retirar no mínimo
  /// `requiredPerHa × areaHa` deste insumo. Só faz sentido para insumos.
  final double requiredPerHa;

  /// "Pasta" a que o insumo pertence (ex.: Defensivos, Fertilizantes), ou null
  /// se não foi classificado. Só faz sentido para insumos. A categoria pode
  /// carregar uma regra de mínimo que trava o envio da permuta. Ver
  /// [InputCategoryModel].
  final String? categoryId;

  const ProductModel({
    required this.id,
    required this.name,
    required this.unit,
    required this.currentPrice,
    required this.type,
    required this.priceHistory,
    this.requiredPerHa = 0,
    this.categoryId,
  });
}

/// Como a exigência mínima de uma categoria de insumos é calculada.
enum CategoryRuleType {
  /// Sem exigência: a categoria é só um agrupamento.
  none,

  /// A categoria deve representar no mínimo X% do custo total dos insumos da
  /// permuta. [InputCategoryModel.ruleValue] é o percentual (ex.: 10 = 10%).
  percentOfTotal,

  /// A categoria exige no mínimo `ruleValue × areaHa` em valor (R$). Generaliza
  /// o `requiredPerHa` por produto para a pasta inteira. [ruleValue] é R$/ha.
  valuePerHa,
}

/// "Pasta" de insumos (ex.: Defensivos, Fertilizantes). Agrupa produtos e pode
/// carregar uma regra de mínimo que funciona como gatilho para fechar a permuta:
/// enquanto o mínimo da pasta não é atingido, o vendedor não consegue enviar.
///
/// A regra é o percentual/valor VIGENTE, editável pelo admin a cada período
/// (ex.: 2% numa semana, 3% na outra). Não há calendário: o admin troca o valor
/// quando o período vira.
class InputCategoryModel {
  final String id;
  final String name;
  final CategoryRuleType ruleType;

  /// Percentual (0–100) quando [ruleType] é [CategoryRuleType.percentOfTotal];
  /// valor em R$ por hectare quando [CategoryRuleType.valuePerHa]; ignorado
  /// quando [CategoryRuleType.none].
  final double ruleValue;

  const InputCategoryModel({
    required this.id,
    required this.name,
    this.ruleType = CategoryRuleType.none,
    this.ruleValue = 0,
  });

  /// A categoria tem uma exigência ativa que pode travar o envio da permuta.
  bool get hasRule => ruleType != CategoryRuleType.none && ruleValue > 0;

  /// Descrição da regra para o ADMIN (pode citar R$, diferente do vendedor).
  String get ruleLabelAdmin {
    switch (ruleType) {
      case CategoryRuleType.none:
        return 'Sem exigência';
      case CategoryRuleType.percentOfTotal:
        return 'Mín. ${_fmtNum(ruleValue)}% do valor total da permuta';
      case CategoryRuleType.valuePerHa:
        return 'Mín. R\$ ${_fmtNum(ruleValue)}/ha';
    }
  }

  static String _fmtNum(double v) {
    final s = v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(2);
    return s.replaceAll('.', ',');
  }
}

class PriceHistoryEntry {
  final double price;
  final DateTime changedAt;
  final String changedBy;

  const PriceHistoryEntry({
    required this.price,
    required this.changedAt,
    required this.changedBy,
  });
}
