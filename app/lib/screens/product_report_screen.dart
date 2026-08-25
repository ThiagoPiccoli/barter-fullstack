import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/api/api_client.dart';
import '../widgets/common_widgets.dart';
import '../widgets/price_chart.dart';
import 'barter_program_screen.dart';
import 'edit_forms.dart';

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

  /// O produto com a linha do tempo COMPLETA. Vem do detalhe da API, não do
  /// cache: a listagem do catálogo não carrega o histórico (ele cresce um
  /// ponto por produto a cada versão publicada), e é ele que esta tela desenha.
  ProductModel? _detail;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final detail = await AppData.productDetail(widget.productId);
      if (mounted) setState(() => (_detail = detail, _error = null));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// O produto pode ser corrigido? Só se houver Barter vigente E ele estiver na
  /// tabela dessa versão (ou for o grão da safra, cuja cotação é a da versão).
  bool _editableInVersion(ProductModel product) {
    final version = AppData.currentVersion;
    if (version == null || !version.isOpen) return false;
    return version.grainId == product.id || version.priceOf(product.id) != null;
  }

  /// Troca o CÓDIGO do item — único no catálogo e chave da busca.
  Future<void> _editCode(ProductModel product) => _editField(
        product,
        field: 'sku',
        title: 'Código do item',
        label: 'Código',
        icon: Icons.qr_code_2,
        current: product.sku ?? '',
        hint: 'Use o código do fornecedor quando houver: é ele que casa a '
            'planilha com este cadastro na próxima carga.',
        uppercase: true,
      );

  /// Um campo de texto do cadastro, editado em diálogo.
  ///
  /// A recusa do servidor aparece inteira (código repetido, por exemplo): ela
  /// diz de quem é o código, e essa é a informação que resolve.
  Future<void> _editField(
    ProductModel product, {
    required String field,
    required String title,
    required String label,
    required IconData icon,
    required String current,
    required String hint,
    bool uppercase = false,
  }) async {
    final controller = TextEditingController(text: current);
    final novo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization:
                  uppercase ? TextCapitalization.characters : TextCapitalization.none,
              decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
            ),
            const SizedBox(height: 8),
            Text(hint, style: TextStyle(fontSize: 11, color: AppColors.textLight)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (novo == null || novo.isEmpty || novo == current) return;

    try {
      await AppData.updateProductFields(product, {field: novo});
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _correctInVersion(BuildContext context, ProductModel product) {
    final version = AppData.currentVersion!;
    final row = version.priceOf(product.id);
    return showVersionPriceDialog(
      context,
      productId: product.id,
      productName: product.name,
      price: row?.perUnit ?? version.grainPrice,
      // Corrigir o valor acrescenta um ponto na linha do tempo: a tela precisa
      // do detalhe de novo, não de um rebuild do que já estava em mãos.
      onUpdated: _loadDetail,
    );
  }

  /// O produto do cache, para o cabeçalho aparecer enquanto o detalhe carrega.
  /// Null se ele não estiver no catálogo carregado (produto recém-excluído).
  ProductModel? get _cached {
    final list = widget.type == ProductType.grain ? AppData.grains : AppData.inputs;
    for (final product in list) {
      if (product.id == widget.productId) return product;
    }
    return null;
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
    final product = _detail;
    // Enquanto o detalhe não chega (ou falhou), não há série para desenhar. O
    // cabeçalho sai do cache, que já tem nome e valor atual — a tela abre
    // preenchida e só o gráfico espera.
    if (product == null || product.priceHistory.isEmpty) {
      return _placeholder();
    }

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
                        Text('Evolução do valor',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                        const Spacer(),
                        Text('R\$ / ${product.unit}',
                            style: TextStyle(fontSize: 11, color: AppColors.textLight)),
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
              Text('Linha do Tempo',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              const Spacer(),
              Text('${product.priceHistory.length} registros',
                  style: TextStyle(fontSize: 11, color: AppColors.textLight)),
            ],
          ),
          const SizedBox(height: 12),
          _timeline(product),
          const SizedBox(height: 20),

          // Corrigir o valor é ato do LANÇAMENTO, não do cadastro: só aparece
          // enquanto houver Barter vigente, e o que ele muda é a tabela da
          // versão — o `currentPrice` acima é o último valor publicado.
          if (_editableInVersion(product))
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _correctInVersion(context, product),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text('Corrigir no Barter ${AppData.currentVersion!.code}'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
          const SizedBox(height: 20),

          // O CADASTRO do item vive aqui, junto do histórico dele, e não na
          // lista: são atos raros (classificar, exigir por hectare, excluir) e
          // ficavam repetidos em cada cartão de uma lista que se lê para
          // consultar valor.
          _registration(product),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// O cadastro do item: código, classe, exigência por hectare e a saída do
  /// catálogo.
  ///
  /// Classe e exigência só existem para INSUMO — grão não pertence a classe
  /// nem tem mínimo por hectare (ele é o pagamento, não a retirada).
  Widget _registration(ProductModel product) {
    final isInput = product.type == ProductType.input;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, size: 18, color: AppColors.textMedium),
                const SizedBox(width: 6),
                Text('Cadastro do item',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              ],
            ),
            const Divider(height: 20),
            _registrationRow(
              icon: Icons.qr_code_2,
              label: 'Código: ${product.codeLabel}',
              active: product.sku != null,
              action: 'Alterar',
              onPressed: () => _editCode(product),
            ),
            const Divider(height: 20),
            // A unidade costuma vir pronta da planilha (a embalagem sai da
            // descrição), mas alguns itens não dizem a embalagem em lugar
            // nenhum — adubo a peso, por exemplo. Para esses, é aqui que se
            // acerta: a unidade aparece em toda permuta e no comprovante.
            _registrationRow(
              icon: Icons.straighten,
              label: 'Unidade: ${product.unit}',
              active: product.unit != 'unidade',
              action: 'Alterar',
              onPressed: () => _editField(
                product,
                field: 'unit',
                title: 'Unidade do item',
                label: 'Unidade',
                icon: Icons.straighten,
                current: product.unit,
                hint: 'Como o item é vendido: "20 L", "big-bag", "tonelada".',
              ),
            ),
            if (isInput) ...[
              const Divider(height: 20),
              _registrationRow(
                icon: Icons.category_outlined,
                label: 'Classe: ${AppData.classById(product.classId)?.name ?? 'sem classe'}',
                active: product.classId != null,
                action: 'Alterar',
                onPressed: () => showClassAssignDialog(context, product, () => setState(() {})),
              ),
              const Divider(height: 20),
              _registrationRow(
                icon: Icons.straighten,
                label: product.requiredPerHa > 0
                    ? 'Exigência: ${formatQty(product.requiredPerHa)} ${product.unit}/ha'
                    : 'Sem exigência por área',
                active: product.requiredPerHa > 0,
                action: 'Definir',
                onPressed: () => showRequiredPerHaDialog(context, product, () => setState(() {})),
              ),
            ],
            const Divider(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _delete(product),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Excluir do catálogo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.denied,
                  side: BorderSide(color: AppColors.denied.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _registrationRow({
    required IconData icon,
    required String label,
    required bool active,
    required String action,
    required VoidCallback onPressed,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.input),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.input : AppColors.textLight,
              )),
        ),
        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.input,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(action, style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  /// Tirar o item do catálogo. O histórico das permutas não se perde (cada item
  /// guarda o próprio snapshot), mas o admin merece saber o tamanho do que já
  /// passou por ali antes de decidir — e a tela precisa sair, porque o produto
  /// que ela mostra deixou de existir.
  void _delete(ProductModel product) {
    confirmDeleteRegistration(
      context,
      title: product.type == ProductType.grain
          ? 'Excluir ${brand.copy.grain}'
          : 'Excluir ${brand.copy.input}',
      name: product.name,
      barterCount: AppData.barters
          .where((b) => [...b.grains, ...b.inputs].any((i) => i.productId == product.id))
          .length,
      onConfirm: () async {
        await AppData.deleteProduct(product);
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${product.name} saiu do catálogo.'),
          backgroundColor: AppColors.approved,
        ));
      },
    );
  }

  /// A tela antes de o detalhe chegar: o cabeçalho sai do cache (nome e valor
  /// atual já estão lá) e o lugar do gráfico mostra o que está acontecendo —
  /// carregando, sem histórico ou falhou, com como tentar de novo.
  Widget _placeholder() {
    final cached = _cached;
    return Scaffold(
      appBar: AppBar(title: const Text('Relatório do Item')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (cached != null) ...[
            _header(cached, cached.deltaPct, cached.deltaPct >= 0),
            const SizedBox(height: 16),
          ],
          Card(
            child: SizedBox(
              height: 200,
              child: Center(
                child: _error != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off, color: AppColors.textLight, size: 32),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: AppColors.textLight),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () {
                              setState(() => _error = null);
                              _loadDetail();
                            },
                            child: const Text('Tentar de novo'),
                          ),
                        ],
                      )
                    : _detail != null
                        ? Text('Sem histórico de valores para este item.',
                            style: TextStyle(fontSize: 13, color: AppColors.textLight))
                        : const CircularProgressIndicator(),
              ),
            ),
          ),
          if (cached != null) ...[
            const SizedBox(height: 16),
            _registration(cached),
          ],
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
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                    Text(product.unit, style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
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
                  Text('Valor atual', style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
                  Text(formatCurrency(product.currentPrice),
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.primary)),
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
                  color: selected ? AppColors.onPrimary : _accent,
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
        color: AppColors.surface,
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
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textDark)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.textLight)),
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
                    color: isFirst ? accent : AppColors.surface,
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
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                        Text('${_monthsFull[entry.changedAt.month]} ${entry.changedAt.year} • ${entry.changedBy}',
                            style: TextStyle(fontSize: 11, color: AppColors.textLight)),
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

/// Diálogo para classificar um INSUMO em uma CLASSE. A classe pode carregar
/// uma regra de mínimo que trava o envio da permuta. Selecionar "Sem classe"
/// desvincula o insumo.
Future<void> showClassAssignDialog(BuildContext context, ProductModel product, VoidCallback onUpdated) {
  String? selected = product.classId;
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
                ...AppData.classes.map((c) => DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (v) => setLocal(() => selected = v),
            ),
            const SizedBox(height: 8),
            Text(
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
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
              style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
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
          Text(
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
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
