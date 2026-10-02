import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/dashboard_stats.dart';
import '../services/api/api_client.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/common_widgets.dart';
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
    // POR SAFRA DA CULTURA, e não só por grão: cada safra é um Barter à parte,
    // com a sua meta e o seu encerramento.
    final grainEntries = sacksBySeason(stats.closed);
    final seasonStats = statsBySeason(AppData.barters);
    final branchEntries = sacksByBranch(stats.closed);
    final inputEntries = topInputs(stats.closed);

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

            // Estrela do painel: o compromisso de entrega de grãos das aprovadas.
            _ReceivableHero(
              sacks: stats.sacksReceivable,
              value: stats.grainValue,
              approvedCount: stats.closedCount,
              pendingSacks: stats.pendingSacks,
              pendingCount: stats.pendingCount,
              onTapPending: () => onNavigate(1),
            ),
            const SizedBox(height: 16),

            _InsightStrip(
              insumosValue: stats.inputsValue,
              activeProducers: stats.activeProducers,
              avgSacks: stats.averageSacks,
            ),
            const SizedBox(height: 20),

            // Os dois lados da mesma história — o insumo retirado, que origina o
            // custo, e a saca que vai cobri-lo. Lidos juntos quando a tela
            // permite; empilhados quando não permite.
            if (inputEntries.isNotEmpty || grainEntries.isNotEmpty) ...[
              AdaptiveColumns(
                children: [
                  if (inputEntries.isNotEmpty)
                    _DashboardSection(
                      title: '${brand.copy.inputPluralTitle} Mais Retirados',
                      child: _RankingBars(
                          entries: inputEntries,
                          formatValue: formatCurrency,
                          color: AppColors.input),
                    ),
                  if (grainEntries.isNotEmpty)
                    _DashboardSection(
                      title: 'Sacas a Receber por Safra',
                      child: _GrainBreakdownCard(
                          entries: grainEntries, total: stats.sacksReceivable),
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],

            // O PAINEL POR CULTURA: os mesmos números do topo, safra a safra.
            if (seasonStats.length > 1) ...[
              Text('Por Safra',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              const SizedBox(height: 12),
              _SeasonStatsCard(entries: seasonStats),
              const SizedBox(height: 20),
            ],

            Text('${brand.copy.barterPluralTitle} por Status',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 12),
            _StatusBreakdownCard(
              atManager: stats.atManagerCount,
              pending: stats.pendingCount,
              toInvoice: stats.toInvoice,
              invoiced: stats.invoiced,
              denied: stats.denied,
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // "Ver todas" leva à aba Filas, onde o admin também decide.
                Text('No Comitê, Esperando Decisão',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                TextButton(
                  onPressed: () => onNavigate(1),
                  child: Text('Ver todas', style: TextStyle(fontSize: 12, color: AppColors.primaryMedium)),
                ),
              ],
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

            // O rodapé do painel: o volume por filial e o que andou. Nenhum dos
            // dois pede ação, e é por isso que podem dividir a mesma faixa.
            AdaptiveColumns(
              children: [
                if (branchEntries.isNotEmpty)
                  _DashboardSection(
                    title: 'Volume por Filial',
                    child: _RankingBars(
                        entries: branchEntries,
                        formatValue: formatSacks,
                        color: AppColors.primaryAccent),
                  ),
                _DashboardSection(
                  title: 'Atividade Recente',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: AppData.barters
                        .where((b) => b.status != BarterStatus.pending)
                        .take(3)
                        .map((b) => MiniBarterCard(barter: b, isAdmin: true))
                        .toList(),
                  ),
                ),
              ],
            ),
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

/// Um bloco do painel: o título e o que ele apresenta.
///
/// Existe para o bloco poder virar coluna dentro de [AdaptiveColumns] — solto na
/// lista, o título e o conteúdo eram dois irmãos separados por um `SizedBox`, e
/// não havia o que colocar lado a lado.
class _DashboardSection extends StatelessWidget {
  final String title;
  final Widget child;
  const _DashboardSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

/// Cor do grão [i] no painel (soja, milho, trigo, aveia...). A série vem da
/// marca ativa e é cíclica, então qualquer grão cadastrado ganha cor sem
/// prender o app à soja — e sem prender o painel à paleta de um cliente.
Color _grainColor(int i) => AppColors.series(i);

/// Cartão-herói: as sacas a receber (compromisso de entrega das permutas
/// aprovadas) como número-estrela, com o valor em R$ e o potencial parado no comitê.
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
                          ? '$pendingCount no comitê • +${formatSacks(pendingSacks)} se aprovadas'
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

/// Mix das sacas a receber por grão: barra empilhada + legenda com sacas e %.
class _GrainBreakdownCard extends StatelessWidget {
  final List<StatSlice> entries;
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
                    child: Text(entries[i].label,
                        style: TextStyle(fontSize: 13, color: AppColors.textDark, fontWeight: FontWeight.w500)),
                  ),
                  Text(formatSacks(entries[i].value),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 42,
                    child: Text(
                      total > 0 ? '${(entries[i].value / total * 100).round()}%' : '0%',
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
  final List<StatSlice> entries;
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
                        child: Text(entries[i].label,
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

class _StatusBreakdownCard extends StatelessWidget {
  final int atManager, pending, toInvoice, invoiced, denied;
  const _StatusBreakdownCard({
    required this.atManager,
    required this.pending,
    required this.toInvoice,
    required this.invoiced,
    required this.denied,
  });

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
                    // Na ordem do fluxo, e não na do tamanho: a barra lida da
                    // esquerda para a direita conta o caminho da permuta.
                    if (atManager > 0)
                      Expanded(flex: atManager, child: Container(color: AppColors.atManager)),
                    if (pending > 0) Expanded(flex: pending, child: Container(color: AppColors.pending)),
                    if (toInvoice > 0)
                      Expanded(flex: toInvoice, child: Container(color: AppColors.approved)),
                    if (invoiced > 0)
                      Expanded(flex: invoiced, child: Container(color: AppColors.invoiced)),
                    if (denied > 0) Expanded(flex: denied, child: Container(color: AppColors.denied)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceAround,
              spacing: 12,
              runSpacing: 8,
              children: [
                _LegendItem(color: AppColors.atManager, label: 'No Gerente', count: atManager),
                _LegendItem(color: AppColors.pending, label: 'No Comitê', count: pending),
                _LegendItem(color: AppColors.approved, label: 'A Faturar', count: toInvoice),
                _LegendItem(color: AppColors.invoiced, label: 'Faturadas', count: invoiced),
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
    // `MainAxisSize.min` nos dois eixos, e não por economia: o [Wrap] que
    // hospeda a legenda entrega a cada item a largura INTEIRA do cartão como
    // folga. Com o `Row` no padrão (`max`), cada item esticava até a borda,
    // caía sozinho numa linha e empurrava o número para o meio do cartão —
    // cinco linhas de legenda no lugar da faixa única que o `spaceAround`
    // pressupõe.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
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


/// O PAINEL POR CULTURA — uma linha por safra, com o que fechou, o que espera e
/// as sacas que ela tem a receber.
class _SeasonStatsCard extends StatelessWidget {
  final List<({String label, BarterStats stats})> entries;
  const _SeasonStatsCard({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            for (final (index, entry) in entries.indexed) ...[
              if (index > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.grass, size: 18, color: AppColors.grain),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.label,
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                          Text(
                            '${entry.stats.closedCount} fechada(s) • '
                            '${entry.stats.pendingCount} no comitê • '
                            '${entry.stats.atManagerCount} no gerente',
                            style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(formatSacks(entry.stats.sacksReceivable),
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.grain)),
                        Text('sc a receber', style: TextStyle(fontSize: 10, color: AppColors.textLight)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
