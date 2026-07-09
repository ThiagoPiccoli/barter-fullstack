import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/mock_data.dart';
import '../widgets/common_widgets.dart';
import 'barter_detail_screen.dart';

class BartersScreen extends StatefulWidget {
  final bool isAdmin;
  final String? sellerId;
  const BartersScreen({super.key, required this.isAdmin, required this.sellerId});
  @override
  State<BartersScreen> createState() => _BartersScreenState();
}

class _BartersScreenState extends State<BartersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<BarterModel> _filtered(BarterStatus? status) {
    var list = widget.isAdmin
        ? List<BarterModel>.from(mockBarters)
        : mockBarters.where((b) => b.sellerId == widget.sellerId).toList();
    if (status != null) list = list.where((b) => b.status == status).toList();
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((b) =>
              b.id.toLowerCase().contains(q) ||
              b.producerName.toLowerCase().contains(q) ||
              b.sellerName.toLowerCase().contains(q))
          .toList();
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? 'Permutas' : 'Minhas Permutas'),
        actions: const [LogoutButton()],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: 'Todas (${_filtered(null).length})'),
            Tab(text: 'Análise (${_filtered(BarterStatus.pending).length})'),
            Tab(text: 'Aprovadas (${_filtered(BarterStatus.approved).length})'),
            Tab(text: 'Negadas (${_filtered(BarterStatus.denied).length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: widget.isAdmin ? 'Buscar por código ou produtor...' : 'Buscar por código...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _BarterList(barters: _filtered(null), isAdmin: widget.isAdmin, onChanged: () => setState(() {})),
                _BarterList(barters: _filtered(BarterStatus.pending), isAdmin: widget.isAdmin, onChanged: () => setState(() {})),
                _BarterList(barters: _filtered(BarterStatus.approved), isAdmin: widget.isAdmin, onChanged: () => setState(() {})),
                _BarterList(barters: _filtered(BarterStatus.denied), isAdmin: widget.isAdmin, onChanged: () => setState(() {})),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarterList extends StatelessWidget {
  final List<BarterModel> barters;
  final bool isAdmin;
  final VoidCallback onChanged;
  const _BarterList({required this.barters, required this.isAdmin, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (barters.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('Nenhuma permuta encontrada', style: TextStyle(color: AppColors.textLight)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: barters.length,
      itemBuilder: (context, index) =>
          _BarterCard(barter: barters[index], isAdmin: isAdmin, onChanged: onChanged),
    );
  }
}

class _BarterCard extends StatelessWidget {
  final BarterModel barter;
  final bool isAdmin;
  final VoidCallback onChanged;
  const _BarterCard({required this.barter, required this.isAdmin, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => BarterDetailScreen(barter: barter, isAdmin: isAdmin)),
          );
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(barter.id,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const Spacer(),
                  StatusBadge(status: barter.status),
                ],
              ),
              if (isAdmin) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 14, color: AppColors.textLight),
                    const SizedBox(width: 4),
                    Text(barter.producerName,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMedium, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Vend.: ${barter.sellerName}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              // Linha de troca: insumos retirados -> grãos que pagam
              Row(
                children: [
                  Expanded(
                    child: _SidePill(
                      icon: Icons.science_outlined,
                      accent: AppColors.input,
                      title: 'Insumos retirados',
                      value: isAdmin
                          ? formatCurrency(barter.inputCost)
                          : '${barter.inputs.length} item(ns)',
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward, size: 16, color: AppColors.textLight),
                  ),
                  Expanded(
                    child: _SidePill(
                      icon: Icons.grass,
                      accent: AppColors.grain,
                      title: 'Paga com ${barter.referenceGrainName.toLowerCase()}',
                      value: formatSacks(barter.sacksToDeliver),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.textLight),
                  const SizedBox(width: 4),
                  Text(_formatDate(barter.createdAt),
                      style: const TextStyle(fontSize: 12, color: AppColors.textMedium)),
                ],
              ),
              if (isAdmin && barter.status == BarterStatus.pending) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => reviewBarter(context, barter, BarterStatus.denied,
                            onReviewed: (_) => onChanged()),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Negar', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.denied,
                          side: const BorderSide(color: AppColors.denied),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => reviewBarter(context, barter, BarterStatus.approved,
                            onReviewed: (_) => onChanged()),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Aprovar', style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.approved,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
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

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _SidePill extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String value;
  const _SidePill({required this.icon, required this.accent, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 11, color: AppColors.textMedium),
                    overflow: TextOverflow.ellipsis),
                Text(value,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
