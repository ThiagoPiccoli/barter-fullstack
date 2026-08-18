import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../theme/app_theme.dart';
import '../models/barter_simulation.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/api/api_client.dart';
import '../services/barter_math.dart';
import '../services/tax_regime.dart';
import '../widgets/class_avatar.dart';
import '../widgets/filter_bar.dart';
import '../widgets/common_widgets.dart';
import 'send_simulation.dart';

/// Construtor de permuta.
///
/// O consultor escolhe o PRODUTOR e os INSUMOS. Só isso. O grão de pagamento e
/// os valores vêm do Barter vigente — a versão que o admin lançou —, e é ela
/// que converte o custo dos insumos em sacas.
///
/// Escolher grão era do desenho anterior, em que cada permuta carregava a
/// própria cotação. Hoje o Barter é lançado sobre um grão, por um período: sem
/// lançamento aberto não existe permuta nova, e a tela diz isso em vez de
/// montar um pedido que o servidor recusaria.
class NewBarterScreen extends StatefulWidget {
  final UserModel consultant;

  /// Uma SIMULAÇÃO sendo retomada, quando a tela foi aberta pela aba de
  /// simulações.
  ///
  /// Null é o caso normal — a aba "Nova Permuta", com a tela em branco. Com uma
  /// simulação, as três etapas já vêm respondidas e salvar REESCREVE esta mesma
  /// simulação, em vez de deixar uma segunda cópia na lista.
  final BarterSimulation? simulation;

  const NewBarterScreen({super.key, required this.consultant, this.simulation});
  @override
  State<NewBarterScreen> createState() => _NewBarterScreenState();
}

/// Como ordenar a lista de insumos. Sem preço: o consultor não vê R$, então
/// "mais caro primeiro" não existe do lado dele.
enum _InputSort { name, chosenFirst }

class _NewBarterScreenState extends State<NewBarterScreen> {
  final Map<String, double> _inputQty = {};
  String? _producerId;

  /// A UNIDADE onde o produtor vai retirar os insumos (etapa 2).
  ///
  /// É logística e nada mais: qualquer unidade serve, e ela não muda quem
  /// analisa a permuta — isso é sempre o gerente do consultor. A etapa existe
  /// aqui, e não no cadastro do produtor, porque a retirada é combinada caso a
  /// caso: o mesmo produtor pode buscar em praças diferentes ao longo da safra.
  String? _unitId;

  String _searchQuery = '';

  /// Recortes da lista de insumos. Com o catálogo real (centenas de itens), a
  /// busca por texto sozinha obriga a saber o nome antes de procurar — e quem
  /// monta a permuta pensa por classe ("agora os herbicidas") e pelo que já
  /// escolheu, não por nome exato.
  String? _classId;
  bool _onlyChosen = false;
  _InputSort _sort = _InputSort.name;

  /// A simulação que esta tela está escrevendo, quando já existe uma.
  ///
  /// Vem preenchida ao retomar uma simulação, e passa a existir no primeiro
  /// "Salvar" de uma permuta nova. É ela que faz o segundo toque em "Salvar"
  /// REESCREVER a simulação — sem isso, cada toque deixaria mais uma cópia da
  /// mesma permuta na lista.
  String? _simulationId;

  /// COMO o Funrural desta entrega vai ser recolhido — a escolha do fechamento.
  ///
  /// Começa na comercialização porque é o que se aplica a quem não fez a opção
  /// formal pela folha: a permuta não inventa um regime, ela mostra o padrão
  /// para ser confirmado ou trocado. Ver `services/tax_regime.dart`.
  TaxRegime _taxRegime = TaxRegime.comercializacao;

