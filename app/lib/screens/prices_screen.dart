import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../widgets/common_widgets.dart';
import 'product_report_screen.dart';
import 'edit_forms.dart';

/// Gestão dos valores de referência (R$) usados como taxa de troca da permuta.
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
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Valores de Referência'),
        actions: const [LogoutButton()],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.grass_outlined, size: 18), text: 'Grãos'),
            Tab(icon: Icon(Icons.science_outlined, size: 18), text: 'Insumos'),
            Tab(icon: Icon(Icons.folder_outlined, size: 18), text: 'Categorias'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: SearchField(
              controller: _searchCtrl,
              hint: _tabController.index == 2
                  ? 'Buscar categoria...'
                  : 'Buscar grão ou insumo...',
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
                _ProductPriceList(
                  products: AppData.grains,
                  type: ProductType.grain,
                  query: q,
                  onUpdate: () => setState(() {}),
                ),
                _ProductPriceList(
                  products: AppData.inputs,
                  type: ProductType.input,
                  query: q,
                  onUpdate: () => setState(() {}),
                ),
                _CategoryList(query: q, onUpdate: () => setState(() {})),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductPriceList extends StatelessWidget {
  final List<ProductModel> products;
  final ProductType type;
  final String query;
  final VoidCallback onUpdate;

  const _ProductPriceList({
    required this.products,
    required this.type,
    required this.query,
    required this.onUpdate,
  });

  bool get _isGrain => type == ProductType.grain;

  Future<void> _create(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NewProductScreen(type: type)),
    );
    onUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = query.isEmpty
        ? products
        : products.where((p) => p.name.toLowerCase().contains(query)).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _create(context),
            icon: Icon(_isGrain ? Icons.grass : Icons.science_outlined, size: 18),
            label: Text(_isGrain ? 'Novo grão' : 'Novo insumo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _isGrain ? AppColors.grain : AppColors.input,
              side: BorderSide(color: _isGrain ? AppColors.grain : AppColors.input),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off, size: 48, color: AppColors.textLight),
                  SizedBox(height: 8),
                  Text('Nenhum item encontrado', style: TextStyle(color: AppColors.textLight)),
                ],
              ),
            ),
          )
        else
          ...filtered.map((p) => _PriceCard(product: p, onUpdate: onUpdate)),
      ],
    );
  }
}

