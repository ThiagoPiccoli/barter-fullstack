/// Papéis do sistema. Os nomes técnicos são os MESMOS que a API grava em
/// `user.role` (ver api/src/common/roles.ts) — este enum é a tradução deles
/// para o app, e não uma segunda lista para manter em dia de cabeça.
enum UserRole {
  admin('admin', 'Administrador'),
  manager('manager', 'Gerente'),
  committee('committee', 'Comitê'),
  biller('biller', 'Faturista'),
  consultant('consultant', 'Consultor');

  /// Valor gravado no banco e trafegado no JSON.
  final String wire;

  /// Nome que a pessoa lê na tela.
  final String label;

  const UserRole(this.wire, this.label);

  /// Papéis de RETAGUARDA: acompanham a operação inteira, sem carteira própria.
  /// Espelha BACK_OFFICE_ROLES da API, que é quem decide o escopo de verdade.
  bool get isBackOffice => this != UserRole.consultant;

  /// Papel vindo da API. Um valor desconhecido (servidor mais novo que o app)
  /// cai em [consultant], que é o papel de MENOS alcance — errar para menos
  /// deixa a tela pobre; errar para mais abriria o painel de quem manda.
  static UserRole fromWire(Object? value) => UserRole.values.firstWhere(
        (role) => role.wire == value,
        orElse: () => UserRole.consultant,
      );
}

/// Conversões defensivas do JSON da API: números podem chegar como int/double
/// e ids são expostos como String para o restante do app.
double _asDouble(dynamic v) => v == null ? 0 : (v as num).toDouble();
String _asId(dynamic v) => v == null ? '' : v.toString();
DateTime _asDate(dynamic v) => DateTime.parse(v as String).toLocal();
DateTime? _asDateOrNull(dynamic v) => v == null ? null : _asDate(v);

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

  /// Entrou com a senha provisória dada pelo admin: precisa definir a própria
  /// antes de usar o app. O servidor é quem decide isso.
  final bool mustChangePassword;

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
    this.mustChangePassword = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: _asId(json['id']),
        name: (json['fullName'] ?? json['email']) as String,
        email: json['email'] as String,
        phone: (json['phone'] ?? '') as String,
        branch: (json['branch'] ?? '') as String,
        role: UserRole.fromWire(json['role']),
        avatarInitials: (json['initials'] ?? '?') as String,
        createdAt: _asDate(json['createdAt']),
        mustChangePassword: json['mustChangePassword'] == true,
      );
}

/// Consultor recém-provisionado, com a senha de primeira entrada que o
/// servidor sorteou. Chega UMA ÚNICA VEZ — na criação do cadastro ou num
/// reset — e nunca mais pode ser lida de volta: daí em diante o servidor só
/// guarda o hash. É o valor que o admin dita para o consultor.
class ProvisionedConsultant {
  final UserModel consultant;
  final String provisionalPassword;

  const ProvisionedConsultant({
    required this.consultant,
    required this.provisionalPassword,
  });

  factory ProvisionedConsultant.fromJson(Map<String, dynamic> json) =>
      ProvisionedConsultant(
        consultant: UserModel.fromJson(json),
        provisionalPassword: (json['provisionalPassword'] ?? '') as String,
      );
}

/// Produtor (cliente) designado a uma permuta. NÃO loga no app — é cadastrado
/// e selecionado pelo consultor ao registrar cada permuta. É o dono dos grãos
/// que pagarão os insumos.
class ProducerModel {
  final String id;
  final String name;

  /// Consultor dono da CARTEIRA a que este produtor pertence. Cada produtor
  /// pertence a exatamente um consultor: o consultor só vê (e permuta com) os
  /// produtores da própria carteira; o admin vê todas as carteiras.
  final String consultantId;

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
    required this.consultantId,
    required this.document,
    required this.phone,
    required this.farmName,
    required this.city,
    required this.areaHa,
    required this.avatarInitials,
    required this.createdAt,
  });

  factory ProducerModel.fromJson(Map<String, dynamic> json) => ProducerModel(
        id: _asId(json['id']),
        name: json['name'] as String,
        // '' quando o consultor da carteira foi excluído (aguarda realocação).
        consultantId: _asId(json['consultantId']),
        document: json['document'] as String,
        phone: (json['phone'] ?? '') as String,
        farmName: json['farmName'] as String,
        city: json['city'] as String,
        areaHa: _asDouble(json['areaHa']),
        avatarInitials: (json['initials'] ?? '?') as String,
        createdAt: _asDate(json['createdAt']),
      );

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

