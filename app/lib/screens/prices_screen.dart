import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../widgets/class_avatar.dart';
import '../widgets/filter_bar.dart';
import '../widgets/common_widgets.dart';
import 'barter_program_screen.dart';
import 'product_report_screen.dart';
import 'edit_forms.dart';

/// A tela do BARTER, do lado do admin. Quatro abas, na ordem em que a operação
/// acontece:
///
/// 1. **Barter** — a safra, a versão vigente e as metas; é onde se publica a
///    próxima versão a partir da planilha.
/// 2. **Valores** — a tabela da versão vigente (preço e custo de cada insumo,
///    mais o valor da saca), com correção pontual.
/// 3. **Histórico** — como o valor de cada item andou ao longo das versões.
///    Leitura: o cadastro do produto (pasta, exigência, exclusão) mora na tela
///    do próprio item, e o valor de hoje se corrige na aba Valores.
/// 4. **Classes** — a taxonomia que vem da lista de preços, e a regra de
///    mínimo de cada uma.
///
/// Busca e filtros ficam no topo: a busca é do texto, os chips recortam o
/// conjunto e o menu de ordenação responde "em que ordem". Os três se somam.
class PricesScreen extends StatefulWidget {
  const PricesScreen({super.key});
  @override
  State<PricesScreen> createState() => _PricesScreenState();
}

