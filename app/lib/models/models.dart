import '../services/tax_regime.dart';

export '../services/tax_regime.dart' show TaxRegime, TaxRegimeApi;

/// A CÉDULA DE PRODUTO RURAL vive em arquivo próprio (`cpr.dart`) e é
/// reexportada aqui: ela é um DOCUMENTO montado a partir da permuta, com uma
/// dúzia de campos que só o faturista preenche, e misturá-la ao modelo da
/// permuta confundiria "o que foi acordado" com "o que vai impresso no título".
export 'cpr.dart';

/// Papéis do sistema. Os nomes técnicos são os MESMOS que a API grava em
/// `user.role` (ver api/src/common/roles.ts) — este enum é a tradução deles
/// para o app, e não uma segunda lista para manter em dia de cabeça.
enum UserRole {
  admin('admin', 'Administrador'),
  manager('manager', 'Gerente'),
  committee('committee', 'Comitê'),
  biller('biller', 'Faturista'),

  /// EMISSOR — o posto que vem depois do faturamento: ele confere a cédula que
  /// o consultor preencheu, emite o título, colhe as assinaturas e o registra.
  ///
  /// Ele nasceu de uma correção: a CPR era do faturista, e não é. Faturar é
  /// emitir nota; emitir CPR é pôr em circulação um título de crédito, que é
  /// conferido, assinado por gente e levado a registro. Enquanto foram um posto
  /// só, o segundo acontecia "junto com" o primeiro — sem etapa, sem prazo e sem
  /// quem responda por ele.
  emitter('emitter', 'Emissor'),
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

/// As CAPACIDADES que o servidor concede — o que a pessoa PODE FAZER, decidido
/// lá e apenas lido aqui.
///
/// A lista espelha `api/src/common/policy.ts`, e o app não guarda nenhuma regra
/// própria sobre quem tem o quê: ele recebe as capacidades do usuário no login e
/// monta as telas a partir delas. É o que permite mover uma etapa de um papel
/// para outro — como a decisão da permuta, que saiu do admin e foi para o
/// comitê — sem publicar versão nova do aplicativo.
///
/// Só estão aqui as que a interface consulta. Uma capacidade que o app não
/// pergunta não precisa de constante.
class Capability {
  /// Dar o parecer técnico (gerente).
  static const bartersOpinion = 'barters.opinion';

  /// DECIDIR a permuta: aprovar ou negar (comitê).
  static const bartersReview = 'barters.review';

  /// FATURAR a permuta aprovada e ANEXAR as notas fiscais dela (faturista).
  ///
  /// As notas andam junto com o ato, e não numa capacidade própria: a nota é o
  /// que o faturamento produz, e são várias — a permuta sai em mais de um
  /// carregamento, e cada retirada gera a sua.
  static const bartersInvoice = 'barters.invoice';

  /// PREENCHER as informações da cédula — a qualificação do emitente, as
  /// lavouras em penhor, o padrão do grão e o SCR do produtor (CONSULTOR).
  ///
  /// Era do faturista, e mudou de dono: nada do que a cédula pede está na mesa
  /// de quem fatura. A matrícula do imóvel, o nome do cônjuge, quem é o dono da
  /// área arrendada e o SCR são o que se traz da visita à fazenda.
  static const bartersCprFill = 'barters.cprFill';

  /// EMITIR a cédula, colher as ASSINATURAS e REGISTRÁ-LA (emissor).
  ///
  /// Uma capacidade para os três atos porque eles são o mesmo ofício, sobre o
  /// mesmo documento. O que os separa é o TEMPO — a cédula é gerada hoje,
  /// assinada quando o produtor vem à cidade, registrada quando o cartório
  /// responde —, e é por isso que cada um é uma etapa própria da esteira.
  static const bartersCprIssue = 'barters.cprIssue';

  /// LER a mesa da cédula e gerar o documento — sem preenchê-la e sem emiti-la.
  ///
  /// É de TRÊS papéis, com perguntas diferentes: o consultor (para preencher),
  /// o emissor (para conferir e emitir) e o admin (para a segunda via do que a
  /// operação dele emitiu). O faturista NÃO a tem: o que ele produz é a nota.
  static const bartersCprRead = 'barters.cprRead';

  /// Registrar permuta (consultor).
  static const bartersRegister = 'barters.register';

  /// PEDIR a alteração de uma permuta que já saiu da mão de quem a registrou —
  /// o único caminho de volta da esteira (consultor).
  static const bartersChangeRequest = 'barters.changeRequest';

  /// DECIDIR o pedido de alteração: liberar a permuta para ser refeita, ou
  /// recusar com o motivo (admin).
  ///
  /// Ela é do admin e NÃO do comitê, ao contrário de [bartersReview]: o comitê
  /// julga o negócio, e o que se julga aqui é o processo — se o trabalho já
  /// feito pelos outros postos vai ser jogado fora.
  static const bartersChangeReview = 'barters.changeReview';

  /// PEDIR um produto que a tabela do Barter não tem — o pedido de fora do
  /// Barter (consultor). Ver [BarterProductRequest].
  static const bartersProductRequest = 'barters.productRequest';

  /// ATENDER o pedido de fora do Barter: incluir o produto na permuta com o
  /// valor acertado, ou recusá-lo com o motivo (admin).
  ///
  /// É de quem publica a tabela de valores, e não do comitê: acertar um valor
  /// dentro de uma permuta é a mesma decisão de sempre, feita para uma permuta
  /// só.
  static const bartersProductReview = 'barters.productReview';

  /// Enxergar as permutas do PRÓPRIO TIME — o escopo do gerente, entre "só as
  /// minhas" e "todas". É por ela que as telas dizem "do seu time".
  static const bartersReadTeam = 'barters.readTeam';

  /// Enxergar só o que CHEGOU AO FATURAMENTO — o escopo do faturista.
  ///
  /// A tela pergunta por ela para não desenhar cômodo que não existe: sem isto,
  /// o faturista abria abas "No gerente" e "No comitê" que o servidor responde
  /// vazias, e um painel que contava permutas de etapas das quais ele não
  /// participa.
  static const bartersReadInvoicing = 'barters.readInvoicing';

  /// Enxergar só o que CHEGOU À EMISSÃO — o escopo do emissor, um degrau
  /// adiante do faturista.
  ///
  /// A tela pergunta por ela pelo mesmo motivo de [bartersReadInvoicing]: sem
  /// isto, o emissor abriria abas de etapas das quais não participa e um painel
  /// contando permutas que o servidor responde vazias.
  static const bartersReadIssuance = 'barters.readIssuance';

  /// Ver valores em R$ — todo mundo menos o consultor.
  static const pricesRead = 'prices.read';

  /// Manter o cadastro da CREDORA — a razão social, o CNPJ, o endereço e o foro
  /// que saem nos documentos que a empresa emite.
  ///
  /// É do admin **e do EMISSOR**, e é a única que os dois dividem: a credora
  /// não decide permuta nem concede acesso — é o timbre do papel, e quem
  /// percebe o CNPJ errado é quem leva o título a registro. Ela já foi do
  /// faturista, e mudou de mãos junto com a cédula.
  static const creditorManage = 'creditor.manage';

  /// Definir a MARGEM DE SEGURANÇA DO PENHOR — a folga de área que a empresa
  /// exige além da que a produção estimada justifica.
  ///
  /// SEPARADA de [creditorManage], e é por isso que ela existe: aquela é do
  /// admin **e do emissor**, porque é o timbre do papel. Esta decide quanta terra
  /// a empresa exige em garantia de tudo o que for registrado dali em diante — e
  /// é só do ADMIN. A tela da credora é a mesma para os dois; o campo da margem
  /// é o único que o emissor não vê.
  static const pledgePolicyManage = 'pledge.policy';

  const Capability._();
}

/// Conversões defensivas do JSON da API: números podem chegar como int/double
/// e ids são expostos como String para o restante do app.
double _asDouble(dynamic v) => v == null ? 0 : (v as num).toDouble();

/// Número que pode legitimamente NÃO VIR, e cujo ausente não é zero.
///
/// É o caso do investimento por hectare: ele some para quem não pode compará-lo
/// e vem `null` quando não há área para dividir. Lê-lo com [_asDouble] faria os
/// dois casos virarem "0 sc/ha", que é uma afirmação — e falsa.
double? _asDoubleOrNull(dynamic v) => v == null ? null : (v as num).toDouble();
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

