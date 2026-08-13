import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/api/api_client.dart';
import '../widgets/common_widgets.dart';
import '../branding/brand_wordmark.dart';
import 'barters_screen.dart';
import 'barter_detail_screen.dart';
import 'prices_screen.dart';
import 'consultants_screen.dart';

class AdminMainScreen extends StatefulWidget {
  final UserModel admin;
  const AdminMainScreen({super.key, required this.admin});
  @override
  State<AdminMainScreen> createState() => _AdminMainScreenState();
}

class _AdminMainScreenState extends State<AdminMainScreen> {
  int _selectedIndex = 0;

  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      _AdminDashboardTab(admin: widget.admin, onNavigate: (i) => setState(() => _selectedIndex = i)),
      const BartersScreen(isAdmin: true, consultantId: null),
      const PricesScreen(),
      const ConsultantsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textLight,
        selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.swap_horiz_outlined), activeIcon: const Icon(Icons.swap_horiz), label: brand.copy.barterPluralTitle),
          BottomNavigationBarItem(icon: Icon(Icons.price_change_outlined), activeIcon: Icon(Icons.price_change), label: 'Valores'),
          BottomNavigationBarItem(icon: Icon(Icons.groups_outlined), activeIcon: Icon(Icons.groups), label: 'Cadastros'),
        ],
      ),
    );
  }
}

class _AdminDashboardTab extends StatefulWidget {
  final UserModel admin;
  final Function(int) onNavigate;
  const _AdminDashboardTab({required this.admin, required this.onNavigate});