class _PricesScreenState extends State<PricesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// A busca não faz sentido na aba do lançamento (é um cartão só).
  bool get _showsSearch => _tabController.index > 0;

  String get _searchHint {
    switch (_tabController.index) {
      case 1:
        return 'Buscar na tabela de valores...';
      case 3:
        return 'Buscar classe...';
      default:
        return 'Buscar grão ou insumo...';
    }
  }

  /// Cadastrar produto à mão continua existindo — a planilha cria os insumos,
  /// mas o GRÃO precisa existir antes para a safra ser aberta. Fica no cabeçalho
  /// da aba de histórico, e não como botão no meio da lista: é um ato raro.
  Future<void> _createProduct(ProductType type) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NewProductScreen(type: type)),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(
        title: Text(brand.copy.programTitle),
        actions: [
          if (_tabController.index == 2)
            PopupMenuButton<ProductType>(
              tooltip: 'Cadastrar item',
              icon: const Icon(Icons.add),
              onSelected: _createProduct,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: ProductType.grain,
                  child: Text('Novo ${brand.copy.grain}'),
                ),
                PopupMenuItem(
                  value: ProductType.input,
                  child: Text('Novo ${brand.copy.input}'),
                ),
              ],
            ),
          const LogoutButton(),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.rocket_launch_outlined, size: 18), text: 'Lançamento'),
            Tab(icon: Icon(Icons.price_change_outlined, size: 18), text: 'Valores'),
            Tab(icon: Icon(Icons.history, size: 18), text: 'Histórico'),
            Tab(icon: Icon(Icons.category_outlined, size: 18), text: 'Classes'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_showsSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: SearchField(
                controller: _searchCtrl,
                hint: _searchHint,
                onChanged: (v) => setState(() => _search = v),
                onClear: () => setState(() {
                  _search = '';
                  _searchCtrl.clear();
                }),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                BarterProgramTab(onChanged: () => setState(() {})),
                _VersionPriceTable(query: q, onUpdate: () => setState(() {})),
                _HistoryList(query: q, onUpdate: () => setState(() {})),
                _ClassList(query: q, onUpdate: () => setState(() {})),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A tabela de valores da versão VIGENTE: a saca do grão no topo e um cartão
/// por insumo, com preço, custo e margem. É a foto do que está valendo agora —
/// e o único lugar do app onde um valor pode ser corrigido.
class _VersionPriceTable extends StatefulWidget {
  final String query;
  final VoidCallback onUpdate;
  const _VersionPriceTable({required this.query, required this.onUpdate});

  @override
  State<_VersionPriceTable> createState() => _VersionPriceTableState();
}

/// Como ordenar a tabela de valores. "Menor margem" existe porque é a pergunta
/// que o admin faz de verdade ao revisar um lançamento: onde a margem está
/// apertada demais.
enum _ValueSort { name, priceDesc, priceAsc }

class _VersionPriceTableState extends State<_VersionPriceTable> {
  /// Quantos itens da lista são cabeçalho (cotação da saca e título).
  static const int _headerCount = 2;

  /// Classe escolhida (null = todas). A tabela da versão não carrega a classe:
  /// ela é atributo do CADASTRO, então vem do catálogo pelo productId.
  String? _classId;
  _ValueSort _sort = _ValueSort.name;

  /// A linha da versão guarda nome e unidade, não o código — ele vem do
  /// cadastro, pelo productId, do mesmo jeito que a classe.
  bool _matches(VersionPriceModel row, String query) {
    if (row.productName.toLowerCase().contains(query)) return true;
    final code = _productOf(row.productId)?.sku ?? '';
    return code.toLowerCase().contains(query);
  }

  ProductModel? _productOf(String productId) {
    for (final input in AppData.inputs) {
      if (input.id == productId) return input;
    }
    return null;
  }

  String? _classOf(String productId) {
    for (final input in AppData.inputs) {
      if (input.id == productId) return input.classId;
    }
    return null;
  }

  List<VersionPriceModel> _apply(List<VersionPriceModel> rows) {
    final query = widget.query;
    final filtered = rows.where((row) {
      if (query.isNotEmpty && !_matches(row, query)) return false;
      if (_classId != null && _classOf(row.productId) != _classId) return false;
      return true;
    }).toList();

    switch (_sort) {
      case _ValueSort.name:
        filtered.sort((a, b) => a.productName.compareTo(b.productName));
        break;
      case _ValueSort.priceDesc:
        filtered.sort((a, b) => b.price.compareTo(a.price));
        break;
      case _ValueSort.priceAsc:
        filtered.sort((a, b) => a.price.compareTo(b.price));
        break;
    }
    return filtered;
  }

  /// Só as classes que têm insumo NESTA versão viram filtro — oferecer uma
  /// classe que devolveria lista vazia é um filtro que mente.
  List<ProductClassModel> _classesInVersion(BarterVersionModel version) {
    final ids = version.prices.map((row) => _classOf(row.productId)).whereType<String>().toSet();
    return AppData.classes.where((category) => ids.contains(category.id)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final version = AppData.currentVersion;
    if (version == null) {
      return const _EmptyState(
        icon: Icons.price_change_outlined,
        title: 'Nenhum Barter lançado',
        text: 'Publique uma versão na aba Lançamento para definir os valores da safra.',
      );
    }

    final rows = _apply(version.prices);
    final classes = _classesInVersion(version);

    return Column(
      children: [
        FilterBar(
          chips: [
            FilterChipData(label: 'Todas', selected: _classId == null, onTap: () {
              setState(() => _classId = null);
            }),
            for (final productClass in classes)
              FilterChipData(
                label: productClass.name,
                selected: _classId == productClass.id,
                onTap: () => setState(() => _classId = productClass.id),
              ),
          ],
          sortLabel: _sortLabel,
          onSort: (value) => setState(() => _sort = value),
          sortOptions: const {
            _ValueSort.name: 'Nome (A–Z)',
            _ValueSort.priceDesc: 'Maior preço',
            _ValueSort.priceAsc: 'Menor preço',
          },
          current: _sort,
        ),
        // `ListView.builder`, e não `ListView(children:)`: a tabela real tem 656
        // linhas, e a forma com `children` constrói TODAS de uma vez, na
        // primeira montagem — inclusive as que ninguém vai rolar até ver. Com o
        // catálogo de demonstração (cinco itens) dava no mesmo; com a lista do
        // fornecedor, é o custo de abrir a aba.
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            // Cabeçalho (cotação da saca + título) + as linhas, ou a mensagem
            // de lista vazia no lugar delas.
            itemCount: _headerCount + (rows.isEmpty ? 1 : rows.length),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  children: [
                    _GrainPriceCard(version: version, onUpdate: widget.onUpdate),
                    const SizedBox(height: 12),
                  ],
                );
              }
              if (index == 1) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Text('Insumos da versão ${version.code}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark)),
                      const Spacer(),
                      Text(
                        rows.length == version.prices.length
                            ? '${version.prices.length} item(ns)'
                            : '${rows.length} de ${version.prices.length}',
                        style: TextStyle(fontSize: 11, color: AppColors.textLight),
                      ),
                    ],
                  ),
                );
              }
              if (rows.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('Nenhum item com esse filtro',
                        style: TextStyle(fontSize: 13, color: AppColors.textLight)),
                  ),
                );
              }
              final row = rows[index - _headerCount];
              return _VersionPriceCard(
                row: row,
                code: _productOf(row.productId)?.sku,
                productClass: AppData.classById(_classOf(row.productId)),
                editable: version.isOpen,
                onUpdate: widget.onUpdate,
              );
            },
          ),
        ),
      ],
    );
  }

  String get _sortLabel {
    switch (_sort) {
      case _ValueSort.name:
        return 'Nome';
      case _ValueSort.priceDesc:
        return 'Maior preço';
      case _ValueSort.priceAsc:
        return 'Menor preço';
    }
  }
}

