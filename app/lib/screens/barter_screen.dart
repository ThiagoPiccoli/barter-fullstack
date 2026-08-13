import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/api/api_client.dart';
import '../services/barter_math.dart';
import '../services/barter_pdf.dart';
import '../widgets/common_widgets.dart';

/// Construtor de permuta. O produtor primeiro escolhe os INSUMOS de que precisa
/// (eles formam um custo) e depois escolhe UM grão de pagamento — o app calcula
/// quantas sacas desse grão são necessárias para cobrir o custo dos insumos.
class NewBarterScreen extends StatefulWidget {
  final UserModel consultant;
  const NewBarterScreen({super.key, required this.consultant});
  @override
  State<NewBarterScreen> createState() => _NewBarterScreenState();
}

class _NewBarterScreenState extends State<NewBarterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Map<String, double> _inputQty = {};
  String? _paymentGrainId;
  String? _producerId;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Os insumos escolhidos, já precificados — a entrada da matemática da
  /// permuta (services/barter_math.dart, espelho do cálculo do servidor).
  List<PricedInput> get _pricedInputs => [
        for (final e in _inputQty.entries)
          if (e.value > 0)
            () {
              final p = AppData.inputs.firstWhere((i) => i.id == e.key);
              return PricedInput(
                productId: p.id,
                quantity: e.value,
                unitPrice: p.currentPrice,
                categoryId: p.categoryId,
              );
            }(),
      ];

  /// Custo total dos insumos escolhidos (R$) — o valor que a permuta paga.
  double get _inputCost => inputCost(_pricedInputs);

  /// Grão escolhido para pagamento (ou null se ainda não escolheu).
  ProductModel? get _paymentGrain {
    if (_paymentGrainId == null) return null;
    return AppData.grains.firstWhere((g) => g.id == _paymentGrainId);
  }

  /// Produtor (cliente) designado para esta permuta (ou null).
  ProducerModel? get _producer =>
      _producerId == null ? null : AppData.producerById(_producerId!);

  /// Sacas do grão escolhido necessárias para cobrir o custo dos insumos.
  /// Mesmo arredondamento do servidor: o número da tela é o que será gravado.
  double get _sacksNeeded {
    final g = _paymentGrain;
    return g == null ? 0 : sacksToCover(_inputCost, g.currentPrice);
  }

  /// Quantas sacas de [grain] cobririam o custo atual dos insumos.
  double _sacksFor(ProductModel grain) => sacksToCover(_inputCost, grain.currentPrice);

  /// Quantidade mínima obrigatória de um insumo para o produtor atual:
  /// taxa por hectare × área da propriedade. 0 se não há produtor ou exigência.
  double _minFor(String inputId) {
    final p = _producer;
    if (p == null) return 0;
    final input = AppData.inputs.firstWhere((i) => i.id == inputId);
    return minQuantityFor(input.requiredPerHa, p.areaHa);
  }

  /// Há algum insumo com exigência mínima por área para o produtor atual?
  bool get _hasRequiredInputs => AppData.inputs.any((i) => _minFor(i.id) > 0);

  /// Categorias ("pastas") que carregam uma regra de mínimo capaz de travar o
  /// envio da permuta.
  List<InputCategoryModel> get _ruledCategories =>
      AppData.categories.where((c) => c.hasRule).toList();

  /// Custo (R$) dos insumos escolhidos que pertencem à categoria [categoryId].
  double _categorySpend(String categoryId) => categorySpend(_pricedInputs, categoryId);

  /// Mínimo (R$) exigido por uma categoria, dado o estado atual da permuta:
  /// percentual do custo total, ou valor por hectare × área do produtor.
  double _categoryRequired(InputCategoryModel c) {
    final p = _producer;
    // Sem produtor escolhido não há área, e a regra por hectare não tem base
    // de cálculo — o servidor sempre tem, porque a permuta chega com produtor.
    if (p == null && c.ruleType == CategoryRuleType.valuePerHa) return 0;
    return categoryRequired(
      CategoryRule.values.byName(c.ruleType.name),
      c.ruleValue,
      totalCost: _inputCost,
      areaHa: p?.areaHa ?? 0,
    );
  }

  /// O mínimo da categoria foi atingido? (tolerância de centavos)
  bool _categoryMet(InputCategoryModel c) {
    final req = _categoryRequired(c);
    if (req <= 0) return true;
    return _categorySpend(c.id) >= req - moneyEpsilon;
  }

  /// Progresso (0–1) rumo ao mínimo da categoria. Usado na barra do consultor —
  /// é proporção, nunca expõe R\$.
  double _categoryProgress(InputCategoryModel c) {
    final req = _categoryRequired(c);
    if (req <= 0) return 1;
    return (_categorySpend(c.id) / req).clamp(0.0, 1.0);
  }

  /// Todas as exigências de categoria foram cumpridas?
  bool get _categoriesOk => _ruledCategories.every(_categoryMet);

  /// Categorias ainda abaixo do mínimo (para avisar o consultor).
  List<InputCategoryModel> get _unmetCategories =>
      _ruledCategories.where((c) => !_categoryMet(c)).toList();

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

  void _selectGrain(String id) => setState(() => _paymentGrainId = id);

  /// Escolhe o produtor (primeira etapa). Pré-preenche os insumos exigidos por
  /// área com seus mínimos obrigatórios, calculados a partir da área dele.
  void _selectProducer(String id) {
    final p = AppData.producerById(id);
    // Só aceita produtores da carteira do consultor logado.
    if (p == null || p.consultantId != widget.consultant.id) return;
    setState(() {
      _producerId = id;
      _searchQuery = '';
      for (final i in AppData.inputs) {
        final min = minQuantityFor(i.requiredPerHa, p.areaHa);
        if (min > 0) _inputQty[i.id] = min;
      }
    });
  }

  /// Troca o produtor: limpa a permuta em construção e volta à escolha.
  void _changeProducer() {
    setState(() {
      _producerId = null;
      _searchQuery = '';
      _inputQty.clear();
      _paymentGrainId = null;
      _tabController.index = 0;
    });
  }

  bool _submitting = false;

  bool get _canSubmit =>
      !_submitting &&
      _producerId != null &&
      _inputCost > 0 &&
      _paymentGrainId != null &&
      _categoriesOk;

  /// O produtor já foi escolhido na primeira etapa; aqui só revisamos e enviamos.
  Future<void> _onSubmitPressed() async {
    if (_producerId == null) return;
    final confirmed = await _showSummaryDialog();
    if (confirmed == true) await _submit();
  }

  /// Resumo completo da permuta antes de enviar: todos os insumos retirados,
  /// o grão de pagamento e o total de sacas a entregar — para o consultor
  /// revisar antes de finalizar.
  Future<bool?> _showSummaryDialog() {
    final grain = _paymentGrain;
    final producer = _producer;
    final sacks = _sacksNeeded;
    final inputs = _inputQty.entries.where((e) => e.value > 0).map((e) {
      final p = AppData.inputs.firstWhere((i) => i.id == e.key);
      return BarterItem(
        productId: p.id,
        productName: p.name,
        unit: p.unit,
        quantity: e.value,
        unitValue: p.currentPrice,
      );
    }).toList();

    if (grain == null || producer == null || inputs.isEmpty) return Future.value(false);

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.fact_check_outlined, color: AppColors.primary, size: 40),
        title: Text('Confirmar ${brand.copy.barterTitle}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DialogLine('Produtor', producer.name),
                const SizedBox(height: 8),
                Text('Insumos retirados',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.inputBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: inputs
                        .map((i) => _DialogLine(
                              i.productName,
                              _totalVolume(i),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _DialogLine(
                    'Você vai entregar',
                    '${formatSacks(sacks)} ${grain.name.toLowerCase()}',
                    bold: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Revisar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar e Enviar'),
          ),
        ],
      ),
    );
  }

  /// Volume total de um insumo, sem nenhum valor em R$. Quando a unidade traz um
  /// peso (ex.: "saco 50kg"), soma o peso: 2 × 50kg = "100 kg". Caso contrário
  /// (ex.: "litro"), mostra só a quantidade: "3 litro(s)".
  String _totalVolume(BarterItem i) {
    final match = RegExp(r'(\d+(?:[.,]\d+)?)\s*(kg|g|l|ml)', caseSensitive: false)
        .firstMatch(i.unit);
    if (match != null) {
      final weight = double.parse(match.group(1)!.replaceAll(',', '.'));
      final measure = match.group(2)!.toLowerCase();
      return '${formatQty(i.quantity * weight)} $measure';
    }
    return '${formatQty(i.quantity)} ${i.unit}';
  }

  /// Envia a permuta para a API. O app mostra a prévia (sacas, mínimos), mas
  /// quem precifica, valida os mínimos e calcula as sacas finais é o servidor
  /// — a permuta exibida no diálogo de sucesso é a versão oficial devolvida.
  Future<void> _submit() async {
    final grain = _paymentGrain;
    final producer = _producer;
    final chosen = Map<String, double>.from(_inputQty)
      ..removeWhere((_, qty) => qty <= 0);

    if (producer == null) {
      _toast('Selecione o produtor desta permuta.');
      return;
    }
    if (chosen.isEmpty) {
      _toast('Selecione ao menos um insumo para retirar.');
      return;
    }
    if (grain == null) {
      _toast('Escolha o grão com que você vai pagar.');
      return;
    }
    final unmet = _unmetCategories;
    if (unmet.isNotEmpty) {
      _toast('Mínimo não atingido: ${unmet.map((c) => c.name).join(', ')}.');
      return;
    }

    setState(() => _submitting = true);
    final BarterModel barter;
    try {
      barter = await AppData.createBarter(
        producerId: producer.id,
        grainId: grain.id,
        inputQuantities: chosen,
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        _toast(e.message);
      }
      return;
    }
    if (!mounted) return;

    final sacks = barter.sacksToDeliver;

    setState(() {
      _submitting = false;
      _inputQty.clear();
      _paymentGrainId = null;
      _producerId = null;
      _tabController.index = 0;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.swap_horiz, color: AppColors.approved, size: 48),
        title: Text('${brand.copy.barterTitle} Enviada!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Permuta ${barter.id} registrada com sucesso.',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Text(
              'Sua proposta de troca foi enviada para análise do administrador.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textMedium),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _DialogLine('Produtor', producer.name),
                  _DialogLine('Insumos retirados', '${barter.inputs.length} item(ns)'),
                  const Divider(height: 14),
                  _DialogLine(
                    'Você vai entregar',
                    '${formatSacks(sacks)} ${barter.referenceGrainName.toLowerCase()}',
                    bold: true,
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          // Comprovante para controle: PDF do consultor, sem valores em R$.
          OutlinedButton.icon(
            onPressed: () => _sharePdf(barter, producer),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Gerar PDF'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _sharePdf(BarterModel barter, ProducerModel producer) async {
    try {
      await BarterPdf.share(barter, producer: producer, showValues: false);
    } catch (e) {
      if (mounted) _toast('Não foi possível gerar o PDF: $e');
    }
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
    final producer = _producer;
    final inputCount = _inputQty.values.where((q) => q > 0).length;
    final grainChosen = _paymentGrainId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('Nova ${brand.copy.barterTitle}'),
        actions: const [LogoutButton()],
        bottom: producer == null
            ? null
            : TabBar(
                controller: _tabController,
                labelPadding: const EdgeInsets.symmetric(vertical: 4),
                tabs: [
                  Tab(text: '2. Insumos${inputCount > 0 ? ' ($inputCount)' : ''}'),
                  Tab(text: '3. Pagar com Grãos${grainChosen ? ' ✓' : ''}'),
                ],
              ),
      ),
      body: producer == null ? _buildProducerStep() : _buildBarterStep(producer, inputCount),
    );
  }

  /// Etapa 1: escolher o produtor da permuta. Vem antes de tudo porque a área
  /// dele define quais insumos são obrigatórios e em que quantidade mínima.
  /// A lista é a CARTEIRA do consultor logado: ele nunca vê produtores dos
  /// colegas — só o admin enxerga todas as carteiras.
  Widget _buildProducerStep() {
    final wallet = AppData.producersForConsultant(widget.consultant.id);
    if (wallet.isEmpty) return _emptyWalletHint();
    final query = _searchQuery.trim().toLowerCase();
    final producers = query.isEmpty
        ? wallet
        : wallet
            .where((p) =>
                p.name.toLowerCase().contains(query) ||
                p.city.toLowerCase().contains(query) ||
                p.farmName.toLowerCase().contains(query))
            .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: _hint(
            icon: Icons.person_pin_circle_outlined,
            color: AppColors.primary,
            text: 'Etapa 1: escolha um produtor da sua carteira. A área da propriedade '
                'define os insumos obrigatórios e a quantidade mínima de cada um.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: SizedBox(
            height: 40,
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar produtor, fazenda ou cidade...',
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
          ),
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
    );
  }

  /// Etapas 2 e 3: montar os insumos (já com os mínimos pré-preenchidos) e
  /// escolher o grão de pagamento, sempre com o produtor fixado no topo.
  Widget _buildBarterStep(ProducerModel producer, int inputCount) {
    return Column(
      children: [
        _buildProducerHeader(producer),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: BarterBalanceBar(
            inputCost: _inputCost,
            referenceValue: _paymentGrain?.currentPrice ?? 0,
            referenceGrainName: _paymentGrain?.name ?? '',
            inputCount: inputCount,
            showValue: false,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: SizedBox(
            height: 40,
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: _tabController.index == 0 ? 'Buscar insumo...' : 'Buscar grão...',
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
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildInputTab(),
              _buildGrainTab(),
            ],
          ),
        ),
        _buildFooter(),
      ],
    );
  }

  /// Cabeçalho fixo com o produtor escolhido e sua área, com opção de trocar.
  Widget _buildProducerHeader(ProducerModel p) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
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
            child: Text(p.avatarInitials,
                style: TextStyle(color: AppColors.onPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark),
                    overflow: TextOverflow.ellipsis),
                Row(
                  children: [
                    Icon(Icons.straighten, size: 12, color: AppColors.primary),
                    const SizedBox(width: 3),
                    Text('${p.areaLabel} • ${p.city}',
                        style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
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

  Widget _buildInputTab() {
    final query = _searchQuery.trim().toLowerCase();
    final inputs = query.isEmpty
        ? AppData.inputs
        : AppData.inputs.where((i) => i.name.toLowerCase().contains(query)).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      children: [
        if (query.isEmpty)
          _hint(
            icon: _hasRequiredInputs ? Icons.rule : Icons.info_outline,
            color: AppColors.input,
            text: _hasRequiredInputs
                ? 'Os insumos obrigatórios para a área deste produtor já vêm com a '
                    'quantidade mínima preenchida. Você pode aumentar, não reduzir.'
                : 'Escolha os insumos que o produtor precisa. Eles serão '
                    'convertidos em sacas do grão que você escolher para pagar.',
          ),
        if (query.isEmpty) const SizedBox(height: 8),
        if (query.isEmpty && _ruledCategories.isNotEmpty) ...[
          ..._ruledCategories.map((c) => _CategoryRuleTile(
                name: c.name,
                detail: c.ruleType == CategoryRuleType.percentOfTotal
                    ? 'mín. ${_fmtPct(c.ruleValue)} do total da permuta'
                    : 'mínimo por área da propriedade',
                progress: _categoryProgress(c),
                met: _categoryMet(c),
              )),
          const SizedBox(height: 8),
        ],
        if (inputs.isEmpty) _emptySearchHint() else ...inputs.map((i) => _InputTile(
              product: i,
              qty: _inputQty[i.id] ?? 0,
              minQty: _minFor(i.id),
              onChanged: (q) => _setInput(i.id, q),
            )),
      ],
    );
  }

  Widget _buildGrainTab() {
    final hasInputs = _inputCost > 0;
    final query = _searchQuery.trim().toLowerCase();
    final grains = query.isEmpty
        ? AppData.grains
        : AppData.grains.where((g) => g.name.toLowerCase().contains(query)).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      children: [
        if (query.isEmpty)
          _hint(
            icon: hasInputs ? Icons.check_circle_outline : Icons.lock_outline,
            color: hasInputs ? AppColors.grain : AppColors.pending,
            text: hasInputs
                ? 'Escolha com qual grão você vai pagar. Veja quantas sacas de cada '
                    'um cobrem os insumos retirados.'
                : 'Volte à etapa 1 e escolha os insumos para ver quantas sacas serão necessárias.',
          ),
        if (query.isEmpty) const SizedBox(height: 8),
        if (grains.isEmpty) _emptySearchHint() else ...grains.map((g) => _GrainChoiceTile(
              product: g,
              selected: _paymentGrainId == g.id,
              sacksNeeded: _sacksFor(g),
              enabled: hasInputs,
              onSelect: () => _selectGrain(g.id),
            )),
      ],
    );
  }

  Widget _emptySearchHint() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('Nenhum item encontrado para "$_searchQuery"',
              style: TextStyle(fontSize: 13, color: AppColors.textLight)),
        ),
      );

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
              Text('Sua carteira de produtores está vazia',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
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

  Widget _buildFooter() {
    final grain = _paymentGrain;
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
            if (_unmetCategories.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 14, color: AppColors.pending),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Mínimo não atingido: ${_unmetCategories.map((c) => c.name).join(', ')}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.pending),
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
                Text(
                  grain != null
                      ? 'Entregar: ${formatSacks(sacks)} ${grain.name.toLowerCase()} • $inputCount insumo(s)'
                      : 'Escolha insumos e grão para continuar',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _canSubmit ? _onSubmitPressed : null,
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: Text('Enviar ${brand.copy.barterTitle}'),
              ),
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
            child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _DialogLine extends StatelessWidget {
  final String label, value;
  final bool bold;
  const _DialogLine(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                  fontSize: 12,
                  color: bold ? AppColors.primary : AppColors.textMedium,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                )),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                fontSize: bold ? 15 : 12,
                color: bold ? AppColors.primary : AppColors.textDark,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              )),
        ],
      ),
    );
  }
}

