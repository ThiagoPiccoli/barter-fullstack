import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../widgets/common_widgets.dart';
import 'edit_forms.dart';

class SellerProfileAdminScreen extends StatefulWidget {
  final ProducerModel producer;
  const SellerProfileAdminScreen({super.key, required this.producer});

  @override
  State<SellerProfileAdminScreen> createState() => _SellerProfileAdminScreenState();
}

class _SellerProfileAdminScreenState extends State<SellerProfileAdminScreen> {
  late ProducerModel producer = widget.producer;

  Future<void> _edit() async {
    final updated = await Navigator.push<ProducerModel>(
      context,
      MaterialPageRoute(builder: (_) => EditProducerScreen(producer: producer)),
    );
    if (updated != null) setState(() => producer = updated);
  }

  void _delete() {
    confirmDeleteRegistration(
      context,
      title: 'Excluir Produtor',
      name: producer.name,
      barterCount: AppData.barters.where((b) => b.producerId == producer.id).length,
      onConfirm: () async {
        await AppData.deleteProducer(producer.id);
        if (mounted) Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final barters = AppData.barters.where((b) => b.producerId == producer.id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final approvedList = barters.where((b) => b.status == BarterStatus.approved).toList();
    final pending = barters.where((b) => b.status == BarterStatus.pending).length;
    final denied = barters.where((b) => b.status == BarterStatus.denied).length;
    final sacks = approvedList.fold<double>(0, (s, b) => s + b.totalGrainQty);
    final inputsValue = approvedList.fold<double>(0, (s, b) => s + b.inputCost);

    return Scaffold(
      appBar: AppBar(
        title: Text('Produtor – ${producer.name.split(' ')[0]}'),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: _edit),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary,
                  radius: 40,
                  child: Text(producer.avatarInitials,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
                Text(producer.name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                Text(producer.location,
                    style: const TextStyle(fontSize: 13, color: AppColors.textMedium), textAlign: TextAlign.center),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Card(
            child: Column(
              children: [
                InfoTile(
                  icon: Icons.work_outline,
                  label: 'Carteira do vendedor',
                  value: AppData.sellerById(producer.sellerId)?.name ?? 'Sem vendedor vinculado',
                ),
                const Divider(height: 1),
                InfoTile(icon: Icons.badge_outlined, label: 'Documento', value: producer.document),
                const Divider(height: 1),
                InfoTile(icon: Icons.phone_outlined, label: 'Telefone', value: producer.phone),
                const Divider(height: 1),
                InfoTile(icon: Icons.agriculture_outlined, label: 'Propriedade', value: producer.farmName),
                const Divider(height: 1),
                InfoTile(icon: Icons.location_on_outlined, label: 'Município', value: producer.city),
                const Divider(height: 1),
                InfoTile(icon: Icons.straighten, label: 'Área cultivável', value: producer.areaLabel),
                const Divider(height: 1),
                InfoTile(
                  icon: Icons.calendar_today_outlined,
                  label: 'Cliente desde',
                  value: '${producer.createdAt.month.toString().padLeft(2, '0')}/${producer.createdAt.year}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          const Text('Estatísticas',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 12),
          GridView(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 140,
            ),
            physics: const NeverScrollableScrollPhysics(),
            children: [
              SummaryCard(
                title: 'Total Permutas',
                value: barters.length.toString(),
                icon: Icons.swap_horiz,
                color: AppColors.primary,
              ),
              SummaryCard(
                title: 'Sacas Entregues',
                value: formatQty(sacks),
                icon: Icons.grass,
                color: AppColors.grain,
              ),
              SummaryCard(
                title: 'Insumos Retirados',
                value: formatCurrency(inputsValue),
                icon: Icons.science_outlined,
                color: AppColors.input,
              ),
              SummaryCard(
                title: 'Em Análise',
                value: pending.toString(),
                icon: Icons.hourglass_top,
                color: AppColors.pending,
              ),
            ],
          ),
          if (denied > 0) ...[
            const SizedBox(height: 8),
            Text('$denied permuta(s) negada(s)',
                style: const TextStyle(fontSize: 12, color: AppColors.denied)),
          ],
          const SizedBox(height: 20),

          const Text('Log de Permutas',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 12),
          if (barters.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhuma permuta registrada', style: TextStyle(color: AppColors.textLight)),
              ),
            )
          else
            ...barters.map((b) => BarterLogItem(
                  barter: b,
                  subtitle: '${b.inputs.length} insumo(s) • ${formatCurrency(b.inputCost)}',
                )),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline, color: AppColors.denied),
            label: const Text('Excluir produtor', style: TextStyle(color: AppColors.denied)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.denied),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

