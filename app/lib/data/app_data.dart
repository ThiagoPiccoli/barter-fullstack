import '../models/models.dart';
import '../repositories/auth_repository.dart';
import '../repositories/barter_repository.dart';
import '../repositories/catalog_repository.dart';
import '../repositories/producer_repository.dart';
import '../repositories/seller_repository.dart';

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
  static final SellerRepository _sellers = SellerRepository();
  static final CatalogRepository _catalog = CatalogRepository();
  static final BarterRepository _barters = BarterRepository();

  /// Usuário logado (admin ou vendedor).
  static UserModel? currentUser;

  /// Vendedores (visível só para admin — a API restringe a rota).
  static List<UserModel> sellers = [];

  /// Produtores visíveis: a API devolve a carteira do vendedor logado, ou
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
    sellers = [];
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
      if (currentUser?.role == UserRole.admin) refreshSellers(),
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

  static Future<void> refreshSellers() async {
    sellers = await _sellers.list();
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

  /// Carteira de produtores visível para um usuário: vendedor enxerga apenas
  /// os próprios; admin (sellerId null) enxerga todos. O servidor já aplica
  /// essa regra — aqui é apenas um filtro sobre o cache.
  static List<ProducerModel> producersForSeller(String? sellerId) {
    if (sellerId == null) return List.of(producers);
    return producers.where((p) => p.sellerId == sellerId).toList();
  }

  /// Busca um vendedor pelo id (null se não encontrado). Só o admin tem a
  /// lista de vendedores carregada.
  static UserModel? sellerById(String id) {
    for (final s in sellers) {
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

  static Future<UserModel> saveSeller(UserModel seller, {required bool isNew}) async {
    final saved = isNew ? await _sellers.create(seller) : await _sellers.update(seller);
    final index = sellers.indexWhere((s) => s.id == saved.id);
    if (index == -1) {
      sellers.add(saved);
    } else {
      sellers[index] = saved;
    }
    return saved;
  }

  /// Excluir vendedor deixa os produtores da carteira sem dono (regra do
  /// servidor) — recarrega a lista para refletir os vínculos desfeitos.
  static Future<void> deleteSeller(String id) async {
    await _sellers.delete(id);
    sellers.removeWhere((s) => s.id == id);
    await refreshProducers();
  }

  static Future<ProductModel> updatePrice(ProductModel product, double price) async {
    return _replaceProduct(await _catalog.updatePrice(product.id, price));
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