/// Barra de progresso de uma regra de categoria, para o consultor. Mostra o
/// quanto falta para liberar o envio SEM expor valores em R\$ — só proporção.
class _CategoryRuleTile extends StatelessWidget {
  final String name;
  final String detail;
  final double progress;
  final bool met;

  const _CategoryRuleTile({
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
                child: Text(name,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              ),
              Text('${(progress * 100).round()}%',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
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
          Text(met ? 'Exigência atingida • $detail' : 'Exigência: $detail',
              style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
        ],
      ),
    );
  }
}

/// Linha de um insumo nas etapas de montagem. Quando [minQty] > 0, o insumo é
/// obrigatório para a área do produtor: vem pré-preenchido e não pode descer
/// abaixo do mínimo.
class _InputTile extends StatefulWidget {
  final ProductModel product;
  final double qty;
  final double minQty;
  final ValueChanged<double> onChanged;

  const _InputTile({
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
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: AppColors.inputBg, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.science_outlined, color: AppColors.input, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(product.name,
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                          ),
                          if (_required) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.input.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('mín. ${formatQty(minQty)} ${product.unit}',
                                  style: TextStyle(
                                      fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.input)),
                            ),
                          ],
                        ],
                      ),
                      Text(_required ? 'Obrigatório • medido em ${product.unit}' : 'Medido em ${product.unit}',
                          style: TextStyle(fontSize: 12, color: AppColors.textLight)),
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
                  onTap: qty > minQty ? () => onChanged((qty - 1).clamp(minQty, double.infinity)) : null,
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
                _StepBtn(
                  icon: Icons.add,
                  color: AppColors.input,
                  onTap: () => onChanged(qty + 1),
                ),
                const Spacer(),
                if (qty > 0)
                  Text(
                    '${formatQty(qty)} ${product.unit}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.input),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Card de escolha do grão de pagamento (seleção única). Mostra quantas sacas
/// daquele grão cobririam o custo atual dos insumos.
class _GrainChoiceTile extends StatelessWidget {
  final ProductModel product;
  final bool selected;
  final double sacksNeeded;
  final bool enabled;
  final VoidCallback onSelect;

  const _GrainChoiceTile({
    required this.product,
    required this.selected,
    required this.sacksNeeded,
    required this.enabled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? AppColors.grain : Colors.transparent,
            width: 2,
          ),
        ),
        child: InkWell(
          onTap: enabled ? onSelect : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: AppColors.grainBg, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.grass, color: AppColors.grain, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.name,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                      Text('Pago em ${product.unit}',
                          style: TextStyle(fontSize: 12, color: AppColors.textLight)),
                      if (enabled) ...[
                        const SizedBox(height: 2),
                        Text('≈ ${formatSacks(sacksNeeded)} para pagar os insumos',
                            style: TextStyle(fontSize: 11, color: AppColors.grain, fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? AppColors.grain : AppColors.textLight,
                  size: 22,
                ),
              ],
            ),
          ),
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
                child: Text(producer.avatarInitials,
                    style: TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(producer.name,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    const SizedBox(height: 2),
                    Text(producer.location,
                        style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                        overflow: TextOverflow.ellipsis),
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
                          Text('Área: ${producer.areaLabel}',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
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
