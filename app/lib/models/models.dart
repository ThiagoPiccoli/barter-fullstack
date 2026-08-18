import '../services/tax_regime.dart';

export '../services/tax_regime.dart' show TaxRegime, TaxRegimeApi;

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

  /// UNIDADE em que a pessoa trabalha. Vazio nos cadastros anteriores ao
  /// cadastro de unidades.
  final String unitId;

  /// Nome da unidade, congelado no cadastro. É o que as telas mostram e o que
  /// o painel agrupa nos rankings — o servidor o escreve a partir de [unitId].
  final String branch;

  /// O GERENTE desta pessoa. Só o consultor tem, e para ele é obrigatório no
  /// cadastro: é a ele que as permutas do consultor são enviadas, e é ele quem
  /// escreve o parecer técnico delas.
  ///
  /// O vínculo é com a PESSOA. A unidade de retirada é logística e não tem
  /// relação nenhuma com isto — uma permuta retirada na Filial 34 continua
  /// sendo analisada pelo gerente do consultor que a registrou.
  final String managerId;
  final String managerName;

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
    this.unitId = '',
    required this.branch,
    this.managerId = '',
    this.managerName = '',
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
        unitId: _asId(json['unitId']),
        branch: (json['branch'] ?? '') as String,
        managerId: _asId(json['managerId']),
        managerName: (json['managerName'] ?? '') as String,
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

/// UNIDADE de retirada: o lugar onde o produtor busca os insumos da permuta.
///
/// É um LOCAL, e só. Ela não tem responsável, não decide quem analisa a permuta
/// e não participa de regra nenhuma — quem dá o parecer técnico é o gerente do
/// CONSULTOR (ver [UserModel.managerName]), esteja a retirada onde estiver. O
/// consultor escolhe qualquer unidade da lista, porque a retirada é combinada
/// com o produtor.
///
/// Ela existe como cadastro, e não como texto, porque a filial era digitada à
/// mão: "Filial 02", "filial 02" e "F02" eram três lugares em qualquer lista.
class UnitModel {
  final String id;
  final String name;

  /// Município/UF — é o que distingue duas unidades de nome parecido na hora de
  /// escolher onde retirar.
  final String city;

  final String avatarInitials;
  final DateTime createdAt;

  const UnitModel({
    required this.id,
    required this.name,
    required this.city,
    this.avatarInitials = '?',
    required this.createdAt,
  });

  factory UnitModel.fromJson(Map<String, dynamic> json) => UnitModel(
        id: _asId(json['id']),
        name: json['name'] as String,
        city: (json['city'] ?? '') as String,
        avatarInitials: (json['initials'] ?? '?') as String,
        createdAt: _asDate(json['createdAt']),
      );

  /// A unidade como se lê numa linha só: "Filial 02 – Gran. Santa T. • Sarandi/PR".
  String get label => city.isEmpty ? name : '$name • $city';
}

/// Produtor (cliente) designado a uma permuta. NÃO loga no app — é cadastrado
/// e selecionado pelo consultor ao registrar cada permuta. É o dono dos grãos
/// que pagarão os insumos.
class ProducerModel {
  final String id;
  final String name;

  /// Os consultores que ATENDEM este produtor — a carteira dele.
  ///
  /// É lista porque consultores dividem região: o mesmo produtor pode ser
  /// atendido por vários, e todos eles o veem e permutam com ele. Cada permuta
  /// continua sendo de um consultor só — o que a registrou.
  ///
  /// Vazia quando o último consultor vinculado foi excluído: o produtor espera
  /// realocação e, até lá, só a retaguarda o enxerga.
  final List<String> consultantIds;

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
    required this.consultantIds,
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
        // Vazia quando o último consultor vinculado foi excluído (aguarda
        // realocação) — e o app precisa desenhar essa lista vazia, não quebrar.
        consultantIds:
            ((json['consultantIds'] ?? const []) as List).map(_asId).toList(),
        document: json['document'] as String,
        phone: (json['phone'] ?? '') as String,
        farmName: json['farmName'] as String,
        city: json['city'] as String,
        areaHa: _asDouble(json['areaHa']),
        avatarInitials: (json['initials'] ?? '?') as String,
        createdAt: _asDate(json['createdAt']),
      );

  /// Este consultor atende o produtor? É a pergunta que a carteira passou a
  /// responder quando deixou de ser um id só — e a que o servidor faz antes de
  /// aceitar uma permuta.
  bool isAttendedBy(String consultantId) => consultantIds.contains(consultantId);

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

