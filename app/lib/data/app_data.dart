import '../models/models.dart';
import '../repositories/auth_repository.dart';
import '../repositories/barter_program_repository.dart';
import '../repositories/barter_repository.dart';
import '../repositories/catalog_repository.dart';
import '../repositories/producer_repository.dart';
import '../repositories/consultant_repository.dart';
import '../repositories/manager_repository.dart';
import '../repositories/unit_repository.dart';

/// Estado de dados do app: um cache em memória hidratado da API no login.
///
/// Substitui o antigo mock_data.dart mantendo leituras SÍNCRONAS (as telas
/// continuam lendo listas), enquanto TODA mutação passa pela API e atualiza o
/// cache com a resposta do servidor — que é a autoridade das regras de
/// negócio. O dataset é pequeno (cooperativa), então carregar tudo no login
/// mantém o app instantâneo e simples.
class AppData {
  AppData._();

  static final AuthRepository _auth = AuthRepository();
  static final ProducerRepository _producers = ProducerRepository();
  static final ConsultantRepository _consultants = ConsultantRepository();
  static final CatalogRepository _catalog = CatalogRepository();
  static final BarterRepository _barters = BarterRepository();
  static final BarterProgramRepository _program = BarterProgramRepository();
  static final UnitRepository _units = UnitRepository();
  static final ManagerRepository _managers = ManagerRepository();

  /// Usuário logado (admin ou consultor).
  static UserModel? currentUser;

  /// Consultores (visível só para admin — a API restringe a rota).
  static List<UserModel> consultants = [];

  /// Gerentes (idem). O app os carrega por um motivo só: o cadastro do
  /// consultor precisa escolher a quem as permutas dele serão enviadas.
  static List<UserModel> managers = [];

  /// Produtores visíveis: a API devolve a carteira do consultor logado, ou
  /// todas as carteiras para o admin.
  static List<ProducerModel> producers = [];

  /// As UNIDADES de retirada, em ordem alfabética. Todo papel carrega: o
  /// consultor escolhe entre elas ao registrar, o gerente descobre quais são as
  /// dele e o admin as cadastra.
  static List<UnitModel> units = [];

  static List<ProductModel> grains = [];
  static List<ProductModel> inputs = [];
  /// As CLASSES de produto, na ordem de exibição do servidor.
  static List<ProductClassModel> classes = [];
  static List<BarterModel> barters = [];

  /// A versão VIGENTE do Barter, ou null quando não há lançamento aberto.
  ///
  /// É o dado mais importante do cache para o consultor: sem ela não há grão,
  /// não há valores e não há permuta nova — a tela mostra "Barter fechado".
  static BarterVersionModel? currentVersion;

  /// As safras (só o admin carrega — a rota exige `barter.manage`).
  static List<SeasonModel> seasons = [];

  /// Os insumos que estão na tabela da versão vigente: é o que dá para permutar
  /// hoje. Fora da versão, o insumo existe no cadastro mas não tem valor
  /// acordado — e o servidor recusa.
  static List<ProductModel> get barterInputs {
    final version = currentVersion;
    if (version == null) return const [];
    return inputs.where((input) => version.priceOf(input.id) != null).toList();
  }

  /// O valor (R$) de um insumo na versão vigente, ou 0 se ele não está nela.
  static double priceOf(String productId) =>
      currentVersion?.priceOf(productId)?.price ?? 0;

  /* ── Sessão ─────────────────────────────────────────────────────────── */

  /// Autentica e hidrata todo o cache. Lança [ApiException] com mensagem
  /// legível em caso de falha.
  static Future<UserModel> login(String email, String password) async {
    final user = await _auth.login(email, password);
    currentUser = user;
    await _hydrateIfCleared(user);
    return user;
  }

