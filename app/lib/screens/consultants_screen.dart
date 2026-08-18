import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../widgets/common_widgets.dart';
import 'producer_profile_screen.dart';
import 'consultant_profile_screen.dart';
import 'edit_forms.dart';

/// O que a aba de cadastros administra. A ordem é a da dependência: o produtor
/// precisa de um consultor, o consultor precisa de uma unidade e de um gerente.
enum _Registry { producers, consultants, managers, units }

/// Aba de cadastros do admin: PRODUTORES (clientes designados), CONSULTORES
/// (quem registra permuta), GERENTES (quem dá o parecer) e UNIDADES (os locais
/// de retirada), com busca em cada lista.
class ConsultantsScreen extends StatefulWidget {
  const ConsultantsScreen({super.key});
  @override
  State<ConsultantsScreen> createState() => _ConsultantsScreenState();
}

class _ConsultantsScreenState extends State<ConsultantsScreen> {
  _Registry _tab = _Registry.producers;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _setTab(_Registry tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _search = '';
      _searchCtrl.clear();
    });
  }

  /// Abre o cadastro novo do que a aba ativa administra.
  Future<void> _createNew() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => switch (_tab) {
          _Registry.producers => const EditProducerScreen(),
          _Registry.consultants => const EditStaffScreen(role: UserRole.consultant),
          _Registry.managers => const EditStaffScreen(role: UserRole.manager),
          _Registry.units => const EditUnitScreen(),
        },
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();

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
            v.managerName.toLowerCase().contains(q) ||
            v.email.toLowerCase().contains(q))
        .toList();
    final managers = AppData.managers
        .where((m) =>
            q.isEmpty ||
            m.name.toLowerCase().contains(q) ||
            m.branch.toLowerCase().contains(q) ||
            m.email.toLowerCase().contains(q))
        .toList();
    final units = AppData.units
        .where((u) =>
            q.isEmpty ||
            u.name.toLowerCase().contains(q) ||
            u.city.toLowerCase().contains(q))
        .toList();

    final (hint, count, fab) = switch (_tab) {
      _Registry.producers => (
          'Buscar produtor, fazenda ou cidade...',
          '${producers.length} produtor(es)',
          'Novo produtor',
        ),
      _Registry.consultants => (
          'Buscar consultor, unidade, gerente ou e-mail...',
          '${consultants.length} consultor(es)',
          'Novo consultor',
        ),
      _Registry.managers => (
          'Buscar gerente, unidade ou e-mail...',
          '${managers.length} gerente(s)',
          'Novo gerente',
        ),
      _Registry.units => (
          'Buscar unidade ou cidade...',
          '${units.length} unidade(s)',
          'Nova unidade',
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastros'),
        actions: const [LogoutButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNew,
        icon: const Icon(Icons.add),
        label: Text(fab),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: _SegmentedToggle(
              tab: _tab,
              counts: {
                _Registry.producers: AppData.producers.length,
                _Registry.consultants: AppData.consultants.length,
                _Registry.managers: AppData.managers.length,
                _Registry.units: AppData.units.length,
              },
              onChanged: _setTab,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SearchField(
              controller: _searchCtrl,
              hint: hint,
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
                count,
                style: TextStyle(fontSize: 12, color: AppColors.textMedium, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: switch (_tab) {
              _Registry.producers => _buildProducerList(producers),
              _Registry.consultants => _buildConsultantList(consultants),
              _Registry.managers => _buildManagerList(managers),
              _Registry.units => _buildUnitList(units),
            },
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
        return _PersonCard(
          initials: p.avatarInitials,
          name: p.name,
          subtitle: '${p.location} • ${p.areaLabel}',
          accent: AppColors.primary,
          badgeIcon: Icons.agriculture,
          chips: [
            // Quem atende: só o admin vê esta lista completa, então o vínculo
            // produtor → consultores precisa estar visível aqui. Cabe um nome
            // no cartão; o resto vira contagem, e o perfil mostra todos.
            _StatChip(label: _walletLabel(p), color: AppColors.input),
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

  /// A carteira do produtor num selo de uma linha: "Carteira: João",
  /// "Carteira: João +1" quando ele é dividido, "sem consultor" quando o
  /// último vínculo caiu junto com a exclusão do consultor.
  String _walletLabel(ProducerModel p) {
    final nomes = AppData.consultantNamesFor(p);
    if (nomes.isEmpty) return 'Carteira: sem consultor';
    final primeiro = nomes.first.split(' ').first;
    return nomes.length == 1
        ? 'Carteira: $primeiro'
        : 'Carteira: $primeiro +${nomes.length - 1}';
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
          chips: [
            // A quem as permutas dele vão. É a informação que o admin procura
            // ao abrir esta lista depois de alguém perguntar "quem dá o parecer
            // das permutas do Roberto?".
            _StatChip(
              label: 'Gerente: ${v.managerName.isEmpty ? 'sem gerente' : v.managerName.split(' ').first}',
              color: AppColors.atManager,
            ),
            ..._statChips(bs),
          ],
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

  /// Os GERENTES. O cartão mostra as duas coisas que o admin precisa saber
  /// antes de mexer neles: o TAMANHO do time e o que está esperando parecer —
  /// que são exatamente as duas travas que o servidor aplica na exclusão.
  Widget _buildManagerList(List<UserModel> list) {
    if (list.isEmpty) return const _EmptyState(label: 'Nenhum gerente encontrado');
    return ListView.builder(
      key: const PageStorageKey('cadastros_gerentes'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final m = list[i];
        final team = AppData.consultants.where((c) => c.managerId == m.id).length;
        final waiting = AppData.opinionQueueFor(m.id).length;
        return _PersonCard(
          initials: m.avatarInitials,
          name: m.name,
          subtitle: m.branch,
          accent: AppColors.atManager,
          badgeIcon: Icons.assignment_ind,
          chips: [
            _StatChip(label: '$team consultor(es)', color: AppColors.input),
            if (waiting > 0)
              _StatChip(label: '$waiting esperando parecer', color: AppColors.atManager),
          ],
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EditStaffScreen(user: m, role: UserRole.manager),
              ),
            );
            if (mounted) setState(() {});
          },
        );
      },
    );
  }

  /// As UNIDADES de retirada. O cartão mostra quantas permutas são retiradas em
  /// cada uma — que é a leitura de logística da lista, e a única pergunta que
  /// ela responde: a unidade não tem dono nem participa da revisão.
  Widget _buildUnitList(List<UnitModel> list) {
    if (list.isEmpty) return const _EmptyState(label: 'Nenhuma unidade encontrada');
    return ListView.builder(
      key: const PageStorageKey('cadastros_unidades'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final u = list[i];
        final pickups = AppData.barters.where((b) => b.unitId == u.id).length;
        final staff = AppData.consultants.where((c) => c.unitId == u.id).length;
        return _PersonCard(
          initials: u.avatarInitials,
          name: u.name,
          subtitle: u.city,
          accent: AppColors.primaryMedium,
          badgeIcon: Icons.store,
          chips: [
            _StatChip(label: '$pickups retirada(s)', color: AppColors.primary),
            if (staff > 0) _StatChip(label: '$staff consultor(es)', color: AppColors.input),
          ],
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => EditUnitScreen(unit: u)),
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
  final atManager = bs.where((b) => b.awaitsManager).length;
  return [
    _StatChip(label: '${bs.length} permutas', color: AppColors.primary),
    if (approved > 0) _StatChip(label: '$approved aprov.', color: AppColors.approved),
    if (pending > 0) _StatChip(label: '$pending revisão', color: AppColors.pending),
    // A etapa nova precisa de contagem própria: somada a "revisão", ela
    // esconderia justamente o que ainda não saiu da mesa do gerente.
    if (atManager > 0) _StatChip(label: '$atManager no gerente', color: AppColors.atManager),
  ];
}

class _SegmentedToggle extends StatelessWidget {
  final _Registry tab;
  final Map<_Registry, int> counts;
  final ValueChanged<_Registry> onChanged;
  const _SegmentedToggle({
    required this.tab,
    required this.counts,
    required this.onChanged,
  });

  /// Rótulo, ícone e cor de cada segmento, em um lugar só. Com três abas, a
  /// forma anterior (um bloco por segmento, copiado) já era o começo de uma
  /// lista escrita à mão.
  static const _segments = {
    _Registry.producers: ('Produtores', Icons.agriculture),
    _Registry.consultants: ('Consultores', Icons.badge),
    _Registry.managers: ('Gerentes', Icons.assignment_ind),
    _Registry.units: ('Unidades', Icons.store),
  };

  Color _accentOf(_Registry registry) => switch (registry) {
        _Registry.producers => AppColors.primary,
        _Registry.consultants => AppColors.input,
        _Registry.managers => AppColors.atManager,
        _Registry.units => AppColors.primaryMedium,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.disabledBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final entry in _segments.entries)
            Expanded(
              child: _seg(
                label: entry.value.$1,
                icon: entry.value.$2,
                count: counts[entry.key] ?? 0,
                selected: tab == entry.key,
                accent: _accentOf(entry.key),
                onTap: () => onChanged(entry.key),
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
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [BoxShadow(color: accent.withValues(alpha: 0.30), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        // Com QUATRO segmentos, ícone + rótulo + contagem lado a lado não cabe
        // num celular estreito, e o `ellipsis` comia o rótulo até sobrar uma
        // letra. Empilhar (ícone em cima, rótulo e contagem embaixo) devolve a
        // largura ao texto, e o FittedBox garante que nada estoure quando o
        // nome for longo ou a fonte do sistema for maior.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: selected ? AppColors.onPrimary : AppColors.textMedium),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? AppColors.onPrimary : AppColors.textMedium,
                      )),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.onPrimary.withValues(alpha: 0.25)
                          : AppColors.textLight.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: selected ? AppColors.onPrimary : AppColors.textMedium,
                        )),
                  ),
                ],
              ),
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
                        style: TextStyle(color: AppColors.onPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
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
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 4, children: chips),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textLight),
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
          Icon(Icons.search_off, size: 48, color: AppColors.textLight),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: AppColors.textLight)),
        ],
      ),
    );
  }
}
