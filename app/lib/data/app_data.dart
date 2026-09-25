import '../models/barter_simulation.dart';
import '../models/models.dart';
import '../services/api/api_client.dart';
import '../services/offline_cache.dart';
import '../services/simulation_check.dart';
import '../services/simulation_storage.dart';
import '../repositories/auth_repository.dart';
import '../repositories/barter_program_repository.dart';
import '../repositories/barter_repository.dart';
import '../repositories/catalog_repository.dart';
import '../repositories/producer_repository.dart';
import '../repositories/committee_repository.dart';
import '../repositories/creditor_repository.dart';
import '../repositories/insurance_repository.dart';
import '../repositories/staff_repository.dart';
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
  static const StaffRepository _consultants = StaffRepository('/consultants');
  static final CatalogRepository _catalog = CatalogRepository();
  static final BarterRepository _barters = BarterRepository();
  static final BarterProgramRepository _program = BarterProgramRepository();
  static final UnitRepository _units = UnitRepository();

  /// A BASE DE SEGUROS por município — quanto custa segurar um hectare em cada
  /// praça. O admin a mantém; todo mundo a lê.
  static final InsuranceRepository _insurance = InsuranceRepository();
  static const StaffRepository _managers = StaffRepository('/managers');

  /// FATURISTAS — quem fatura o que o comitê aprovou e anexa as notas. Rota de
  /// admin, como as outras de pessoas.
  static const StaffRepository _billers = StaffRepository('/billers');

  /// EMISSORES — o posto da CÉDULA: conferem o que o consultor preencheu,
  /// emitem o título, colhem as assinaturas e o levam a registro.
  static const StaffRepository _emitters = StaffRepository('/emitters');

  /// O COMITÊ — cadastro único, e por isso um repositório de outra forma: sem
  /// lista, sem id e sem exclusão.
  static final CommitteeRepository _committee = CommitteeRepository();

  /// A CREDORA — a empresa nos documentos que ela emite. Cadastro único, como o
  /// comitê, e mantido pelo admin OU pelo faturista.
  static final CreditorRepository _creditor = CreditorRepository();

  /// Usuário logado (admin ou consultor).
  static UserModel? currentUser;

  /// O usuário logado pode isto?
  ///
  /// É a ÚNICA pergunta de autorização do app, e a resposta é sempre do
  /// servidor (ver [Capability]): as telas perguntam "pode decidir?" em vez de
  /// "é admin?". Foi assim que a decisão da permuta pôde sair do admin e ir
  /// para o comitê sem uma linha de tela mudar de lugar.
  ///
  /// Sem ninguém logado, não pode nada — falha fechando.
  static bool can(String capability) => currentUser?.can(capability) ?? false;

  /// Consultores (visível só para admin — a API restringe a rota).
  static List<UserModel> consultants = [];

  /// Gerentes (idem). O app os carrega por um motivo só: o cadastro do
  /// consultor precisa escolher a quem as permutas dele serão enviadas.
  static List<UserModel> managers = [];

  /// FATURISTAS cadastrados (só o admin enxerga — a API restringe a rota).
  static List<UserModel> billers = [];

  /// EMISSORES cadastrados (idem). Sem pelo menos um, toda permuta faturada
  /// para em "a emitir a CPR" — é a primeira coisa que falta numa instalação
  /// nova.
  static List<UserModel> emitters = [];

  /// O CADASTRO DO COMITÊ, ou null enquanto ele não existe.
  ///
  /// Um, e não uma lista: o comitê é uma REUNIÃO, e a conta é do órgão (ver
  /// CommitteeRepository). Null é estado normal do sistema recém-instalado — e é
  /// o que a tela de cadastros do admin existe para resolver.
  static UserModel? committee;

  /// Produtores visíveis: a API devolve a carteira do consultor logado, ou
  /// todas as carteiras para o admin.
  static List<ProducerModel> producers = [];

  /// As UNIDADES de retirada, em ordem alfabética. Todo papel carrega: o
  /// consultor escolhe entre elas ao registrar, o gerente descobre quais são as
  /// dele e o admin as cadastra.
  static List<UnitModel> units = [];

  /// AS PRAÇAS da base de seguros, em ordem alfabética.
  ///
  /// Ela é carregada para todo mundo, e não só para o admin, por causa do
  /// CONSULTOR: quando o Barter vigente leva seguro, a prévia da permuta dele
  /// precisa mostrar quanto a apólice vai custar ao cliente ANTES de ele fechar
  /// o negócio. Quem não vê R$ recebe a taxa em sacas por hectare.
  static List<InsuranceRateModel> insuranceRates = [];

  static List<ProductModel> grains = [];
  static List<ProductModel> inputs = [];
  /// As CLASSES de produto, na ordem de exibição do servidor.
  static List<ProductClassModel> classes = [];
  static List<BarterModel> barters = [];

  /// As SIMULAÇÕES gravadas neste aparelho — permutas montadas que ainda não
  /// foram enviadas ao gerente.
  ///
  /// É a única lista do cache que NÃO vem da API: ela é lida do aparelho, e por
  /// isso continua respondendo quando não há sinal. Guarda as simulações de
  /// todos os consultores que já usaram este aparelho; quem separa por dono é
  /// [mySimulations].
  static List<BarterSimulation> simulations = [];

  /// O app está rodando com o pacote GRAVADO no aparelho, sem ter conseguido
  /// falar com o servidor nesta abertura.
  ///
  /// Muda o que as telas dizem, não o que elas deixam fazer: montar e guardar
  /// simulação funciona igual, e encaminhar ao gerente sempre exigiu rede.
  static bool isOffline = false;

  /// Quando o pacote do Barter foi baixado pela última vez — null se este
  /// aparelho NUNCA sincronizou.
  ///
  /// É o que separa duas telas que pareciam a mesma: "não há Barter aberto"
  /// (o servidor respondeu, e a resposta foi nenhuma) de "ainda não baixei o
  /// Barter" (ninguém perguntou). A primeira é um fato do negócio; a segunda é
  /// uma pendência do aparelho, e só ela se resolve conectando.
  static DateTime? lastSyncAt;

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

  /// O valor de um insumo na versão vigente — na MOEDA DA LENTE (R$ para a
  /// retaguarda, sacas para o consultor) —, ou 0 se ele não está nela.
  ///
  /// Quem soma isto obtém um custo na mesma moeda, e quem quer o custo em sacas
  /// divide por [BarterVersionModel.costPerSack]. Ver [VersionPriceModel.perUnit].
  static double valuePerUnitOf(String productId) =>
      currentVersion?.priceOf(productId)?.perUnit ?? 0;

  /* ── Sessão ─────────────────────────────────────────────────────────── */

  /// Autentica e hidrata todo o cache. Lança [ApiException] com mensagem
  /// legível em caso de falha.
  static Future<UserModel> login(String email, String password) async {
    final user = await _auth.login(email, password);
    currentUser = user;
    // As simulações vêm ANTES da hidratação, e fora dela: elas são do aparelho,
    // e [refreshAll] é o passo que depende de rede. Carregá-las junto faria o
    // trabalho guardado offline sumir da tela justamente quando a API não
    // responde — que é quando ele é a única coisa que o consultor ainda tem.
    await loadSimulations();
    await _hydrateIfCleared(user);
    isOffline = false;
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
    await loadSimulations();
    try {
      final user = await _auth.restore();
      if (user == null) return null;
      currentUser = user;
      await _hydrateIfCleared(user);
      isOffline = false;
      return user;
    } on ApiException {
      // O servidor não respondeu. Um 401 não chega aqui: [AuthRepository.restore]
      // já o trata esquecendo a sessão e devolvendo null, então o que sobra é
      // falta de rede ou API fora do ar — e nenhuma das duas invalida sessão.
      final cached = await _restoreFromCache();
      if (cached == null) rethrow;
      return cached;
    }
  }

  /// Abre o app com o pacote gravado no aparelho.
  ///
  /// É o caminho de quem liga o celular na lavoura: sem isto, a tela de abertura
  /// parava em "tentar novamente" e o consultor não alcançava nem as simulações
  /// que ele mesmo tinha guardado.
  ///
  /// **O que esta sessão vale.** Ela é o cache dizendo quem estava logado, não o
  /// servidor confirmando que ainda está — offline, essa confirmação não existe.
  /// O que se ganha é ler os próprios dados e montar simulação; o que continua
  /// impossível é ENCAMINHAR, que sempre exigiu rede. Se a conta tiver sido
  /// revogada nesse meio-tempo, o 401 aparece na primeira chamada real e o app
  /// volta ao login — a permuta não entra, e é isso que precisa ser verdade.
  static Future<UserModel?> _restoreFromCache() async {
    final package = await OfflineCache.load();
    final row = package?.user;
    if (package == null || row == null) return null;

    final UserModel user;
    try {
      user = UserModel.fromJson(row);
    } catch (_) {
      return null;
    }
    // Senha ainda provisória não abre offline: definir a senha é uma conversa
    // com o servidor, e deixar entrar aqui só levaria a uma tela que não
    // consegue concluir nada.
    if (user.mustChangePassword) return null;

    // O `/me` pode ter passado e a hidratação, não — nesse caso o usuário fresco
    // vale mais do que o gravado, e só as listas vêm do pacote.
    currentUser ??= user;
    _applyPackage(package);
    isOffline = true;
    return currentUser;
  }

  /// Repõe o cache em memória a partir do pacote gravado. As permutas já
  /// enviadas ficam vazias de propósito: elas são do servidor, e uma lista
  /// desatualizada de permutas alheias vale menos do que a ausência dela — o que
  /// o consultor precisa offline são as SIMULAÇÕES, que vêm de outro lugar.
  static void _applyPackage(OfflinePackage package) {
    final products = _catalog.parseProducts(package.products);
    grains = products.where((p) => p.type == ProductType.grain).toList();
    inputs = products.where((p) => p.type == ProductType.input).toList();
    classes = _catalog.parseClasses(package.classes);
    producers = _producers.parse(package.producers);
    units = _units.parse(package.units);
    insuranceRates = _insurance.parse(package.insuranceRates);
    currentVersion = _program.parseVersion(package.version);
    lastSyncAt = package.savedAt;
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
    // O pacote sai junto: carteira e tabela do Barter não têm por que continuar
    // no aparelho depois que a pessoa se desconectou. As SIMULAÇÕES ficam — elas
    // são trabalho dela, e reaparecem no próximo login.
    await OfflineCache.clear();
    _clearCache();
  }

  /// Encerra a sessão local sem falar com o servidor — usado quando o próprio
  /// servidor já rejeitou o token (401).
  static Future<void> discardSession() async {
    await _auth.forget();
    await OfflineCache.clear();
    _clearCache();
  }

  static void _clearCache() {
    currentUser = null;
    consultants = [];
    managers = [];
    billers = [];
    emitters = [];
    committee = null;
    producers = [];
    units = [];
    insuranceRates = [];
    grains = [];
    inputs = [];
    classes = [];
    barters = [];
    currentVersion = null;
    seasons = [];
    isOffline = false;
    lastSyncAt = null;
    // Só a CÓPIA EM MEMÓRIA cai; o aparelho continua com as simulações
    // gravadas. Sair do app (ou tomar um 401 por sessão expirada) não pode
    // apagar o trabalho de campo de ninguém — no próximo login,
    // [loadSimulations] o traz de volta. Limpar aqui é só para a sessão seguinte
    // não herdar a lista da anterior sem ter lido o disco.
    simulations = [];
  }

  /* ── Cargas / refresh ───────────────────────────────────────────────── */

  static Future<void> refreshAll() async {
    final isAdmin = currentUser?.role == UserRole.admin;
    await Future.wait([
      syncOfflinePackage(),
      refreshBarters(),
      if (isAdmin) refreshConsultants(),
      if (isAdmin) refreshManagers(),
      if (isAdmin) refreshBillers(),
      if (isAdmin) refreshEmitters(),
      if (isAdmin) refreshCommittee(),
      if (isAdmin) refreshSeasons(),
      // A BASE DE SEGUROS vai para todo mundo: ela é leitura aberta, e é da
      // prévia do consultor que ela participa. Ver `insuranceRates`.
      refreshInsuranceRates(),
    ]);
  }

  /// Baixa AS CINCO COISAS que montar uma permuta exige — versão vigente,
  /// catálogo, classes, carteira e unidades — e as grava no aparelho.
  ///
  /// Elas viajam juntas de propósito, e este é o único lugar que escreve o
  /// cache. Uma versão cuja tabela referencia um catálogo de outro momento
  /// produz um número de sacas que nunca existiu; buscar as cinco na mesma
  /// viagem é o que impede o pacote de ficar internamente incoerente. Os
  /// refreshes avulsos abaixo continuam existindo para quem só quer atualizar a
  /// memória, e não tocam no disco.
  ///
  /// Só o consultor precisa do pacote gravado — é ele que vai a campo. Gravar
  /// para o admin encheria o cofre com a base inteira sem que nada fosse usar.
  static Future<void> syncOfflinePackage() async {
    final results = await Future.wait([
      _catalog.listProductsRaw(),
      _catalog.listClassesRaw(),
      _producers.listRaw(),
      _units.listRaw(),
      _program.currentRaw(),
      // A BASE DE SEGUROS viaja com as outras cinco, e pelo mesmo motivo que
      // elas: a prévia da permuta depende dela quando o Barter leva seguro, e
      // quem monta permuta faz isso na fazenda, sem sinal.
      _insurance.listRaw(),
    ]);

    final productRows = results[0] as List<Map<String, dynamic>>;
    final classRows = results[1] as List<Map<String, dynamic>>;
    final producerRows = results[2] as List<Map<String, dynamic>>;
    final unitRows = results[3] as List<Map<String, dynamic>>;
    final versionRow = results[4] as Map<String, dynamic>?;
    final rateRows = results[5] as List<Map<String, dynamic>>;

    final package = OfflinePackage(
      savedAt: DateTime.now(),
      user: _auth.lastMeRaw,
      version: versionRow,
      products: productRows,
      classes: classRows,
      producers: producerRows,
      units: unitRows,
      insuranceRates: rateRows,
    );

    _applyPackage(package);
    isOffline = false;

    if (currentUser?.role == UserRole.consultant) {
      await OfflineCache.save(package);
    }
  }

  /// As unidades de retirada. Todo papel carrega — sem elas o consultor não
  /// consegue registrar permuta e o gerente não sabe quais filas são dele.
  static Future<void> refreshUnits() async {
    units = await _units.list();
  }

  /// A BASE DE SEGUROS por município.
  ///
  /// Falhar aqui NÃO pode derrubar o login nem o refresh: o seguro é opcional, e
  /// um Barter sem ele não depende desta lista para nada. Sem a base, a tela do
  /// consultor deixa de mostrar a prévia do custo — e quem cobra a praça que
  /// falta continua sendo o servidor, no registro, com a frase que nomeia o
  /// município.
  static Future<void> refreshInsuranceRates() async {
    try {
      insuranceRates = await _insurance.list();
    } on ApiException {
      // Mantém o que já estava em memória: uma lista zerada por falha de rede
      // faria a tela afirmar que não há praça cadastrada nenhuma.
    }
  }

  /// A TAXA da praça deste produtor, ou `null` quando ela não está na base.
  ///
  /// A comparação é a MESMA do servidor (`sameCity`), e ela tem duas partes. A
  /// primeira é a forma canônica — sem acento, sem caixa, sem espaço em volta
  /// da barra: o cadastro do produtor tem "Maringá/PR" e a base pode ter
  /// "maringa / pr", escritos por duas pessoas diferentes.
  ///
  /// A segunda é a UF, e é o caso NORMAL: a planilha da seguradora é toda de um
  /// estado só e traz "TUPANCIRETÃ", enquanto o cadastro do produtor traz
  /// "Tupanciretã/RS". Quem não declara o estado não contradiz quem declara —
  /// mas dois estados DIFERENTES separam de verdade ("Bom Jesus/RS" não é "Bom
  /// Jesus/SC"), e duas praças casando ao mesmo tempo é ambiguidade: devolve
  /// `null`, como o servidor, em vez de escolher uma delas no palpite.
  static InsuranceRateModel? insuranceRateFor(String city) {
    final key = _cityKey(city);
    if (key.isEmpty) return null;

    final matches = insuranceRates.where((rate) => _sameCity(rate.city, city)).toList();
    if (matches.length == 1) return matches.single;
    // Empate: a praça escrita exatamente igual vence — é o que acontece quando
    // a base tem "Bom Jesus/RS" e "Bom Jesus/SC" e o produtor disse qual é.
    for (final rate in matches) {
      if (_cityKey(rate.city) == key) return rate;
    }
    return null;
  }

  /// Estes dois textos falam do mesmo município? Ver `sameCity` na API.
  static bool _sameCity(String a, String b) {
    final nameA = _cityKey(a).split('/').first.trim();
    final nameB = _cityKey(b).split('/').first.trim();
    if (nameA != nameB) return false;
    final ufA = _uf(a);
    final ufB = _uf(b);
    return ufA.isEmpty || ufB.isEmpty || ufA == ufB;
  }

  /// A UF, quando ela foi escrita. Vazio quando o município veio sozinho.
  static String _uf(String city) {
    final parts = _cityKey(city).split('/');
    return parts.length > 1 ? parts.last.trim() : '';
  }

  /// A forma COMPARÁVEL de um município — a mesma regra do `cityKeyOf` da API:
  /// sem acento, sem caixa, sem espaço repetido e sem espaço em volta da barra.
  ///
  /// O acento cai aqui, e não só lá, porque as duas pontas precisam concordar:
  /// o dia em que a base tiver "maringa/pr" e o produtor "Maringá/PR", o
  /// servidor encontra a praça e a prévia da tela não encontraria — e o
  /// consultor veria "sem seguro cadastrado" numa permuta que vai nascer com a
  /// linha dele.
  static String _cityKey(String city) {
    final lower = city.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_accents[char] ?? char);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s*/\s*'), '/');
  }

  /// As letras acentuadas do português, reduzidas à forma sem acento.
  ///
  /// Um mapa, e não `unorm`: são estas e nada mais — o que entra aqui é nome de
  /// município brasileiro, e uma dependência a mais para dobrar quinze letras
  /// seria um pacote inteiro no aparelho de quem vai a campo.
  static const Map<String, String> _accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };

  /// A versão vigente do Barter. Todo papel carrega — o consultor precisa dela
  /// para montar a permuta, e a retaguarda para saber o que está aberto.
  static Future<void> refreshBarterVersion({String? grainId}) async {
    currentVersion = await _program.current(grainId: grainId);
  }

  /// A VERSÃO VIGENTE convertida por OUTRA CULTURA, sem tocar no cache.
  ///
  /// É o que a tela do consultor pede ao trocar o seletor de cultura: a tabela
  /// inteira volta em sacas daquele grão. Ela não substitui [currentVersion]
  /// porque a escolha é DAQUELA permuta — outra tela, aberta em seguida, começa
  /// de novo na primeira cultura do lançamento.
  static Future<BarterVersionModel?> versionPricedIn(String grainId) =>
      _program.current(grainId: grainId);

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

  static Future<void> refreshBillers() async {
    billers = await _billers.list();
  }

  static Future<void> refreshEmitters() async {
    emitters = await _emitters.list();
  }

  static Future<void> refreshCommittee() async {
    committee = await _committee.find();
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

  /// Carteira de produtores visível para um usuário: consultor enxerga os que
  /// ATENDE — os próprios e os que divide com colegas —; admin (consultantId
  /// null) enxerga todos. O servidor já aplica essa regra; aqui é apenas um
  /// filtro sobre o cache.
  static List<ProducerModel> producersForConsultant(String? consultantId) {
    if (consultantId == null) return List.of(producers);
    return producers.where((p) => p.isAttendedBy(consultantId)).toList();
  }

  /// Os nomes dos consultores que atendem o produtor, para as telas mostrarem
  /// a carteira por extenso.
  ///
  /// Um id sem nome é PULADO, não vira "?": só o admin tem a lista de
  /// consultores carregada, e nas telas dele a ausência significa consultor
  /// excluído — cujo vínculo já não existe mais no servidor.
  static List<String> consultantNamesFor(ProducerModel producer) => producer.consultantIds
      .map(consultantById)
      .whereType<UserModel>()
      .map((c) => c.name)
      .toList();

  /// Busca um consultor pelo id (null se não encontrado). Só o admin tem a
  /// lista de consultores carregada.
  static UserModel? consultantById(String id) {
    for (final s in consultants) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// O CÓDIGO de um item de permuta, como a tela o mostra.
  ///
  /// Preferência absoluta pelo código CONGELADO no item: é ele que estava no
  /// cadastro no dia do acordo, e é o que a conferência da retirada vai
  /// comparar. O do catálogo entra só quando o item não tem o seu — os
  /// registrados antes de o campo existir —, e aí o número está sendo LIDO do
  /// cadastro de hoje, não afirmado sobre aquele dia.
  ///
  /// Null quando nenhum dos dois responde: produto sem código, ou catálogo que
  /// não veio (o consultor sem rede). A tela cala em vez de mostrar um traço
  /// onde caberia o nome do insumo.
  static String? skuOf(BarterItem item) {
    final frozen = item.sku;
    if (frozen != null && frozen.isNotEmpty) return frozen;
    return productSkuById(item.productId);
  }

  /// O CÓDIGO de um produto do catálogo, pelo id — para onde não há item de
  /// permuta com código congelado: a simulação guardada no aparelho e a
  /// conferência de envio, que carregam só o id, o nome e a quantidade.
  ///
  /// Null quando o catálogo não veio (consultor sem rede) ou o produto não tem
  /// código: quem chama some com a informação em vez de mostrar um traço.
  static String? productSkuById(String productId) {
    for (final product in [...inputs, ...grains]) {
      if (product.id == productId) {
        final sku = product.sku;
        return sku != null && sku.isNotEmpty ? sku : null;
      }
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

  /// A fila do COMITÊ: as permutas com parecer, esperando decisão.
  ///
  /// Diferente da do gerente, ela não tem destinatário — o comitê é um só, e a
  /// fila dele é o ESTADO da permuta. É a mesma regra do servidor.
  static List<BarterModel> get committeeQueue =>
      barters.where((b) => b.awaitsCommittee).toList();

  /// A fila do FATURISTA: o que o comitê aprovou e ainda não foi faturado.
  static List<BarterModel> get invoiceQueue =>
      barters.where((b) => b.awaitsInvoice).toList();

  /// A fila do EMISSOR: o que foi faturado e ainda não virou título registrado.
  ///
  /// Ela inclui os TRÊS degraus da cédula — a que espera emissão, a que espera
  /// assinatura e a que espera registro —, e não só o primeiro: os três são
  /// trabalho dele, acontecem em dias diferentes, e uma fila que mostrasse só o
  /// primeiro esconderia dele as cédulas assinadas paradas esperando cartório —
  /// que é exatamente o que estava invisível antes deste posto existir.
  static List<BarterModel> get issuanceQueue => barters
      .where((b) => b.awaitsCprIssue || b.awaitsSignatures || b.awaitsRegistration)
      .toList();

  /// Busca uma classe pelo id (null se não encontrada ou id null).
  static ProductClassModel? classById(String? id) {
    if (id == null) return null;
    for (final c in classes) {
      if (c.id == id) return c;
    }
    return null;
  }

  /* ── Mutações (API primeiro, cache depois) ──────────────────────────── */

  /// Registra a permuta. Ela nasce RASCUNHO — ver [BarterRepository.create]. O
  /// parecer é opcional aqui e obrigatório no encaminhamento.
  static Future<BarterModel> createBarter({
    required String producerId,
    required String unitId,
    required String grainId,
    required Map<String, double> inputQuantities,
    String note = '',
  }) async {
    final barter = await _barters.create(
      producerId: producerId,
      unitId: unitId,
      grainId: grainId,
      inputQuantities: inputQuantities,
      note: note,
    );
    barters.insert(0, barter);
    return barter;
  }

  /// O PARECER DO CONSULTOR salvo no rascunho, sem encaminhar. O cache guarda a
  /// resposta do servidor, nunca uma versão montada aqui.
  static Future<BarterModel> saveBarterNote(String code, String note) async {
    final updated = await _barters.saveNote(code, note);
    _replaceBarter(updated);
    return updated;
  }

  /// O ENCAMINHAMENTO ao gerente, com o parecer do consultor junto.
  static Future<BarterModel> forwardBarter(String code, String note) async {
    final updated = await _barters.forward(code, note);
    _replaceBarter(updated);
    return updated;
  }

  /* ── Simulações (o aparelho é a autoridade; só o envio fala com a API) ─ */

  /// Simulações do consultor logado, da mais recente para a mais antiga.
  ///
  /// Filtrar por dono não é zelo excessivo: o aparelho é compartilhado em
  /// algumas praças, e a permuta nasce em nome de QUEM ENVIA. Mostrar a
  /// simulação de um colega convidaria a enviá-la pela pessoa errada, e o
  /// servidor não teria como perceber — para ele seria uma permuta comum de quem
  /// clicou.
  static List<BarterSimulation> get mySimulations {
    final me = currentUser?.id;
    if (me == null) return const [];
    final mine = simulations.where((item) => item.consultantId == me).toList();
    mine.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return mine;
  }

  static BarterSimulation? simulationById(String id) {
    for (final item in simulations) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Lê as simulações do aparelho. Não lança e não depende de rede.
  static Future<void> loadSimulations() async {
    simulations = await SimulationStorage.load();
  }

  /// Grava (ou reescreve) uma simulação. Devolve `false` quando o aparelho
  /// recusou a gravação — a tela precisa dizer isso, ver
  /// [SimulationStorage.saveAll].
  ///
  /// A memória é atualizada MESMO quando o disco falha: perder também a sessão
  /// em curso não ajudaria ninguém, e assim o consultor ainda consegue enviar a
  /// permuta enquanto o app estiver aberto.
  static Future<bool> saveSimulation(BarterSimulation simulation) async {
    final index = simulations.indexWhere((item) => item.id == simulation.id);
    if (index == -1) {
      simulations.add(simulation);
    } else {
      simulations[index] = simulation;
    }
    return SimulationStorage.saveAll(simulations);
  }

  static Future<bool> deleteSimulation(String id) async {
    simulations.removeWhere((item) => item.id == id);
    return SimulationStorage.saveAll(simulations);
  }

  /// A CHECAGEM DE PRÉ-ENVIO: fala com a API, rebaixa tudo o que a conferência
  /// precisa e devolve o que mudou desde que a simulação foi montada.
  ///
  /// É aqui que "checar a disponibilidade do serviço" acontece — e ela é feita
  /// BUSCANDO OS DADOS, não perguntando ao sistema operacional se há rede. Um
  /// aparelho conectado a um wi-fi de sede sem rota para a API, ou a API fora do
  /// ar, passariam num teste de conectividade e falhariam no envio logo depois.
  /// A única pergunta que interessa é "o servidor respondeu?", e a resposta vem
  /// junto com os dados de que a conferência precisa — uma viagem, não duas.
  ///
  /// Lança [ApiException] quando o serviço não responde: nesse caso nada foi
  /// enviado, e a simulação continua intacta no aparelho.
  static Future<SimulationCheck> reviewSimulation(BarterSimulation simulation) async {
    await syncOfflinePackage();

    final producer = producerById(simulation.producerId);
    return checkSimulation(
      simulation,
      version: currentVersion,
      producerInWallet:
          producer != null && producer.isAttendedBy(currentUser?.id ?? ''),
      unitExists: unitById(simulation.unitId) != null,
    );
  }

  /// Envia uma simulação: registra a permuta de verdade e, SÓ ENTÃO, apaga a
  /// simulação.
  ///
  /// A ordem é a regra inteira. O envio pode falhar por rede, por Barter
  /// encerrado ou por mínimo de classe não atingido — e em qualquer um desses
  /// casos a simulação tem de continuar lá, intacta, para o consultor corrigir e
  /// tentar de novo. Quem apaga é o sucesso, nunca a tentativa.
  ///
  /// ## O caso incerto, e por que ele tem tratamento próprio
  ///
  /// Existe uma falha que não é sucesso nem recusa: o `POST` chega ao servidor,
  /// a permuta é criada e a RESPOSTA se perde no caminho (timeout de 15s, rede
  /// que caiu no meio). O app vê um erro; o servidor tem a permuta. Tocar
  /// "Enviar" de novo criaria uma SEGUNDA permuta idêntica na mesa do gerente, e
  /// nada no sistema diria qual das duas é a verdadeira.
  ///
  /// O risco não é teórico aqui: simulação existe justamente para ser enviada de
  /// onde o sinal é ruim. Por isso, quando o erro é de transporte
  /// (`statusCode == 0`, e só nele — uma recusa de negócio veio com resposta e
  /// portanto não gravou nada), este método vai CONFERIR no servidor se a
  /// permuta entrou antes de dar o envio por perdido.
  ///
  /// A conferência é um casamento por produtor + horário, e é heurística por
  /// natureza. A correção definitiva é uma chave de idempotência no `POST`, que
  /// deixaria o servidor reconhecer o reenvio — e que exige uma coluna nova.
  /// Enquanto ela não existe, é melhor perguntar do que duplicar em silêncio.
  /// [note] é o parecer do consultor e [forward] diz se a permuta sai da mesa
  /// dele agora. Os dois andam juntos e são o mesmo desenho do rascunho: quem já
  /// conversou com o produtor manda de uma vez; quem ainda não, guarda o
  /// registro e escreve depois.
  ///
  /// O ENCAMINHAMENTO é um segundo ato, e por isso pode falhar sozinho — a
  /// permuta já está registrada quando ele acontece. Falhando, o método devolve
  /// a permuta como ela ficou (rascunho), e é a tela que diz isso a quem enviou:
  /// perder o registro para relatar um erro seria trocar um aviso por um
  /// prejuízo.
  static Future<SendResult> sendSimulation(
    BarterSimulation simulation, {
    String note = '',
    bool forward = true,
  }) async {
    final startedAt = DateTime.now();
    try {
      final barter = await createBarter(
        producerId: simulation.producerId,
        unitId: simulation.unitId,
        // A CULTURA guardada na simulação. As simulações montadas ANTES de as
        // culturas coexistirem não a têm — e para elas a primeira cultura do
        // lançamento é a resposta certa: era a única que existia quando elas
        // foram montadas.
        grainId: simulation.grainId.isNotEmpty
            ? simulation.grainId
            : (currentVersion?.grains.firstOrNull?.grainId ?? ''),
        inputQuantities: simulation.inputQuantities,
        note: note,
      );
      await deleteSimulation(simulation.id);
      if (!forward) return SendResult.sent(barter);
      try {
        return SendResult.sent(await forwardBarter(barter.id, note));
      } on ApiException catch (error) {
        // A PERMUTA ENTROU e não foi encaminhada — e agora a tela sabe POR QUÊ.
        //
        // O motivo mais comum passou a ser a cédula: encaminhar exige a CPR
        // preenchida, e quem envia a simulação sem tê-la feito para no rascunho.
        // Engolir a mensagem aqui faria a tela dizer "enviada" e o consultor
        // descobrir dias depois, pelo gerente que nunca recebeu nada.
        return SendResult.sent(barter, notForwardedReason: error.message);
      }
    } on ApiException catch (error) {
      if (error.statusCode != 0) return SendResult.refused(error.message);

      final existing = await _findRegistered(simulation, startedAt);
      if (existing == null) return SendResult.uncertain(error.message);

      await deleteSimulation(simulation.id);
      return SendResult.sent(existing, reconciled: true);
    }
  }

  /// A permuta desta simulação já está no servidor?
  ///
  /// Casa por produtor e por horário: uma permuta deste consultor, para este
  /// produtor, criada depois que a tentativa começou. A margem de dois minutos é
  /// para o relógio do aparelho, que não é o do servidor — sem ela, um celular
  /// alguns segundos adiantado nunca encontraria a permuta que acabou de criar.
  ///
  /// Se nem esta consulta responder, devolve null: aí não dá para afirmar nada,
  /// e é isso que [SendResult.uncertain] diz ao consultor.
  static Future<BarterModel?> _findRegistered(
    BarterSimulation simulation,
    DateTime startedAt,
  ) async {
    final me = currentUser?.id;
    if (me == null) return null;
    try {
      await refreshBarters();
    } on ApiException {
      return null;
    }
    final since = startedAt.subtract(const Duration(minutes: 2));
    for (final barter in barters) {
      if (barter.consultantId == me &&
          barter.producerId == simulation.producerId &&
          !barter.createdAt.isBefore(since)) {
        return barter;
      }
    }
    return null;
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

  /* ── Base de seguros (admin mantém; todo mundo lê) ──────────────────── */

  /// Cadastra ou corrige uma praça. A lista em memória é reordenada por
  /// município, que é a ordem em que a tela e o servidor a entregam.
  static Future<InsuranceRateModel> saveInsuranceRate({
    String? id,
    required String city,
    required double valuePerHa,
    String? note,
  }) async {
    final saved = id == null
        ? await _insurance.create(city: city, valuePerHa: valuePerHa, note: note)
        : await _insurance.update(id, city: city, valuePerHa: valuePerHa, note: note);
    final index = insuranceRates.indexWhere((rate) => rate.id == saved.id);
    if (index == -1) {
      insuranceRates.add(saved);
    } else {
      insuranceRates[index] = saved;
    }
    insuranceRates.sort((a, b) => a.city.compareTo(b.city));
    return saved;
  }

  /// Excluir a praça NÃO mexe nas permutas dela: a taxa está congelada em cada
  /// uma. O que some é a possibilidade de registrar permuta nova naquele
  /// município enquanto o Barter levar seguro — que é o que "a seguradora não
  /// cobre mais esta praça" significa.
  static Future<void> deleteInsuranceRate(String id) async {
    await _insurance.delete(id);
    insuranceRates.removeWhere((rate) => rate.id == id);
  }

  /// A CARGA DA PLANILHA. Devolve o relatório da leitura — a base inteira mais
  /// a coluna de onde o valor saiu, que é o que a tela mostra de volta ao
  /// admin.
  static Future<InsuranceImportResult> importInsuranceRates({
    required String filename,
    required List<int> bytes,
    bool replace = false,
    String? column,
  }) async {
    final result = await _insurance.importSheet(
      filename: filename,
      bytes: bytes,
      replace: replace,
      column: column,
    );
    insuranceRates = result.rates;
    return result;
  }

  /// PARECER TÉCNICO do gerente. A permuta volta do servidor já em revisão —
  /// o cache guarda a resposta dele, nunca uma versão montada aqui.
  static Future<BarterModel> giveOpinion(String code, String note) async {
    final updated = await _barters.giveOpinion(code, note);
    _replaceBarter(updated);
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
    required List<VersionGrainInput> grains,
    DateTime? endsAt,
    double? targetSales,
    int? targetBarters,
    bool closeOnGoal = false,
    bool insuranceRequired = false,
    String? note,
    bool carryOver = false,
  }) async {
    final version = await _program.publishFromFile(
      seasonCode: seasonCode,
      filename: filename,
      bytes: bytes,
      grains: grains,
      endsAt: endsAt,
      targetSales: targetSales,
      targetBarters: targetBarters,
      closeOnGoal: closeOnGoal,
      insuranceRequired: insuranceRequired,
      note: note,
      carryOver: carryOver,
    );
    // A publicação mexe no catálogo (cria insumos, atualiza o último valor
    // publicado), então o cache inteiro do catálogo precisa vir de novo.
    await Future.wait([refreshCatalog(), refreshSeasons(), refreshBarterVersion()]);
    return version;
  }

  /// Corrige um valor da versão vigente (a cotação de uma CULTURA inclusive).
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

  /// Liga ou desliga o encerramento automático por meta na versão vigente.
  ///
  /// Recarrega safras e versão vigente como o encerramento manual faz, e pelo
  /// mesmo motivo: ligar com a meta já batida ENCERRA o Barter no servidor, e um
  /// cache que só guardasse o interruptor mostraria um Barter aberto que não
  /// existe mais. Devolve a versão como o servidor a deixou.
  static Future<BarterVersionModel> setVersionCloseOnGoal(String code, bool enabled) async {
    final version = await _program.setCloseOnGoal(code, enabled);
    await Future.wait([refreshSeasons(), refreshBarterVersion()]);
    return version;
  }

  static Future<void> closeSeason(String code) async {
    await _program.closeSeason(code);
    await Future.wait([refreshSeasons(), refreshBarterVersion()]);
  }

  static Future<void> openSeason({
    required int year,
    String? name,
    String? letter,
  }) async {
    await _program.openSeason(year: year, name: name, letter: letter);
    await Future.wait([refreshSeasons(), refreshBarterVersion()]);
  }

  /// LIGA ou DESLIGA o seguro agrícola do Barter vigente.
  ///
  /// Vale para as permutas que ainda vão nascer: as registradas têm a taxa
  /// congelada e não são tocadas. A versão vigente em memória é atualizada com
  /// o que o servidor devolveu.
  static Future<BarterVersionModel> setVersionInsurance(String code, bool enabled) async {
    final updated = await _program.setInsurance(code, enabled);
    if (currentVersion?.code == updated.code) currentVersion = updated;
    return updated;
  }

  /// ACERTA UMA CULTURA da versão vigente: a cotação, a produtividade, o
  /// vencimento da CPR ou a meta de sacas dela.
  ///
  /// O vencimento é a data de entrega de todas as cédulas DAQUELA CULTURA que
  /// ainda não foram emitidas — as emitidas congelaram a delas. Recarrega safras
  /// e versão vigente porque as duas mostram os números da cultura.
  static Future<BarterVersionModel> updateVersionGrain(
    String code,
    String grainId, {
    double? price,
    double? estimatedYield,
    DateTime? cprDueDate,
    double? targetSacks,
  }) async {
    final updated = await _program.updateGrain(
      code,
      grainId,
      price: price,
      estimatedYield: estimatedYield,
      cprDueDate: cprDueDate,
      targetSacks: targetSacks,
    );
    await Future.wait([refreshSeasons(), refreshBarterVersion()]);
    return updated;
  }

  /// A DECISÃO DO COMITÊ: aprovar, aprovar com RESSALVA ou negar. O cache
  /// guarda a resposta do servidor, nunca uma versão montada aqui.
  ///
  /// AS EXIGÊNCIAS (avalista, garantia real, seguro) andam junto com a decisão:
  /// elas dizem O QUÊ o comitê exigiu, e o texto continua dizendo QUAL — qual
  /// matrícula, qual valor segurado, quem se espera como avalista.
  static Future<BarterModel> reviewBarter(
    String code,
    BarterStatus status,
    String note, {
    bool requiresGuarantor = false,
    bool requiresCollateral = false,
    bool requiresInsurance = false,
  }) async {
    final updated = await _barters.review(
      code,
      status,
      note,
      requiresGuarantor: requiresGuarantor,
      requiresCollateral: requiresCollateral,
      requiresInsurance: requiresInsurance,
    );
    _replaceBarter(updated);
    return updated;
  }

  /* ── O DOSSIÊ DO COMITÊ ─────────────────────────────────────────────── */

  /// ANEXA uma peça da análise de crédito à permuta (comitê).
  ///
  /// O cache guarda a permuta que o servidor devolveu — ela já volta com o
  /// dossiê inteiro, e remontá-la aqui abriria a chance de a tela mostrar uma
  /// lista que o servidor não tem.
  static Future<BarterModel> attachCreditFile(
    String code, {
    required String filename,
    required List<int> bytes,
    String kind = 'other',
    String note = '',
  }) async {
    final updated = await _barters.attachCreditFile(
      code,
      filename: filename,
      bytes: bytes,
      kind: kind,
      note: note,
    );
    _replaceBarter(updated);
    return updated;
  }

  /// REMOVE uma peça do dossiê. A janela é a mesma de anexar: até a decisão.
  static Future<BarterModel> removeCreditFile(String code, String creditFileId) async {
    final updated = await _barters.removeCreditFile(code, creditFileId);
    _replaceBarter(updated);
    return updated;
  }

  /// O FATURAMENTO da permuta aprovada.
  ///
  /// O servidor recusa (422) sem NOTA anexada: é ela que a cédula cita como
  /// origem da dívida. A tela cuida de anexar antes — ver [attachBarterInvoice].
  static Future<BarterModel> invoiceBarter(String code, String note) async {
    final updated = await _barters.invoice(code, note);
    _replaceBarter(updated);
    return updated;
  }

  /// ANEXA UMA NOTA FISCAL ao faturamento — o arquivo e os dados dele.
  ///
  /// SÃO VÁRIAS por permuta: a retirada sai em mais de um carregamento, cada uma
  /// gera a sua nota, e a cancelada é reemitida. A resposta é a permuta inteira,
  /// e é ela que entra no cache — a lista precisa saber que a permuta já tem
  /// nota.
  static Future<BarterModel> attachBarterInvoice(
    String code, {
    required String number,
    required String filename,
    required List<int> bytes,
    String series = '',
    String duplicateNumber = '',
    DateTime? issuedAt,
    double? value,
    String note = '',
  }) async {
    final updated = await _barters.attachInvoice(
      code,
      number: number,
      filename: filename,
      bytes: bytes,
      series: series,
      duplicateNumber: duplicateNumber,
      issuedAt: issuedAt,
      value: value,
      note: note,
    );
    _replaceBarter(updated);
    return updated;
  }

  /// REMOVE uma nota anexada — a cancelada, ou a que subiu trocada.
  static Future<BarterModel> removeBarterInvoice(String code, String invoiceId) async {
    final updated = await _barters.removeInvoice(code, invoiceId);
    _replaceBarter(updated);
    return updated;
  }

  /* ── A EMISSÃO DA CÉDULA: os três atos do emissor ───────────────────── */

  /// EMITE a cédula — o ato que CONFERE o que os outros postos produziram.
  ///
  /// O servidor recusa (422) com a lista do que falta, e cada item dela diz com
  /// quem a pendência se resolve: o RG é com o consultor, a nota é com o
  /// faturista, o vencimento é com quem cadastra a safra.
  static Future<BarterModel> issueBarterCpr(
    String code, {
    String number = '',
    String note = '',
  }) async {
    final updated = await _barters.issueCpr(code, number: number, note: note);
    _replaceBarter(updated);
    return updated;
  }

  /// A COLETA DE ASSINATURAS concluída — o lançamento de um fato de fora, com a
  /// CÉDULA ASSINADA anexada no mesmo ato.
  static Future<BarterModel> signBarterCpr(
    String code, {
    required String filename,
    required List<int> bytes,
    DateTime? signedAt,
    String note = '',
  }) async {
    final updated = await _barters.signCpr(
      code,
      filename: filename,
      bytes: bytes,
      signedAt: signedAt,
      note: note,
    );
    _replaceBarter(updated);
    return updated;
  }

  /// O REGISTRO do título — o fim da linha. O número é obrigatório; a via
  /// carimbada do cartório, não (ver [saveCprRegistryFile]).
  static Future<BarterModel> registerBarterCpr(
    String code, {
    required String registryNumber,
    String registryPlace = '',
    DateTime? registeredAt,
    String note = '',
    String? filename,
    List<int>? bytes,
  }) async {
    final updated = await _barters.registerCpr(
      code,
      registryNumber: registryNumber,
      registryPlace: registryPlace,
      registeredAt: registeredAt,
      note: note,
      filename: filename,
      bytes: bytes,
    );
    _replaceBarter(updated);
    return updated;
  }

  /// O PEDIDO DE ALTERAÇÃO do consultor — o caminho de volta da esteira.
  static Future<BarterModel> requestBarterChange(String code, String note) async {
    final updated = await _barters.requestChange(code, note);
    _replaceBarter(updated);
    return updated;
  }

  /// A DECISÃO DO ADMIN sobre o pedido: liberar ou recusar.
  static Future<BarterModel> decideBarterChange(
    String code, {
    required bool accept,
    String note = '',
  }) async {
    final updated = await _barters.decideChange(code, accept: accept, note: note);
    _replaceBarter(updated);
    return updated;
  }

  /// O ATENDIMENTO DO PEDIDO NO VALOR: o admin corrige a linha de R$ e a
  /// permuta continua onde estava, com as sacas recalculadas pelo servidor.
  static Future<BarterModel> changeBarterPrices(
    String code,
    Map<String, double> valueByItemId, {
    String note = '',
  }) async {
    final updated = await _barters.changePrices(code, valueByItemId, note: note);
    _replaceBarter(updated);
    return updated;
  }

  /// O PEDIDO DE FORA DO BARTER: o consultor pede o produto que falta na tabela.
  static Future<BarterModel> requestBarterProduct(
    String code, {
    required String productName,
    required String unit,
    required double quantity,
    String note = '',
  }) async {
    final updated = await _barters.requestProduct(
      code,
      productName: productName,
      unit: unit,
      quantity: quantity,
      note: note,
    );
    _replaceBarter(updated);
    return updated;
  }

  /// A DECISÃO DO ADMIN sobre o pedido de produto: incluir com o valor
  /// acertado, ou recusar com o motivo.
  static Future<BarterModel> decideBarterProduct(
    String code,
    String requestId, {
    required bool accept,
    double? unitValue,
    String? productName,
    String? unit,
    double? quantity,
    String? sku,
    String note = '',
  }) async {
    final updated = await _barters.decideProduct(
      code,
      requestId,
      accept: accept,
      unitValue: unitValue,
      productName: productName,
      unit: unit,
      quantity: quantity,
      sku: sku,
      note: note,
    );
    _replaceBarter(updated);
    return updated;
  }

  /// A TABELA com que uma permuta foi fechada — a gestão DELA, não a vigente.
  ///
  /// Fora do cache, como o detalhe: o cache guarda a versão VIGENTE, que é a que
  /// precifica permuta nova. Esta é a de uma permuta específica, e guardá-la no
  /// mesmo lugar faria a tela de registro passar a montar com a tabela de uma
  /// gestão encerrada.
  /// A TABELA COM QUE UMA PERMUTA FOI FECHADA, na CULTURA dela: remontar um
  /// rascunho de milho lendo a tabela em sacas de soja mostraria ao produtor um
  /// total que o servidor não gravaria.
  static Future<BarterVersionModel> barterVersion(String code, {String? grainId}) =>
      _barters.versionOf(code, grainId: grainId);

  /// TROCA A CULTURA de um rascunho — a permuta passa a ser paga em outro grão.
  ///
  /// Os insumos ficam; o que muda são as sacas (a cotação da cultura nova
  /// converte o mesmo custo) e a produtividade que dimensiona o penhor. Quem
  /// recalcula é o servidor, e o cache guarda a resposta dele.
  static Future<BarterModel> setBarterCulture(String code, String grainId) async {
    final updated = await _barters.setCulture(code, grainId);
    _replaceBarter(updated);
    return updated;
  }

  /// A REESCRITA DOS INSUMOS do rascunho — a permuta remontada.
  ///
  /// Quem reprecifica é o servidor, pela tabela da versão em que a permuta foi
  /// fechada: o cache guarda a resposta dele, e não uma permuta montada aqui.
  static Future<BarterModel> replaceBarterInputs(
    String code,
    Map<String, double> inputQuantities,
  ) async {
    final updated = await _barters.replaceInputs(code, inputQuantities);
    _replaceBarter(updated);
    return updated;
  }

  /// O DETALHE de uma permuta, com a LINHA DO TEMPO.
  ///
  /// Não entra no cache: o cache é alimentado pela LISTAGEM, que não carrega
  /// histórico — guardar o detalhe ali faria a mesma permuta ter ou não ter
  /// linha do tempo conforme a tela por onde se passou.
  static Future<BarterModel> barterDetail(String code) => _barters.find(code);

  /// A CÉDULA (CPR) desta permuta, e a gravação dela.
  ///
  /// Fora do cache pelo mesmo motivo do detalhe, e com um a mais: a cédula é
  /// lida por três papéis (o consultor que preenche, o emissor que confere e o
  /// admin que tira a segunda via), e um rascunho guardado em memória mostraria
  /// a versão de quem abriu a tela primeiro. Ela é sempre lida do servidor e a
  /// gravação devolve a mesa recalculada — inclusive o que falta.
  static Future<CprDesk> barterCpr(String code) => _barters.cpr(code);

  static Future<CprDesk> saveBarterCpr(String code, CprDraft draft) =>
      _barters.saveCpr(code, draft);

  /// ANEXA O SCR DO PRODUTOR à cédula — anexo OBRIGATÓRIO para ela ser emitida.
  static Future<CprDesk> saveBarterScr(
    String code, {
    required String filename,
    required List<int> bytes,
  }) =>
      _barters.saveScr(code, filename: filename, bytes: bytes);

  /// BAIXA o arquivo de uma NOTA FISCAL anexada ao faturamento.
  static Future<({List<int> bytes, String filename, String contentType})>
      downloadBarterInvoiceFile(String code, String invoiceId) =>
          _barters.download(_barters.invoiceFilePath(code, invoiceId));

  /// BAIXA uma peça do DOSSIÊ do comitê (Serasa, endividamento interno).
  ///
  /// Só o comitê e o admin chegam aqui: o servidor recusa os demais com 403,
  /// e a tela nem oferece o botão — ver `Capability.bartersCreditRead`.
  static Future<({List<int> bytes, String filename, String contentType})> downloadCreditFile(
    String code,
    String creditFileId,
  ) =>
      _barters.download(_barters.creditFilePath(code, creditFileId));

  /// BAIXA o arquivo do SCR anexado à cédula.
  static Future<({List<int> bytes, String filename, String contentType})> downloadBarterScr(
    String code,
  ) =>
      _barters.download(_barters.scrFilePath(code));

  /// ANEXA A VIA CARIMBADA do registro, quando ela chega depois do ato.
  static Future<CprDesk> saveCprRegistryFile(
    String code, {
    required String filename,
    required List<int> bytes,
  }) =>
      _barters.saveCprRegistryFile(code, filename: filename, bytes: bytes);

  /// BAIXA a CÉDULA ASSINADA e a VIA DO REGISTRO — os documentos que voltaram.
  static Future<({List<int> bytes, String filename, String contentType})> downloadSignedCpr(
    String code,
  ) =>
      _barters.download(_barters.signedCprPath(code));

  static Future<({List<int> bytes, String filename, String contentType})>
      downloadCprRegistryFile(String code) =>
          _barters.download(_barters.cprRegistryFilePath(code));

  /// O CADASTRO DA CREDORA. Fora do cache pelo mesmo motivo da cédula: ele tem
  /// dois donos (admin e EMISSOR), e uma cópia em memória mostraria a versão de
  /// quem abriu a tela primeiro.
  static Future<CprCreditor> creditor() => _creditor.get();

  static Future<CprCreditor> saveCreditor(CprCreditor creditor) => _creditor.save(creditor);

  /// A MARGEM DE SEGURANÇA DO PENHOR — só para quem tem
  /// `Capability.pledgePolicyManage` (o admin). Chamada à parte do cadastro
  /// porque no servidor são duas rotas com autoridades diferentes.
  static Future<CprCreditor> saveCreditorPledgeMargin(double percent) =>
      _creditor.savePledgeMargin(percent);

  /// Troca uma permuta do cache pela versão que o servidor devolveu.
  static void _replaceBarter(BarterModel updated) {
    final index = barters.indexWhere((b) => b.id == updated.id);
    if (index != -1) barters[index] = updated;
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

  /* ── Faturistas (pessoas, várias) ───────────────────────────────────── */

  static Future<ProvisionedConsultant> createBiller(UserModel biller) async {
    final provisioned = await _billers.create(biller);
    _cacheBiller(provisioned.consultant);
    return provisioned;
  }

  static Future<UserModel> updateBiller(UserModel biller) async {
    final saved = await _billers.update(biller);
    _cacheBiller(saved);
    return saved;
  }

  static Future<ProvisionedConsultant> resetBillerPassword(String id) async {
    final provisioned = await _billers.resetPassword(id);
    _cacheBiller(provisioned.consultant);
    return provisioned;
  }

  /// Excluir faturista não trava em nada: as permutas que ele faturou guardam o
  /// nome dele no próprio registro (snapshot), e o que estava na fila continua
  /// aparecendo para os outros — a fila é o ESTADO da permuta, não uma caixa
  /// de entrada pessoal.
  static Future<void> deleteBiller(String id) async {
    await _billers.delete(id);
    billers.removeWhere((b) => b.id == id);
  }

  static void _cacheBiller(UserModel saved) {
    final index = billers.indexWhere((b) => b.id == saved.id);
    if (index == -1) {
      billers.add(saved);
    } else {
      billers[index] = saved;
    }
  }

  /* ── Emissores (pessoas, várias) ────────────────────────────────────── */
  //
  // O posto da CÉDULA. Ele é cadastrado como o faturista — pessoa, unidade, sem
  // gerente — porque o formulário é o mesmo: o que muda entre os dois é o que
  // cada um faz, e isso está na tabela de capacidades do servidor, não aqui.

  static Future<ProvisionedConsultant> createEmitter(UserModel emitter) async {
    final provisioned = await _emitters.create(emitter);
    _cacheEmitter(provisioned.consultant);
    return provisioned;
  }

  static Future<UserModel> updateEmitter(UserModel emitter) async {
    final saved = await _emitters.update(emitter);
    _cacheEmitter(saved);
    return saved;
  }

  static Future<ProvisionedConsultant> resetEmitterPassword(String id) async {
    final provisioned = await _emitters.resetPassword(id);
    _cacheEmitter(provisioned.consultant);
    return provisioned;
  }

  /// Excluir emissor não trava em nada, pelo mesmo motivo do faturista: as
  /// cédulas que ele emitiu guardam o nome dele no próprio registro (snapshot),
  /// e a fila é o ESTADO da permuta, não uma caixa de entrada pessoal.
  static Future<void> deleteEmitter(String id) async {
    await _emitters.delete(id);
    emitters.removeWhere((e) => e.id == id);
  }

  static void _cacheEmitter(UserModel saved) {
    final index = emitters.indexWhere((e) => e.id == saved.id);
    if (index == -1) {
      emitters.add(saved);
    } else {
      emitters[index] = saved;
    }
  }

  /* ── Comitê (um órgão, um cadastro) ─────────────────────────────────── */

  /// Cria o cadastro do comitê. O servidor recusa se já houver um — o app não
  /// repete essa conferência, ele mostra a mensagem de lá.
  static Future<ProvisionedConsultant> createCommittee(UserModel draft) async {
    final provisioned = await _committee.create(draft);
    committee = provisioned.consultant;
    return provisioned;
  }

  static Future<UserModel> updateCommittee(UserModel draft) async {
    committee = await _committee.update(draft);
    return committee!;
  }

  static Future<ProvisionedConsultant> resetCommitteePassword() async {
    final provisioned = await _committee.resetPassword();
    committee = provisioned.consultant;
    return provisioned;
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