  @override
  State<_AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends State<_AdminDashboardTab> {
  UserModel get admin => widget.admin;
  Function(int) get onNavigate => widget.onNavigate;

  /// Puxar para atualizar: recarrega tudo da API e redesenha o painel.
  Future<void> _refresh() async {
    try {
      await AppData.refreshAll();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final approvedList = AppData.barters.where((b) => b.status == BarterStatus.approved).toList();
    // Pendentes da mais antiga para a mais nova: são a fila de "ação necessária".
    final pendingList = AppData.barters.where((b) => b.status == BarterStatus.pending).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final approved = approvedList.length;
    final pending = pendingList.length;
    final denied = AppData.barters.where((b) => b.status == BarterStatus.denied).length;

    // Sacas a receber: o grão que os produtores entregarão pelas permutas
    // aprovadas — o "a receber" da empresa, em saca, na colheita.
    final sacksReceivable = approvedList.fold<double>(0, (s, b) => s + b.totalGrainQty);
    final grainValue = approvedList.fold<double>(0, (s, b) => s + b.grainCredit);
    final inputsValue = approvedList.fold<double>(0, (s, b) => s + b.inputCost);
    // Sacas ainda em análise (potencial a entrar se aprovadas).
    final pendingSacks = pendingList.fold<double>(0, (s, b) => s + b.totalGrainQty);
    // Produtores distintos com permuta aprovada.
    final activeProducers = approvedList.map((b) => b.producerId).toSet().length;

    // Sacas a receber agrupadas por grão de pagamento (soja, milho, trigo...).
    final byGrain = <String, double>{};
    for (final b in approvedList) {
      final name = b.referenceGrainName.isEmpty ? '—' : b.referenceGrainName;
      byGrain[name] = (byGrain[name] ?? 0) + b.totalGrainQty;
    }
    final grainEntries = byGrain.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // Volume (sacas) por filial do consultor.
    final byBranch = <String, double>{};
    for (final b in approvedList) {
      byBranch[b.consultantBranch] = (byBranch[b.consultantBranch] ?? 0) + b.totalGrainQty;
    }
    final branchEntries = byBranch.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // Insumos mais retirados (R$) nas permutas aprovadas — o lado insumo da
    // história, que origina o custo e, por consequência, as sacas.
    final byInput = <String, double>{};
    for (final b in approvedList) {
      for (final it in b.inputs) {
        byInput[it.productName] = (byInput[it.productName] ?? 0) + it.total;
      }
    }
    final topInputs = (byInput.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .toList();

    // Ticket médio em sacas por permuta aprovada.
    final avgSacks = approved > 0 ? sacksReceivable / approved : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const BrandWordmark(size: 32, showTagline: false),
        actions: [
          const ChangePasswordButton(),
          const LogoutButton(),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              backgroundColor: AppColors.primaryAccent,
              radius: 18,
              child: Text(admin.avatarInitials,
                  style: TextStyle(color: AppColors.onPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primary,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DashboardHeader(
              greetingName: admin.name.split(' ')[0],
              subtitle: 'Central de ${brand.copy.barterPluralTitle} • ${_todayDate()}',
              icon: Icons.admin_panel_settings,
            ),
            const SizedBox(height: 16),

            // Estrela do painel: o compromisso de entrega de grãos das aprovadas.
            _ReceivableHero(
              sacks: sacksReceivable,
              value: grainValue,
              approvedCount: approved,
              pendingSacks: pendingSacks,
              pendingCount: pending,
              onTapPending: () => onNavigate(1),
            ),
            const SizedBox(height: 16),

            _InsightStrip(
              insumosValue: inputsValue,
              activeProducers: activeProducers,
              avgSacks: avgSacks,
            ),
            const SizedBox(height: 20),

            if (topInputs.isNotEmpty) ...[
              Text('${brand.copy.inputPluralTitle} Mais Retirados',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              const SizedBox(height: 12),
              _RankingBars(entries: topInputs, formatValue: formatCurrency, color: AppColors.input),
              const SizedBox(height: 20),
            ],

            if (grainEntries.isNotEmpty) ...[
              Text('Sacas a Receber por ${brand.copy.grainTitle}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              const SizedBox(height: 12),
              _GrainBreakdownCard(entries: grainEntries, total: sacksReceivable),
              const SizedBox(height: 20),
            ],

            Text('${brand.copy.barterPluralTitle} por Status',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 12),
            _StatusBreakdownCard(approved: approved, pending: pending, denied: denied),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Pendentes – Ação Necessária',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                TextButton(
                  onPressed: () => onNavigate(1),
                  child: Text('Ver todas', style: TextStyle(fontSize: 12, color: AppColors.primaryMedium)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (pendingList.isEmpty)
              const _EmptyHint(
                icon: Icons.check_circle_outline,
                text: 'Nenhuma permuta aguardando revisão. Tudo em dia!',
              )
            else
              ...pendingList.map((b) => _PendingActionCard(barter: b)),
            const SizedBox(height: 20),

            if (branchEntries.isNotEmpty) ...[
              Text('Volume por Filial',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              const SizedBox(height: 12),
              _RankingBars(entries: branchEntries, formatValue: formatSacks, color: AppColors.primaryAccent),
              const SizedBox(height: 20),
            ],

            Text('Atividade Recente',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 12),
            ...AppData.barters
                .where((b) => b.status != BarterStatus.pending)
                .take(3)
                .map((b) => MiniBarterCard(barter: b, isAdmin: true)),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _todayDate() {
    final now = DateTime.now();
    const months = ['', 'jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
    return '${now.day} ${months[now.month]} ${now.year}';
  }
}

/// Cor do grão [i] no painel (soja, milho, trigo, aveia...). A série vem da
/// marca ativa e é cíclica, então qualquer grão cadastrado ganha cor sem
/// prender o app à soja — e sem prender o painel à paleta de um cliente.
Color _grainColor(int i) => AppColors.series(i);

/// Cartão-herói: as sacas a receber (compromisso de entrega das permutas
/// aprovadas) como número-estrela, com o valor em R$ e o potencial em análise.
class _ReceivableHero extends StatelessWidget {
  final double sacks;
  final double value;
  final int approvedCount;
  final double pendingSacks;
  final int pendingCount;
  final VoidCallback onTapPending;
  const _ReceivableHero({
    required this.sacks,
    required this.value,
    required this.approvedCount,
    required this.pendingSacks,
    required this.pendingCount,
    required this.onTapPending,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Sacas a Receber',
                  style: TextStyle(color: AppColors.onPrimaryMuted, fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.onPrimaryOverlay,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$approvedCount aprovadas',
                    style: TextStyle(color: AppColors.onPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: formatSacks(sacks),
                style: TextStyle(color: AppColors.onPrimary, fontSize: 34, fontWeight: FontWeight.w800),
              ),
            ]),
          ),
          Text('≈ ${formatCurrency(value)} em grãos na colheita',
              style: TextStyle(color: AppColors.onPrimarySubtle, fontSize: 12)),
          const SizedBox(height: 14),
          InkWell(
            onTap: onTapPending,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.onPrimaryOverlay,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.hourglass_top, color: AppColors.onPrimaryMuted, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pendingCount > 0
                          ? '$pendingCount em análise • +${formatSacks(pendingSacks)} se aprovadas'
                          : 'Nenhuma permuta aguardando revisão',
                      style: TextStyle(color: AppColors.onPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.onPrimarySubtle, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mix das sacas a receber por grão: barra empilhada + legenda com sacas e %.
class _GrainBreakdownCard extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  final double total;
  const _GrainBreakdownCard({required this.entries, required this.total});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (var i = 0; i < entries.length; i++)
                      Expanded(
                        flex: (entries[i].value * 100).round().clamp(1, 1 << 30),
                        child: Container(color: _grainColor(i)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Row(
                children: [
                  Container(width: 10, height: 10,
                      decoration: BoxDecoration(color: _grainColor(i), shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(entries[i].key,
                        style: TextStyle(fontSize: 13, color: AppColors.textDark, fontWeight: FontWeight.w500)),
                  ),
                  Text(formatSacks(entries[i].value),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 42,
                    child: Text(
                      total > 0 ? '${(entries[i].value / total * 100).round()}%' : '—',
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 12, color: AppColors.textLight),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Moeda compacta para faixas estreitas: "R$ 125,2 mil" / "R$ 1,3 mi".
String _compactCurrency(double v) {
  String n(double x) => x.toStringAsFixed(1).replaceAll('.', ',');
  if (v >= 1000000) return 'R\$ ${n(v / 1000000)} mi';
  if (v >= 1000) return 'R\$ ${n(v / 1000)} mil';
  return formatCurrency(v);
}

/// Faixa enxuta de 3 indicadores secundários, separados por divisórias. Substitui
/// um grid de cards genéricos por algo compacto que não repete o herói/status.
class _InsightStrip extends StatelessWidget {
  final double insumosValue;
  final int activeProducers;
  final double avgSacks;
  const _InsightStrip({
    required this.insumosValue,
    required this.activeProducers,
    required this.avgSacks,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _StripCell(
                  icon: Icons.science_outlined,
                  color: AppColors.input,
                  value: _compactCurrency(insumosValue),
                  label: 'Insumos liberados',
                ),
              ),
              const VerticalDivider(width: 1, indent: 4, endIndent: 4),
              Expanded(
                child: _StripCell(
                  icon: Icons.agriculture,
                  color: AppColors.primary,
                  value: '$activeProducers',
                  label: 'Produtores ativos',
                ),
              ),
              const VerticalDivider(width: 1, indent: 4, endIndent: 4),
              Expanded(
                child: _StripCell(
                  icon: Icons.grass,
                  color: AppColors.grain,
                  value: formatSacks(avgSacks),
                  label: 'Ticket médio',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StripCell extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _StripCell({required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              maxLines: 1,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textDark)),
        ),
        const SizedBox(height: 2),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
      ],
    );
  }
}

/// Ranking genérico (filiais, insumos...) com barra proporcional ao maior valor.
/// [formatValue] decide se o valor sai em sacas, R$, etc.
class _RankingBars extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  final String Function(double) formatValue;
  final Color color;
  const _RankingBars({required this.entries, required this.formatValue, required this.color});

  @override
  Widget build(BuildContext context) {
    final max = entries.first.value;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(entries[i].key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
                      ),
                      const SizedBox(width: 8),
                      Text(formatValue(entries[i].value),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: max > 0 ? entries[i].value / max : 0,
                      minHeight: 7,
                      backgroundColor: AppColors.primarySurface,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Card de permuta pendente com o tempo de espera ("há X dias") destacado, para
/// priorizar a fila de revisão. Quanto mais antiga, mais quente a cor.
class _PendingActionCard extends StatelessWidget {
  final BarterModel barter;
  const _PendingActionCard({required this.barter});

  @override
  Widget build(BuildContext context) {
    final days = DateTime.now().difference(barter.createdAt).inDays;
    final urgency = days >= 14
        ? AppColors.denied
        : days >= 7
            ? AppColors.pending
            : AppColors.primaryMedium;
    final waitLabel = days <= 0 ? 'hoje' : 'há $days dia${days == 1 ? '' : 's'}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BarterDetailScreen(barter: barter, isAdmin: true)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 46,
                decoration: BoxDecoration(color: urgency, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(barter.id,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: urgency.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.schedule, size: 11, color: urgency),
                              const SizedBox(width: 3),
                              Text(waitLabel,
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: urgency)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('${barter.consultantName} • ${barter.producerName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                      barter.referenceValue > 0
                          ? formatSacks(barter.sacksToDeliver)
                          : '—',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  Text(barter.referenceGrainName.toLowerCase(),
                      style: TextStyle(fontSize: 10, color: AppColors.textLight)),
                ],
              ),
              Icon(Icons.chevron_right, size: 18, color: AppColors.textLight),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aviso curto e amigável para seções vazias (ex.: nenhuma pendência).
class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: AppColors.approved, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 13, color: AppColors.textMedium)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBreakdownCard extends StatelessWidget {
  final int approved, pending, denied;
  const _StatusBreakdownCard({required this.approved, required this.pending, required this.denied});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    if (approved > 0) Expanded(flex: approved, child: Container(color: AppColors.approved)),
                    if (pending > 0) Expanded(flex: pending, child: Container(color: AppColors.pending)),
                    if (denied > 0) Expanded(flex: denied, child: Container(color: AppColors.denied)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _LegendItem(color: AppColors.approved, label: 'Aprovadas', count: approved),
                _LegendItem(color: AppColors.pending, label: 'Em Análise', count: pending),
                _LegendItem(color: AppColors.denied, label: 'Negadas', count: denied),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  const _LegendItem({required this.color, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
        ]),
        const SizedBox(height: 4),
        Text('$count', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }
}

