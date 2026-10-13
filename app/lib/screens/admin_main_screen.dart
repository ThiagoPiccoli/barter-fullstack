import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/dashboard_stats.dart';
import '../services/api/api_client.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dashboard_widgets.dart';
import 'barters_screen.dart';
import 'barter_detail_screen.dart';
import 'prices_screen.dart';
import 'consultants_screen.dart';
import 'back_office_main_screen.dart';

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
      // As filas dos quatro postos da linha: o admin tem todas as capacidades,
      // e age em qualquer etapa.
      WorkQueuesTab(user: widget.admin, onQueueChanged: () => setState(() {})),
      BartersScreen(isAdmin: true, consultantId: null, onChanged: () => setState(() {})),
      const PricesScreen(),
      const ConsultantsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveNavScaffold(
      user: widget.admin,
      selectedIndex: _selectedIndex,
      onSelect: (i) => setState(() => _selectedIndex = i),
      body: IndexedStack(index: _selectedIndex, children: _screens),
      destinations: [
        const AdaptiveDestination(
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard,
          label: 'Dashboard',
        ),
        AdaptiveDestination(
          icon: Icons.inbox_outlined,
          activeIcon: Icons.inbox,
          label: 'Filas',
          badgeCount: workQueuesCount(widget.admin),
        ),
        AdaptiveDestination(
          icon: Icons.swap_horiz_outlined,
          activeIcon: Icons.swap_horiz,
          label: brand.copy.barterPluralTitle,
        ),
        AdaptiveDestination(
          icon: Icons.price_change_outlined,
          activeIcon: Icons.price_change,
          label: brand.copy.programTitle,
        ),
        const AdaptiveDestination(
          icon: Icons.groups_outlined,
          activeIcon: Icons.groups,
          label: 'Cadastros',
        ),
      ],
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
    // OS NÚMEROS DO PAINEL saem de `services/dashboard_stats.dart`, e não
    // daqui: quem conta como negócio fechado, como as permutas se agrupam e há
    // quanto tempo a fila espera são decisões de DOMÍNIO — "faturada ainda
    // conta como aprovada" é regra, não layout. Dentro do `build` elas eram
    // reescritas a cada mudança de tela e não tinham teste fora do widget.
    final stats = statsOf(AppData.barters);
    final phases = phaseCounts(AppData.barters);
    final visible = backOfficePhases.where((p) => (phases[p] ?? 0) > 0).toList();
    final total = visible.fold(0, (sum, p) => sum + phases[p]!);

    return Scaffold(
      appBar: AppBar(
        title: const MainAppBarTitle('Dashboard'),
        actions: [
          const ChangePasswordButton(),
          const LogoutButton(),
          AppBarUserAvatar(user: admin),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primary,
        child: BoundedContent(
          child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DashboardHeader(
              greetingName: admin.name.split(' ')[0],
              subtitle: 'Central de ${brand.copy.barterPluralTitle} • ${_todayDate()}',
              icon: Icons.admin_panel_settings,
            ),
            const SizedBox(height: 16),

            // Estrela do painel: a ÁREA FEITA — a lavoura que as permutas
            // fechadas cobrem — e o investimento médio por hectare dela. As
            // sacas a receber continuam no cartão, como a outra ponta da conta.
            _AreaHero(
              stats: stats,
              pendingArea: areaOf(stats.pending),
              onTapPending: () => onNavigate(1),
            ),
            const SizedBox(height: 16),

            // A OPERAÇÃO NUM OLHAR: cada número com o seu desdobramento ao lado.
            // Os rankings (insumos, safras, filiais) e as fases moravam em
            // blocos espalhados pelo painel, e quem lia "R$ 293 mil em insumos"
            // tinha de rolar até achar QUAIS insumos.
            KpiGrid(tiles: [
              KpiTile(
                icon: Icons.swap_horiz,
                color: AppColors.primary,
                label: '${brand.copy.barterPluralTitle} por status',
                value: '$total',
                caption: 'na linha de produção',
                onTap: () => onNavigate(2),
                child: visible.isEmpty
                    ? null
                    : PhaseBreakdown(counts: phases, phases: visible, dense: true),
              ),
              KpiTile(
                icon: Icons.science_outlined,
                color: AppColors.input,
                label: '${brand.copy.inputPluralTitle} liberados',
                value: formatCompactCurrency(stats.inputsValue),
                caption: 'em ${stats.closedCount} permutas aprovadas',
                child: rankingBars(
                  topInputs(stats.closed),
                  format: formatCompactCurrency,
                  color: AppColors.input,
                  empty: 'Nenhum insumo liberado ainda.',
                ),
              ),
              KpiTile(
                icon: Icons.agriculture,
                color: AppColors.primary,
                label: 'Produtores ativos',
                value: '${stats.activeProducers}',
                caption: 'com permuta aprovada • os que mais devem',
                child: rankingBars(
                  sacksByProducer(stats.closed),
                  format: formatSacks,
                  color: AppColors.primaryAccent,
                  empty: 'Nenhum produtor com permuta aprovada.',
                ),
              ),
              KpiTile(
                icon: Icons.grass,
                color: AppColors.grain,
                label: 'Ticket médio',
                value: formatSacks(stats.averageSacks),
                caption: 'por permuta aprovada',
                child: KpiFacts(facts: [
                  KpiFact('Área média', areaLabelOf(stats.averageArea)),
                  KpiFact('Insumos por permuta', formatCompactCurrency(stats.averageInputsValue)),
                  KpiFact('Investimento médio', formatInvestment(stats.investmentPerHa)),
                  KpiFact('No comitê', '${stats.pendingCount} • ${formatSacks(stats.pendingSacks)}'),
                ]),
              ),
              KpiTile(
                icon: Icons.eco_outlined,
                color: AppColors.grain,
                label: 'Sacas a receber por safra',
                value: formatSacks(stats.sacksReceivable),
                caption: '≈ ${formatCompactCurrency(stats.grainValue)} na colheita',
                child: seasonSacksBars(AppData.barters),
              ),
              KpiTile(
                icon: Icons.store_outlined,
                color: AppColors.primaryAccent,
                label: 'Volume por filial',
                value: '${sacksByBranch(stats.closed).length}',
                caption: 'filiais com permuta aprovada',
                child: rankingBars(
                  sacksByBranch(stats.closed),
                  format: formatSacks,
                  color: AppColors.primaryAccent,
                  empty: 'Nenhuma permuta aprovada ainda.',
                ),
              ),
            ]),
            const SizedBox(height: 24),

            // O QUE PEDE AÇÃO fica embaixo dos números, em lista: é para abrir
            // uma a uma, e não para ler de relance.
            DashboardSectionTitle(
              'No Comitê, Esperando Decisão',
              // "Ver todas" leva à aba Filas, onde o admin também decide.
              trailing: TextButton(
                onPressed: () => onNavigate(1),
                child: Text('Ver todas', style: TextStyle(fontSize: 12, color: AppColors.primaryMedium)),
              ),
            ),
            const SizedBox(height: 8),
            if (stats.pending.isEmpty)
              const _EmptyHint(
                icon: Icons.check_circle_outline,
                text: 'Nenhuma permuta esperando o comitê. Tudo em dia!',
              )
            else
              ...stats.pending.map((b) => _PendingActionCard(barter: b)),
            const SizedBox(height: 20),

            DashboardSectionTitle('Atividade Recente'),
            const SizedBox(height: 12),
            ...AppData.barters
                .where((b) => b.status != BarterStatus.pending)
                .take(3)
                .map((b) => MiniBarterCard(barter: b, isAdmin: true)),
            const SizedBox(height: 16),
          ],
          ),
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

/// Cartão-herói: a ÁREA FEITA — os hectares de lavoura que as permutas
/// aprovadas cobrem — como número-estrela, com o investimento médio por hectare
/// ao lado, as sacas a receber embaixo e o que ainda está parado no comitê.
///
/// A área entrou no lugar das sacas porque é a medida que se compara entre
/// culturas: sacas de soja e de milho não somam, hectares somam. As sacas não
/// saíram do cartão — são o numerador do investimento, e é por isso que ficam
/// logo abaixo dele.
class _AreaHero extends StatelessWidget {
  final BarterStats stats;
  final double pendingArea;
  final VoidCallback onTapPending;
  const _AreaHero({
    required this.stats,
    required this.pendingArea,
    required this.onTapPending,
  });

  @override
  Widget build(BuildContext context) {
    final perHa = stats.investmentPerHa;
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
              Text('Área Total Feita',
                  style: TextStyle(color: AppColors.onPrimaryMuted, fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.onPrimaryOverlay,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${stats.closedCount} aprovadas',
                    style: TextStyle(color: AppColors.onPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                areaLabelOf(stats.area),
                style: TextStyle(color: AppColors.onPrimary, fontSize: 34, fontWeight: FontWeight.w800),
              ),
              if (perHa != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatSacksPerHa(perHa),
                          style: TextStyle(
                              color: AppColors.onPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                      Text('investimento médio',
                          style: TextStyle(color: AppColors.onPrimarySubtle, fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ),
          Text(
            '${formatSacks(stats.sacksReceivable)} a receber '
            '≈ ${formatCurrency(stats.grainValue)} em grãos na colheita',
            style: TextStyle(color: AppColors.onPrimarySubtle, fontSize: 12),
          ),
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
                      stats.pendingCount > 0
                          ? '${stats.pendingCount} no comitê • +${areaLabelOf(pendingArea)} se aprovadas'
                          : 'Nenhuma permuta esperando o comitê',
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

/// Card de permuta parada no comitê, com o tempo de espera ("há X dias")
/// destacado. Quanto mais antiga, mais quente a cor.
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
          // O trilho acompanha a altura da identificação, que tem duas ou três
          // linhas conforme quem lê recebe a área e o investimento.
          child: IntrinsicHeight(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(color: urgency, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: BarterIdentity(
                  barter: barter,
                  trailing: Container(
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
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                      barter.hasSacks
                          ? formatSacks(barter.sacksToDeliver)
                          : 'a definir',
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