/// O valor da saca — a cotação que converte custo de insumo em grão.
class _GrainPriceCard extends StatelessWidget {
  final BarterVersionModel version;
  final VoidCallback onUpdate;
  const _GrainPriceCard({required this.version, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.grainBg,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.grain.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.grass, color: AppColors.grain, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Saca de ${version.grainName.toLowerCase()}',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  Text('Cotação do Barter ${version.code}',
                      style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
                ],
              ),
            ),
            Text(formatCurrency(version.grainPrice),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.grain)),
            if (version.isOpen && version.grainId.isNotEmpty)
              IconButton(
                tooltip: 'Corrigir',
                onPressed: () => showVersionPriceDialog(
                  context,
                  productId: version.grainId,
                  productName: 'Saca de ${version.grainName.toLowerCase()}',
                  price: version.grainPrice,
                  onUpdated: onUpdate,
                ),
                icon: Icon(Icons.edit_outlined, size: 18, color: AppColors.grain),
              ),
          ],
        ),
      ),
    );
  }
}

/// Uma linha da tabela: preço, custo e a margem que alimenta a meta de lucro.
class _VersionPriceCard extends StatelessWidget {
  final VersionPriceModel row;

  /// Código do item no cadastro — a linha da versão não o guarda.
  final String? code;