class _PriceCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onUpdate;
  const _PriceCard({required this.product, required this.onUpdate});

  Color get _accent => product.type == ProductType.grain ? AppColors.grain : AppColors.input;

  /// Em quantas permutas este produto já apareceu. Serve para avisar o admin
  /// do tamanho do histórico antes de tirar o item do catálogo — o histórico
  /// não se perde (cada item guarda seu próprio snapshot), mas ele merece
  /// saber que não está mexendo num cadastro sem uso.
  int _barterCount() => AppData.barters
      .where((b) => [...b.grains, ...b.inputs].any((i) => i.productId == product.id))
      .length;

  void _delete(BuildContext context) {
    confirmDeleteRegistration(
      context,
      title: product.type == ProductType.grain ? 'Excluir grão' : 'Excluir insumo',
      name: product.name,
      barterCount: _barterCount(),
      onConfirm: () async {
        await AppData.deleteProduct(product);
        onUpdate();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${product.name} saiu do catálogo.'),
          backgroundColor: AppColors.approved,
        ));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Todo produto nasce com um ponto no histórico, mas a tela não pode
    // depender disso: um catálogo importado por fora chegaria sem nenhum.
    final first = product.priceHistory.isEmpty
        ? product.currentPrice
        : product.priceHistory.first.price;
    final deltaPct = first == 0 ? 0.0 : (product.currentPrice - first) / first * 100;
    final up = product.currentPrice >= first;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TypeBadge(type: product.type),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.name,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                        Text(product.unit, style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatCurrency(product.currentPrice),
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.primary)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(up ? Icons.trending_up : Icons.trending_down,
                              size: 13, color: up ? AppColors.denied : AppColors.approved),
                          const SizedBox(width: 2),
                          Text('${up ? '+' : ''}${deltaPct.toStringAsFixed(1).replaceAll('.', ',')}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: up ? AppColors.denied : AppColors.approved,
                              )),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => _delete(context),
                    icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.denied),
                    tooltip: 'Excluir do catálogo',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.show_chart, size: 14, color: _accent),
                  const SizedBox(width: 4),
                  Text('Ver relatório completo',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _accent)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => showUpdateValueDialog(context, product, onUpdate),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('Atualizar', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18, color: AppColors.textLight),
                ],
              ),
              if (product.type == ProductType.input) ...[
                const Divider(height: 18),
                Row(
                  children: [
                    Icon(Icons.folder_outlined, size: 14, color: AppColors.input),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Categoria: ${AppData.categoryById(product.categoryId)?.name ?? 'sem categoria'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: product.categoryId != null ? AppColors.input : AppColors.textLight,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => showCategoryAssignDialog(context, product, onUpdate),
                      icon: const Icon(Icons.folder_open, size: 15),
                      label: const Text('Alterar', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.input,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 18),
                Row(
                  children: [
                    Icon(Icons.straighten, size: 14, color: AppColors.input),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        product.requiredPerHa > 0
                            ? 'Exigência: ${formatQty(product.requiredPerHa)} ${product.unit}/ha'
                            : 'Sem exigência por área',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: product.requiredPerHa > 0 ? AppColors.input : AppColors.textLight,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => showRequiredPerHaDialog(context, product, onUpdate),
                      icon: const Icon(Icons.tune, size: 15),
                      label: const Text('Definir', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.input,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Lista de "pastas" (categorias) de insumos com sua regra de mínimo. Permite
/// criar, editar e excluir. A regra é o gatilho que trava o envio da permuta.
class _CategoryList extends StatelessWidget {
  final String query;
  final VoidCallback onUpdate;
  const _CategoryList({required this.query, required this.onUpdate});

  Future<void> _openEditor(BuildContext context, {InputCategoryModel? category}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditCategoryScreen(category: category)),
    );
    onUpdate();
  }

  /// Quantos insumos estão classificados nesta pasta.
  int _inputCount(String categoryId) =>
      AppData.inputs.where((i) => i.categoryId == categoryId).length;

  void _delete(BuildContext context, InputCategoryModel category) {
    final count = _inputCount(category.id);
    confirmDeleteRegistration(
      context,
      title: 'Excluir categoria',
      name: category.name,
      barterCount: 0,
      onConfirm: () async {
        // O servidor desvincula os insumos da pasta antes de removê-la.
        await AppData.deleteCategory(category.id);
        onUpdate();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(count > 0
              ? 'Categoria excluída. $count insumo(s) ficaram sem categoria.'
              : 'Categoria excluída.'),
          backgroundColor: AppColors.approved,
        ));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = query.isEmpty
        ? AppData.categories
        : AppData.categories.where((c) => c.name.toLowerCase().contains(query)).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _openEditor(context),
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('Nova categoria'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.input,
              side: const BorderSide(color: AppColors.input),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text('Nenhuma categoria encontrada', style: TextStyle(color: AppColors.textLight)),
            ),
          )
        else
          ...filtered.map((c) => _CategoryCard(
                category: c,
                inputCount: _inputCount(c.id),
                onEdit: () => _openEditor(context, category: c),
                onDelete: () => _delete(context, c),
              )),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final InputCategoryModel category;
  final int inputCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _CategoryCard({
    required this.category,
    required this.inputCount,
    required this.onEdit,
    required this.onDelete,
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
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: AppColors.inputBg, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.folder, color: AppColors.input, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category.name,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                        Text('$inputCount insumo(s)',
                            style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.denied),
                    tooltip: 'Excluir',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: (category.hasRule ? AppColors.pending : AppColors.textLight).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(category.hasRule ? Icons.rule : Icons.remove_circle_outline,
                        size: 14, color: category.hasRule ? AppColors.pending : AppColors.textLight),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(category.ruleLabelAdmin,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: category.hasRule ? AppColors.textDark : AppColors.textLight,
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
