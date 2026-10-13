import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/dashboard_stats.dart';
import '../services/tax_regime.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/common_widgets.dart';
import 'edit_forms.dart';

class ProducerProfileScreen extends StatefulWidget {
  final ProducerModel producer;
  const ProducerProfileScreen({super.key, required this.producer});

  @override
  State<ProducerProfileScreen> createState() => _ProducerProfileScreenState();
}

class _ProducerProfileScreenState extends State<ProducerProfileScreen> {
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
      barterCount: ofProducer(AppData.barters, producer.id).length,
      onConfirm: () async {
        await AppData.deleteProducer(producer.id);
        if (mounted) Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final barters = ofProducer(AppData.barters, producer.id)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    // Aprovadas E faturadas: faturar não desfaz o negócio. A conta é a mesma
    // dos painéis (ver `services/dashboard_stats.dart`).
    final stats = statsOf(barters);
    final pending = stats.pendingCount;
    final denied = stats.denied;
    final atManager = stats.atManagerCount;
    final sacks = stats.sacksReceivable;
    final inputsValue = stats.inputsValue;
    final consultor = AppData.consultantNameFor(producer);

    return Scaffold(
      appBar: AppBar(
        title: Text('Produtor: ${producer.name.split(' ')[0]}'),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: _edit),
        ],
      ),
      body: BoundedContent(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.primary,
                    radius: 40,
                    child: Text(producer.avatarInitials,
                        style: TextStyle(color: AppColors.onPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Text(producer.name,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  Text(producer.location,
                      style: TextStyle(fontSize: 13, color: AppColors.textMedium), textAlign: TextAlign.center),
                ],
              ),
            ),
            const SizedBox(height: 20),
  
            Card(
              child: Column(
                children: [
                  InfoTile(
                    icon: Icons.work_outline,
                    label: 'Carteira do consultor',
                    value: consultor ?? 'Sem consultor vinculado',
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
                  // O REGIME dele, com a alíquota que ele produz para este
                  // documento: é o que toda permuta nova deste produtor vai
                  // aplicar, e é aqui que se confere antes de fechar uma.
                  InfoTile(
                    icon: Icons.receipt_long_outlined,
                    label: 'Funrural',
                    value: '${producer.taxRegime.shortLabel} • '
                        '${taxRateOf(producer.taxRegime, producer.document).toStringAsFixed(2).replaceAll('.', ',')}%',
                  ),
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
  
            Text('Estatísticas',
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
                  title: 'Total ${brand.copy.barterPluralTitle}',
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
                  title: 'No Comitê',
                  value: pending.toString(),
                  icon: Icons.hourglass_top,
                  color: AppColors.pending,
                ),
                // Contagem própria: uma permuta que ainda não saiu da mesa do
                // gerente não está no comitê, e juntar as duas esconderia
                // exatamente onde ela parou.
                SummaryCard(
                  title: 'No Gerente',
                  value: atManager.toString(),
                  icon: Icons.assignment_ind_outlined,
                  color: AppColors.atManager,
                ),
              ],
            ),
            if (denied > 0) ...[
              const SizedBox(height: 8),
              Text('$denied permuta(s) negada(s)',
                  style: TextStyle(fontSize: 12, color: AppColors.denied)),
            ],
            const SizedBox(height: 20),
  
            Text('Log de ${brand.copy.barterPluralTitle}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 12),
            if (barters.isEmpty)
              Center(
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
              icon: Icon(Icons.delete_outline, color: AppColors.denied),
              label: Text('Excluir produtor', style: TextStyle(color: AppColors.denied)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.denied),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