  /// Carrega o cache só para quem já pode usar o app. Com a senha ainda
  /// provisória o servidor recusa as rotas de negócio (403) — pedir as listas
  /// aqui só produziria erro na cara de quem ainda vai definir a senha. A
  /// hidratação acontece depois da troca, ao entrar de fato.
  static Future<void> _hydrateIfCleared(UserModel user) async {
    if (user.mustChangePassword) return;
    await refreshAll();
  }

  /// Retoma a sessão guardada no aparelho e hidrata o cache. Devolve null
  /// quando não há o que retomar (nunca logou, ou o token já foi revogado no
  /// servidor). Falhas de rede sobem como [ApiException] para a tela de
  /// abertura oferecer nova tentativa, sem descartar a sessão.
  static Future<UserModel?> restoreSession() async {
    final user = await _auth.restore();
    if (user == null) return null;
    currentUser = user;
    await _hydrateIfCleared(user);
    return user;
  }

  /// Troca a senha do usuário logado e atualiza [currentUser] — é o que apaga
  /// o aviso de senha provisória e libera o painel.
  static Future<UserModel> changePassword(String current, String next) async {
    final updated = await _auth.changePassword(current, next);
    currentUser = updated;
    return updated;
  }

  static Future<void> logout() async {
    await _auth.logout();
    _clearCache();
  }

  /// Encerra a sessão local sem falar com o servidor — usado quando o próprio
  /// servidor já rejeitou o token (401).
  static Future<void> discardSession() async {
    await _auth.forget();
    _clearCache();
  }

  static void _clearCache() {
    currentUser = null;
    consultants = [];
    managers = [];
    producers = [];
    units = [];
    grains = [];
    inputs = [];
    classes = [];
    barters = [];
    currentVersion = null;
    seasons = [];
  }

  /* ── Cargas / refresh ───────────────────────────────────────────────── */

  static Future<void> refreshAll() async {
    final isAdmin = currentUser?.role == UserRole.admin;
    await Future.wait([
      refreshCatalog(),
      refreshProducers(),
      refreshUnits(),
      refreshBarters(),
      refreshBarterVersion(),
      if (isAdmin) refreshConsultants(),
      if (isAdmin) refreshManagers(),
      if (isAdmin) refreshSeasons(),
    ]);
  }

  /// As unidades de retirada. Todo papel carrega — sem elas o consultor não
  /// consegue registrar permuta e o gerente não sabe quais filas são dele.
  static Future<void> refreshUnits() async {
    units = await _units.list();
  }

  /// A versão vigente do Barter. Todo papel carrega — o consultor precisa dela
  /// para montar a permuta, e a retaguarda para saber o que está aberto.
  static Future<void> refreshBarterVersion() async {
    currentVersion = await _program.current();
  }

  /// As safras com o histórico de versões (admin).
  static Future<void> refreshSeasons() async {
    seasons = await _program.listSeasons();
  }

  /// Um produto com a linha do tempo completa, buscado sob demanda. A listagem
  /// do catálogo não carrega o histórico (ele cresce a cada versão publicada),
  /// então quem desenha o gráfico pede o detalhe.
  static Future<ProductModel> productDetail(String id) => _catalog.findProduct(id);

  static Future<void> refreshCatalog() async {
    final results = await Future.wait([
      _catalog.listProducts(),
      _catalog.listClasses(),
    ]);
    final products = results[0] as List<ProductModel>;
    grains = products.where((p) => p.type == ProductType.grain).toList();
    inputs = products.where((p) => p.type == ProductType.input).toList();
    classes = results[1] as List<ProductClassModel>;
  }

  static Future<void> refreshProducers() async {
    producers = await _producers.list();
  }

  static Future<void> refreshConsultants() async {
    consultants = await _consultants.list();
  }

  static Future<void> refreshManagers() async {
    managers = await _managers.list();
  }

  static Future<void> refreshBarters() async {
    barters = await _barters.list();
  }

  /* ── Consultas (mesmos contratos do antigo mock_data) ───────────────── */

