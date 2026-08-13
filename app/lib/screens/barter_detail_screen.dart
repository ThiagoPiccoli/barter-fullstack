import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/barter_pdf.dart';
import '../widgets/common_widgets.dart';

class BarterDetailScreen extends StatefulWidget {
  final BarterModel barter;
  final bool isAdmin;
  const BarterDetailScreen({super.key, required this.barter, required this.isAdmin});
  @override
  State<BarterDetailScreen> createState() => _BarterDetailScreenState();
}

class _BarterDetailScreenState extends State<BarterDetailScreen> {
  late BarterModel _barter;

  @override
  void initState() {
    super.initState();
    _barter = widget.barter;
  }

  /// Comprovante em PDF para controle. Segue a regra das telas: o admin recebe
  /// o documento com valores em R$; o consultor, só quantidades e sacas.
  Future<void> _sharePdf(ProducerModel? producer) async {
    try {
      await BarterPdf.share(_barter, producer: producer, showValues: widget.isAdmin);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível gerar o PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final producer = AppData.producerById(_barter.producerId);
    return Scaffold(
      appBar: AppBar(
        title: Text(_barter.id),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Gerar PDF',
            onPressed: () => _sharePdf(producer),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: StatusBadge(status: _barter.status)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          BarterBalanceBar(
            inputCost: _barter.inputCost,
            referenceValue: _barter.referenceValue,
            referenceGrainName: _barter.referenceGrainName,
            inputCount: _barter.inputs.length,
            showValue: widget.isAdmin,
          ),
          const SizedBox(height: 16),

          // Meta info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(label: 'Produtor', value: _barter.producerName),
                  if (producer != null)
                    _InfoRow(label: 'Propriedade', value: producer.location),
                  if (widget.isAdmin) ...[
                    _InfoRow(label: 'Consultor', value: _barter.consultantName),
                    _InfoRow(label: 'Filial', value: _barter.consultantBranch),
                  ],
                  const Divider(height: 16),
                  _InfoRow(label: 'Criada em', value: _formatDate(_barter.createdAt)),
                  if (_barter.updatedAt != null)
                    _InfoRow(label: 'Atualizada em', value: _formatDate(_barter.updatedAt!)),
                  if (_barter.reviewedBy != null)
                    _InfoRow(label: 'Revisada por', value: _barter.reviewedBy!),
                  if (_barter.adminNote != null && _barter.adminNote!.isNotEmpty) ...[
                    const Divider(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.comment_outlined, size: 16, color: AppColors.textLight),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Observação do Administrador',
                                  style: TextStyle(fontSize: 11, color: AppColors.textLight)),
                              const SizedBox(height: 2),
                              Text(_barter.adminNote!,
                                  style: const TextStyle(fontSize: 13, color: AppColors.textDark)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          _ItemsSection(
            title: 'Insumos Retirados',
            subtitle: 'O que o produtor precisa — origem da permuta',
            icon: Icons.science_outlined,
            accent: AppColors.input,
            items: _barter.inputs,
            totalLabel: widget.isAdmin ? 'Custo total' : 'Total retirado',
            total: _barter.inputCost,
            referenceValue: _barter.referenceValue,
            referenceGrainName: _barter.referenceGrainName,
            showValue: widget.isAdmin,
          ),
          const SizedBox(height: 16),

          _ItemsSection(
            title: 'Pagamento em Grãos',
            subtitle: 'Sacas a entregar para cobrir os insumos',
            icon: Icons.grass,
            accent: AppColors.grain,
            items: _barter.grains,
            totalLabel: 'Total a entregar',
            total: _barter.grainCredit,
            referenceValue: _barter.referenceValue,
            referenceGrainName: _barter.referenceGrainName,
            showValue: widget.isAdmin,
          ),
          const SizedBox(height: 16),

          // Resumo do pagamento: quantas sacas o produtor entrega para pagar tudo
          Card(
            color: AppColors.primarySurface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOTAL A ENTREGAR',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _barter.referenceValue > 0
                            ? '${formatSacks(_barter.sacksToDeliver)} ${_barter.referenceGrainName.toLowerCase()}'
                            : '0 sc',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                      Text(
                          widget.isAdmin
                              ? '≈ ${formatCurrency(_barter.inputCost)} em insumos'
                              : 'para ${_barter.inputs.length} insumo(s) retirado(s)',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMedium)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          if (widget.isAdmin && _barter.status == BarterStatus.pending) ...[
            const Text('Ação do Administrador',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => reviewBarter(context, _barter, BarterStatus.denied,
                        onReviewed: (updated) => setState(() => _barter = updated)),
                    icon: const Icon(Icons.close),
                    label: const Text('Negar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.denied,
                      side: const BorderSide(color: AppColors.denied),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => reviewBarter(context, _barter, BarterStatus.approved,
                        onReviewed: (updated) => setState(() => _barter = updated)),
                    icon: const Icon(Icons.check),
                    label: const Text('Aprovar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.approved,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _ItemsSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<BarterItem> items;
  final String totalLabel;
  final double total;
  final double referenceValue;
  final String referenceGrainName;
  final bool showValue;

  const _ItemsSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.items,
    required this.totalLabel,
    required this.total,
    required this.referenceValue,
    required this.referenceGrainName,
    required this.showValue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ...items.asMap().entries.map((entry) {
                final i = entry.key;
                final item = entry.value;
                return Column(
                  children: [
                    if (i > 0) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.productName,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  showValue
                                      ? '${formatQty(item.quantity)} ${item.unit} × ${formatCurrency(item.unitValue)}'
                                      : '${formatQty(item.quantity)} ${item.unit}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textMedium),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                referenceValue > 0
                                    ? formatSacks(item.total / referenceValue)
                                    : (showValue ? formatCurrency(item.total) : formatSacks(0)),
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accent),
                              ),
                              if (referenceValue > 0 && showValue)
                                Text('≈ ${formatCurrency(item.total)}',
                                    style: const TextStyle(fontSize: 10, color: AppColors.textLight)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(totalLabel,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          referenceValue > 0
                              ? '${formatSacks(total / referenceValue)} ${referenceGrainName.toLowerCase()}'
                              : (showValue ? formatCurrency(total) : formatSacks(0)),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: accent),
                        ),
                        if (referenceValue > 0 && showValue)
                          Text('≈ ${formatCurrency(total)}',
                              style: const TextStyle(fontSize: 10, color: AppColors.textLight)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, color: AppColors.textDark, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
