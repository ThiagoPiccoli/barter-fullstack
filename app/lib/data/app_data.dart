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

  /// O valor (R$) de um insumo na versão vigente, ou 0 se ele não está nela.
  static double priceOf(String productId) =>
      currentVersion?.priceOf(productId)?.price ?? 0;

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
    producers = [];
    units = [];
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
      if (isAdmin) refreshSeasons(),
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
    ]);

    final productRows = results[0] as List<Map<String, dynamic>>;
    final classRows = results[1] as List<Map<String, dynamic>>;
    final producerRows = results[2] as List<Map<String, dynamic>>;
    final unitRows = results[3] as List<Map<String, dynamic>>;
    final versionRow = results[4] as Map<String, dynamic>?;

    final package = OfflinePackage(
      savedAt: DateTime.now(),
      user: _auth.lastMeRaw,
      version: versionRow,
      products: productRows,
      classes: classRows,
      producers: producerRows,
      units: unitRows,
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
    TaxRegime taxRegime = TaxRegime.comercializacao,
  }) async {
    final barter = await _barters.create(
      producerId: producerId,
      unitId: unitId,
      inputQuantities: inputQuantities,
      taxRegime: taxRegime,
    );
    barters.insert(0, barter);
    return barter;
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
  static Future<SendResult> sendSimulation(BarterSimulation simulation) async {
    final startedAt = DateTime.now();
    try {
      final barter = await createBarter(
        producerId: simulation.producerId,
        unitId: simulation.unitId,
        inputQuantities: simulation.inputQuantities,
        taxRegime: simulation.taxRegime,
      );
      await deleteSimulation(simulation.id);
      return SendResult.sent(barter);
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