  /// Busca um produtor pelo id (null se não encontrado).
  static ProducerModel? producerById(String id) {
    for (final p in producers) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Carteira de produtores visível para um usuário: consultor enxerga apenas
  /// os próprios; admin (consultantId null) enxerga todos. O servidor já aplica
  /// essa regra — aqui é apenas um filtro sobre o cache.
  static List<ProducerModel> producersForConsultant(String? consultantId) {
    if (consultantId == null) return List.of(producers);
    return producers.where((p) => p.consultantId == consultantId).toList();
  }

  /// Busca um consultor pelo id (null se não encontrado). Só o admin tem a
  /// lista de consultores carregada.
  static UserModel? consultantById(String id) {
    for (final s in consultants) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Busca uma unidade pelo id (null se não encontrada ou id vazio).
  static UnitModel? unitById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final u in units) {
      if (u.id == id) return u;
    }
    return null;
  }

  /// As permutas que esperam o parecer DESTE gerente — a fila dele.
  ///
  /// A permuta já chega com o destinatário dentro (`managerId`), então o recorte
  /// é sobre o próprio cache: o gerente não precisa da lista de consultores,
  /// que é rota de admin. O servidor aplica a mesma regra ao recusar o parecer
  /// de outro gerente.
  static List<BarterModel> opinionQueueFor(String managerId) =>
      barters.where((b) => b.awaitsOpinionFrom(managerId)).toList();

  /// Busca uma classe pelo id (null se não encontrada ou id null).
  static ProductClassModel? classById(String? id) {
    if (id == null) return null;
    for (final c in classes) {
      if (c.id == id) return c;
    }
    return null;
  }

  /* ── Mutações (API primeiro, cache depois) ──────────────────────────── */

  static Future<BarterModel> createBarter({
    required String producerId,
    required String unitId,
    required Map<String, double> inputQuantities,
  }) async {
    final barter = await _barters.create(
      producerId: producerId,
      unitId: unitId,
      inputQuantities: inputQuantities,
    );
    barters.insert(0, barter);
    return barter;
  }

  /* ── Unidades (admin cadastra; gerente responde por elas) ───────────── */

  static Future<UnitModel> saveUnit(UnitModel unit, {required bool isNew}) async {
    final saved = isNew ? await _units.create(unit) : await _units.update(unit);
    final index = units.indexWhere((u) => u.id == saved.id);
    if (index == -1) {
      units.add(saved);
    } else {
      units[index] = saved;
    }
    units.sort((a, b) => a.name.compareTo(b.name));
    return saved;
  }

  /// Excluir a unidade desfaz o vínculo das permutas dela no servidor (o nome
  /// congelado fica, e a etapa do gerente não é afetada — a unidade é só o
  /// local). As permutas em cache são recarregadas em vez de remendadas, pelo
  /// mesmo motivo da exclusão de consultor.
  static Future<void> deleteUnit(String id) async {
    await _units.delete(id);
    units.removeWhere((u) => u.id == id);
    await refreshBarters();
  }

  /// PARECER TÉCNICO do gerente. A permuta volta do servidor já em revisão —
  /// o cache guarda a resposta dele, nunca uma versão montada aqui.
  static Future<BarterModel> giveOpinion(String code, String note) async {
    final updated = await _barters.giveOpinion(code, note);
    final index = barters.indexWhere((b) => b.id == updated.id);
    if (index != -1) barters[index] = updated;
    return updated;
  }

  /* ── Lançamento do Barter (admin) ───────────────────────────────────── */