  /// O QUE ESTA PESSOA PODE FAZER, resolvido pelo servidor (ver [Capability]).
  ///
  /// Vazio quando a resposta não traz o campo — e vazio significa "não pode
  /// nada", nunca "pode tudo". É a mesma escolha do servidor com papel
  /// desconhecido: falhar fechando deixa a tela pobre, e o contrário ofereceria
  /// um botão que levaria 403.
  final Set<String> capabilities;

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
    this.capabilities = const {},
  });

  /// Esta pessoa pode isto? A única pergunta de autorização do app — e a
  /// resposta é sempre do servidor.
  bool can(String capability) => capabilities.contains(capability);

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
        capabilities: ((json['capabilities'] as List?) ?? const [])
            .map((c) => c as String)
            .toSet(),
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

  /// COMO ESTE PRODUTOR RECOLHE o Funrural: sobre a comercialização (o padrão,
  /// de quem não fez opção nenhuma) ou sobre a folha de pagamento — e aí sobre
  /// a entrega fica só o Senar. Ver `services/tax_regime.dart`.
  ///
  /// É dado de CADASTRO porque é o que ele é: a opção formal perante o fisco é
  /// feita uma vez e vale para todas as entregas do produtor. Toda permuta nova
  /// nasce com ele, e grava a alíquota que ele produziu — que é o número
  /// congelado no comprovante.
  final TaxRegime taxRegime;

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
    this.taxRegime = TaxRegime.comercializacao,
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
        taxRegime: taxRegimeFrom(json['taxRegime']),
        avatarInitials: (json['initials'] ?? '?') as String,
        createdAt: _asDate(json['createdAt']),
      );

  /// Este consultor atende o produtor? É a pergunta que a carteira passou a
  /// responder quando deixou de ser um id só — e a que o servidor faz antes de
  /// aceitar uma permuta.
  bool isAttendedBy(String consultantId) => consultantIds.contains(consultantId);

  /// Localização resumida (ex.: "Fazenda Boa Vista – Maringá/PR").
  String get location => '$farmName, $city';

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

/// O caminho de uma permuta — uma LINHA DE PRODUÇÃO de três postos:
///
///     sentToManager → pending → approved → invoiced
///      (gerente)     (comitê)  (faturista)
///                        ↘ denied
///
/// [sentToManager] é onde ela nasce: está na mesa do gerente do consultor,
/// esperando o parecer técnico. Escrito o parecer, ela vai ao COMITÊ
/// ([pending]), que lê o pedido e o parecer e decide — é a única instância que
/// aprova ou nega. Aprovada, ela cai na fila do FATURISTA, que fatura
/// ([invoiced]) e encerra a linha.
///
/// "Revisão" continua sendo a palavra da etapa do comitê no vocabulário técnico
/// (a rota é `POST /barters/:code/review`, os campos são `reviewedBy` e
/// `reviewedAt`); nas telas ela aparece como DECISÃO, que é o que ela é. O que
/// não muda é a distinção do começo: o gerente ANALISA e o comitê DECIDE — dar o
/// mesmo nome às duas deixava as etapas indistinguíveis.
///
/// Os nomes são os MESMOS que a API grava (ver BARTER_STATUS em
/// api/src/barters/barter-workflow.ts) — é o que [_asStatus] compara.
/// Os estados de uma permuta, na ordem da LINHA DE PRODUÇÃO:
///
///     draft → sentToManager → pending → approved             → invoiced
///  (consultor) (gerente)     (comitê)   approvedWithConditions (faturista)
///                                ↘ denied
///
/// Espelham `api/src/barters/barter-workflow.ts`, que é quem decide o caminho.
/// `draft` é o RASCUNHO do consultor: ela existe, os valores já estão
/// congelados nela, e ninguém da retaguarda a enxerga até ele encaminhar.
/// `pending` é a permuta na mesa do COMITÊ — o nome ficou de quando a decisão
/// era do admin, e ficou porque descreve o estado, não o cargo de quem decide.
/// `approvedWithConditions` é a aprovação COM RESSALVA: mesma fila do faturista,
/// e uma exigência escrita junto (ver [BarterModel.reviewNote]).
enum BarterStatus {
  draft,
  sentToManager,
  pending,
  approved,
  approvedWithConditions,
  denied,
  invoiced,

  /// O TRECHO DA CÉDULA — três estados, um por ato do EMISSOR.
  ///
  /// `invoiced` deixou de ser o fim da linha quando a emissão virou etapa: uma
  /// permuta faturada ainda deve o título que formaliza a entrega, e enquanto
  /// isso não tinha estado, ela aparecia como concluída com a cédula por emitir.
  cprIssued,
  cprSigned,
  cprRegistered,
}

/// Status vindo do servidor, tolerante ao desconhecido.
///
/// `BarterStatus.values.byName` LANÇA num nome que não existe: bastaria o
/// servidor ganhar um status novo (uma permuta cancelada, por exemplo) para a
/// lista inteira parar de carregar nas versões do app já instaladas — uma tela
/// vazia no lugar de todas as permutas.
///
/// Um status que o app não conhece cai em [BarterStatus.pending]: o registro
/// continua visível, e quem decide se ele aceita ação continua sendo o servidor,
/// que recusa qualquer ato fora da etapa dele. Foi o que aconteceu quando
/// `sentToManager` nasceu, e de novo com `invoiced`: as versões instaladas do
/// app passaram a mostrar as permutas novas na etapa errada — impreciso, mas
/// visível e sem ação indevida, que é exatamente o que este padrão existe para
/// dar. O rótulo, esse vem certo mesmo assim: quem o escreve é o servidor (ver
/// [BarterModel.statusLabel]).
BarterStatus _asStatus(dynamic v) {
  for (final status in BarterStatus.values) {
    if (status.name == v) return status;
  }
  return BarterStatus.pending;
}

/// Estado da permuta que pode simplesmente NÃO VIR — é o caso de
/// `changeRequestFrom`, presente só enquanto há (ou houve) pedido de alteração.
///
/// Diferente de [_asStatus], que cai em `pending`: aqui o desconhecido vira
/// null, e a tela cala em vez de afirmar que o pedido foi feito de um estado
/// que ninguém escolheu.
BarterStatus? _asStatusOrNull(dynamic v) {
  for (final status in BarterStatus.values) {
    if (status.name == v) return status;
  }
  return null;
}

/// Papel vindo da API quando ele pode simplesmente NÃO VIR — é o caso de
/// `waitingFor`, que é null nos fins de linha (negada, faturada).
///
/// Diferente de [UserRole.fromWire], que cai em consultor: aqui um valor
/// desconhecido vira null, e a tela não diz nada em vez de dizer errado quem
/// está com a permuta.
UserRole? _asRoleOrNull(Object? value) {
  for (final role in UserRole.values) {
    if (role.wire == value) return role;
  }
  return null;
}

/// Um passo da LINHA DO TEMPO da permuta: quem a moveu, de onde para onde e o
/// que escreveu ao fazê-lo.
///
/// Vem só no DETALHE (`GET /barters/:code`) — a listagem não carrega histórico,
/// pelo mesmo motivo do histórico de preço do produto: lista mostra estado,
/// não trajetória.
///
/// O autor chega em texto, congelado no momento do ato: o histórico precisa
/// continuar legível depois que a conta for excluída.
class BarterEventModel {
  /// O ato: `register`, `opinion`, `review` ou `invoice`.
  final String action;

  /// De onde para onde. [fromStatus] é null no registro, que não vem de
  /// estado nenhum.
  final BarterStatus? fromStatus;
  final BarterStatus toStatus;

  final String actorName;
  final UserRole? actorRole;

  /// O papel escrito como se lê, resolvido pelo SERVIDOR — um papel que este
  /// app ainda não conhece aparece com o nome certo mesmo assim.
  final String actorRoleLabel;

  /// O texto que acompanhou o ato (o parecer, a observação da decisão, a nota
  /// do faturamento).
  final String? note;

  final DateTime at;

  const BarterEventModel({
    required this.action,
    required this.fromStatus,
    required this.toStatus,
    required this.actorName,
    required this.actorRole,
    required this.actorRoleLabel,
    required this.note,
    required this.at,
  });

  factory BarterEventModel.fromJson(Map<String, dynamic> json) => BarterEventModel(
        action: (json['action'] ?? '') as String,
        fromStatus: json['fromStatus'] == null ? null : _asStatus(json['fromStatus']),
        toStatus: _asStatus(json['toStatus']),
        actorName: (json['actorName'] ?? '') as String,
        actorRole: _asRoleOrNull(json['actorRole']),
        actorRoleLabel: (json['actorRoleLabel'] ?? '') as String,
        note: json['note'] as String?,
        at: _asDate(json['at']),
      );