  /// A classe do item, para a figura. Também vem do cadastro.
  final ProductClassModel? productClass;
  final bool editable;
  final VoidCallback onUpdate;
  const _VersionPriceCard({
    required this.row,
    required this.code,
    required this.productClass,
    required this.editable,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClassAvatar(productClass: productClass, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.productName,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  Row(
                    children: [
                      if (code != null) ...[
                        _CodeChip(code: code!),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(row.unit,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: AppColors.textLight)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatCurrency(row.price),
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
                if (editable)
                  TextButton(
                    onPressed: () => showVersionPriceDialog(
                      context,
                      productId: row.productId,
                      productName: row.productName,
                      price: row.price,
                      onUpdated: onUpdate,
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Corrigir', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// O HISTÓRICO de valores por produto: cada item com o último valor publicado e
/// a variação desde o primeiro. Tocar abre a linha do tempo completa (gráfico,
/// pontos e o cadastro do item).
///
/// É leitura. O valor de hoje se corrige na aba Valores, dentro da versão; o
/// cadastro (pasta, exigência, exclusão) mora na tela do produto — aqui só se
/// enxerga como o preço andou.
class _HistoryList extends StatefulWidget {
  final String query;
  final VoidCallback onUpdate;
  const _HistoryList({required this.query, required this.onUpdate});

  @override
  State<_HistoryList> createState() => _HistoryListState();
}

enum _HistorySort { name, price, up, down }

class _HistoryListState extends State<_HistoryList> {
  /// null = todos; senão, só grãos ou só insumos.
  ProductType? _type;

  /// Só os itens com unidade a revisar — o filtro que resolve a lista de uma
  /// vez depois de uma carga.
  bool _onlyPending = false;
  _HistorySort _sort = _HistorySort.name;

  /// Variação (%) do último valor publicado contra o primeiro ponto da linha
  /// do tempo. Zero quando não há histórico com que comparar.
  ///
  /// A conta mora no modelo porque a listagem do catálogo não carrega a série
  /// — ela vem com o primeiro valor já resolvido (ver [ProductModel.deltaPct]).
  static double deltaPctOf(ProductModel product) => product.deltaPct;

  List<ProductModel> _apply() {
    final query = widget.query;
    final all = [...AppData.grains, ...AppData.inputs];
    final filtered = all.where((product) {
      if (!product.matches(query)) return false;
      if (_type != null && product.type != _type) return false;
      return true;
    }).toList();

    switch (_sort) {
      case _HistorySort.name:
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
      case _HistorySort.price:
        filtered.sort((a, b) => b.currentPrice.compareTo(a.currentPrice));
        break;
      case _HistorySort.up:
        filtered.sort((a, b) => deltaPctOf(b).compareTo(deltaPctOf(a)));
        break;
      case _HistorySort.down:
        filtered.sort((a, b) => deltaPctOf(a).compareTo(deltaPctOf(b)));
        break;
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final products = _apply();
    final total = AppData.grains.length + AppData.inputs.length;
    final pendentes = [...AppData.grains, ...AppData.inputs]
        .where((p) => p.unitPending)
        .length;

    return Column(
      children: [
        FilterBar(
          chips: [
            FilterChipData(
              label: 'Todos',
              selected: _type == null,
              onTap: () => setState(() => _type = null),
            ),
            FilterChipData(
              label: brand.copy.grainPluralTitle,
              selected: _type == ProductType.grain,
              onTap: () => setState(() => _type = ProductType.grain),
            ),
            FilterChipData(
              label: brand.copy.inputPluralTitle,
              selected: _type == ProductType.input,
              onTap: () => setState(() => _type = ProductType.input),
            ),
            // Só aparece quando há o que revisar: filtro que devolveria lista
            // vazia é ruído na barra.
            if (pendentes > 0)
              FilterChipData(
                label: 'Sem unidade ($pendentes)',
                selected: _onlyPending,
                onTap: () => setState(() => _onlyPending = !_onlyPending),
              ),
          ],
          sortLabel: _sortLabel,
          onSort: (value) => setState(() => _sort = value),
          sortOptions: const {
            _HistorySort.name: 'Nome (A–Z)',
            _HistorySort.price: 'Maior valor',
            _HistorySort.up: 'Maior alta',
            _HistorySort.down: 'Maior queda',
          },
          current: _sort,
        ),
        Expanded(
          child: products.isEmpty
              ? const _EmptyState(
                  icon: Icons.search_off,
                  title: 'Nenhum item encontrado',
                  text: 'Ajuste a busca ou o filtro para ver o histórico de outros itens.',
                )
              // Builder pelo mesmo motivo da tabela de valores: com o catálogo
              // real são 661 cartões, e `children:` os construiria todos na
              // abertura da aba.
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: products.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Text('Linha do tempo de valores',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textDark)),
                            const Spacer(),
                            Text(
                              products.length == total
                                  ? '$total item(ns)'
                                  : '${products.length} de $total',
                              style: TextStyle(fontSize: 11, color: AppColors.textLight),
                            ),
                          ],
                        ),
                      );
                    }
                    final product = products[index - 1];
                    return _HistoryCard(
                      product: product,
                      deltaPct: deltaPctOf(product),
                      onUpdate: widget.onUpdate,
                    );
                  },
                ),
        ),
      ],
    );
  }

  String get _sortLabel {
    switch (_sort) {
      case _HistorySort.name:
        return 'Nome';
      case _HistorySort.price:
        return 'Maior valor';
      case _HistorySort.up:
        return 'Maior alta';
      case _HistorySort.down:
        return 'Maior queda';
    }
  }
}

/// Linha do histórico de um produto. Só leitura: último valor publicado, a
/// variação desde o começo e a porta para a linha do tempo completa.
class _HistoryCard extends StatelessWidget {
  final ProductModel product;
  final double deltaPct;
  final VoidCallback onUpdate;
  const _HistoryCard({required this.product, required this.deltaPct, required this.onUpdate});

  Color get _accent => product.type == ProductType.grain ? AppColors.grain : AppColors.input;

  /// Preço subindo é notícia RUIM para quem compra insumo — daí a cor de alerta
  /// na alta e a de aprovação na queda. É a leitura do lado da cooperativa.
  Color get _trendColor => deltaPct >= 0 ? AppColors.denied : AppColors.approved;

  /// O produto está na tabela do Barter vigente? Fora dela ele existe no
  /// cadastro mas não é permutável — e isso precisa aparecer aqui, senão o
  /// admin só descobre quando o consultor reclama.
  bool get _inCurrentVersion {
    final version = AppData.currentVersion;
    if (version == null) return false;
    return version.grainId == product.id || version.priceOf(product.id) != null;
  }

  @override
  Widget build(BuildContext context) {
    // A contagem vem do resumo: a listagem não traz a série (ver
    // CatalogRepository.listProducts).
    final points = product.priceHistoryCount;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProductReportScreen(productId: product.id, type: product.type),
            ),
          );
          onUpdate();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              TypeBadge(type: product.type),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    Row(
                      children: [
                        _CodeChip(code: product.codeLabel),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(product.unit,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: AppColors.textLight)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.show_chart, size: 12, color: _accent),
                        const SizedBox(width: 4),
                        Text('$points ponto(s)',
                            style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
                        if (!_inCurrentVersion) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.textLight.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('fora do Barter',
                                style: TextStyle(fontSize: 10, color: AppColors.textMedium)),
                          ),
                        ],
                        // A unidade entrou como palpite: o aviso fica no item,
                        // e não só num relatório, porque é aqui que se resolve.
                        if (product.unitPending) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.pending.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('sem unidade',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.pending)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatCurrency(product.currentPrice),
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(deltaPct >= 0 ? Icons.trending_up : Icons.trending_down,
                          size: 13, color: _trendColor),
                      const SizedBox(width: 2),
                      Text('${deltaPct >= 0 ? '+' : ''}${deltaPct.toStringAsFixed(1).replaceAll('.', ',')}%',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600, color: _trendColor)),
                    ],
                  ),
                ],
              ),
              Icon(Icons.chevron_right, size: 18, color: AppColors.textLight),
            ],
          ),
        ),
      ),
    );
  }
}

