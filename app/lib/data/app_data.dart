import '../models/models.dart';
import '../repositories/auth_repository.dart';
import '../repositories/barter_repository.dart';
import '../repositories/catalog_repository.dart';
import '../repositories/producer_repository.dart';
import '../repositories/consultant_repository.dart';

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

  /// Usuário logado (admin ou consultor).
  static UserModel? currentUser;

  /// Consultores (visível só para admin — a API restringe a rota).
  static List<UserModel> consultants = [];

  /// Produtores visíveis: a API devolve a carteira do consultor logado, ou
  /// todas as carteiras para o admin.
  static List<ProducerModel> producers = [];

  static List<ProductModel> grains = [];
  static List<ProductModel> inputs = [];
  static List<InputCategoryModel> categories = [];
  static List<BarterModel> barters = [];

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
    producers = [];
    grains = [];
    inputs = [];
    categories = [];
    barters = [];
  }

  /* ── Cargas / refresh ───────────────────────────────────────────────── */

  static Future<void> refreshAll() async {
    await Future.wait([
      refreshCatalog(),
      refreshProducers(),
      refreshBarters(),
      if (currentUser?.role == UserRole.admin) refreshConsultants(),
    ]);
  }

  static Future<void> refreshCatalog() async {
    final results = await Future.wait([
      _catalog.listProducts(),
      _catalog.listCategories(),
    ]);
    final products = results[0] as List<ProductModel>;
    grains = products.where((p) => p.type == ProductType.grain).toList();
    inputs = products.where((p) => p.type == ProductType.input).toList();
    categories = results[1] as List<InputCategoryModel>;
  }

  static Future<void> refreshProducers() async {
    producers = await _producers.list();
  }

  static Future<void> refreshConsultants() async {
    consultants = await _consultants.list();
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

  /// Busca uma categoria pelo id (null se não encontrada ou id null).
  static InputCategoryModel? categoryById(String? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /* ── Mutações (API primeiro, cache depois) ──────────────────────────── */

  static Future<BarterModel> createBarter({
    required String producerId,
    required String grainId,
    required Map<String, double> inputQuantities,
  }) async {
    final barter = await _barters.create(
      producerId: producerId,
      grainId: grainId,
      inputQuantities: inputQuantities,
    );
    barters.insert(0, barter);
    return barter;
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

  static Future<ProductModel> updatePrice(ProductModel product, double price) async {
    return _replaceProduct(await _catalog.updatePrice(product.id, price));
  }

  static Future<ProductModel> createProduct({
    required String name,
    required String unit,
    required ProductType type,
    required double currentPrice,
    double requiredPerHa = 0,
    String? categoryId,
  }) async {
    return _replaceProduct(await _catalog.createProduct(
      name: name,
      unit: unit,
      type: type,
      currentPrice: currentPrice,
      requiredPerHa: requiredPerHa,
      categoryId: categoryId,
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

  static Future<InputCategoryModel> saveCategory(
    InputCategoryModel category, {
    required bool isNew,
  }) async {
    final saved =
        isNew ? await _catalog.createCategory(category) : await _catalog.updateCategory(category);
    final index = categories.indexWhere((c) => c.id == saved.id);
    if (index == -1) {
      categories.add(saved);
    } else {
      categories[index] = saved;
    }
    return saved;
  }

  /// Excluir a pasta desvincula os insumos no servidor — recarrega o catálogo
  /// para os `categoryId` ficarem coerentes.
  static Future<void> deleteCategory(String id) async {
    await _catalog.deleteCategory(id);
    categories.removeWhere((c) => c.id == id);
    await refreshCatalog();
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