  /// Publica a próxima versão a partir da planilha. Recarrega safras E versão
  /// vigente: publicar encerra a anterior no servidor, e um cache remendado à
  /// mão mostraria duas vigentes.
  static Future<BarterVersionModel> publishVersion({
    required String seasonCode,
    required String filename,
    required List<int> bytes,
    required double grainPrice,
    DateTime? endsAt,
    double? targetSales,
    double? targetSacks,
    int? targetBarters,
    String? note,
    bool carryOver = false,
  }) async {
    final version = await _program.publishFromFile(
      seasonCode: seasonCode,
      filename: filename,
      bytes: bytes,
      grainPrice: grainPrice,
      endsAt: endsAt,
      targetSales: targetSales,
      targetSacks: targetSacks,
      targetBarters: targetBarters,
      note: note,
      carryOver: carryOver,
    );
    // A publicação mexe no catálogo (cria insumos, atualiza o último valor
    // publicado), então o cache inteiro do catálogo precisa vir de novo.
    await Future.wait([refreshCatalog(), refreshSeasons(), refreshBarterVersion()]);
    return version;
  }

  /// Corrige um valor da versão vigente (o grão da safra inclusive).
  static Future<void> updateVersionPrice(String productId, double price) async {
    final version = currentVersion;
    if (version == null) return;
    currentVersion = await _program.updatePrice(version.code, productId, price);
    // O produto guarda o último valor publicado e ganha ponto no histórico.
    await refreshCatalog();
  }

  /// Detalhe de uma versão, com metas e realizado.
  static Future<BarterVersionModel> versionDetail(String code) => _program.findVersion(code);

  /// Encerra o Barter vigente: o consultor passa a ver "Barter fechado".
  static Future<void> closeVersion(String code) async {
    await _program.closeVersion(code);
    await Future.wait([refreshSeasons(), refreshBarterVersion()]);
  }

  static Future<void> closeSeason(String code) async {
    await _program.closeSeason(code);
    await Future.wait([refreshSeasons(), refreshBarterVersion()]);
  }

  static Future<void> openSeason({
    required String grainId,
    required int year,
    String? name,
    String? letter,
  }) async {
    await _program.openSeason(grainId: grainId, year: year, name: name, letter: letter);
    await Future.wait([refreshSeasons(), refreshBarterVersion()]);
  }

  static Future<BarterModel> reviewBarter(
    String code,
    BarterStatus status,
    String note,
  ) async {
    final updated = await _barters.review(code, status, note);
    final index = barters.indexWhere((b) => b.id == updated.id);
    if (index != -1) {
      barters[index] = updated;
    }
    return updated;
  }

  static Future<ProducerModel> saveProducer(ProducerModel producer, {required bool isNew}) async {
    final saved = isNew ? await _producers.create(producer) : await _producers.update(producer);
    final index = producers.indexWhere((p) => p.id == saved.id);
    if (index == -1) {
      producers.add(saved);
    } else {
      producers[index] = saved;
    }
    return saved;
  }

  static Future<void> deleteProducer(String id) async {
    await _producers.delete(id);
    producers.removeWhere((p) => p.id == id);
  }

  /// Provisiona um consultor. Devolve o cadastro E a senha de primeira
  /// entrada, que a tela precisa mostrar na hora: ela não pode ser consultada
  /// depois. Criação e edição são separadas justamente por isso — só uma delas
  /// produz um segredo com prazo de validade de uma tela.
  static Future<ProvisionedConsultant> createConsultant(UserModel consultant) async {
    final provisioned = await _consultants.create(consultant);
    _cacheConsultant(provisioned.consultant);
    return provisioned;
  }

  static Future<UserModel> updateConsultant(UserModel consultant) async {
    final saved = await _consultants.update(consultant);
    _cacheConsultant(saved);
    return saved;
  }

  /// Nova senha provisória para um consultor. As sessões dele caem no
  /// servidor; aqui só o cadastro precisa ser atualizado (ele volta com
  /// `mustChangePassword` ligado).
  static Future<ProvisionedConsultant> resetConsultantPassword(String id) async {
    final provisioned = await _consultants.resetPassword(id);
    _cacheConsultant(provisioned.consultant);
    return provisioned;
  }