  @override
  void initState() {
    super.initState();
    final simulation = widget.simulation;
    if (simulation == null) return;
    _simulationId = simulation.id;
    _taxRegime = simulation.taxRegime;
    _producerId = simulation.producerId;
    _unitId = simulation.unitId;
    _inputQty.addAll(simulation.inputQuantities);

    // A simulação é mais velha do que o cadastro: entre guardar e retomar, o
    // produtor pode ter saído da carteira e a unidade pode ter sido desativada.
    // A tela sozinha só voltaria para a etapa 1, sem dizer por quê — e o
    // consultor concluiria que o app perdeu a simulação dele.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_producer == null) {
        _toast(
          '${simulation.producerName} não está mais na sua carteira — escolha outro produtor.',
        );
      } else if (_unit == null) {
        _toast('A unidade ${simulation.unitName} não está mais disponível — escolha outra.');
      }
    });
  }

  /// O Barter vigente. Null (ou fechado) trava a tela inteira.
  BarterVersionModel? get _version => AppData.currentVersion;

  /// Os insumos que a versão vigente colocou na mesa.
  List<ProductModel> get _catalog => AppData.barterInputs;

  /// Os insumos escolhidos, precificados PELA VERSÃO — a entrada da matemática
  /// da permuta (services/barter_math.dart, espelho do cálculo do servidor).
  List<PricedInput> get _pricedInputs => [
    for (final e in _inputQty.entries)
      if (e.value > 0)
        PricedInput(
          productId: e.key,
          quantity: e.value,
          unitPrice: AppData.priceOf(e.key),
          classId: _productById(e.key)?.classId,
        ),
  ];

  ProductModel? _productById(String id) {
    for (final input in _catalog) {
      if (input.id == id) return input;
    }
    return null;
  }

  /// Custo total dos insumos escolhidos (R$) — o valor que a permuta paga.
  double get _inputCost => inputCost(_pricedInputs);

  /// Produtor (cliente) designado para esta permuta (ou null).
  ProducerModel? get _producer => _producerId == null ? null : AppData.producerById(_producerId!);

  /// A unidade de retirada escolhida (ou null).
  UnitModel? get _unit => AppData.unitById(_unitId);

  /// Sacas do grão da safra necessárias para cobrir o custo dos insumos.
  /// Mesmo arredondamento do servidor: o número da tela é o que será gravado.
  double get _sacksNeeded {
    final version = _version;
    return version == null ? 0 : sacksToCover(_inputCost, version.grainPrice);
  }

  /// Quantidade mínima obrigatória de um insumo para o produtor atual:
  /// taxa por hectare × área da propriedade. 0 se não há produtor ou exigência.
  double _minFor(String inputId) {
    final producer = _producer;
    final input = _productById(inputId);
    if (producer == null || input == null) return 0;
    return minQuantityFor(input.requiredPerHa, producer.areaHa);
  }

  /// Há algum insumo com exigência mínima por área para o produtor atual?
  bool get _hasRequiredInputs => _catalog.any((i) => _minFor(i.id) > 0);

  /// Classes que carregam uma regra de mínimo capaz de travar o envio da
  /// permuta.
  List<ProductClassModel> get _ruledClasses => AppData.classes.where((c) => c.hasRule).toList();

  /// Custo (R$) dos insumos escolhidos que pertencem à classe [classId].
  double _classSpend(String classId) => classSpend(_pricedInputs, classId);

  /// Mínimo (R$) exigido por uma classe, dado o estado atual da permuta:
  /// percentual do custo total, ou valor por hectare × área do produtor.
  double _classRequired(ProductClassModel c) {
    final p = _producer;
    // Sem produtor escolhido não há área, e a regra por hectare não tem base
    // de cálculo — o servidor sempre tem, porque a permuta chega com produtor.
    if (p == null && c.ruleType == ClassRuleType.valuePerHa) return 0;
    return classRequired(
      ClassRule.values.byName(c.ruleType.name),
      c.ruleValue,
      totalCost: _inputCost,
      areaHa: p?.areaHa ?? 0,
    );
  }

  /// O mínimo da classe foi atingido? (tolerância de centavos)
  bool _classMet(ProductClassModel c) {
    final req = _classRequired(c);
    if (req <= 0) return true;
    return _classSpend(c.id) >= req - moneyEpsilon;
  }

  /// Progresso (0–1) rumo ao mínimo da classe. Usado na barra do consultor —
  /// é proporção, nunca expõe R\$.
  ///
  /// Com a permuta VAZIA a barra fica em zero, e não em 100%. A regra
  /// percentual sobre um custo zero dá exigência zero — matematicamente
  /// cumprida —, mas "Exigência atingida" antes de o consultor escolher o
  /// primeiro insumo é a tela dizendo que ele terminou sem ter começado.
  double _classProgress(ProductClassModel c) {
    if (_inputCost <= 0) return 0;
    final req = _classRequired(c);
    if (req <= 0) return 1;
    return (_classSpend(c.id) / req).clamp(0.0, 1.0);
  }

  /// A classe aparece como cumprida na tela? Só depois de haver permuta: é o
  /// mesmo motivo de [_classProgress]. Quem decide o ENVIO é [_classMet], que
  /// não muda — a permuta vazia já é barrada por não ter insumo nenhum.
  bool _classMetOnScreen(ProductClassModel c) => _inputCost > 0 && _classMet(c);

  /// Classes ainda abaixo do mínimo (para avisar o consultor).
  List<ProductClassModel> get _unmetClasses => _ruledClasses.where((c) => !_classMet(c)).toList();

  void _setInput(String id, double qty) {
    final min = _minFor(id);
    setState(() {
      // Insumos exigidos por área não podem ficar abaixo do mínimo obrigatório.
      final v = qty < min ? min : qty;
      if (v <= 0) {
        _inputQty.remove(id);
      } else {
        _inputQty[id] = roundQuantity(v);
      }
    });
  }

  /// Escolhe o produtor (primeira etapa). Pré-preenche os insumos exigidos por
  /// área com seus mínimos obrigatórios, calculados a partir da área dele.
  void _selectProducer(String id) {
    final p = AppData.producerById(id);
    // Só aceita produtores da carteira do consultor logado — e a carteira é
    // compartilhável, então a pergunta é "ele me atende?", não "ele é meu?".
    if (p == null || !p.isAttendedBy(widget.consultant.id)) return;
    setState(() {
      _producerId = id;
      _searchQuery = '';
      for (final i in _catalog) {
        final min = minQuantityFor(i.requiredPerHa, p.areaHa);
        if (min > 0) _inputQty[i.id] = min;
      }
    });
  }

  /// Troca o produtor: limpa a permuta em construção e volta à escolha.
  ///
  /// A unidade cai junto porque a etapa dela vem DEPOIS: voltar para a primeira
  /// etapa com a segunda ainda respondida deixaria a tela mostrando uma
  /// retirada escolhida para um produtor que ainda não existe.
  void _changeProducer() {
    setState(() {
      _producerId = null;
      _unitId = null;
      _searchQuery = '';
      _inputQty.clear();
    });
  }

  /// Escolhe a unidade de retirada (segunda etapa).
  void _selectUnit(String id) {
    if (AppData.unitById(id) == null) return;
    setState(() {
      _unitId = id;
      _searchQuery = '';
    });
  }

  /// Volta para a escolha da unidade, preservando os insumos já montados.
  void _changeUnit() => setState(() {
    _unitId = null;
    _searchQuery = '';
  });

  bool _saving = false;

  /// Dá para GUARDAR o que está montado?
  ///
  /// Repare no que NÃO está aqui: [_classesOk]. Guardar uma permuta incompleta é
  /// o ponto da simulação — o consultor para no meio porque acabou o expediente,
  /// porque falta combinar um item com o produtor, ou porque ainda vai conferir
  /// o estoque. Exigir a permuta pronta para salvar deixaria o botão desligado
  /// exatamente nas horas em que ele serve. Quem cobra o mínimo das classes é o
  /// ENVIO, lá na aba de simulações, e antes dele o próprio servidor.
  bool get _canSave =>
      !_saving && _producerId != null && _unitId != null && _inputQty.values.any((qty) => qty > 0);

  /// Guarda a simulação NO APARELHO. Montar e guardar não falam com o servidor
  /// em momento algum — a permuta é montada na fazenda, onde pode não haver
  /// sinal, e enviar dependia de rede no exato momento em que o consultor estava
  /// mais longe dela.
  ///
  /// GUARDAR é o desfecho; ENVIAR é oferecido logo depois, em `_offerToSend`, e
  /// a ordem é o ponto. O trabalho já está no aparelho quando a pergunta chega,
  /// então dizer "agora não" — ou ficar sem sinal no meio do envio — não custa
  /// nada. Era um botão de enviar NO RODAPÉ, concorrendo com o de guardar, que
  /// fazia a permuta depender de rede para não se perder.
  Future<void> _save() async {
    final producer = _producer;
    final unit = _unit;
    final chosen = _inputQty.entries.where((entry) => entry.value > 0).toList();
    if (producer == null || unit == null || chosen.isEmpty) {
      _toast('Escolha o produtor, a unidade de retirada e ao menos um insumo.');
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    final version = _version;
    final simulation = BarterSimulation(
      id: _simulationId ?? BarterSimulation.newId(),
      consultantId: widget.consultant.id,
      producerId: producer.id,
      producerName: producer.name,
      unitId: unit.id,
      unitName: unit.name,
      versionCode: version?.code ?? '',
      // Nome e unidade de cada insumo vão CONGELADOS: sem rede o catálogo do
      // AppData está vazio, e a lista de simulações mostraria uma coluna de ids
      // justamente na situação em que ela é a única coisa que o consultor tem.
      items: [
        for (final entry in chosen)
          SimulationItem(
            productId: entry.key,
            productName: _productById(entry.key)?.name ?? '',
            unit: _productById(entry.key)?.unit ?? '',
            quantity: entry.value,
          ),
      ],
      simulatedSacks: _sacksNeeded,
      grainName: version?.grainName ?? '',
      taxRegime: _taxRegime,
      createdAt: widget.simulation?.createdAt ?? now,
      updatedAt: now,
    );

    final persisted = await AppData.saveSimulation(simulation);
    if (!mounted) return;

    // GUARDADA. Só a partir daqui o envio é oferecido — nesta ordem, e não como
    // um segundo botão no rodapé: o trabalho já está no aparelho, então o
    // consultor pode dizer "não" (ou ficar sem sinal no meio do envio) sem
    // perder nada. Era esse o motivo de o envio não morar nesta tela.
    final enviada = await _offerToSend(simulation);
    if (!mounted) return;

    // Retomada a partir da lista: volta para ela, que é de onde o consultor
    // veio. Se a permuta foi encaminhada agora, a simulação já não está lá.
    if (widget.simulation != null) {
      Navigator.pop(context, true);
      return;
    }

    // Vindo da aba "Nova Permuta", a simulação foi ARQUIVADA e a tela volta a
    // ficar em branco. Deixá-la preenchida sugeriria que ainda há algo pendente
    // ali, e o consultor acabaria montando a próxima por cima da que guardou.
    setState(() {
      _saving = false;
      _simulationId = null;
      _inputQty.clear();
      _producerId = null;
      _unitId = null;
      _searchQuery = '';
    });
    // Quem acabou de encaminhar já viu o diálogo do registro: repetir "envie em
    // Simulações" mandaria procurar uma simulação que não existe mais.
    if (enviada) return;
    _toast(
      persisted
          ? 'Simulação de ${producer.name} guardada. Envie ao gerente em Minhas '
                '${brand.copy.barterPluralTitle} › Simulações.'
          : 'Simulação guardada só nesta sessão: o aparelho não permitiu gravá-la. '
                'Envie-a antes de fechar o app.',
    );
  }

  /// "Encaminhar agora?" — a pergunta que vem logo depois de guardar.
  ///
  /// Ela é BARATA de propósito: não fala com o servidor. Só quem responde que
  /// sim é que entra no fluxo de envio (que aí sim busca a tabela vigente e
  /// confere o que mudou). Perguntar depois de já ter tentado a rede faria a
  /// tela pedir sinal para quem só queria guardar e ir embora.
  ///
  /// Devolve `true` quando a permuta foi mesmo registrada.
  Future<bool> _offerToSend(BarterSimulation simulation) async {
    final agora = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.bookmark_added_outlined, color: AppColors.primary, size: 40),
        title: const Text('Simulação guardada'),
        content: Text(
          'A permuta de ${simulation.producerName} está guardada neste aparelho. '
          'Quer encaminhá-la ao gerente agora? Se preferir, ela espera em Minhas '
          '${brand.copy.barterPluralTitle} › Simulações.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Agora não')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Encaminhar'),
          ),
        ],
      ),
    );
    if (agora != true || !mounted) return false;

    // O resumo do envio não é perguntado de novo — ele acabou de dizer que quer
    // mandar, e a tela que ele está vendo É a permuta. O diálogo volta sozinho
    // se houver o que dizer (o Barter virou, as sacas mudaram).
    return sendSimulationToManager(
      context,
      simulation: simulation,
      consultant: widget.consultant,
      alreadyConfirmed: true,
    );
  }

  /// Rebaixa o PACOTE do Barter — tabela, catálogo, classes, carteira e
  /// unidades —, que é tudo o que esta tela lê, e o grava no aparelho.
  ///
  /// É o pacote inteiro e não só a versão: a tabela de valores referencia o
  /// catálogo, e atualizar uma sem a outra deixaria a tela calculando sacas com
  /// as duas metades de momentos diferentes.
  Future<void> _refreshVersion() async {
    try {
      await AppData.syncOfflinePackage();
    } on ApiException catch (e) {
      // Sem rede a tela continua com o que tinha — que agora pode vir do
      // aparelho. Só avisa quem não tem nada: para quem já baixou uma vez, o
      // silêncio é a resposta certa, porque a tela continua utilizável.
      if (mounted && AppData.lastSyncAt == null) _toast(e.message);
    }
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  /// Formata um percentual de regra (ex.: 2,5%).
  String _fmtPct(double v) {
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '${s.replaceAll('.', ',')}%';
  }

  @override
  Widget build(BuildContext context) {
    final version = _version;
    final producer = _producer;
    final unit = _unit;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.simulation == null
              ? 'Nova ${brand.copy.barterTitle}'
              : 'Simulação • ${widget.simulation!.producerName}',
        ),
        actions: const [LogoutButton()],
      ),
      // As três etapas, na ordem em que uma habilita a seguinte: o produtor
      // define a área (e com ela os mínimos por hectare); a unidade define
      // onde se retira e de quem é o parecer; só então os insumos.
      body: version == null || !version.isOpen
          ? _buildClosedBarter()
          : producer == null
          ? _buildProducerStep(version)
          : unit == null
          ? _buildUnitStep(version, producer)
          : _buildInputStep(version, producer, unit),
    );
  }

  /// Sem Barter aberto não há o que montar: nem grão, nem valores, nem regra.
  /// A tela diz isso — e não deixa o consultor descobrir no envio.
  ///
  /// São TRÊS situações diferentes atrás da mesma tela vazia, e confundi-las é
  /// caro. "Barter fechado" respondido a quem nunca baixou a tabela manda o
  /// consultor embora achando que não há o que fazer — quando bastava conectar
  /// uma vez. O que separa as duas é [AppData.lastSyncAt]: com ele, o servidor
  /// já respondeu alguma vez, e a ausência de versão é um fato do negócio; sem
  /// ele, ninguém nunca perguntou.
  Widget _buildClosedBarter() {
    final version = _version;
    final neverSynced = AppData.lastSyncAt == null;
    final closed = version != null && !version.isOpen;

    final String title;
    final String body;
    if (neverSynced) {
      title = 'Baixe o ${brand.copy.programTitle} uma vez';
      body =
          'Este aparelho ainda não tem a tabela de valores. Conecte-se à '
          'internet e atualize: depois disso você monta simulações offline, '
          'inclusive abrindo o app sem sinal.';
    } else if (closed) {
      title = '${brand.copy.programTitle} encerrado';
      body =
          'A versão ${version.code} foi encerrada. Assim que o administrador '
          'publicar a próxima, ela aparece aqui.';
    } else {
      title = '${brand.copy.programTitle} fechado no momento';
      body =
          'Não há lançamento aberto para registrar permutas. Assim que o '
          'administrador publicar a próxima versão, ela aparece aqui.';
    }

    return RefreshIndicator(
      onRefresh: _refreshVersion,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 40),
          Icon(
            neverSynced ? Icons.cloud_download_outlined : Icons.event_busy_outlined,
            size: 64,
            color: AppColors.textLight,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMedium),
          ),
          // Quem chegou aqui abrindo uma simulação precisa ouvir a outra metade:
          // ela não se perdeu. Sem esta frase, a tela em branco no lugar da
          // permuta que ele montou diz exatamente o contrário — e o consultor
          // remonta tudo do zero quando o Barter reabrir.
          if (widget.simulation != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Sua simulação continua guardada neste aparelho. Assim que houver '
                '${brand.copy.programTitle} aberto, ela é refeita com os mesmos '
                'insumos e volta a poder ser encaminhada.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.primary),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Center(
            child: FilledButton.icon(
              onPressed: _refreshVersion,
              icon: Icon(neverSynced ? Icons.cloud_download_outlined : Icons.refresh, size: 18),
              label: Text(neverSynced ? 'Baixar agora' : 'Verificar novamente'),
            ),
          ),
        ],
      ),
    );
  }

  /// Etapa 1: escolher o produtor da permuta. Vem antes de tudo porque a área
  /// dele define quais insumos são obrigatórios e em que quantidade mínima.
  /// A lista é a CARTEIRA do consultor logado: ele nunca vê produtores dos
  /// colegas — só o admin enxerga todas as carteiras.
  Widget _buildProducerStep(BarterVersionModel version) {
    final wallet = AppData.producersForConsultant(widget.consultant.id);
    final query = _searchQuery.trim().toLowerCase();
    final producers = query.isEmpty
        ? wallet
        : wallet
              .where(
                (p) =>
                    p.name.toLowerCase().contains(query) ||
                    p.city.toLowerCase().contains(query) ||
                    p.farmName.toLowerCase().contains(query),
              )
              .toList();

    return Column(
      children: [
        const OfflineBanner(),
        _BarterBanner(version: version),
        if (wallet.isEmpty)
          Expanded(child: _emptyWalletHint())
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: _hint(
              icon: Icons.person_pin_circle_outlined,
              color: AppColors.primary,
              text:
                  'Etapa 1: escolha um produtor da sua carteira. A área da propriedade '
                  'define os insumos obrigatórios e a quantidade mínima de cada um.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: _searchBox('Buscar produtor, fazenda ou cidade...'),
          ),
          Expanded(
            child: producers.isEmpty
                ? _emptySearchHint()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    itemCount: producers.length,
                    itemBuilder: (_, i) => _ProducerChoiceTile(
                      producer: producers[i],
                      onSelect: () => _selectProducer(producers[i].id),
                    ),
                  ),
          ),
        ],
      ],
    );
  }

  /// Etapa 2: escolher a UNIDADE de retirada.
  ///
  /// É uma etapa própria, e não um campo no rodapé da lista de insumos, porque
  /// é um combinado com o produtor ("onde você quer buscar?") e não um detalhe
  /// de preenchimento. Qualquer unidade serve — inclusive de outra praça —, e
  /// ela não muda quem analisa a permuta: isso é sempre o gerente do consultor.
  Widget _buildUnitStep(BarterVersionModel version, ProducerModel producer) {
    final all = AppData.units;
    final query = _searchQuery.trim().toLowerCase();
    final units = query.isEmpty
        ? all
        : all
              .where(
                (u) => u.name.toLowerCase().contains(query) || u.city.toLowerCase().contains(query),
              )
              .toList();

    return Column(
      children: [
        const OfflineBanner(),
        _BarterBanner(version: version),
        _buildProducerHeader(producer),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: _hint(
            icon: Icons.store_outlined,
            color: AppColors.primary,
            text:
                'Etapa 2: onde ${producer.name.split(' ').first} vai retirar os insumos. '
                'Pode ser qualquer unidade — combine com ele.',
          ),
        ),
        if (all.isEmpty)
          Expanded(child: _emptyUnitsHint())
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: _searchBox('Buscar unidade ou cidade...'),
          ),
          Expanded(
            child: units.isEmpty
                ? _emptySearchHint()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    itemCount: units.length,
                    itemBuilder: (_, i) =>
                        _UnitChoiceTile(unit: units[i], onSelect: () => _selectUnit(units[i].id)),
                  ),
          ),
        ],
      ],
    );
  }

  /// Não há nenhuma unidade cadastrada — e sem local não há retirada.
  Widget _emptyUnitsHint() {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 40),
        Icon(Icons.store_mall_directory_outlined, size: 56, color: AppColors.textLight),
        const SizedBox(height: 14),
        Text(
          'Nenhuma unidade cadastrada',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark),
        ),
        const SizedBox(height: 8),
        Text(
          'A permuta é retirada em uma unidade, e ainda não há nenhuma no cadastro. '
          'Fale com o administrador.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textMedium),
        ),
        const SizedBox(height: 18),
        Center(
          child: TextButton.icon(
            onPressed: _refreshVersion,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Verificar novamente'),
          ),
        ),
      ],
    );
  }

  /// Etapa 3: montar os insumos (já com os mínimos pré-preenchidos), com o
  /// produtor, a unidade e o Barter vigente fixados no topo.
  Widget _buildInputStep(BarterVersionModel version, ProducerModel producer, UnitModel unit) {
    final inputCount = _inputQty.values.where((q) => q > 0).length;
    return Column(
      children: [
        const OfflineBanner(),
        _BarterBanner(version: version),
        _buildProducerHeader(producer),
        _buildUnitHeader(unit),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: BarterBalanceBar(
            inputCost: _inputCost,
            referenceValue: version.grainPrice,
            referenceGrainName: version.grainName,
            inputCount: inputCount,
            showValue: false,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: _searchBox('Buscar insumo ou código...'),
        ),
        _buildInputFilters(),
        Expanded(child: _buildInputList()),
        _buildFooter(version, producer),
      ],
    );
  }

  /// A barra de filtros da lista de insumos.
  ///
  /// Os chips recortam por CLASSE — que é como quem monta a permuta pensa
  /// ("agora os herbicidas") — e por "escolhidos", que é a revisão do que já
  /// está na permuta sem precisar caçar item por item numa lista de centenas.
  Widget _buildInputFilters() {
    final chosen = _inputQty.values.where((qty) => qty > 0).length;
    return FilterBar<_InputSort>(
      chips: [
        FilterChipData(
          label: 'Todos',
          selected: _classId == null && !_onlyChosen,
          onTap: () => setState(() {
            _classId = null;
            _onlyChosen = false;
          }),
        ),
        // Só aparece quando há o que revisar: chip que devolveria lista vazia
        // é ruído na barra.
        if (chosen > 0)
          FilterChipData(
            label: 'Escolhidos ($chosen)',
            selected: _onlyChosen,
            onTap: () => setState(() => _onlyChosen = !_onlyChosen),
          ),
        for (final productClass in _classesInVersion)
          FilterChipData(
            label: productClass.name,
            selected: _classId == productClass.id,
            onTap: () => setState(() {
              _classId = _classId == productClass.id ? null : productClass.id;
            }),
          ),
      ],
      sortLabel: _sort == _InputSort.name ? 'Nome' : 'Escolhidos',
      sortOptions: const {
        _InputSort.name: 'Nome (A–Z)',
        _InputSort.chosenFirst: 'Escolhidos primeiro',
      },
      current: _sort,
      onSort: (value) => setState(() => _sort = value),
    );
  }

  Widget _searchBox(String hint) => SizedBox(
    height: 40,
    child: TextField(
      onChanged: (v) => setState(() => _searchQuery = v),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => setState(() => _searchQuery = ''),
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      ),
    ),
  );

  /// Cabeçalho fixo com o produtor escolhido e sua área, com opção de trocar.
  Widget _buildProducerHeader(ProducerModel p) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary,
            child: Text(
              p.avatarInitials,
              style: TextStyle(
                color: AppColors.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Icon(Icons.straighten, size: 12, color: AppColors.primary),
                    const SizedBox(width: 3),
                    // Expanded, e não Text solto — o mesmo motivo dos 33 pixels
                    // do rodapé: numa Row sem Expanded o texto recebe largura
                    // infinita, e `ellipsis` só corta DEPOIS que existe uma
                    // largura máxima. Aqui vinha "1.200 ha • Nome da Cidade/PR"
                    // estourando 127 pixels num telefone de 360 — a linha
                    // vermelha por cima do cabeçalho do produtor.
                    Expanded(
                      child: Text(
                        '${p.areaLabel} • ${p.city}',
                        style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _changeProducer,
            icon: const Icon(Icons.swap_horiz, size: 16),
            label: const Text('Trocar', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  /// Faixa fina com a unidade de retirada escolhida.
  ///
  /// Ela fica visível durante a montagem inteira porque é um combinado com o
  /// produtor, e é o tipo de coisa que se lembra tarde ("ele disse que buscaria
  /// na Matriz") — com a faixa à vista, trocar custa um toque.
  Widget _buildUnitHeader(UnitModel unit) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.store_outlined, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Retirada em ${unit.label}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            onPressed: _changeUnit,
            icon: const Icon(Icons.swap_horiz, size: 16),
            label: const Text('Trocar', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  /// A lista de insumos do Barter vigente.
  ///
  /// `ListView.builder` não é otimização prematura aqui: cada `_InputTile` é um
  /// widget COM ESTADO, que cria o próprio `TextEditingController`. Com a lista
  /// real (656 insumos), a forma `children:` montava 656 tiles e 656
  /// controllers na abertura da tela — para o consultor ver oito.
  /// Os insumos que a lista mostra: busca + classe + "só os escolhidos", na
  /// ordem pedida.
  List<ProductModel> get _visibleInputs {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _catalog.where((input) {
      if (!input.matches(query)) return false;
      if (_classId != null && input.classId != _classId) return false;
      if (_onlyChosen && (_inputQty[input.id] ?? 0) <= 0) return false;
      return true;
    }).toList();

    filtered.sort((a, b) {
      if (_sort == _InputSort.chosenFirst) {
        final chosenA = (_inputQty[a.id] ?? 0) > 0;
        final chosenB = (_inputQty[b.id] ?? 0) > 0;
        if (chosenA != chosenB) return chosenA ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    return filtered;
  }

  /// Só as classes que TÊM insumo no Barter vigente viram chip — oferecer um
  /// recorte que devolveria lista vazia é um filtro que mente.
  List<ProductClassModel> get _classesInVersion {
    final ids = _catalog.map((input) => input.classId).whereType<String>().toSet();
    return AppData.classes.where((c) => ids.contains(c.id)).toList();
  }

  Widget _buildInputList() {
    final query = _searchQuery.trim().toLowerCase();
    final inputs = _visibleInputs;

    // O cabeçalho (dica + barras de mínimo por classe) só aparece sem busca:
    // quem está procurando um item quer a lista, não a explicação.
    final filtrando = query.isNotEmpty || _classId != null || _onlyChosen;
    final header = <Widget>[
      // Com filtro ativo, quantos itens sobraram de quantos — é o que diz se
      // vale continuar rolando ou refinar a busca.
      if (filtrando && inputs.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            '${inputs.length} de ${_catalog.length} insumo(s)',
            style: TextStyle(fontSize: 11, color: AppColors.textLight),
          ),
        ),
      if (query.isEmpty) ...[
        _hint(
          icon: _hasRequiredInputs ? Icons.rule : Icons.info_outline,
          color: AppColors.input,
          text: _hasRequiredInputs
              ? 'Os insumos obrigatórios para a área deste produtor já vêm com a '
                    'quantidade mínima preenchida. Você pode aumentar, não reduzir.'
              : 'Escolha os insumos que o produtor precisa. Eles serão '
                    'convertidos em sacas do grão desta safra.',
        ),
        const SizedBox(height: 8),
        ..._ruledClasses.map(
          (c) => _ClassRuleTile(
            name: c.name,
            detail: c.ruleType == ClassRuleType.percentOfTotal
                ? 'mín. ${_fmtPct(c.ruleValue)} do total da permuta'
                : 'mínimo por área da propriedade',
            progress: _classProgress(c),
            met: _classMetOnScreen(c),
          ),
        ),
        if (_ruledClasses.isNotEmpty) const SizedBox(height: 8),
      ],
    ];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      itemCount: header.length + (inputs.isEmpty ? 1 : inputs.length),
      itemBuilder: (context, index) {
        if (index < header.length) return header[index];
        if (inputs.isEmpty) return _emptySearchHint();
        final input = inputs[index - header.length];
        return _InputTile(
          // A chave amarra o estado do tile ao PRODUTO, não à posição: sem
          // ela, filtrar a lista faria o campo de quantidade de um insumo
          // aparecer noutro.
          key: ValueKey(input.id),
          product: input,
          qty: _inputQty[input.id] ?? 0,
          minQty: _minFor(input.id),
          onChanged: (q) => _setInput(input.id, q),
        );
      },
    );
  }

  /// Nada encontrado — dizendo POR QUE, que é o que permite desfazer. Com três
  /// recortes possíveis (busca, classe, escolhidos), "nenhum item encontrado"
  /// sozinho deixa o consultor procurando o que ele mesmo ligou.
  Widget _emptySearchHint() {
    final motivos = [
      if (_searchQuery.trim().isNotEmpty) '"${_searchQuery.trim()}"',
      if (_classId != null) AppData.classById(_classId)?.name ?? 'classe',
      if (_onlyChosen) 'só os escolhidos',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 40, color: AppColors.textLight),
          const SizedBox(height: 8),
          Text(
            motivos.isEmpty
                ? 'Nenhum insumo neste Barter'
                : 'Nenhum insumo em ${motivos.join(' + ')}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textLight),
          ),
          if (motivos.isNotEmpty) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => setState(() {
                _searchQuery = '';
                _classId = null;
                _onlyChosen = false;
              }),
              child: const Text('Limpar filtros', style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  /// Aviso para o consultor sem produtores na carteira: sem carteira não há
  /// permuta, e quem cadastra/atribui produtores é o administrador.
  Widget _emptyWalletHint() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group_off_outlined, size: 56, color: AppColors.textLight),
          const SizedBox(height: 12),
          Text(
            'Sua carteira de produtores está vazia',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark),
          ),
          const SizedBox(height: 6),
          Text(
            'Peça ao administrador para cadastrar produtores na sua carteira '
            'antes de registrar uma permuta.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMedium),
          ),
        ],
      ),
    ),
  );

  /// O rodapé da etapa 3: o total em sacas, o Funrural e o botão de guardar.
  ///
  /// Recebe o [producer] em vez de reler `_producerId`: o documento dele é o que
  /// escolhe entre as alíquotas de CPF e as de CNPJ, e o rodapé só existe dentro
  /// da etapa que já o tem resolvido. Buscá-lo de novo abriria um caminho em que
  /// a busca falha e a conta cai calada nas alíquotas de CPF — imposto errado,
  /// sem aviso nenhum. Pela assinatura isso não é representável.
  Widget _buildFooter(BarterVersionModel version, ProducerModel producer) {
    final sacks = _sacksNeeded;
    final inputCount = _inputQty.values.where((q) => q > 0).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(color: AppColors.cardShadow, blurRadius: 10, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_unmetClasses.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 14, color: AppColors.pending),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Mínimo não atingido: ${_unmetClasses.map((c) => c.name).join(', ')}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.pending,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Icon(Icons.local_shipping_outlined, size: 14, color: AppColors.textMedium),
                const SizedBox(width: 6),
                // Expanded, e não Text solto: `overflow: ellipsis` só corta o
                // texto DEPOIS que ele recebe uma largura máxima. Numa Row sem
                // Expanded ele recebe largura infinita, não corta nada e
                // estoura a linha — eram os 33 pixels vermelhos no rodapé.
                Expanded(
                  child: Text(
                    inputCount > 0
                        ? 'Entregar: ${formatSacks(sacks)} ${version.grainName.toLowerCase()} • $inputCount insumo(s)'
                        : 'Escolha os insumos para ver quantas sacas serão necessárias',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            // O IMPOSTO DA ENTREGA, no fechamento da permuta: as duas formas de
            // recolher o Funrural, e o que cada uma custa em sacas — a unidade
            // em que o consultor enxerga a permuta (ele não vê R$).
            //
            // A escolha fica AQUI, junto do total, porque é onde a conversa
            // acontece: o produtor pergunta "quanto eu entrego?" na fazenda, e a
            // resposta honesta inclui o Funrural. Descobrir depois, na nota, era
            // a diferença virar assunto no pior momento.
            if (inputCount > 0) ...[
              const SizedBox(height: 8),
              _TaxRegimeChooser(
                selected: _taxRegime,
                document: producer.document,
                sacks: sacks,
                grainName: version.grainName,
                onChanged: (regime) => setState(() => _taxRegime = regime),
              ),
            ],
            const SizedBox(height: 8),
            // UM botão, e não dois. Enviar ao gerente existe nesta tela, mas
            // DEPOIS de guardar (ver `_offerToSend`), nunca como uma segunda
            // saída aqui: duas saídas deixariam o consultor escolher a que
            // depende de rede no pior lugar para depender dela, e perder o
            // trabalho junto com o envio que não completou.
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _canSave ? _save : null,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.bookmark_added_outlined, size: 18),
                label: Text(
                  _saving
                      ? 'Guardando...'
                      : widget.simulation == null
                      ? 'Guardar simulação'
                      : 'Salvar alterações',
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Dito em voz alta porque é a pergunta que o botão sozinho deixa no
            // ar — "então já foi para o gerente?". Vale com e sem sinal: ter
            // rede não faz a permuta escapar; quem decide o momento é ele.
            Text(
              'Nada é enviado agora. Você encaminha ao gerente quando quiser, '
              'em Minhas ${brand.copy.barterPluralTitle} › Simulações.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textLight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hint({required IconData icon, required Color color, required String text}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// AS DUAS FORMAS DE RECOLHER O FUNRURAL, no fechamento da permuta.
///
/// A entrega de grão é comercialização de produção rural: sobre ela incidem o
/// Funrural e o Senar. O que se escolhe aqui é a base da parte previdenciária —
/// a receita da venda ou a folha de pagamento do produtor.
///
/// Escolher a FOLHA não isenta a entrega: o Senar continua saindo da
/// comercialização, e é por isso que a alíquota cai (para 0,20% de CPF, 0,25%
/// de CNPJ) em vez de zerar. O número ao lado existe justamente para essa
/// diferença aparecer no momento da escolha, e não na nota fiscal.
///
/// PF ou PJ não é perguntado: sai do documento do produtor desta permuta.
///
/// ## Por que cada segmento diz a alíquota E o nome
///
/// Os dois juntos, e não um ou outro. A alíquota sozinha era o desenho
/// anterior, pela razão certa — é o percentual que muda a conta, e é ele que a
/// pessoa do outro lado do balcão pergunta. Mas com só o número o nome da opção
/// NÃO SELECIONADA ficava invisível, e descobri-lo custava tocar nela — o que
/// não é espiar, é declarar: esta escolha é gravada na permuta e vira o
/// `taxRate` congelado do comprovante.
///
/// E "1,63% ou 0,20%, escolha" descreve errado o que está sendo perguntado. O
/// regime não é preferência de quem fecha a permuta: é a opção FORMAL que o
/// produtor fez (ou não fez) perante o fisco, e quem não fez cai na
/// comercialização. Dois números anônimos lado a lado, um deles oito vezes
/// menor, convidam a marcar o barato — que só é legítimo para quem de fato
/// optou. Por isso o nome voltou ao segmento e a linha de baixo diz o que a
/// forma selecionada significa, em vez de só repetir o rótulo dela.
class _TaxRegimeChooser extends StatelessWidget {
  final TaxRegime selected;

  /// O documento do produtor desta permuta — é a contagem de dígitos dele que
  /// decide se as alíquotas mostradas são as de CPF ou as de CNPJ.
  final String document;

  /// As sacas a entregar, para a linha de baixo dizer quanto o percentual dá em
  /// grão — o consultor não vê R$ em lugar nenhum do app.
  final double sacks;
  final String grainName;

  final ValueChanged<TaxRegime> onChanged;

  const _TaxRegimeChooser({
    required this.selected,
    required this.document,
    required this.sacks,
    required this.grainName,
    required this.onChanged,
  });

  String _rateLabel(TaxRegime regime) =>
      '${taxRateOf(regime, document).toStringAsFixed(2).replaceAll('.', ',')}%';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.receipt_long_outlined, size: 14, color: AppColors.textMedium),
            const SizedBox(width: 6),
            // Expanded aqui pela mesma razão do cabeçalho do produtor: `Text`
            // solto numa `Row` não tem largura máxima e não corta.
            Expanded(
              child: Text(
                'Recolhimento do Funrural',
                style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<TaxRegime>(
            segments: [
              for (final regime in TaxRegime.values)
                ButtonSegment(
                  value: regime,
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Nenhum dos dois fixa `color`: quem pinta o texto do
                      // segmento é o próprio botão, conforme selecionado ou
                      // não, e uma cor nossa aqui apagaria essa diferença — que
                      // é o que diz qual das formas está valendo.
                      Text(
                        _rateLabel(regime),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        regime.shortLabel,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
            ],
            selected: {selected},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (escolha) => onChanged(escolha.first),
          ),
        ),
        const SizedBox(height: 3),
        // O QUANTO e o PORQUÊ, em um parágrafo só.
        //
        // O quanto vem primeiro porque é a resposta à pergunta que o produtor
        // faz na fazenda ("quanto eu entrego?"), e sai em sacas porque é a
        // unidade em que o consultor enxerga a permuta. O porquê é
        // `description`, que existia no modelo desde o começo e não aparecia em
        // lugar nenhum — era a única frase do app que dizia a diferença entre as
        // duas formas, e estava sobrando enquanto a tela pedia a escolha sem
        // explicá-la.
        //
        // Um Text só, e não dois: em tela estreita ambos quebram de qualquer
        // jeito, e separá-los custava uma linha inteira de altura num rodapé que
        // já disputa espaço com a lista de insumos.
        Text(
          '+ ${formatSacks(taxAmountOf(sacks, taxRateOf(selected, document)))} '
          '${grainName.toLowerCase()} de Funrural/Senar sobre a entrega — estimativa. '
          '${selected.description}',
          style: TextStyle(fontSize: 11, color: AppColors.textLight, height: 1.25),
        ),
      ],
    );
  }
}

/// Faixa do Barter vigente: qual lançamento está valendo e em que grão a
/// permuta será paga. Sem R\$ — o consultor não vê valores, e o grão aqui é
/// informação, não escolha.
class _BarterBanner extends StatelessWidget {
  final BarterVersionModel version;
  const _BarterBanner({required this.version});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.grainBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grain.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.grass, size: 18, color: AppColors.grain),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${brand.copy.programTitle} ${version.code}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  'Pagamento em ${version.grainName.toLowerCase()}'
                  '${version.endsAt != null ? ' • até ${_shortDate(version.endsAt!)}' : ''}',
                  style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _shortDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
}

class _ClassRuleTile extends StatelessWidget {
  final String name;
  final String detail;
  final double progress;
  final bool met;

  const _ClassRuleTile({
    required this.name,
    required this.detail,
    required this.progress,
    required this.met,
  });

  @override
  Widget build(BuildContext context) {
    final color = met ? AppColors.approved : AppColors.pending;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(met ? Icons.check_circle : Icons.rule, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            met ? 'Exigência atingida • $detail' : 'Exigência: $detail',
            style: TextStyle(fontSize: 11, color: AppColors.textMedium),
          ),
        ],
      ),
    );
  }
}

/// Linha de um insumo na etapa de montagem. Quando [minQty] > 0, o insumo é
/// obrigatório para a área do produtor: vem pré-preenchido e não pode descer
/// abaixo do mínimo.
class _InputTile extends StatefulWidget {
  final ProductModel product;
  final double qty;
  final double minQty;
  final ValueChanged<double> onChanged;

  const _InputTile({
    super.key,
    required this.product,
    required this.qty,
    required this.minQty,
    required this.onChanged,
  });

  @override
  State<_InputTile> createState() => _InputTileState();
}

class _InputTileState extends State<_InputTile> {
  /// Controller próprio (com dispose) para o campo não perder foco/teclado a
  /// cada rebuild — antes era recriado em todo build, com vazamento.
  late final TextEditingController _qtyCtrl = TextEditingController(
    text: widget.qty > 0 ? formatQty(widget.qty) : '',
  );

  ProductModel get product => widget.product;
  double get qty => widget.qty;
  double get minQty => widget.minQty;
  ValueChanged<double> get onChanged => widget.onChanged;

  bool get _required => minQty > 0;

  @override
  void didUpdateWidget(_InputTile old) {
    super.didUpdateWidget(old);
    // Sincroniza o texto apenas quando a mudança veio de fora (botões +/-,
    // pré-preenchimento do mínimo), sem brigar com a digitação do usuário.
    final typed = double.tryParse(_qtyCtrl.text.replaceAll(',', '.')) ?? 0;
    if ((widget.qty - typed).abs() > 0.004) {
      _qtyCtrl.text = widget.qty > 0 ? formatQty(widget.qty) : '';
      _qtyCtrl.selection = TextSelection.collapsed(offset: _qtyCtrl.text.length);
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // A figura é da CLASSE: com centenas de insumos na lista, é ela
                // que deixa o consultor varrer por bloco (herbicida, adubo) em
                // vez de ler item por item.
                ClassAvatar(productClass: AppData.classById(product.classId)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              product.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                          if (_required) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.input.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'mín. ${formatQty(minQty)} ${product.unit}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.input,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        _required
                            ? 'Obrigatório • medido em ${product.unit}'
                            : 'Medido em ${product.unit}',
                        style: TextStyle(fontSize: 12, color: AppColors.textLight),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StepBtn(
                  icon: Icons.remove,
                  color: AppColors.input,
                  onTap: qty > minQty
                      ? () => onChanged((qty - 1).clamp(minQty, double.infinity))
                      : null,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                      hintText: '0',
                      contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      isDense: true,
                    ),
                    onSubmitted: (v) => onChanged(double.tryParse(v.replaceAll(',', '.')) ?? 0),
                    onChanged: (v) => onChanged(double.tryParse(v.replaceAll(',', '.')) ?? 0),
                  ),
                ),
                const SizedBox(width: 8),
                _StepBtn(icon: Icons.add, color: AppColors.input, onTap: () => onChanged(qty + 1)),
                const Spacer(),
                if (qty > 0)
                  Text(
                    '${formatQty(qty)} ${product.unit}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.input,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Card de escolha do produtor (etapa 1). Destaca a área da propriedade, que é
/// a base das exigências mínimas de insumo da permuta.
class _ProducerChoiceTile extends StatelessWidget {
  final ProducerModel producer;
  final VoidCallback onSelect;

  const _ProducerChoiceTile({required this.producer, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primarySurface,
                child: Text(
                  producer.avatarInitials,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      producer.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      producer.location,
                      style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.straighten, size: 12, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Área: ${producer.areaLabel}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textLight),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card de escolha da unidade de retirada (etapa 2). Nome e cidade, porque é
/// só isso que a unidade é: um local. Qualquer uma da lista serve.
class _UnitChoiceTile extends StatelessWidget {
  final UnitModel unit;
  final VoidCallback onSelect;

  const _UnitChoiceTile({required this.unit, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primarySurface,
                child: Icon(Icons.store_outlined, size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unit.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      unit.city,
                      style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textLight),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled ? color.withValues(alpha: 0.12) : AppColors.disabledBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: enabled ? color : AppColors.divider),
        ),
        child: Icon(icon, size: 16, color: enabled ? color : AppColors.disabledFg),
      ),
    );
  }
}
