import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/api/api_client.dart';
import '../widgets/common_widgets.dart';
import '../widgets/price_chart.dart';

const _monthsFull = [
  '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
];

enum _Period { m3, m6, all }

/// Relatório de um produto: gráfico da evolução do valor + estatísticas +
/// linha do tempo dos reajustes.
class ProductReportScreen extends StatefulWidget {
  final String productId;
  final ProductType type;
  const ProductReportScreen({super.key, required this.productId, required this.type});

  @override
  State<ProductReportScreen> createState() => _ProductReportScreenState();
}

class _ProductReportScreenState extends State<ProductReportScreen> {
  _Period _period = _Period.all;

  ProductModel get _product {
    final list = widget.type == ProductType.grain ? AppData.grains : AppData.inputs;
    return list.firstWhere((p) => p.id == widget.productId);
  }

  Color get _accent => widget.type == ProductType.grain ? AppColors.grain : AppColors.input;

  List<PriceHistoryEntry> _visibleHistory(ProductModel p) {
    final all = p.priceHistory;
    if (_period == _Period.all || all.length <= 2) return all;
    final now = DateTime.now();
    final cutoff = _period == _Period.m3
        ? DateTime(now.year, now.month - 3, now.day)
        : DateTime(now.year, now.month - 6, now.day);
    final filtered = all.where((e) => e.changedAt.isAfter(cutoff)).toList();
    return filtered.length >= 2 ? filtered : all;
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    final history = _visibleHistory(product);
    final values = history.map((e) => e.price).toList();
    final first = values.first;
    final last = values.last;
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final avgV = values.reduce((a, b) => a + b) / values.length;
    final deltaPct = first == 0 ? 0.0 : (last - first) / first * 100;
    final up = last >= first;

    return Scaffold(
      appBar: AppBar(title: const Text('Relatório do Item')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header(product, deltaPct, up),
          const SizedBox(height: 16),

          // Chart card
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.show_chart, size: 18, color: _accent),
                        const SizedBox(width: 6),
                        const Text('Evolução do valor',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                        const Spacer(),
                        Text('R\$ / ${product.unit}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 200,
                    child: PriceLineChart(
                      key: ValueKey('${product.id}_${_period}_${product.priceHistory.length}'),
                      history: history,
                      color: _accent,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _periodSelector(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Stats
          Row(
            children: [
              Expanded(child: _StatChip(label: 'Menor', value: formatCurrency(minV), color: AppColors.approved, icon: Icons.south)),
              const SizedBox(width: 10),
              Expanded(child: _StatChip(label: 'Médio', value: formatCurrency(avgV), color: AppColors.primaryMedium, icon: Icons.drag_handle)),
              const SizedBox(width: 10),
              Expanded(child: _StatChip(label: 'Maior', value: formatCurrency(maxV), color: AppColors.denied, icon: Icons.north)),
            ],
          ),
          const SizedBox(height: 20),

          // Timeline
          Row(
            children: [
              Icon(Icons.history, size: 18, color: _accent),
              const SizedBox(width: 6),
              const Text('Linha do Tempo',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              const Spacer(),
              Text('${product.priceHistory.length} registros',
                  style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
            ],
          ),
          const SizedBox(height: 12),
          _timeline(product),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => showUpdateValueDialog(context, product, () => setState(() {})),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Atualizar Valor'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _header(ProductModel product, double deltaPct, bool up) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_accent.withValues(alpha: 0.14), _accent.withValues(alpha: 0.03)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: _accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                child: Icon(widget.type == ProductType.grain ? Icons.grass : Icons.science_outlined,
                    color: _accent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                    Text(product.unit, style: const TextStyle(fontSize: 12, color: AppColors.textMedium)),
                  ],
                ),
              ),
              TypeBadge(type: product.type),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Valor atual', style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
                  Text(formatCurrency(product.currentPrice),
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.primary)),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (up ? AppColors.denied : AppColors.approved).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(up ? Icons.trending_up : Icons.trending_down,
                        size: 16, color: up ? AppColors.denied : AppColors.approved),
                    const SizedBox(width: 4),
                    Text('${up ? '+' : ''}${deltaPct.toStringAsFixed(1).replaceAll('.', ',')}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: up ? AppColors.denied : AppColors.approved,
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Variação no período selecionado',
              style: TextStyle(fontSize: 11, color: AppColors.textLight)),
        ],
      ),
    );
  }