/// Status vindo do servidor, tolerante ao desconhecido.
///
/// `BarterStatus.values.byName` LANÇA num nome que não existe: bastaria o
/// servidor ganhar um status novo (uma permuta cancelada, por exemplo) para a
/// lista inteira parar de carregar nas versões do app já instaladas — uma tela
/// vazia no lugar de todas as permutas.
///
/// Um status que o app não conhece cai em "em análise": o registro continua
/// visível, e quem decide se ele aceita ação continua sendo o servidor, que
/// recusa revisar o que não está pendente.
BarterStatus _asStatus(dynamic v) {
  for (final status in BarterStatus.values) {
    if (status.name == v) return status;
  }
  return BarterStatus.pending;
}

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

  factory BarterItem.fromJson(Map<String, dynamic> json) => BarterItem(
        productId: _asId(json['productId']),
        productName: json['productName'] as String,
        unit: json['unit'] as String,
        quantity: _asDouble(json['quantity']),
        unitValue: _asDouble(json['unitValue']),
      );

  /// Valor total de troca deste item (R$).
  double get total => quantity * unitValue;
}

/// Uma permuta: o produtor RETIRA os insumos de que precisa e os PAGA com um
/// único grão. Primeiro montam-se os insumos (o custo), depois calcula-se
/// quantas sacas do grão escolhido cobrem esse custo — esse é o coração do escambo.
class BarterModel {
  final String id;
  // Consultor: usuário que registrou a permuta (loga no app).
  final String consultantId;
  final String consultantName;
  final String consultantBranch;
  // Produtor: cliente designado pelo consultor, dono dos grãos que pagam.
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
    required this.consultantId,
    required this.consultantName,
    required this.consultantBranch,
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

  /// O `id` exibido no app é o código público da permuta (ex.: PRM-2026-001);
  /// os itens chegam numa lista única e são separados aqui por tipo.
  factory BarterModel.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return BarterModel(
      id: json['code'] as String,
      consultantId: _asId(json['consultantId']),
      consultantName: json['consultantName'] as String,
      consultantBranch: (json['consultantBranch'] ?? '') as String,
      producerId: _asId(json['producerId']),
      producerName: json['producerName'] as String,
      status: _asStatus(json['status']),
      grains: items
          .where((i) => i['kind'] == 'grain')
          .map(BarterItem.fromJson)
          .toList(),
      inputs: items
          .where((i) => i['kind'] == 'input')
          .map(BarterItem.fromJson)
          .toList(),
      createdAt: _asDate(json['createdAt']),
      updatedAt: _asDateOrNull(json['reviewedAt']),
      adminNote: json['adminNote'] as String?,
      reviewedBy: json['reviewedBy'] as String?,
    );
  }

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

  factory ProductModel.fromJson(Map<String, dynamic> json) => ProductModel(
        id: _asId(json['id']),
        name: json['name'] as String,
        unit: json['unit'] as String,
        currentPrice: _asDouble(json['currentPrice']),
        type: json['type'] == 'grain' ? ProductType.grain : ProductType.input,
        priceHistory: (json['priceHistory'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(PriceHistoryEntry.fromJson)
            .toList(),
        requiredPerHa: _asDouble(json['requiredPerHa']),
        categoryId: json['categoryId'] == null ? null : _asId(json['categoryId']),
      );
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
/// enquanto o mínimo da pasta não é atingido, o consultor não consegue enviar.
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

  factory InputCategoryModel.fromJson(Map<String, dynamic> json) =>
      InputCategoryModel(
        id: _asId(json['id']),
        name: json['name'] as String,
        // Mesmo cuidado do status: uma regra que o app não conhece não pode
        // derrubar o catálogo inteiro. Sem exigência é o padrão seguro — o
        // servidor valida os mínimos de novo no envio da permuta.
        ruleType: CategoryRuleType.values.firstWhere(
          (r) => r.name == json['ruleType'],
          orElse: () => CategoryRuleType.none,
        ),
        ruleValue: _asDouble(json['ruleValue']),
      );

  /// A categoria tem uma exigência ativa que pode travar o envio da permuta.
  bool get hasRule => ruleType != CategoryRuleType.none && ruleValue > 0;

  /// Descrição da regra para o ADMIN (pode citar R$, diferente do consultor).
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

  factory PriceHistoryEntry.fromJson(Map<String, dynamic> json) =>
      PriceHistoryEntry(
        price: _asDouble(json['price']),
        changedAt: _asDate(json['changedAt']),
        changedBy: json['changedBy'] as String,
      );
}
