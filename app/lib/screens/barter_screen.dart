import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/api/api_client.dart';
import '../services/barter_math.dart';
import '../services/barter_pdf.dart';
import '../widgets/class_avatar.dart';
import '../widgets/filter_bar.dart';
import '../widgets/common_widgets.dart';

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
  const NewBarterScreen({super.key, required this.consultant});
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
  ProducerModel? get _producer =>
      _producerId == null ? null : AppData.producerById(_producerId!);

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
  List<ProductClassModel> get _ruledClasses =>
      AppData.classes.where((c) => c.hasRule).toList();

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

  /// Todas as exigências de classe foram cumpridas?
  bool get _classesOk => _ruledClasses.every(_classMet);

  /// Classes ainda abaixo do mínimo (para avisar o consultor).
  List<ProductClassModel> get _unmetClasses =>
      _ruledClasses.where((c) => !_classMet(c)).toList();

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
    // Só aceita produtores da carteira do consultor logado.
    if (p == null || p.consultantId != widget.consultant.id) return;
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

  bool _submitting = false;

  bool get _canSubmit =>
      !_submitting &&
      (_version?.isOpen ?? false) &&
      _producerId != null &&
      _unitId != null &&
      _inputCost > 0 &&
      _classesOk;

  /// Produtor e unidade já foram escolhidos; aqui só revisamos e enviamos.
  Future<void> _onSubmitPressed() async {
    if (_producerId == null || _unitId == null) return;
    final confirmed = await _showSummaryDialog();
    if (confirmed == true) await _submit();
  }

  /// Resumo completo da permuta antes de enviar: os insumos retirados e o total
  /// de sacas a entregar — para o consultor revisar antes de finalizar.
  Future<bool?> _showSummaryDialog() {
    final version = _version;
    final producer = _producer;
    final unit = _unit;
    final sacks = _sacksNeeded;
    final inputs = _inputQty.entries.where((e) => e.value > 0).map((e) {
      final p = _productById(e.key)!;
      return BarterItem(
        productId: p.id,
        productName: p.name,
        unit: p.unit,
        quantity: e.value,
        unitValue: AppData.priceOf(p.id),
      );
    }).toList();

    if (version == null || producer == null || unit == null || inputs.isEmpty) {
      return Future.value(false);
    }

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
                _DialogLine('Retirada em', unit.name),
                _DialogLine('Barter', version.code),
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
                    '${formatSacks(sacks)} ${version.grainName.toLowerCase()}',
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
    final producer = _producer;
    final unit = _unit;
    final chosen = Map<String, double>.from(_inputQty)
      ..removeWhere((_, qty) => qty <= 0);

    if (producer == null) {
      _toast('Selecione o produtor desta permuta.');
      return;
    }
    if (unit == null) {
      _toast('Selecione a unidade de retirada desta permuta.');
      return;
    }
    if (chosen.isEmpty) {
      _toast('Selecione ao menos um insumo para retirar.');
      return;
    }
    final unmet = _unmetClasses;
    if (unmet.isNotEmpty) {
      _toast('Mínimo não atingido: ${unmet.map((c) => c.name).join(', ')}.');
      return;
    }

    setState(() => _submitting = true);
    final BarterModel barter;
    try {
      barter = await AppData.createBarter(
        producerId: producer.id,
        unitId: unit.id,
        inputQuantities: chosen,
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        _toast(e.message);
        // O Barter pode ter sido encerrado enquanto a permuta era montada:
        // recarrega a vigência para a tela contar a verdade na hora.
        _refreshVersion();
      }
      return;
    }
    if (!mounted) return;

    final sacks = barter.sacksToDeliver;

    setState(() {
      _submitting = false;
      _inputQty.clear();
      _producerId = null;
      _unitId = null;
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
            // O próximo passo agora tem NOME. Dizer "enviada para revisão do
            // administrador" seria falso: ela está na mesa do gerente do
            // consultor, e é dele que ele espera a resposta.
            Text(
              'Ela foi enviada a ${barter.managerLabel}, que dará o parecer técnico '
              'antes de a permuta seguir para revisão.',
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
                  _DialogLine('Retirada em', barter.unitLabel),
                  if (barter.versionCode.isNotEmpty) _DialogLine('Barter', barter.versionCode),
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

  /// Recarrega o Barter vigente (e o catálogo, que depende da tabela dela).
  Future<void> _refreshVersion() async {
    try {
      await AppData.refreshBarterVersion();
    } on ApiException {
      // Sem rede a tela continua com o que tinha; o envio é que decide.
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
        title: Text('Nova ${brand.copy.barterTitle}'),
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
  Widget _buildClosedBarter() {
    return RefreshIndicator(
      onRefresh: _refreshVersion,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 60),
          Icon(Icons.event_busy_outlined, size: 64, color: AppColors.textLight),
          const SizedBox(height: 16),
          Text(
            '${brand.copy.programTitle} fechado no momento',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark),
          ),
          const SizedBox(height: 8),
          Text(
            'Não há lançamento aberto para registrar permutas. Assim que o '
            'administrador publicar a próxima versão, ela aparece aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMedium),
          ),
          const SizedBox(height: 20),
          Center(
            child: TextButton.icon(
              onPressed: _refreshVersion,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Verificar novamente'),
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
            .where((p) =>
                p.name.toLowerCase().contains(query) ||
                p.city.toLowerCase().contains(query) ||
                p.farmName.toLowerCase().contains(query))
            .toList();

    return Column(
      children: [
        _BarterBanner(version: version),
        if (wallet.isEmpty)
          Expanded(child: _emptyWalletHint())
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: _hint(
              icon: Icons.person_pin_circle_outlined,
              color: AppColors.primary,
              text: 'Etapa 1: escolha um produtor da sua carteira. A área da propriedade '
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
            .where((u) =>
                u.name.toLowerCase().contains(query) || u.city.toLowerCase().contains(query))
            .toList();

    return Column(
      children: [
        _BarterBanner(version: version),
        _buildProducerHeader(producer),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: _hint(
            icon: Icons.store_outlined,
            color: AppColors.primary,
            text: 'Etapa 2: onde ${producer.name.split(' ').first} vai retirar os insumos. '
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
                    itemBuilder: (_, i) => _UnitChoiceTile(
                      unit: units[i],
                      onSelect: () => _selectUnit(units[i].id),
                    ),
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
        _buildFooter(version),
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
              style:
                  TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDark),
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
          child: Text('${inputs.length} de ${_catalog.length} insumo(s)',
              style: TextStyle(fontSize: 11, color: AppColors.textLight)),
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
        ..._ruledClasses.map((c) => _ClassRuleTile(
              name: c.name,
              detail: c.ruleType == ClassRuleType.percentOfTotal
                  ? 'mín. ${_fmtPct(c.ruleValue)} do total da permuta'
                  : 'mínimo por área da propriedade',
              progress: _classProgress(c),
              met: _classMetOnScreen(c),
            )),
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

  Widget _buildFooter(BarterVersionModel version) {
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
                        fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textDark),
                    overflow: TextOverflow.ellipsis,
                  ),
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
                Text('${brand.copy.programTitle} ${version.code}',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textDark)),
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

/// Barra de progresso da regra de uma classe, para o consultor. Mostra o
/// quanto falta para liberar o envio SEM expor valores em R\$ — só proporção.
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
                    Text(unit.name,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark)),
                    const SizedBox(height: 2),
                    Text(unit.city,
                        style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                        overflow: TextOverflow.ellipsis),
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