/// O caminho de uma permuta, na ordem em que ela o percorre:
///
///     sentToManager → pending → approved
///                             ↘ denied
///
/// [sentToManager] é onde ela nasce: ela está na mesa do gerente do consultor,
/// esperando o parecer técnico. Escrito o parecer, ela vira [pending] — a fila
/// de REVISÃO, que é onde alguém aprova ou nega.
///
/// "Revisão" e não "análise" porque é a palavra que o resto do sistema já usa
/// para esta etapa: a rota é `POST /barters/:code/review` e os campos são
/// `reviewedBy` e `reviewedAt`. Enquanto a tela dizia "em análise", ela dava um
/// segundo nome à mesma coisa — e "análise" descrevia igualmente bem o que o
/// gerente faz, deixando as duas etapas indistinguíveis no vocabulário.
///
/// Os nomes são os MESMOS que a API grava (ver BARTER_STATUSES em
/// api/src/barters/dto/barter.dto.ts) — é o que [_asStatus] compara.
enum BarterStatus { sentToManager, pending, approved, denied }

/// Status vindo do servidor, tolerante ao desconhecido.
///
/// `BarterStatus.values.byName` LANÇA num nome que não existe: bastaria o
/// servidor ganhar um status novo (uma permuta cancelada, por exemplo) para a
/// lista inteira parar de carregar nas versões do app já instaladas — uma tela
/// vazia no lugar de todas as permutas.
///
/// Um status que o app não conhece cai em "aguardando revisão": o registro continua
/// visível, e quem decide se ele aceita ação continua sendo o servidor, que
/// recusa revisar o que não está pendente. Foi o que aconteceu quando
/// `sentToManager` nasceu: as versões instaladas do app passaram a mostrar as
/// permutas novas como "Aguardando Revisão" — impreciso, mas visível e sem ação
/// indevida, que é exatamente o que este padrão existe para dar.
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

  /// Versão do Barter em que esta permuta foi fechada (ex.: "S2026.02").
  /// Vazio nas permutas anteriores ao lançamento por versões.
  final String versionCode;
  // Consultor: usuário que registrou a permuta (loga no app).
  final String consultantId;
  final String consultantName;
  final String consultantBranch;
  // Produtor: cliente designado pelo consultor, dono dos grãos que pagam.
  final String producerId;
  final String producerName;

  /// UNIDADE em que o produtor retira os insumos. É logística: não decide quem
  /// analisa a permuta. Vazio nas permutas anteriores ao cadastro de unidades.
  final String unitId;
  final String unitName;

  final BarterStatus status;
  final List<BarterItem> grains;
  final List<BarterItem> inputs;

  /// O IMPOSTO DA ENTREGA — a entrega de grão é comercialização de produção
  /// rural, e sobre ela incidem o Funrural e o Senar.
  ///
  /// [taxRegime] é a FORMA de recolhimento escolhida no fechamento desta
  /// permuta; [taxRate] é a alíquota (%) que ela produziu.
  ///
  /// A alíquota fica congelada no registro, e não é recalculada na hora de
  /// mostrar: ela muda por lei, e o comprovante de uma permuta fechada não pode
  /// passar a mostrar outro imposto. Zero nas permutas anteriores ao campo — e
  /// aí a linha do imposto não aparece, porque não houve alíquota aplicada a
  /// elas.
  final TaxRegime taxRegime;
  final double taxRate;

  final DateTime createdAt;
  final DateTime? updatedAt;

  /// A QUEM esta permuta foi enviada — o gerente do consultor no momento do
  /// registro — e o PARECER TÉCNICO dele sobre a negociação.
  ///
  /// [managerId] e [managerName] vêm preenchidos desde a criação: são o
  /// destinatário. [managerNote] é null enquanto a permuta está em
  /// [BarterStatus.sentToManager] — é justamente o que a etapa dele preenche, e
  /// é essa diferença que [hasManagerOpinion] lê.
  ///
  /// O parecer é texto, e só texto: ele não aprova nem nega — quem decide é
  /// quem revisa, e ele lê isto antes.
  final String managerId;
  final String? managerName;
  final String? managerNote;
  final DateTime? managerReviewedAt;

  final String? adminNote;
  final String? reviewedBy;

  const BarterModel({
    required this.id,
    this.versionCode = '',
    required this.consultantId,
    required this.consultantName,
    required this.consultantBranch,
    required this.producerId,
    required this.producerName,
    this.unitId = '',
    this.unitName = '',
    required this.status,
    required this.grains,
    required this.inputs,
    this.taxRegime = TaxRegime.comercializacao,
    this.taxRate = 0,
    required this.createdAt,
    this.updatedAt,
    this.managerId = '',
    this.managerName,
    this.managerNote,
    this.managerReviewedAt,
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
      versionCode: (json['versionCode'] ?? '') as String,
      consultantId: _asId(json['consultantId']),
      consultantName: json['consultantName'] as String,
      consultantBranch: (json['consultantBranch'] ?? '') as String,
      producerId: _asId(json['producerId']),
      producerName: json['producerName'] as String,
      unitId: _asId(json['unitId']),
      unitName: (json['unitName'] ?? '') as String,
      status: _asStatus(json['status']),
      grains: items
          .where((i) => i['kind'] == 'grain')
          .map(BarterItem.fromJson)
          .toList(),
      inputs: items
          .where((i) => i['kind'] == 'input')
          .map(BarterItem.fromJson)
          .toList(),
      taxRegime: taxRegimeFrom(json['taxRegime']),
      taxRate: _asDouble(json['taxRate']),
      createdAt: _asDate(json['createdAt']),
      updatedAt: _asDateOrNull(json['reviewedAt']),
      managerId: _asId(json['managerId']),
      managerName: json['managerName'] as String?,
      managerNote: json['managerNote'] as String?,
      managerReviewedAt: _asDateOrNull(json['managerReviewedAt']),
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

  /// Esta permuta tem imposto registrado? Falso nas anteriores ao campo, e é o
  /// que as telas leem para não inventar uma linha de imposto para elas.
  bool get hasTax => taxRate > 0;

  /// Funrural/Senar sobre a entrega de grão (R$).
  ///
  /// A base é [grainCredit] — o valor do grão entregue —, e não o custo dos
  /// insumos: o que o produtor comercializa é o grão. Os dois são praticamente
  /// iguais na permuta (o pagamento cobre o custo), mas a base do imposto é a
  /// venda, e é dela que ela precisa sair.
  ///
  /// Zero para quem não vê R$: os itens chegam sem valor unitário, e é
  /// [taxInSacks] que serve a essa tela.
  double get taxAmount => taxAmountOf(grainCredit, taxRate);

  /// O mesmo imposto medido em SACAS do grão de pagamento — a unidade do
  /// consultor, que não enxerga R$ em lugar nenhum do app.
  double get taxInSacks => taxAmountOf(totalGrainQty, taxRate);

  /// A alíquota como se lê (ex.: "1,63%").
  String get taxRateLabel => '${taxRate.toStringAsFixed(2).replaceAll('.', ',')}%';

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

  /// O parecer técnico já foi escrito? É o que separa a etapa do gerente da
  /// revisão — e o que decide se o detalhe mostra o bloco do parecer.
  bool get hasManagerOpinion => (managerNote ?? '').trim().isNotEmpty;

  /// Está esperando o parecer do gerente a quem foi enviada.
  bool get awaitsManager => status == BarterStatus.sentToManager;

  /// Esta permuta espera o parecer DESTE gerente? Mesma conferência do servidor
  /// — repetida aqui só para a tela não oferecer um botão que levaria 403.
  bool awaitsOpinionFrom(String? managerId) =>
      managerId != null && managerId.isNotEmpty && awaitsManager && this.managerId == managerId;

  /// O gerente a quem ela foi enviada, como se lê na tela.
  String get managerLabel => managerName ?? '—';

  /// A unidade de retirada como se lê na tela (travessão nas permutas antigas,
  /// anteriores ao cadastro de unidades).
  String get unitLabel => unitName.isEmpty ? '—' : unitName;

  String get statusLabel {
    switch (status) {
      case BarterStatus.sentToManager:
        return 'Enviada ao Gerente';
      case BarterStatus.pending:
        return 'Aguardando Revisão';
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

  /// A linha do tempo dos reajustes — **só vem preenchida no DETALHE**
  /// (`GET /products/:id`, via [CatalogRepository.findProduct]).
  ///
  /// A listagem do catálogo não a carrega: ela ganha um ponto por produto a
  /// cada versão do Barter publicada, e o app pede o catálogo inteiro a cada
  /// login. Quem só precisa da variação e da contagem usa [firstPrice] e
  /// [priceHistoryCount], que a listagem traz. Ver [hasFullHistory].
  final List<PriceHistoryEntry> priceHistory;

  /// Primeiro valor já publicado deste produto, ou null quando não há
  /// histórico. É contra ele que se mede a variação exibida na lista.
  final double? firstPrice;

  /// Quantos pontos a linha do tempo tem — inclusive quando ela não veio.
  final int priceHistoryCount;

  /// Exigência mínima do insumo por hectare, definida pelo admin (0 = sem
  /// exigência). Em uma permuta, o produtor é obrigado a retirar no mínimo
  /// `requiredPerHa × areaHa` deste insumo. Só faz sentido para insumos.
  final double requiredPerHa;

  /// CLASSE do insumo (ex.: Herbicidas, Sementes), ou null se ele ainda não
  /// foi classificado. Só faz sentido para insumos. A classe pode carregar uma
  /// regra de mínimo que trava o envio da permuta. Ver [ProductClassModel].
  final String? classId;

  /// CÓDIGO do item (`INS-0007`, `NPK-0414`). Todo produto tem um: quando o
  /// admin não informa, o servidor gera. É por ele que a planilha do fornecedor
  /// reconhece o item já cadastrado — e é por ele que se procura na busca.
  final String? sku;

  /// O código como se lê na tela (vazio vira travessão).
  String get codeLabel => sku?.isNotEmpty == true ? sku! : '—';

  /// A UNIDADE deste item é palpite e precisa de revisão.
  ///
  /// A lista de preços não tem coluna de unidade: a embalagem sai da descrição
  /// (`emb.20 l`, `BIG-BAG`) e, quando ela não aparece, do padrão da classe. O
  /// que nem assim se resolve entra com "unidade" e marcado — melhor uma dúzia
  /// de itens pedindo revisão do que uma unidade inventada no comprovante.
  final bool unitPending;

  const ProductModel({
    required this.id,
    required this.name,
    required this.unit,
    required this.currentPrice,
    required this.type,
    required this.priceHistory,
    this.firstPrice,
    this.priceHistoryCount = 0,
    this.requiredPerHa = 0,
    this.classId,
    this.sku,
    this.unitPending = false,
  });

  /// O item atende a uma busca por nome OU por código.
  ///
  /// Mora aqui, e não em cada tela, porque a resposta precisa ser a mesma nas
  /// três listas que buscam item — se uma delas esquecer o código, quem digita
  /// "NPK-0414" acha o insumo numa tela e não acha na outra.
  bool matches(String query) {
    if (query.isEmpty) return true;
    return name.toLowerCase().contains(query) ||
        (sku ?? '').toLowerCase().contains(query);
  }

  /// A série inteira está em mãos? Falso no que veio da listagem — é o sinal
  /// de que o relatório precisa buscar o detalhe antes de desenhar o gráfico.
  bool get hasFullHistory => priceHistory.length == priceHistoryCount;

  /// Variação (%) do último valor publicado contra o primeiro da linha do
  /// tempo. Zero quando não há com que comparar. Funciona nas duas formas: a
  /// listagem manda [firstPrice] pronto, o detalhe traz a série.
  double get deltaPct {
    final first = firstPrice ?? (priceHistory.isEmpty ? null : priceHistory.first.price);
    if (first == null || first == 0) return 0;
    return (currentPrice - first) / first * 100;
  }

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final history = (json['priceHistory'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(PriceHistoryEntry.fromJson)
        .toList();
    return ProductModel(
      id: _asId(json['id']),
      name: json['name'] as String,
      unit: json['unit'] as String,
      currentPrice: _asDouble(json['currentPrice']),
      type: json['type'] == 'grain' ? ProductType.grain : ProductType.input,
      priceHistory: history,
      // A listagem manda o resumo; o detalhe manda a série. Um sem o outro é o
      // normal, e cada forma sabe se completar a partir do que recebeu.
      firstPrice: json['firstPrice'] == null
          ? (history.isEmpty ? null : history.first.price)
          : _asDouble(json['firstPrice']),
      priceHistoryCount: (json['priceHistoryCount'] as num?)?.toInt() ?? history.length,
      requiredPerHa: _asDouble(json['requiredPerHa']),
      classId: json['classId'] == null ? null : _asId(json['classId']),
      sku: json['sku'] as String?,
    );
  }
}

/// Como a exigência mínima de uma classe é calculada.
enum ClassRuleType {
  /// Sem exigência: a classe é só a taxonomia do item.
  none,

  /// A classe deve representar no mínimo X% do custo total dos insumos da
  /// permuta. [ProductClassModel.ruleValue] é o percentual (ex.: 10 = 10%).
  percentOfTotal,

  /// A classe exige no mínimo `ruleValue × areaHa` em valor (R$). Generaliza o
  /// `requiredPerHa` por produto para a classe inteira. [ruleValue] é R$/ha.
  valuePerHa,
}

/// CLASSE do produto (fungicidas, herbicidas, sementes, seguro agrícola…).
///
/// A lista é FIXA — vem da migration do servidor e não há como criar, renomear
/// ou excluir uma classe pelo app. Ela é o vocabulário com que a cooperativa
/// fala de mix e de exigência mínima, e enquanto era editável cada carga de
/// planilha inventava uma pasta nova.
///
/// O que se altera é a REGRA de mínimo: enquanto ela não é atingida, o
/// consultor não consegue enviar a permuta. É decisão comercial, e muda de
/// safra para safra.
class ProductClassModel {
  final String id;

  /// Identificador estável (`fungicidas`, `seguro-agricola`). O nome é o que a
  /// pessoa lê; o slug é o que o código e a planilha reconhecem.
  final String slug;
  final String name;

  /// Ordem de exibição definida pelo servidor. Também é o índice da cor da
  /// classe na paleta da marca — ver `ClassAvatar`.
  final int position;

  final ClassRuleType ruleType;

  /// Percentual (0–100) quando [ruleType] é [ClassRuleType.percentOfTotal];
  /// valor em R$ por hectare quando [ClassRuleType.valuePerHa]; ignorado
  /// quando [ClassRuleType.none].
  final double ruleValue;

  const ProductClassModel({
    required this.id,
    required this.slug,
    required this.name,
    this.position = 0,
    this.ruleType = ClassRuleType.none,
    this.ruleValue = 0,
  });

  factory ProductClassModel.fromJson(Map<String, dynamic> json) => ProductClassModel(
        id: _asId(json['id']),
        slug: (json['slug'] ?? '') as String,
        name: json['name'] as String,
        position: (json['position'] as num?)?.toInt() ?? 0,
        // Mesmo cuidado do status da permuta: uma regra que o app não conhece
        // não pode derrubar a lista inteira. Sem exigência é o padrão seguro —
        // o servidor valida os mínimos de novo no envio.
        ruleType: ClassRuleType.values.firstWhere(
          (r) => r.name == json['ruleType'],
          orElse: () => ClassRuleType.none,
        ),
        ruleValue: _asDouble(json['ruleValue']),
      );

  /// A classe tem uma exigência ativa que pode travar o envio da permuta.
  bool get hasRule => ruleType != ClassRuleType.none && ruleValue > 0;

  /// Descrição da regra para o ADMIN (pode citar R$, diferente do consultor).
  String get ruleLabelAdmin {
    switch (ruleType) {
      case ClassRuleType.none:
        return 'Sem exigência';
      case ClassRuleType.percentOfTotal:
        return 'Mín. ${_fmtNum(ruleValue)}% do valor total da permuta';
      case ClassRuleType.valuePerHa:
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

/// Em que unidade uma meta do Barter é medida. Espelha `GOAL_KIND` da API.
///
/// Não há lucro: a lista de preços do fornecedor traz preço de VENDA e mais
/// nada. Sem custo, "lucro" seria o faturamento com outro nome.
enum GoalKind {
  /// R$ em insumos retirados nas permutas aprovadas.
  sales,

  /// Sacas do grão comprometidas.
  sacks,

  /// Quantidade de permutas aprovadas.
  barters,
}

/// Uma meta da versão com o quanto dela já foi cumprido.
class BarterGoal {
  final GoalKind kind;
  final double target;
  final double realized;

  /// 0–1, já saturado pelo servidor (a barra não passa do fim).
  final double ratio;
  final bool met;

  const BarterGoal({
    required this.kind,
    required this.target,
    required this.realized,
    required this.ratio,
    required this.met,
  });

  factory BarterGoal.fromJson(Map<String, dynamic> json) => BarterGoal(
        // Uma meta que este app ainda não conhece não pode derrubar a tela:
        // ela cai em "vendas", que é a leitura mais comum, e o número segue
        // aparecendo. Mesmo critério do status da permuta.
        kind: GoalKind.values.firstWhere(
          (kind) => kind.name == json['kind'],
          orElse: () => GoalKind.sales,
        ),
        target: _asDouble(json['target']),
        realized: _asDouble(json['realized']),
        ratio: _asDouble(json['ratio']),
        met: json['met'] == true,
      );

  String get label {
    switch (kind) {
      case GoalKind.sales:
        return 'Vendas';
      case GoalKind.sacks:
        return 'Sacas';
      case GoalKind.barters:
        return 'Permutas';
    }
  }

  /// Metas em R$ e metas em contagem se leem de formas diferentes.
  bool get isMoney => kind == GoalKind.sales;
}

/// O valor de um insumo dentro de uma versão do Barter — uma linha da tabela.
class VersionPriceModel {
  final String productId;
  final String productName;
  final String unit;
  final double price;

  const VersionPriceModel({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.price,
  });

  factory VersionPriceModel.fromJson(Map<String, dynamic> json) => VersionPriceModel(
        productId: _asId(json['productId']),
        productName: json['productName'] as String,
        unit: json['unit'] as String,
        price: _asDouble(json['price']),
      );
}

/// O BARTER LANÇADO: uma versão da safra (ex.: S2026.02).
///
/// É ela que responde "por quanto se permuta agora": o valor da saca do grão e
/// a tabela de valores dos insumos. O consultor não escolhe grão nem tabela —
/// recebe esta aqui pronta, e sem ela não existe permuta nova.
class BarterVersionModel {
  final String id;
  final String code;
  final int number;
  final String seasonCode;
  final String seasonName;
  final String grainId;
  final String grainName;
  final String grainUnit;

  /// Valor (R$) da saca do grão nesta versão — a taxa que converte o custo dos
  /// insumos em sacas.
  final double grainPrice;

  final String status;

  /// Aceita permuta agora? Quem decide é o servidor (versão ativa e dentro da
  /// vigência), para o app não manter uma segunda cópia da regra.
  final bool isOpen;

  final DateTime startsAt;
  final DateTime? endsAt;
  final DateTime? closedAt;
  final String? closedBy;
  final String? sourceFile;
  final String? note;

  /// A tabela de valores desta versão, por produto.
  final List<VersionPriceModel> prices;

  /// Metas e realizado — só chegam para quem gerencia o Barter.
  final List<BarterGoal> goals;
  final double realizedSales;
  final double realizedSacks;
  final int realizedBarters;

  const BarterVersionModel({
    required this.id,
    required this.code,
    required this.number,
    required this.seasonCode,
    required this.seasonName,
    required this.grainId,
    required this.grainName,
    required this.grainUnit,
    required this.grainPrice,
    required this.status,
    required this.isOpen,
    required this.startsAt,
    required this.prices,
    this.endsAt,
    this.closedAt,
    this.closedBy,
    this.sourceFile,
    this.note,
    this.goals = const [],
    this.realizedSales = 0,
    this.realizedSacks = 0,
    this.realizedBarters = 0,
  });

  factory BarterVersionModel.fromJson(Map<String, dynamic> json) {
    final realized = (json['realized'] as Map<String, dynamic>?) ?? const {};
    return BarterVersionModel(
      id: _asId(json['id']),
      code: json['code'] as String,
      number: (json['number'] as num?)?.toInt() ?? 0,
      seasonCode: (json['seasonCode'] ?? '') as String,
      seasonName: (json['seasonName'] ?? '') as String,
      grainId: _asId(json['grainId']),
      grainName: (json['grainName'] ?? '') as String,
      grainUnit: (json['grainUnit'] ?? '') as String,
      grainPrice: _asDouble(json['grainPrice']),
      status: (json['status'] ?? 'closed') as String,
      isOpen: json['isOpen'] == true,
      startsAt: _asDate(json['startsAt']),
      endsAt: _asDateOrNull(json['endsAt']),
      closedAt: _asDateOrNull(json['closedAt']),
      closedBy: json['closedBy'] as String?,
      sourceFile: json['sourceFile'] as String?,
      note: json['note'] as String?,
      prices: (json['prices'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(VersionPriceModel.fromJson)
          .toList(),
      goals: (json['goals'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(BarterGoal.fromJson)
          .toList(),
      realizedSales: _asDouble(realized['sales']),
      realizedSacks: _asDouble(realized['sacks']),
      realizedBarters: (realized['barters'] as num?)?.toInt() ?? 0,
    );
  }

  /// O valor de um insumo nesta versão, ou null se ele não está na tabela —
  /// e um insumo fora da tabela não é permutável nesta gestão.
  VersionPriceModel? priceOf(String productId) {
    for (final price in prices) {
      if (price.productId == productId) return price;
    }
    return null;
  }

  /// Alguma meta foi atingida? É o aviso de "hora de encerrar" para o admin —
  /// o Barter não se fecha sozinho.
  bool get anyGoalMet => goals.any((goal) => goal.met);

  /// Rótulo curto para a faixa do consultor: "S2026.02 • paga em soja".
  String get shortLabel => '$code • paga em ${grainName.toLowerCase()}';
}

/// A SAFRA: a temporada em que o Barter acontece, sobre um grão. Carrega as
/// versões lançadas nela, da mais recente para a mais antiga.
class SeasonModel {
  final String id;
  final String code;
  final String name;
  final int year;
  final String grainId;
  final String grainName;
  final String status;
  final DateTime openedAt;
  final DateTime? closedAt;
  final List<BarterVersionModel> versions;

  const SeasonModel({
    required this.id,
    required this.code,
    required this.name,
    required this.year,
    required this.grainId,
    required this.grainName,
    required this.status,
    required this.openedAt,
    required this.versions,
    this.closedAt,
  });

  factory SeasonModel.fromJson(Map<String, dynamic> json) => SeasonModel(
        id: _asId(json['id']),
        code: json['code'] as String,
        name: json['name'] as String,
        year: (json['year'] as num?)?.toInt() ?? 0,
        grainId: _asId(json['grainId']),
        grainName: (json['grainName'] ?? '') as String,
        status: (json['status'] ?? 'closed') as String,
        openedAt: _asDate(json['openedAt']),
        closedAt: _asDateOrNull(json['closedAt']),
        versions: (json['versions'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(BarterVersionModel.fromJson)
            .toList(),
      );

  bool get isOpen => status == 'open';
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