  /// O título do passo na linha do tempo — o que ACONTECEU, não o estado a que
  /// se chegou.
  String get title {
    switch (action) {
      case 'register':
        return 'Registrada pelo consultor';
      case 'opinion':
        return 'Parecer do gerente';
      case 'review':
        // As duas saídas conhecidas, e nada além delas: uma decisão que este app
        // não conhece vira "Decisão do comitê" em vez de virar "Aprovada" por
        // eliminação — errar para o vago é diferente de errar para o oposto.
        if (toStatus == BarterStatus.approved) return 'Aprovada pelo comitê';
        if (toStatus == BarterStatus.denied) return 'Negada pelo comitê';
        return 'Decisão do comitê';
      case 'invoice':
        return 'Faturada';
      // O DESVIO: o pedido de alteração e a decisão do admin sobre ele. Três
      // atos, e três linhas na história — quem pediu, e o que responderam. Ver
      // `api/src/barters/change-request.ts`.
      case 'changeRequested':
        return 'Alteração solicitada';
      case 'changeAccepted':
        return 'Alteração liberada: voltou a rascunho';
      case 'changeDenied':
        return 'Pedido de alteração recusado';
      // A TERCEIRA saída do pedido: o admin atendeu mexendo no valor, e a
      // permuta não saiu do lugar. O texto do evento diz o que mudou, de quanto
      // para quanto — ver `priceChangeRefusal` na API.
      case 'changeApplied':
        return 'Valores alterados pelo administrador';
      // O PEDIDO DE FORA DO BARTER: o produto que a tabela não tem. Ver
      // `api/src/barters/product-request.ts`.
      case 'productRequested':
        return 'Produto de fora do Barter solicitado';
      case 'productAdded':
        return 'Produto incluído na permuta';
      case 'productDenied':
        return 'Pedido de produto recusado';
      default:
        // Ato de um servidor mais novo que este app: mostra o passo em vez de
        // esconder um pedaço da história por não saber nomeá-lo.
        return 'Andamento';
    }
  }
}

/// Em que pé está uma etapa da permuta — ver `BARTER_STEP_STATE` em
/// `api/src/barters/barter-workflow.ts`, que é quem decide.
enum BarterStepState {
  /// Cumprida. É a parte que tem autor, data e texto para mostrar.
  done,

  /// É AQUI que a permuta está parada agora.
  current,

  /// Ainda vai acontecer.
  ahead,

  /// NÃO vai acontecer: a permuta saiu da linha antes de chegar aqui (foi
  /// negada). Diferente de [ahead], e a diferença é o que impede a tela de
  /// prometer um faturamento que ninguém vai fazer.
  halted,
}

/// Estado de etapa vindo do servidor, tolerante ao desconhecido.
///
/// Cai em [BarterStepState.ahead] — a leitura menos comprometida das quatro. Um
/// estado novo que este app não conhece vira "ainda vem", que é impreciso;
/// virar `done` seria dizer que uma etapa que ninguém cumpriu está cumprida, e
/// numa tela de acompanhamento essa é a mentira que custa caro.
BarterStepState _asStepState(Object? value) {
  for (final state in BarterStepState.values) {
    if (state.name == value) return state;
  }
  return BarterStepState.ahead;
}

/// Uma etapa da permuta no ANDAMENTO dela: o caminho inteiro, do registro ao
/// faturamento, com o que já aconteceu preenchido.
///
/// É a linha do tempo e a checklist na mesma lista. [BarterEventModel] conta o
/// que houve; sozinho, ele faz uma permuta parada no comitê parecer terminada —
/// mostra dois passos, e nada neles diz que faltam dois. Aqui as quatro etapas
/// aparecem sempre, e é isso que responde à pergunta que o consultor leva do
/// produtor: falta o quê, e com quem está?
///
/// Quem monta a lista é o SERVIDOR (`GET /barters/:code`), e não uma cópia do
/// fluxo em Dart: uma etapa nova aparece nas telas já instaladas em vez de pedir
/// versão nova do app — a mesma razão de `capabilities` e `waitingFor`.
class BarterStepModel {
  /// O ato desta etapa: `register`, `opinion`, `review` ou `invoice`.
  final String action;

  final BarterStepState state;

  /// O nome da etapa ("Parecer do gerente"), escrito pelo servidor. Substantivo,
  /// porque o mesmo rótulo serve à etapa cumprida e à que ainda vem.
  final String label;

  /// De quem é a etapa — quem a cumpriu, ou quem ainda vai cumpri-la. É o que a
  /// tela mostra nas etapas que ainda não têm autor.
  final UserRole? role;
  final String roleLabel;

  /// O que há para dizer sobre o ESTADO desta etapa, escrito pelo servidor: o
  /// que a etapa de agora espera ("Esta permuta aguarda o parecer do gerente
  /// Beatriz Nogueira") ou por que a que não vem não vem ("Não acontece: a
  /// permuta foi negada"). Null nas cumpridas e nas que ainda estão por vir.
  final String? stateNote;

  /// A ASSINATURA da etapa cumprida — quem, quando, e o que escreveu. Tudo null
  /// enquanto ela não aconteceu.
  final String? actorName;
  final String actorRoleLabel;
  final DateTime? at;
  final String? note;

  /// COMO a etapa terminou, quando ela podia terminar de mais de um jeito
  /// ("Aprovada", "Negada"). Null nas que só empurram adiante.
  final String? outcomeLabel;

  /// O estado que o ato alcançou — é dele que sai a COR do passo, igual à da
  /// linha do tempo. Null enquanto a etapa não foi cumprida.
  final BarterStatus? toStatus;

  const BarterStepModel({
    required this.action,
    required this.state,
    required this.label,
    required this.role,
    required this.roleLabel,
    required this.stateNote,
    required this.actorName,
    required this.actorRoleLabel,
    required this.at,
    required this.note,
    required this.outcomeLabel,
    required this.toStatus,
  });

  factory BarterStepModel.fromJson(Map<String, dynamic> json) => BarterStepModel(
        action: (json['action'] ?? '') as String,
        state: _asStepState(json['state']),
        label: (json['label'] ?? '') as String,
        role: _asRoleOrNull(json['role']),
        roleLabel: (json['roleLabel'] ?? '') as String,
        stateNote: json['stateNote'] as String?,
        actorName: json['actorName'] as String?,
        actorRoleLabel: (json['actorRoleLabel'] ?? '') as String,
        at: _asDateOrNull(json['at']),
        note: json['note'] as String?,
        outcomeLabel: json['outcomeLabel'] as String?,
        toStatus: json['toStatus'] == null ? null : _asStatus(json['toStatus']),
      );

  /// Esta etapa já foi cumprida — é a que tem o que mostrar.
  bool get isDone => state == BarterStepState.done;

  /// É nesta etapa que a permuta está parada agora.
  bool get isCurrent => state == BarterStepState.current;

  /// Esta etapa não vai acontecer (a permuta foi negada antes de chegar nela).
  bool get isHalted => state == BarterStepState.halted;
}

/// Item de uma permuta. Serve tanto para o grão entregue quanto para o
/// insumo retirado. [unitValue] é o valor de referência (R$) por unidade no
/// momento da permuta — é o que permite converter grão em insumo.
class BarterItem {
  /// O ID DA LINHA na permuta — não do produto.
  ///
  /// Ele existe porque o admin altera o valor de UM item ao atender o pedido do
  /// consultor, e o produto não serve de endereço: os itens de fora do Barter
  /// (ver [offBarter]) não têm produto no catálogo, e são justamente os que
  /// mais mudam de valor. Vazio nas respostas anteriores ao campo.
  final String id;

  final String productId;
  final String productName;

  /// O CÓDIGO do produto congelado no registro (o `sku` do catálogo).
  ///
  /// Ele anda junto do nome em toda tela e em todo documento: é por ele que o
  /// insumo é procurado no depósito, conferido na retirada e batido contra a
  /// nota — e dois produtos de nomes parecidos ("Glifosato 480 SL" e "Glifosato
  /// 480 WG") só se distinguem por ele.
  ///
  /// Null nos itens gravados antes de o campo existir e nos produtos sem
  /// código. Aí a tela cai no código ATUAL do catálogo (ver `AppData.skuOf`), o
  /// que é uma leitura do cadastro e não uma afirmação sobre o dia do acordo.
  final String? sku;

  final String unit;
  final double quantity;
  final double unitValue;

  /// O valor unitário VEIO nesta resposta?
  ///
  /// Separa "R$ 0,00" de "a lente de valor não manda R$ para este papel" — dois
  /// casos que [unitValue] sozinho não distingue, porque o campo ausente parseia
  /// zero. O consultor recebe o item sem `unitValue` (ver `toBarterItemJson`),
  /// e era esse zero que fazia o detalhe da permuta dele anunciar "0 sc" em
  /// TOTAL A ENTREGAR.
  final bool hasUnitValue;

