import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../widgets/common_widgets.dart';
import 'producer_profile_screen.dart';
import 'consultant_profile_screen.dart';
import 'edit_forms.dart';

/// Aba de cadastros do admin: alterna entre PRODUTORES (clientes designados) e
/// CONSULTORES (usuários que registram permutas), com busca em cada lista.
class ConsultantsScreen extends StatefulWidget {
  const ConsultantsScreen({super.key});
  @override
  State<ConsultantsScreen> createState() => _ConsultantsScreenState();
}

class _ConsultantsScreenState extends State<ConsultantsScreen> {
  int _tab = 0; // 0 = produtores, 1 = consultores
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _setTab(int i) {
    if (i == _tab) return;
    setState(() {
      _tab = i;
      _search = '';
      _searchCtrl.clear();
    });
  }

  /// Abre o cadastro de um novo produtor ou consultor, conforme a aba ativa.
  Future<void> _createNew() async {
    final isProducers = _tab == 0;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isProducers ? const EditProducerScreen() : const EditConsultantScreen(),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final isProducers = _tab == 0;

    final producers = AppData.producers
        .where((p) =>
            q.isEmpty ||
            p.name.toLowerCase().contains(q) ||
            p.city.toLowerCase().contains(q) ||
            p.farmName.toLowerCase().contains(q))
        .toList();
    final consultants = AppData.consultants
        .where((v) =>
            q.isEmpty ||
            v.name.toLowerCase().contains(q) ||
            v.branch.toLowerCase().contains(q) ||
            v.email.toLowerCase().contains(q))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastros'),
        actions: const [LogoutButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNew,
        icon: const Icon(Icons.add),
        label: Text(isProducers ? 'Novo produtor' : 'Novo consultor'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: _SegmentedToggle(
              tab: _tab,
              producerCount: AppData.producers.length,
              consultantCount: AppData.consultants.length,
              onChanged: _setTab,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SearchField(
              controller: _searchCtrl,
              hint: isProducers
                  ? 'Buscar produtor, fazenda ou cidade...'
                  : 'Buscar consultor, filial ou e-mail...',
              onChanged: (v) => setState(() => _search = v),
              onClear: () => setState(() {
                _search = '';
                _searchCtrl.clear();
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                isProducers
                    ? '${producers.length} produtor(es)'
                    : '${consultants.length} consultor(es)',
                style: const TextStyle(fontSize: 12, color: AppColors.textMedium, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: isProducers ? _buildProducerList(producers) : _buildConsultantList(consultants),
          ),
        ],
      ),
    );
  }

  Widget _buildProducerList(List<ProducerModel> list) {
    if (list.isEmpty) return const _EmptyState(label: 'Nenhum produtor encontrado');
    return ListView.builder(
      // Chave própria: alternar Produtores↔Consultores não pode herdar a
      // rolagem da outra lista (o PageStorage compartilharia o offset).
      key: const PageStorageKey('cadastros_produtores'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final p = list[i];
        final bs = AppData.barters.where((b) => b.producerId == p.id).toList();
        final owner = AppData.consultantById(p.consultantId);
        return _PersonCard(
          initials: p.avatarInitials,
          name: p.name,
          subtitle: '${p.location} • ${p.areaLabel}',
          accent: AppColors.primary,
          badgeIcon: Icons.agriculture,
          chips: [
            // Dono da carteira: só o admin vê esta lista completa, então o
            // vínculo produtor → consultor precisa estar visível aqui.
            _StatChip(
              label: 'Carteira: ${owner?.name.split(' ').first ?? 'sem consultor'}',
              color: AppColors.input,
            ),
            ..._statChips(bs),
          ],
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ProducerProfileScreen(producer: p)),
            );
            if (mounted) setState(() {});
          },
        );
      },
    );
  }

  Widget _buildConsultantList(List<UserModel> list) {
    if (list.isEmpty) return const _EmptyState(label: 'Nenhum consultor encontrado');
    return ListView.builder(
      key: const PageStorageKey('cadastros_consultores'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final v = list[i];
        final bs = AppData.barters.where((b) => b.consultantId == v.id).toList();
        return _PersonCard(
          initials: v.avatarInitials,
          name: v.name,
          subtitle: v.branch,
          accent: AppColors.input,
          badgeIcon: Icons.badge,
          chips: _statChips(bs),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ConsultantProfileScreen(consultant: v)),
            );
            if (mounted) setState(() {});
          },
        );
      },
    );
  }
}

List<Widget> _statChips(List<BarterModel> bs) {
  final approved = bs.where((b) => b.status == BarterStatus.approved).length;
  final pending = bs.where((b) => b.status == BarterStatus.pending).length;
  return [
    _StatChip(label: '${bs.length} permutas', color: AppColors.primary),
    if (approved > 0) _StatChip(label: '$approved aprov.', color: AppColors.approved),
    if (pending > 0) _StatChip(label: '$pending análise', color: AppColors.pending),
  ];
}

class _SegmentedToggle extends StatelessWidget {
  final int tab;
  final int producerCount, consultantCount;
  final ValueChanged<int> onChanged;
  const _SegmentedToggle({
    required this.tab,
    required this.producerCount,
    required this.consultantCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEDED),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _seg(
              label: 'Produtores',
              icon: Icons.agriculture,
              count: producerCount,
              selected: tab == 0,
              accent: AppColors.primary,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _seg(
              label: 'Consultores',
              icon: Icons.badge,
              count: consultantCount,
              selected: tab == 1,
              accent: AppColors.input,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seg({
    required String label,
    required IconData icon,
    required int count,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [BoxShadow(color: accent.withValues(alpha: 0.30), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : AppColors.textMedium),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textMedium,
                  )),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.25) : AppColors.textLight.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textMedium,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  final String initials, name, subtitle;
  final Color accent;
  final IconData badgeIcon;
  final List<Widget> chips;
  final VoidCallback onTap;
  const _PersonCard({
    required this.initials,
    required this.name,
    required this.subtitle,
    required this.accent,
    required this.badgeIcon,
    required this.chips,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    backgroundColor: accent,
                    radius: 24,
                    child: Text(initials,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle),
                      child: Icon(badgeIcon, size: 12, color: accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMedium),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 4, children: chips),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textLight),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String label;
  const _EmptyState({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, size: 48, color: AppColors.textLight),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: AppColors.textLight)),
        ],
      ),
    );
  }
}