  /* ── Gerentes (quem recebe as permutas para dar parecer) ────────────── */

  static Future<ProvisionedConsultant> createManager(UserModel manager) async {
    final provisioned = await _managers.create(manager);
    _cacheManager(provisioned.consultant);
    return provisioned;
  }

  static Future<UserModel> updateManager(UserModel manager) async {
    final saved = await _managers.update(manager);
    _cacheManager(saved);
    // O nome dele aparece dentro de cada consultor do time (`managerName`), e
    // o cache guarda essa cópia — recarrega em vez de remendar linha a linha.
    await refreshConsultants();
    return saved;
  }

  static Future<ProvisionedConsultant> resetManagerPassword(String id) async {
    final provisioned = await _managers.resetPassword(id);
    _cacheManager(provisioned.consultant);
    return provisioned;
  }

  /// O servidor recusa enquanto ele tiver time ou fila; quando aceita, os
  /// consultores dele já não existiam para apontar, então não há o que
  /// recarregar além da própria lista.
  static Future<void> deleteManager(String id) async {
    await _managers.delete(id);
    managers.removeWhere((m) => m.id == id);
  }

  static void _cacheManager(UserModel saved) {
    final index = managers.indexWhere((m) => m.id == saved.id);
    if (index == -1) {
      managers.add(saved);
    } else {
      managers[index] = saved;
    }
  }

  static void _cacheConsultant(UserModel saved) {
    final index = consultants.indexWhere((s) => s.id == saved.id);
    if (index == -1) {
      consultants.add(saved);
    } else {
      consultants[index] = saved;
    }
  }

  /// Excluir consultor deixa os produtores da carteira sem dono (regra do
  /// servidor) — recarrega a lista para refletir os vínculos desfeitos.
  static Future<void> deleteConsultant(String id) async {
    await _consultants.delete(id);
    consultants.removeWhere((s) => s.id == id);
    await refreshProducers();
  }

  static Future<ProductModel> createProduct({
    required String name,
    String sku = '',
    required String unit,
    required ProductType type,
    required double currentPrice,
    double requiredPerHa = 0,
    String? classId,
  }) async {
    return _replaceProduct(await _catalog.createProduct(
      name: name,
      sku: sku,
      unit: unit,
      type: type,
      currentPrice: currentPrice,
      requiredPerHa: requiredPerHa,
      classId: classId,
    ));
  }

  /// Tira o produto do catálogo. O histórico não é afetado — as permutas
  /// guardam o snapshot do item —, mas as permutas em cache passam a apontar
  /// para um produto que não existe mais, então recarrega para o app refletir
  /// exatamente o que o servidor tem.
  static Future<void> deleteProduct(ProductModel product) async {
    await _catalog.deleteProduct(product.id);
    (product.type == ProductType.grain ? grains : inputs)
        .removeWhere((p) => p.id == product.id);
    await refreshBarters();
  }

  static Future<ProductModel> updateProductFields(
    ProductModel product,
    Map<String, dynamic> fields,
  ) async {
    return _replaceProduct(await _catalog.updateProduct(product.id, fields));
  }

  /// Ajusta a regra de mínimo de uma classe. Não há criar nem excluir: a lista
  /// vem da lista de preços do fornecedor, e o casamento por nome normalizado
  /// é o que mantém o vocabulário estável entre uma carga e outra.
  static Future<ProductClassModel> updateClassRule(ProductClassModel productClass) async {
    final saved = await _catalog.updateClassRule(productClass);
    final index = classes.indexWhere((c) => c.id == saved.id);
    if (index != -1) classes[index] = saved;
    return saved;
  }

  static ProductModel _replaceProduct(ProductModel updated) {
    final list = updated.type == ProductType.grain ? grains : inputs;
    final index = list.indexWhere((p) => p.id == updated.id);
    if (index == -1) {
      list.add(updated);
    } else {
      list[index] = updated;
    }
    return updated;
  }
}