  /// Este item veio de FORA DO BARTER: de um pedido do consultor que o admin
  /// atendeu, e não da tabela de valores da versão.
  ///
  /// A marca é sobre a PROCEDÊNCIA, e não sobre o valor — por isso ela chega a
  /// todo mundo, inclusive a quem não vê R$. Quem confere a retirada no balcão
  /// precisa saber que aquele item não está na lista da praça.
  final bool offBarter;

  /// O VALOR DE TABELA deste item, quando o admin escreveu outro por cima ao
  /// atender um pedido de alteração.
  ///
  /// Null é o caso normal: o item vale o que a versão do Barter diz. Preenchido,
  /// é o que permite à tela mostrar "R$ 110,00 (tabela: R$ 120,00)" em vez de um
  /// número sem história. Só chega a quem vê R$, como [unitValue].
  final double? listValue;

  const BarterItem({
    this.id = '',
    required this.productId,
    required this.productName,
    this.sku,
    required this.unit,
    required this.quantity,
    required this.unitValue,
    this.hasUnitValue = true,
    this.offBarter = false,
    this.listValue,
  });

  factory BarterItem.fromJson(Map<String, dynamic> json) => BarterItem(
        id: _asId(json['id']),
        productId: _asId(json['productId']),
        productName: json['productName'] as String,
        sku: json['sku'] as String?,
        unit: json['unit'] as String,
        quantity: _asDouble(json['quantity']),
        unitValue: _asDouble(json['unitValue']),
        hasUnitValue: json['unitValue'] != null,
        offBarter: json['offBarter'] == true,
        listValue: _asDoubleOrNull(json['listValue']),
      );

  /// O valor deste item foi REESCRITO pelo admin — e [listValue] diz de quanto.
  bool get hasChangedValue => listValue != null && hasUnitValue;

  /// Valor total de troca deste item (R$). Zero para quem não vê R$ — ver
  /// [hasUnitValue].
  double get total => quantity * unitValue;
}

/// O PEDIDO DE FORA DO BARTER: o consultor pede um produto que a tabela da
/// versão não tem, e o admin o inclui NAQUELA permuta com o valor que acertou.
///
/// A tabela do Barter é uma lista fechada e a lavoura não é — o produtor quer o
/// adjuvante da marca dele, um serviço que ninguém lançou, uma semente sob
/// encomenda. Sem este caminho, ou o item fica fora da permuta (e o produtor
/// compra à vista em outro lugar) ou vira preço de praça para todo mundo por
/// causa de um cliente.
///
/// O valor acertado vale para ESTA permuta e morre com ela: foi cotado para
/// esta quantidade, nesta data, neste negócio.
class BarterProductRequest {
  final String id;

  /// O que vai entrar na permuta: nome, unidade e quantidade. Depois de
  /// atendido, é o que o ADMIN escreveu — ele corrige a descrição do
  /// fornecedor, e é o item dele que vai ser separado no balcão.
  final String productName;
  final String unit;
  final double quantity;

  /// O código do fornecedor, quando o admin o tem. Ver [BarterItem.sku].
  final String? sku;

  /// O que o consultor tem a dizer sobre o pedido. Opcional, ao contrário do
  /// pedido de alteração: aqui o pedido é o produto e a quantidade.
  final String? note;

  /// `open` (na mesa do admin), `added` (atendido: o item está na permuta) ou
  /// `denied` (recusado, e o motivo está em [reply]).
  final String status;

  final String requestedBy;
  final DateTime? requestedAt;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String? reply;

  /// O VALOR acertado (R$ por unidade) — só para quem vê R$. Null enquanto o
  /// pedido não foi atendido: não há preço nenhum, e um zero seria um item de
  /// graça.
  final double? unitValue;

  /// O mesmo valor na moeda de quem NÃO vê R$: sacas do grão por unidade. É o
  /// que o consultor — que fez o pedido — lê no lugar do preço.
  final double? sacksPerUnit;

  const BarterProductRequest({
    required this.id,
    required this.productName,
    required this.unit,
    required this.quantity,
    this.sku,
    this.note,
    required this.status,
    required this.requestedBy,
    this.requestedAt,
    this.decidedBy,
    this.decidedAt,
    this.reply,
    this.unitValue,
    this.sacksPerUnit,
  });

  factory BarterProductRequest.fromJson(Map<String, dynamic> json) =>
      BarterProductRequest(
        id: _asId(json['id']),
        productName: (json['productName'] ?? '') as String,
        unit: (json['unit'] ?? '') as String,
        quantity: _asDouble(json['quantity']),
        sku: json['sku'] as String?,
        note: json['note'] as String?,
        status: (json['status'] ?? 'open') as String,
        requestedBy: (json['requestedBy'] ?? '') as String,
        requestedAt: _asDateOrNull(json['requestedAt']),
        decidedBy: json['decidedBy'] as String?,
        decidedAt: _asDateOrNull(json['decidedAt']),
        reply: json['reply'] as String?,
        unitValue: _asDoubleOrNull(json['unitValue']),
        sacksPerUnit: _asDoubleOrNull(json['sacksPerUnit']),
      );

  /// Está na mesa do admin, esperando um valor.
  bool get isOpen => status == 'open';

  /// Foi atendido: o item está na permuta.
  bool get isAdded => status == 'added';

  /// Foi recusado, e [reply] diz por quê.
  bool get isDenied => status == 'denied';

  /// Quanto este item custa na permuta inteira — na moeda de quem está
  /// olhando. Null quando não há valor acertado (ou quando ele não veio).
  double? get total {
    final perUnit = unitValue ?? sacksPerUnit;
    return perUnit == null ? null : perUnit * quantity;
  }
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

  /// O PENHOR — quanta área de lavoura esta permuta precisa dar em garantia, e
  /// as duas taxas que produziram esse número.
  ///
  /// [pledgeAreaHa] é `(sacas ÷ [pledgeYield]) × (1 + [pledgeMarginPercent]%)`,
  /// calculada pelo SERVIDOR — o app não refaz a conta pelo mesmo motivo de não
  /// refazer a da cédula: as sacas mudam quando um produto de fora do Barter é
  /// deferido, e duas contas divergiriam no primeiro arredondamento.
  ///
  /// As DUAS TAXAS vêm junto, e não só o resultado, porque "por que 34 ha?" é a
  /// primeira pergunta de quem lê o número — e o lançamento do Barter, onde a
  /// resposta mora, é tela que o consultor não abre.
  ///
  /// Zero nos três quando a resposta não os trouxe (a listagem não carrega os
  /// itens) ou quando a permuta é anterior ao dimensionamento. Ver [hasPledge],
  /// que é o que as telas leem antes de mostrar qualquer um deles.
  final double pledgeAreaHa;
  final double pledgeYield;
  final double pledgeMarginPercent;

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

  /// O PARECER DO CONSULTOR e o momento em que ele encaminhou a permuta.
  ///
  /// É a peça que abre o processo: quem conhece o cliente dizendo o que pensa do
  /// negócio, para o gerente e o comitê lerem antes de opinar e decidir.
  ///
  /// Os dois são independentes de propósito, e a tela lê a diferença: o texto
  /// existe assim que ele salva o rascunho; [consultantSentAt] só quando a
  /// permuta é encaminhada. Um rascunho com parecer escrito e não encaminhado é
  /// exatamente o caso para o qual o rascunho existe.
  final String? consultantNote;
  final DateTime? consultantSentAt;

  /// A ÁREA cultivável (ha) congelada no registro e o INVESTIMENTO POR HECTARE
  /// que ela produz — quantas sacas do grão a lavoura compromete por hectare.
  ///
  /// Os dois vêm null para quem não tem `barters.investmentPerHa` (consultor e
  /// gerente): o servidor simplesmente não os manda. [sacksPerHa] também é null
  /// nas permutas anteriores ao campo de área — sem área não há divisão, e zero
  /// seria afirmar um investimento por hectare que ninguém fez.
  final double? producerAreaHa;
  final double? sacksPerHa;

  /// A DECISÃO DO COMITÊ: a observação e quem assinou.
  ///
  /// [reviewNote] se chamava `adminNote` — o nome saiu junto com o poder, porque
  /// quem decide permuta é o comitê, e não o admin.
  final String? reviewNote;
  final String? reviewedBy;

  /// O FATURAMENTO. Null enquanto ela não foi faturada, que é o que
  /// [isInvoiced] lê.
  final String? invoicedBy;
  final DateTime? invoicedAt;
  final String? invoiceNote;

