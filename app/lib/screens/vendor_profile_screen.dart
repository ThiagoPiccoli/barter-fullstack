import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/mock_data.dart';
import '../widgets/common_widgets.dart';
import 'edit_forms.dart';
import 'seller_profile_admin_screen.dart';

/// Perfil de um vendedor visto pelo admin: dados, desempenho e as permutas que
/// ele registrou (filtradas por sellerId).
class VendorProfileScreen extends StatefulWidget {
  final UserModel vendor;
  const VendorProfileScreen({super.key, required this.vendor});

  @override
  State<VendorProfileScreen> createState() => _VendorProfileScreenState();
}

class _VendorProfileScreenState extends State<VendorProfileScreen> {
  late UserModel vendor = widget.vendor;

  Future<void> _edit() async {
    final updated = await Navigator.push<UserModel>(
      context,
      MaterialPageRoute(builder: (_) => EditVendorScreen(vendor: vendor)),
    );
    if (updated != null) setState(() => vendor = updated);
  }

  void _delete() {
    confirmDeleteRegistration(
      context,
      title: 'Excluir Vendedor',
      name: vendor.name,
      barterCount: mockBarters.where((b) => b.sellerId == vendor.id).length,
      onConfirm: () {
        mockSellers.removeWhere((v) => v.id == vendor.id);
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = producersForSeller(vendor.id);
    final barters = mockBarters.where((b) => b.sellerId == vendor.id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final approvedList = barters.where((b) => b.status == BarterStatus.approved).toList();
    final pending = barters.where((b) => b.status == BarterStatus.pending).length;
    final denied = barters.where((b) => b.status == BarterStatus.denied).length;
    final sacks = approvedList.fold<double>(0, (s, b) => s + b.totalGrainQty);
    final inputsValue = approvedList.fold<double>(0, (s, b) => s + b.inputCost);

    return Scaffold(
      appBar: AppBar(
        title: Text('Vendedor – ${vendor.name.split(' ')[0]}'),
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
                  backgroundColor: AppColors.input,
                  radius: 40,
                  child: Text(vendor.avatarInitials,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
                Text(vendor.name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                Text(vendor.branch,
                    style: const TextStyle(fontSize: 13, color: AppColors.textMedium), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.inputBg, borderRadius: BorderRadius.circular(20)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.badge_outlined, size: 13, color: AppColors.input),
                      SizedBox(width: 4),
                      Text('Vendedor',
                          style: TextStyle(fontSize: 12, color: AppColors.input, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                InfoTile(icon: Icons.email_outlined, label: 'E-mail', value: vendor.email),
                const Divider(height: 1),
                InfoTile(icon: Icons.phone_outlined, label: 'Telefone', value: vendor.phone),
                const Divider(height: 1),
                InfoTile(icon: Icons.store_outlined, label: 'Filial', value: vendor.branch),
                const Divider(height: 1),
                InfoTile(
                  icon: Icons.calendar_today_outlined,
                  label: 'Na empresa desde',
                  value: '${vendor.createdAt.month.toString().padLeft(2, '0')}/${vendor.createdAt.year}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Desempenho',
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
                title: 'Permutas Criadas',
                value: barters.length.toString(),
                icon: Icons.swap_horiz,
                color: AppColors.primary,
              ),
              SummaryCard(
                title: 'Sacas Intermediadas',
                value: formatQty(sacks),
                icon: Icons.grass,
                color: AppColors.grain,
              ),
              SummaryCard(
                title: 'Insumos Movimentados',
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
          // Carteira de produtores: os clientes que só este vendedor atende.
          Text('Carteira de Produtores (${wallet.length})',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 12),
          if (wallet.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhum produtor na carteira', style: TextStyle(color: AppColors.textLight)),
              ),
            )
          else
            ...wallet.map((p) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => SellerProfileAdminScreen(producer: p)),
                      );
                      if (mounted) setState(() {});
                    },
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primarySurface,
                      child: Text(p.avatarInitials,
                          style: const TextStyle(
                              color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(p.name,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                    subtitle: Text('${p.location} • ${p.areaLabel}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textMedium),
                        overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textLight),
                  ),
                )),
          const SizedBox(height: 20),
          const Text('Permutas Registradas',
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
                  subtitle: 'Produtor: ${b.producerName}',
                )),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline, color: AppColors.denied),
            label: const Text('Excluir vendedor', style: TextStyle(color: AppColors.denied)),
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