/* ── Peças compartilhadas pelas duas listas ───────────────────────────── */

/// O CÓDIGO do item, em selo de monoespaçado. É o que se digita na busca —
/// por isso ele aparece antes da unidade, e não escondido no detalhe.
class _CodeChip extends StatelessWidget {
  final String code;
  const _CodeChip({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.textLight.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontSize: 10,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          color: AppColors.textMedium,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _EmptyState({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: AppColors.textLight),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 6),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textMedium)),
          ],
        ),
      ),
    );
  }
}

/// As CLASSES de produto — a taxonomia do negócio (fungicidas, herbicidas,
/// sementes, seguro agrícola…).
///
/// A lista é FIXA: não há criar, renomear nem excluir. O que se ajusta aqui é a
/// REGRA de mínimo de cada uma — o gatilho que trava o envio da permuta
/// enquanto a classe não representar o quanto foi combinado.
class _ClassList extends StatelessWidget {
  final String query;
  final VoidCallback onUpdate;
  const _ClassList({required this.query, required this.onUpdate});

  Future<void> _editRule(BuildContext context, ProductClassModel productClass) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditClassRuleScreen(productClass: productClass)),
    );
    onUpdate();
  }

  /// Quantos insumos do catálogo estão nesta classe.
  int _inputCount(String classId) =>
      AppData.inputs.where((i) => i.classId == classId).length;

  @override
  Widget build(BuildContext context) {
    final filtered = query.isEmpty
        ? AppData.classes
        : AppData.classes.where((c) => c.name.toLowerCase().contains(query)).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: AppColors.input),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Toque em uma classe para definir o mínimo que ela precisa '
                  'representar na permuta.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text('Nenhuma classe encontrada', style: TextStyle(color: AppColors.textLight)),
            ),
          )
        else
          ...filtered.map((c) => _ClassCard(
                productClass: c,
                inputCount: _inputCount(c.id),
                onEdit: () => _editRule(context, c),
              )),
      ],
    );
  }
}

class _ClassCard extends StatelessWidget {
  final ProductClassModel productClass;
  final int inputCount;
  final VoidCallback onEdit;
  const _ClassCard({
    required this.productClass,
    required this.inputCount,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClassAvatar(productClass: productClass),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(productClass.name,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                        Text('$inputCount insumo(s)',
                            style: TextStyle(fontSize: 12, color: AppColors.textLight)),
                      ],
                    ),
                  ),
                  // Sem excluir: a classe é do negócio, não do cadastro. O que
                  // se abre ao tocar é a regra de mínimo dela.
                  Icon(Icons.chevron_right, size: 20, color: AppColors.textLight),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: (productClass.hasRule ? AppColors.pending : AppColors.textLight).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(productClass.hasRule ? Icons.rule : Icons.remove_circle_outline,
                        size: 14, color: productClass.hasRule ? AppColors.pending : AppColors.textLight),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(productClass.ruleLabelAdmin,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: productClass.hasRule ? AppColors.textDark : AppColors.textLight,
                          )),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