  /// AS NOTAS FISCAIS anexadas ao faturamento — o que o posto do faturista
  /// produz, e a origem da dívida que a cédula afirma.
  ///
  /// São VÁRIAS: a permuta sai em mais de um carregamento, cada retirada gera a
  /// sua, e a cancelada é reemitida. Elas vêm na LISTAGEM também, como os
  /// pedidos de produto, porque são ESTADO — "esta permuta já tem nota?" é o que
  /// a fila do faturista pergunta.
  final List<BarterInvoiceModel> invoices;

  /// A EMISSÃO DA CÉDULA — os três atos do emissor, cada um null até acontecer.
  ///
  /// É essa diferença que a tela lê para saber em que pé a CPR está, do mesmo
  /// jeito que [managerNote] diz se o parecer saiu.
  final String? cprEmittedBy;
  final DateTime? cprEmittedAt;
  final String? cprEmissionNote;
  final DateTime? cprSignedAt;
  final String? cprSignatureNote;
  final DateTime? cprRegisteredAt;

  /// O NÚMERO do registro — o que se leva ao cartório para pedir a certidão.
  /// Sem ele, "registrada" seria uma afirmação sem como ser conferida.
  final String? cprRegistryNumber;
  final String? cprRegistryPlace;

  /// O PEDIDO DE ALTERAÇÃO — o único caminho de volta que a permuta tem.
  ///
  /// O consultor que registrou pede, com uma justificativa, enquanto a permuta
  /// não foi faturada; o ADMIN decide. Liberar devolve a permuta a rascunho (e
  /// apaga o parecer do gerente e a decisão do comitê, que falavam de insumos
  /// prestes a mudar); recusar deixa tudo onde está, com o motivo escrito.
  ///
  /// [changeRequestStatus] é `open` (na mesa do admin), `denied` (recusado, e o
  /// motivo está em [changeRequestReply]) ou null — que é o caso normal: nunca
  /// se pediu nada, ou o pedido foi atendido e a permuta voltou a ser rascunho.
  ///
  /// O pedido NÃO move a permuta: ela continua na fila em que estava, e quem a
  /// tem na mesa vê a bandeira antes de gastar trabalho nela.
  final String? changeRequestStatus;
  final String? changeRequestNote;
  final String? changeRequestBy;
  final DateTime? changeRequestAt;

  /// O ESTADO em que a permuta estava quando o pedido foi feito — é ele que diz
  /// ao admin o tamanho do que ele vai desfazer: um parecer, ou uma decisão.
  final BarterStatus? changeRequestFrom;

  /// A resposta do admin, que só sobrevive na RECUSA: a liberação fala pelo
  /// próprio efeito, e a permuta reaparece na mão de quem pediu.
  final String? changeRequestReply;

  /// COM QUEM a permuta está parada agora, resolvido pelo servidor. Null nos
  /// dois fins de linha (negada, faturada), onde não há próximo passo.
  ///
  /// A tela pergunta isto em vez de deduzir do status: o caminho mora no
  /// servidor, e uma etapa nova aparece aqui sem versão nova do app.
  final UserRole? waitingFor;

  /// O rótulo do estado, vindo do servidor. Null nas respostas anteriores ao
  /// campo — aí vale o rótulo local (ver [statusLabel]).
  final String? serverStatusLabel;

  /// A LINHA DO TEMPO — só vem no detalhe (`GET /barters/:code`). Vazia na
  /// listagem, e é [hasHistory] que separa "não veio" de "não tem".
  final List<BarterEventModel> events;

  /// O ANDAMENTO: a esteira INTEIRA, com o que já aconteceu preenchido. Vem
  /// pela mesma porta que [events] e pela mesma razão — listagem mostra estado,
  /// detalhe mostra trajetória.
  ///
  /// Vazia também quando o servidor não sabe desenhar o caminho desta permuta
  /// (um estado que nenhuma etapa produz). Aí vale [events], que é fato
  /// gravado — ver [hasProgress].
  final List<BarterStepModel> steps;