  Widget _periodSelector() {
    Widget chip(_Period p, String label) {
      final selected = _period == p;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _period = p),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected ? _accent : _accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : _accent,
                )),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(_Period.m3, '3 meses'),
        chip(_Period.m6, '6 meses'),
        chip(_Period.all, 'Tudo'),
      ],
    );
  }

  Widget _timeline(ProductModel product) {
    final entries = product.priceHistory.reversed.toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (int i = 0; i < entries.length; i++)
              _TimelineRow(
                entry: entries[i],
                previous: i < entries.length - 1 ? entries[i + 1] : null,
                isFirst: i == 0,
                isLast: i == entries.length - 1,
                accent: _accent,
              ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _StatChip({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textDark)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final PriceHistoryEntry entry;
  final PriceHistoryEntry? previous;
  final bool isFirst;
  final bool isLast;
  final Color accent;
  const _TimelineRow({
    required this.entry,
    required this.previous,
    required this.isFirst,
    required this.isLast,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final delta = previous == null ? 0.0 : entry.price - previous!.price;
    final up = delta > 0;
    final flat = delta.abs() < 0.001;
    final deltaColor = flat ? AppColors.textLight : (up ? AppColors.denied : AppColors.approved);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Trilho com nó
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(width: 2, height: 10, color: isFirst ? Colors.transparent : AppColors.divider.withValues(alpha: 0.5)),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isFirst ? accent : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 2),
                  ),
                ),
                Expanded(child: Container(width: 2, color: isLast ? Colors.transparent : AppColors.divider.withValues(alpha: 0.5))),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(formatCurrency(entry.price),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                        Text('${_monthsFull[entry.changedAt.month]} ${entry.changedAt.year} • ${entry.changedBy}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                      ],
                    ),
                  ),
                  if (previous != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: deltaColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(flat ? Icons.remove : (up ? Icons.arrow_upward : Icons.arrow_downward),
                              size: 12, color: deltaColor),
                          const SizedBox(width: 2),
                          Text('${up ? '+' : ''}${delta.toStringAsFixed(2).replaceAll('.', ',')}',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: deltaColor)),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                      child: Text('inicial',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accent)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Diálogo de atualização de valor, compartilhado entre a lista e o relatório.
Future<void> showUpdateValueDialog(BuildContext context, ProductModel product, VoidCallback onUpdated) {
  final ctrl = TextEditingController(text: product.currentPrice.toStringAsFixed(2));
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Atualizar Valor'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Text('Valor atual: ${formatCurrency(product.currentPrice)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMedium)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Novo Valor (R\$)', prefixIcon: Icon(Icons.attach_money)),
            autofocus: true,
          ),
          const SizedBox(height: 8),
          const Text('Este valor será usado como taxa de troca em todas as novas permutas.',
              style: TextStyle(fontSize: 11, color: AppColors.textLight)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () async {
            final newPrice = double.tryParse(ctrl.text.replaceAll(',', '.'));
            if (newPrice == null || newPrice <= 0) return;
            try {
              // O servidor reajusta e acrescenta o ponto na linha do tempo,
              // registrando quem alterou (usuário logado).
              await AppData.updatePrice(product, newPrice);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              onUpdated();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Valor atualizado com sucesso!'),
                backgroundColor: AppColors.approved,
              ));
            } on ApiException catch (e) {
              if (ctx.mounted) showErrorSnack(ctx, e);
            }
          },
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
}

/// Diálogo para classificar um INSUMO em uma "pasta" (categoria). A pasta pode
/// carregar uma regra de mínimo que trava o envio da permuta. Selecionar
/// "Sem categoria" desvincula o insumo.
Future<void> showCategoryAssignDialog(BuildContext context, ProductModel product, VoidCallback onUpdated) {
  String? selected = product.categoryId;
  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Categoria do insumo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Pasta',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Sem categoria')),
                ...AppData.categories.map((c) => DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (v) => setLocal(() => selected = v),
            ),
            const SizedBox(height: 8),
            const Text(
              'A pasta agrupa insumos e pode exigir um mínimo (% do total ou R\$/ha) '
              'para que a permuta possa ser enviada.',
              style: TextStyle(fontSize: 11, color: AppColors.textLight),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              try {
                await AppData.updateProductFields(product, {
                  'categoryId': selected == null ? null : int.parse(selected!),
                });
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                onUpdated();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Categoria atualizada!'),
                  backgroundColor: AppColors.approved,
                ));
              } on ApiException catch (e) {
                if (ctx.mounted) showErrorSnack(ctx, e);
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
}

/// Diálogo de exigência mínima por hectare de um INSUMO. Define a taxa
/// (unidade do insumo por ha) que o produtor é obrigado a retirar na permuta,
/// proporcional à área da propriedade. 0 = insumo sem exigência.
Future<void> showRequiredPerHaDialog(BuildContext context, ProductModel product, VoidCallback onUpdated) {
  final ctrl = TextEditingController(
      text: product.requiredPerHa > 0 ? formatQty(product.requiredPerHa) : '');
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Exigência por hectare'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Text('Medido em ${product.unit}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMedium)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Quantidade por hectare',
              prefixIcon: Icon(Icons.straighten),
              hintText: 'Ex.: 2,5',
            ),
            autofocus: true,
          ),
          const SizedBox(height: 8),
          const Text(
            'Cada permuta exigirá no mínimo esta quantidade × a área (ha) do '
            'produtor. Deixe vazio ou 0 para não exigir este insumo.',
            style: TextStyle(fontSize: 11, color: AppColors.textLight),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () async {
            final value = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
            try {
              await AppData.updateProductFields(product, {
                'requiredPerHa': value < 0 ? 0 : value,
              });
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              onUpdated();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Exigência por hectare atualizada!'),
                backgroundColor: AppColors.approved,
              ));
            } on ApiException catch (e) {
              if (ctx.mounted) showErrorSnack(ctx, e);
            }
          },
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
}