  /// OS PEDIDOS DE FORA DO BARTER desta permuta — os que esperam o admin, os
  /// que ele atendeu e os que recusou. Ver [BarterProductRequest].
  ///
  /// Vêm na listagem também, e não só no detalhe como [events]: um pedido em
  /// aberto é ESTADO ("esta permuta espera alguém"), e é isso que a fila do
  /// admin lista.
  final List<BarterProductRequest> productRequests;

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
    this.pledgeAreaHa = 0,
    this.pledgeYield = 0,
    this.pledgeMarginPercent = 0,
    required this.createdAt,
    this.updatedAt,
    this.managerId = '',
    this.managerName,
    this.managerNote,
    this.managerReviewedAt,
    this.consultantNote,
    this.consultantSentAt,
    this.producerAreaHa,
    this.sacksPerHa,
    this.reviewNote,
    this.reviewedBy,
    this.invoicedBy,
    this.invoicedAt,
    this.invoiceNote,
    this.invoices = const [],
    this.cprEmittedBy,
    this.cprEmittedAt,
    this.cprEmissionNote,
    this.cprSignedAt,
    this.cprSignatureNote,
    this.cprRegisteredAt,
    this.cprRegistryNumber,
    this.cprRegistryPlace,
    this.changeRequestStatus,
    this.changeRequestNote,
    this.changeRequestBy,
    this.changeRequestAt,
    this.changeRequestFrom,
    this.changeRequestReply,
    this.waitingFor,
    this.serverStatusLabel,
    this.events = const [],
    this.steps = const [],
    this.productRequests = const [],
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
      pledgeAreaHa: _asDouble(json['pledgeAreaHa']),
      pledgeYield: _asDouble(json['pledgeYield']),
      pledgeMarginPercent: _asDouble(json['pledgeMarginPercent']),
      createdAt: _asDate(json['createdAt']),
      updatedAt: _asDateOrNull(json['reviewedAt']),
      managerId: _asId(json['managerId']),
      managerName: json['managerName'] as String?,
      managerNote: json['managerNote'] as String?,
      managerReviewedAt: _asDateOrNull(json['managerReviewedAt']),
      consultantNote: json['consultantNote'] as String?,
      consultantSentAt: _asDateOrNull(json['consultantSentAt']),
      producerAreaHa: _asDoubleOrNull(json['producerAreaHa']),
      sacksPerHa: _asDoubleOrNull(json['sacksPerHa']),
      reviewNote: json['reviewNote'] as String?,
      reviewedBy: json['reviewedBy'] as String?,
      invoicedBy: json['invoicedBy'] as String?,
      invoicedAt: _asDateOrNull(json['invoicedAt']),
      invoiceNote: json['invoiceNote'] as String?,
      invoices: ((json['invoices'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(BarterInvoiceModel.fromJson)
          .toList(),
      cprEmittedBy: json['cprEmittedBy'] as String?,
      cprEmittedAt: _asDateOrNull(json['cprEmittedAt']),
      cprEmissionNote: json['cprEmissionNote'] as String?,
      cprSignedAt: _asDateOrNull(json['cprSignedAt']),
      cprSignatureNote: json['cprSignatureNote'] as String?,
      cprRegisteredAt: _asDateOrNull(json['cprRegisteredAt']),
      cprRegistryNumber: json['cprRegistryNumber'] as String?,
      cprRegistryPlace: json['cprRegistryPlace'] as String?,
      changeRequestStatus: json['changeRequestStatus'] as String?,
      changeRequestNote: json['changeRequestNote'] as String?,
      changeRequestBy: json['changeRequestBy'] as String?,
      changeRequestAt: _asDateOrNull(json['changeRequestAt']),
      changeRequestFrom: _asStatusOrNull(json['changeRequestFrom']),
      changeRequestReply: json['changeRequestReply'] as String?,
      waitingFor: _asRoleOrNull(json['waitingFor']),
      serverStatusLabel: json['statusLabel'] as String?,
      events: ((json['events'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(BarterEventModel.fromJson)
          .toList(),
      steps: ((json['steps'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(BarterStepModel.fromJson)
          .toList(),
      productRequests: ((json['productRequests'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(BarterProductRequest.fromJson)
          .toList(),
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

  /// Esta permuta tem área de penhor dimensionada?
  ///
  /// Falso nas anteriores à regra e nas respostas que não trouxeram os itens —
  /// e nos dois casos a tela CALA em vez de mostrar "0 ha exigidos", que é o
  /// que alguém leria como "esta permuta não precisa de garantia".
  bool get hasPledge => pledgeAreaHa > 0;

  /// A área do penhor como se lê ("24,00 ha").
  String get pledgeAreaLabel => '${pledgeAreaHa.toStringAsFixed(2).replaceAll('.', ',')} ha';

  /// DE ONDE SAIU O NÚMERO, em uma linha ("produção estimada de 60 sc/ha + 20%
  /// de margem"). É a resposta a "por que essa área?", que é o que todo mundo
  /// pergunta antes de aceitar a exigência — e o lançamento do Barter, onde ela
  /// mora, é tela que o consultor não abre.
  String get pledgeBasisLabel {
    final base = 'produção estimada de ${pledgeYield.toStringAsFixed(0)} sc/ha';
    return pledgeMarginPercent > 0
        ? '$base + ${pledgeMarginPercent.toStringAsFixed(0)}% de margem de segurança'
        : base;
  }

  /// A alíquota como se lê (ex.: "1,63%").
  String get taxRateLabel => '${taxRate.toStringAsFixed(2).replaceAll('.', ',')}%';

  /// Total de sacas do grão de pagamento a entregar.
  double get totalGrainQty => grains.fold(0.0, (sum, i) => sum + i.quantity);

  /// Total de unidades de insumos retiradas.
  double get totalInputQty => inputs.fold(0.0, (sum, i) => sum + i.quantity);

  /// Esta permuta chegou com os valores em R$?
  ///
  /// É a LENTE DE VALOR da API vista do lado de cá — a mesma pergunta que
  /// [BarterVersionModel.showsCurrency] faz sobre a tabela, agora sobre a
  /// permuta gravada. Quem não vê R$ recebe os itens sem `unitValue`, e tudo o
  /// que se mede em dinheiro aqui ([inputCost], [grainCredit], [balance],
  /// [taxAmount]) vale zero para ele — as telas dele já escondem esses números,
  /// e o que ele lê são as SACAS.
  bool get showsCurrency =>
      grains.any((i) => i.hasUnitValue) || inputs.any((i) => i.hasUnitValue);

  /// Grão de pagamento da permuta. Escolhe-se um único grão; havendo mais de um
  /// (dados legados), usa-se o maior como referência. Não fica preso à soja.
  ///
  /// O critério é o valor quando ele existe e a QUANTIDADE quando não — sem R$
  /// na resposta todos os `total` empatam em zero, e o "maior" sairia sendo
  /// simplesmente o primeiro da lista.
  BarterItem? get dominantGrain {
    BarterItem? best;
    double bestVal = -1;
    for (final g in grains) {
      final measure = g.hasUnitValue ? g.total : g.quantity;
      if (measure > bestVal) {
        bestVal = measure;
        best = g;
      }
    }
    return best;
  }

  /// Nome do grão de pagamento (ex.: "Soja"). Vazio se nenhum foi escolhido.
  String get referenceGrainName => dominantGrain?.productName ?? '';

  /// Valor (R$) de uma saca do grão de pagamento. Zero para quem não vê R$ —
  /// quem quer saber se dá para DIZER as sacas pergunta a [hasSacks].
  double get referenceValue => dominantGrain?.unitValue ?? 0;

  /// Dá para dizer, em sacas, quanto esta permuta paga?
  ///
  /// Existe porque `referenceValue > 0` era a pergunta que as telas faziam no
  /// lugar desta, e ela responde "não" ao consultor — de quem a API retém o R$
  /// justamente por ele já receber o número em sacas.
  bool get hasSacks => sacksToDeliver > 0;

  /// Sacas do grão de pagamento necessárias para cobrir o custo dos insumos — o
  /// coração da permuta: "quantas sacas o produtor precisa entregar para pagar".
  ///
  /// Duas medidas para o MESMO número, e a lente decide qual está ao alcance.
  /// Com R$ na resposta, é o custo dos insumos dividido pela cotação congelada;
  /// sem R$, é a quantidade gravada na linha do grão — que é esta mesma conta,
  /// já resolvida pelo servidor no momento do registro.
  ///
  /// A segunda medida é o conserto de um defeito real: enquanto isto dividia por
  /// uma cotação que chega zerada ao consultor, o detalhe da permuta dele
  /// mostrava "0 sc" em TOTAL A ENTREGAR, e o comprovante saía igual.
  double get sacksToDeliver =>
      showsCurrency && referenceValue > 0 ? inputCost / referenceValue : totalGrainQty;

  /// Valor pago em grãos, expresso em sacas do grão de pagamento.
  double get grainCreditInSacks =>
      showsCurrency && referenceValue > 0 ? grainCredit / referenceValue : totalGrainQty;

  /// Custo dos insumos expresso em sacas do grão de pagamento (= [sacksToDeliver]).
  double get inputCostInSacks => sacksToDeliver;

  /// Folga do pagamento expressa em sacas do grão de pagamento (~0).
  ///
  /// Sem R$ na resposta ela é zero e não "desconhecida", e isso é exato: as duas
  /// medidas de [sacksToDeliver] e [grainCreditInSacks] caem na mesma quantidade
  /// gravada, então a folga que se pode afirmar dali é nenhuma.
  double get balanceInSacks =>
      showsCurrency && referenceValue > 0 ? balance / referenceValue : 0;

  /// O parecer técnico já foi escrito? É o que separa a etapa do gerente da do
  /// comitê — e o que decide se o detalhe mostra o bloco do parecer.
  bool get hasManagerOpinion => (managerNote ?? '').trim().isNotEmpty;

  /// O PARECER DO CONSULTOR já está escrito? Vale no rascunho (ele salvou e
  /// ainda não mandou) e depois dele — o texto segue com a permuta.
  bool get hasConsultantOpinion => (consultantNote ?? '').trim().isNotEmpty;

  /// É RASCUNHO: registrada, com as contas congeladas, e ainda na mão do
  /// consultor. É o único estado em que ele tem o que fazer.
  bool get isDraft => status == BarterStatus.draft;

  /// Está esperando o parecer do gerente a quem foi enviada.
  bool get awaitsManager => status == BarterStatus.sentToManager;

  /// Está na mesa do COMITÊ, esperando ser aprovada ou negada.
  bool get awaitsCommittee => status == BarterStatus.pending;

  /// Foi aprovada e espera o FATURAMENTO — a fila do faturista.
  ///
  /// As DUAS aprovações contam: a ressalva é uma condição do negócio (garantia,
  /// seguro, aval), não um portão do fluxo, e a permuta com ressalva está na
  /// mesma fila. Ler só `approved` faria ela sumir da tela de quem tem de
  /// faturá-la.
  bool get awaitsInvoice =>
      status == BarterStatus.approved || status == BarterStatus.approvedWithConditions;

  /// Foi aprovada COM RESSALVA — há uma exigência escrita em [reviewNote].
  bool get hasConditions => status == BarterStatus.approvedWithConditions;

  /// Já foi faturada — e aí ela passa ao EMISSOR, que emite a cédula.
  ///
  /// Não é mais fim de linha: [awaitsCprIssue] é o que a tela do emissor lê.
  bool get isInvoiced => status == BarterStatus.invoiced;

  /* ── A cédula: o trecho do emissor ────────────────────────────────── */

  /// Faturada e ESPERANDO a emissão da cédula — a fila do emissor.
  bool get awaitsCprIssue => status == BarterStatus.invoiced;

  /// A cédula saiu e espera as ASSINATURAS.
  bool get awaitsSignatures => status == BarterStatus.cprIssued;

  /// Assinada, esperando o REGISTRO — a garantia ainda não vale contra
  /// terceiros, que é justamente o que precisa aparecer numa lista.
  bool get awaitsRegistration => status == BarterStatus.cprSigned;

  /// A cédula foi REGISTRADA: o fim da linha, agora de verdade.
  bool get isCprRegistered => status == BarterStatus.cprRegistered;

  /// A cédula já foi emitida? — inclusive se já foi assinada ou registrada.
  ///
  /// É o que separa o RASCUNHO do DOCUMENTO: até a emissão o consultor corrige
  /// à vontade; daí em diante o papel existe no mundo e não se reescreve.
  bool get isCprIssued => awaitsSignatures || awaitsRegistration || isCprRegistered;

  /// O FATURAMENTO já aconteceu — inclusive se a cédula já andou depois dele.
  ///
  /// É a pergunta de quem conta o que saiu ("quanto já foi faturado?"), e não
  /// `status == invoiced`: emitir a cédula não desfaz o faturamento.
  bool get wasInvoiced => isInvoiced || isCprIssued;

  /// FOI APROVADA pelo comitê — inclusive se já foi faturada ou emitida.
  ///
  /// É esta a pergunta dos painéis ("quanto já foi fechado?"), e não
  /// `status == approved`: faturar não desfaz a aprovação. Enquanto os totais
  /// olhavam um estado só, a permuta sumia da conta no dia em que a nota saía —
  /// o negócio mais consolidado que existe fazia a barra andar para trás.
  bool get wasApproved => awaitsInvoice || wasInvoiced;

  /// A decisão do comitê já foi tomada? (aprovada, negada ou já faturada).
  bool get hasDecision => reviewedBy != null && reviewedBy!.isNotEmpty;

  /// A linha do tempo veio nesta resposta? Distingue "não carregada" (listagem)
  /// de "sem passos" — que não existe: toda permuta nasce com o registro.
  bool get hasHistory => events.isNotEmpty;

  /// O andamento veio nesta resposta?
  ///
  /// Falso em dois casos, e a tela trata os dois igual (cai na linha do tempo
  /// dos eventos): a resposta é uma listagem, ou é de um servidor anterior a
  /// este campo. Nenhum dos dois é motivo para esconder a história da permuta.
  bool get hasProgress => steps.isNotEmpty;

  /* ── O pedido de alteração ────────────────────────────────────────── */

  /// Há um pedido de alteração ESPERANDO o admin?
  ///
  /// É o que acende a bandeira na permuta — para quem pediu ("já está lá") e
  /// para quem a tem na mesa ("os insumos disto podem mudar; não gaste o
  /// parecer ainda").
  bool get hasOpenChangeRequest => changeRequestStatus == 'open';

  /// O último pedido foi RECUSADO, e o motivo está em [changeRequestReply].
  ///
  /// Ele sobrevive à decisão, e o aceito não: o aceite fala pelo próprio efeito
  /// (a permuta voltou a ser rascunho), e a recusa precisa continuar visível —
  /// sem ela, o consultor veria só a permuta parada onde estava, sem nada
  /// dizendo que ele já pediu e ouviu não.
  bool get changeRequestDenied => changeRequestStatus == 'denied';

  /// ESTE usuário pode pedir alteração desta permuta agora?
  ///
  /// Mesma regra do servidor (`api/src/barters/change-request.ts`), repetida
  /// aqui pela razão de sempre: a tela não oferece um botão que levaria 422. O
  /// rascunho fica de fora porque ele já é dele — altera-se direto; a faturada,
  /// porque o que saiu para fora não se corrige por aqui.
  bool canBeChangedBy(String? userId) =>
      userId != null &&
      consultantId == userId &&
      !isDraft &&
      !wasInvoiced &&
      !hasOpenChangeRequest;

  /* ── O pedido de fora do Barter ───────────────────────────────────── */

  /// Os pedidos que ESPERAM o admin — os que acendem a bandeira na permuta.
  List<BarterProductRequest> get openProductRequests =>
      productRequests.where((r) => r.isOpen).toList();

  /// Os itens que entraram por pedido: o que está na permuta e não estava na
  /// tabela do Barter.
  List<BarterProductRequest> get addedProductRequests =>
      productRequests.where((r) => r.isAdded).toList();

  /// Há pedido de produto esperando resposta?
  bool get hasOpenProductRequest => productRequests.any((r) => r.isOpen);

  /// ESTE usuário pode pedir um produto de fora do Barter para esta permuta?
  ///
  /// Mesma janela do servidor (`api/src/barters/product-request.ts`), repetida
  /// aqui pela razão de sempre — a tela não oferece um botão que levaria 422.
  /// Ela vai do RASCUNHO até a mesa do comitê: depois da decisão, um insumo a
  /// mais mudaria o que foi aprovado, e o caminho passa a ser o pedido de
  /// alteração.
  bool canRequestProductBy(String? userId) =>
      userId != null &&
      consultantId == userId &&
      (isDraft || status == BarterStatus.sentToManager || status == BarterStatus.pending);

  /// Esta permuta espera o parecer DESTE gerente? Mesma conferência do servidor
  /// — repetida aqui só para a tela não oferecer um botão que levaria 403.
  bool awaitsOpinionFrom(String? managerId) =>
      managerId != null && managerId.isNotEmpty && awaitsManager && this.managerId == managerId;

  /// O gerente a quem ela foi enviada, como se lê na tela.
  String get managerLabel => managerName ?? 'não definido';

  /// A unidade de retirada como se lê na tela ("não informada" nas permutas
  /// anteriores ao cadastro de unidades).
  String get unitLabel => unitName.isEmpty ? 'não informada' : unitName;

  /// O estado como se lê na tela.
  ///
  /// Prefere o rótulo do SERVIDOR quando ele vem: é lá que a linha de produção
  /// está escrita, e um estado que este app ainda não conhece chega com o nome
  /// certo em vez de cair no rótulo genérico do `_asStatus`. O switch abaixo é
  /// o que sustenta as respostas antigas e os testes de unidade.
  String get statusLabel {
    final fromServer = serverStatusLabel;
    if (fromServer != null && fromServer.isNotEmpty) return fromServer;
    return barterStatusLabel(status);
  }
}

/// UM ARQUIVO ANEXADO — a nota fiscal do faturamento e o SCR do produtor.
///
/// Ele chega SEM os bytes, e é de propósito: o conteúdo se baixa por rota
/// própria, e uma listagem de cinquenta permutas não pode carregar cinquenta
/// PDFs para desenhar uma tabela.
class BarterFileModel {
  final String id;
  final String fileName;
  final String contentType;

  /// O tamanho em bytes — é o servidor quem o guarda, para a tela dizer
  /// "2,4 MB" sem ler o arquivo.
  final int size;

  final String uploadedBy;
  final DateTime? uploadedAt;

  const BarterFileModel({
    this.id = '',
    this.fileName = '',
    this.contentType = '',
    this.size = 0,
    this.uploadedBy = '',
    this.uploadedAt,
  });

  factory BarterFileModel.fromJson(Map<String, dynamic> json) => BarterFileModel(
        id: _asId(json['id']),
        fileName: (json['fileName'] ?? '') as String,
        contentType: (json['contentType'] ?? '') as String,
        size: (json['size'] as num?)?.toInt() ?? 0,
        uploadedBy: (json['uploadedBy'] ?? '') as String,
        uploadedAt: _asDateOrNull(json['uploadedAt']),
      );

  /// O tamanho como se lê. KB abaixo de um mega — um DANFE tem 80 KB, e
  /// "0,1 MB" esconde a diferença entre ele e um anexo de trinta páginas.
  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).round()} KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
  }
}

/// UMA NOTA FISCAL do faturamento, com o arquivo dela.
///
/// Ela era um par de campos de texto DENTRO da cédula, digitado por quem não
/// emitia a nota — e cabia uma só. Agora é lista, com o documento junto: a
/// permuta sai em mais de um carregamento, cada retirada gera a sua nota, e a
/// cancelada é reemitida.
class BarterInvoiceModel {
  final String id;
  final String number;
  final String series;

  /// A DUPLICATA que a nota originou, quando há. A cédula a cita ao lado da
  /// nota — as duas são documento do faturamento, não da negociação.
  final String duplicateNumber;

  final DateTime? issuedAt;
  final double value;
  final String? note;

  final String attachedBy;
  final DateTime? attachedAt;

  /// O anexo. Null só nas notas HERDADAS do campo de texto que ficava dentro da
  /// cédula — a tela as mostra como pendentes de arquivo em vez de escondê-las.
  final BarterFileModel? file;

  const BarterInvoiceModel({
    this.id = '',
    this.number = '',
    this.series = '',
    this.duplicateNumber = '',
    this.issuedAt,
    this.value = 0,
    this.note,
    this.attachedBy = '',
    this.attachedAt,
    this.file,
  });

  factory BarterInvoiceModel.fromJson(Map<String, dynamic> json) => BarterInvoiceModel(
        id: _asId(json['id']),
        number: (json['number'] ?? '') as String,
        series: (json['series'] ?? '') as String,
        duplicateNumber: (json['duplicateNumber'] ?? '') as String,
        issuedAt: _asDateOrNull(json['issuedAt']),
        value: _asDouble(json['value']),
        note: json['note'] as String?,
        attachedBy: (json['attachedBy'] ?? '') as String,
        attachedAt: _asDateOrNull(json['attachedAt']),
        file: json['file'] == null
            ? null
            : BarterFileModel.fromJson((json['file'] as Map).cast<String, dynamic>()),
      );

  /// "NF 55.318/1" — o jeito como a operação se refere a ela. A série só entra
  /// quando existe: há praça que não a usa, e "55.318/" seria ruído.
  String get label => series.isEmpty ? 'NF $number' : 'NF $number/$series';
}

/// O rótulo LOCAL de um estado da permuta.
///
/// Ele sustenta [BarterModel.statusLabel] quando a resposta não traz o rótulo do
/// servidor, e serve a quem precisa nomear um estado que NÃO é o atual da
/// permuta — o pedido de alteração é o caso: ele guarda de onde foi feito
/// (`changeRequestFrom`), e a tela diz "pedido com ela em Aprovada, a faturar"
/// em vez de imprimir o nome cru do enum.
String barterStatusLabel(BarterStatus status) {
  switch (status) {
    case BarterStatus.draft:
      return 'Rascunho';
    case BarterStatus.sentToManager:
      return 'No gerente';
    case BarterStatus.pending:
      return 'No comitê';
    case BarterStatus.approved:
      return 'Aprovada, a faturar';
    case BarterStatus.approvedWithConditions:
      return 'Aprovada com ressalva, a faturar';
    case BarterStatus.denied:
      return 'Negada';
    // "Faturada" sozinho dizia que tinha acabado. O rótulo agora diz o que
    // falta, que é o que muda a leitura de quem passa os olhos numa lista.
    case BarterStatus.invoiced:
      return 'Faturada, a emitir a CPR';
    case BarterStatus.cprIssued:
      return 'CPR emitida, a assinar';
    case BarterStatus.cprSigned:
      return 'CPR assinada, a registrar';
    case BarterStatus.cprRegistered:
      return 'CPR registrada';
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

  /// O código como se lê na tela (vazio vira "sem código").
  String get codeLabel => sku?.isNotEmpty == true ? sku! : 'sem código';

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

  /// O valor de UMA unidade deste insumo, na MOEDA DA LENTE: R$ para quem vê
  /// R$, SACAS do grão da safra para quem não vê — o consultor.
  ///
  /// O servidor manda um OU outro, nunca os dois: `price` ou `sacksPerUnit`
  /// (ver `toVersionPriceJson` em `api/src/common/serializers.ts`). Guardar os
  /// dois num campo só é deliberado, e é o que conserta o defeito que existia
  /// aqui: enquanto este campo lia só `price`, o consultor — que recebe
  /// `sacksPerUnit` — parseava zero, e a prévia da permuta dele mostrava 0 saca
  /// para qualquer quantidade de insumo.
  ///
  /// A conta é a MESMA nas duas moedas — soma quantidade × valor, divide pelo
  /// que custa uma saca —, e a única diferença é o divisor, que a versão sabe
  /// dizer (ver [BarterVersionModel.costPerSack]). Dois campos convidariam cada
  /// tela a escolher um, que foi exatamente como o defeito passou.
  final double perUnit;

  const VersionPriceModel({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.perUnit,
  });

  factory VersionPriceModel.fromJson(Map<String, dynamic> json) => VersionPriceModel(
        productId: _asId(json['productId']),
        productName: json['productName'] as String,
        unit: json['unit'] as String,
        perUnit: _asDouble(json['price'] ?? json['sacksPerUnit']),
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
  ///
  /// **Zero para quem não vê R$.** O servidor não a manda ao consultor de
  /// propósito: entregá-la a quem recebe a tabela em sacas devolveria os R$ por
  /// multiplicação. Quem precisa converter custo em sacas usa [costPerSack], que
  /// responde nas duas lentes.
  final double grainPrice;

  /// A PRODUTIVIDADE ESTIMADA da cultura (sc/ha) — a taxa que converte as sacas
  /// da permuta na ÁREA DE LAVOURA que precisa garanti-las.
  ///
  /// Ao contrário de [grainPrice], ela vai para TODO MUNDO, inclusive para quem
  /// não vê R$: é sacas por hectare, e não moeda. É a outra metade da conversão
  /// que o preço da saca começa, e é o que explica ao consultor por que a
  /// permuta dele exige a área que exige.
  ///
  /// Zero é a versão anterior ao campo — e nela o servidor RECUSA permuta nova,
  /// porque sem a taxa não há como dimensionar o penhor. A tela do admin lê este
  /// zero para mostrar o Barter vigente e travado.
  final double estimatedYield;

  /// Esta versão chegou com os valores em R$?
  ///
  /// É a LENTE DE VALOR da API vista do lado de cá: quem tem `prices.read`
  /// recebe `grainPrice` e a tabela em `price`; o consultor recebe a tabela já
  /// convertida em `sacksPerUnit`, e sem a cotação. A presença de `grainPrice` é
  /// o sinal porque é exatamente nela que o servidor decide — ver
  /// `toBarterVersionJson` em `api/src/common/serializers.ts`.
  final bool showsCurrency;

  final String status;

  /// Aceita permuta agora? Quem decide é o servidor (versão ativa e dentro da
  /// vigência), para o app não manter uma segunda cópia da regra.
  final bool isOpen;

  final DateTime startsAt;
  final DateTime? endsAt;
  final DateTime? closedAt;

  /// Quem encerrou — ou a FRASE do encerramento automático ("Automático — meta
  /// de vendas atingida"). O servidor escreve as duas coisas no mesmo campo de
  /// propósito: quem lê uma versão encerrada quer saber por que ela fechou, e a
  /// resposta é uma pessoa ou uma meta.
  final String? closedBy;

  /// Bater a meta ENCERRA este Barter, ou só avisa?
  ///
  /// A escolha é do lançamento e vive no servidor — o app não decide nada com
  /// ela, só conta ao admin em que modo o Barter está. Quem fecha, quando ligado,
  /// é a aprovação que cruza a meta (ver `closeIfGoalReached` na API).
  final bool closeOnGoal;
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
    // Padrão da RETAGUARDA porque é o único que se pode montar à mão: quem
    // escreve `grainPrice:` num construtor está escrevendo R$. O caminho que
    // vem da rede — [BarterVersionModel.fromJson] — nunca usa este padrão, ele
    // lê a lente do próprio JSON.
    this.showsCurrency = true,
    required this.status,
    required this.isOpen,
    required this.startsAt,
    required this.prices,
    this.endsAt,
    this.closedAt,
    this.closedBy,
    this.estimatedYield = 0,
    this.closeOnGoal = false,
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
      estimatedYield: _asDouble(json['estimatedYield']),
      showsCurrency: json['grainPrice'] != null,
      status: (json['status'] ?? 'closed') as String,
      isOpen: json['isOpen'] == true,
      startsAt: _asDate(json['startsAt']),
      endsAt: _asDateOrNull(json['endsAt']),
      closedAt: _asDateOrNull(json['closedAt']),
      closedBy: json['closedBy'] as String?,
      closeOnGoal: json['closeOnGoal'] == true,
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

  /// Quanto custa UMA SACA, na moeda da lente — o divisor que transforma custo
  /// em sacas.
  ///
  /// Em R$ é a cotação do grão; em sacas é **1**, porque o custo somado a partir
  /// de [VersionPriceModel.perUnit] já ESTÁ em sacas. É esta linha que permite
  /// [sacksToCover] continuar sendo espelho exato de `barter-math.ts`: a conta
  /// não muda, muda a unidade em que ela entra — e as duas dão o mesmo número,
  /// porque `Σ(qtd × preço/cotação)` é `Σ(qtd × preço)/cotação`.
  ///
  /// Somar em sacas e só então arredondar é o que o próprio servidor pede (ver
  /// o comentário de `inSacks` em `serializers.ts`): arredondar por linha
  /// introduziria uma diferença por item, e a prévia deixaria de bater com o
  /// que é gravado.
  double get costPerSack => showsCurrency ? grainPrice : 1;

  /// O valor de um insumo nesta versão, ou null se ele não está na tabela —
  /// e um insumo fora da tabela não é permutável nesta gestão.
  VersionPriceModel? priceOf(String productId) {
    for (final price in prices) {
      if (price.productId == productId) return price;
    }
    return null;
  }

  /// Alguma meta foi atingida? No modo manual é o aviso de "hora de encerrar"
  /// para o admin; no automático, a versão já vem encerrada do servidor.
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

  /// O VENCIMENTO DA CPR desta safra — a data em que o produtor entrega o grão.
  ///
  /// Mora na SAFRA, e não na cédula, porque ele muda conforme a CULTURA: soja
  /// vence na colheita da soja, milho safrinha no dele, e todas as cédulas de
  /// uma mesma safra vencem no mesmo dia. Enquanto foi campo do formulário, quem
  /// o digitava não tinha nada que dissesse qual era a data certa daquela
  /// cultura — e duas cédulas da mesma safra saíam com vencimentos diferentes.
  ///
  /// Nulo é "ainda não acertado", e não é erro: a safra abre sem ele e a
  /// pendência aparece na cédula, endereçada a quem a resolve (o admin, aqui).
  /// O servidor o copia para cada cédula a cada gravação, até ela ser emitida —
  /// depois disso, congela.
  final DateTime? cprDueDate;

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
    this.cprDueDate,
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
        cprDueDate: _asDateOrNull(json['cprDueDate']),
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
