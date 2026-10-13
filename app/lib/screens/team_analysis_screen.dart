import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../services/api/api_client.dart';
import '../services/dashboard_stats.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dashboard_widgets.dart';

/// As etapas que a Análise mede por consultor: as três por onde a permuta passa
/// ANTES da decisão — a montagem dele, o parecer do gerente e a decisão do
/// comitê. Daí em diante (apólice, nota, cédula) o relógio é de postos que não
/// dependem do consultor, e compará-los por consultor seria comparar a fila da
/// seguradora.
const _teamStages = [BarterStage.assembly, BarterStage.opinion, BarterStage.decision];

/// Por qual número a lista de consultores se ordena.
enum _SortBy { sacks, area, investment, count, name }

String _sortLabel(_SortBy sort) {
  switch (sort) {
    case _SortBy.sacks:
      return 'Sacas';
    case _SortBy.area:
      return 'Área';
    case _SortBy.investment:
      return 'sc/ha';
    case _SortBy.count:
      return 'Permutas';
    case _SortBy.name:
      return 'Nome';
  }
}

/// A ANÁLISE DO GERENTE — os consultores do time dele, lado a lado.
///
/// O painel de início mostra a FILA dele (o que espera o parecer); esta aba
/// mostra o TIME: quanto cada consultor fechou, em quanta área, com que
/// investimento por hectare, e quanto tempo as permutas dele levam em cada
/// etapa. É a mesma conta de todo painel (`services/dashboard_stats.dart`),
/// recortada por consultor.
///
/// Os consultores saem das permutas que o servidor entregou a ele — ver
/// [analysisByConsultant] —, então a aba enxerga exatamente o que ele enxerga.
class TeamAnalysisTab extends StatefulWidget {
  final UserModel user;
  const TeamAnalysisTab({super.key, required this.user});

  @override
  State<TeamAnalysisTab> createState() => _TeamAnalysisTabState();
}

class _TeamAnalysisTabState extends State<TeamAnalysisTab> {
  _SortBy _sort = _SortBy.sacks;

  Future<void> _refresh() async {
    try {
      await AppData.refreshAll();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
    if (mounted) setState(() {});
  }

  /// O número pelo qual [_sort] ordena — e que a barra de cada cartão mede.
  double _metric(ConsultantAnalysis a) {
    switch (_sort) {
      case _SortBy.sacks:
        return a.stats.sacksReceivable;
      case _SortBy.area:
        return a.stats.area;
      case _SortBy.investment:
        return a.stats.investmentPerHa ?? 0;
      case _SortBy.count:
        return a.barters.length.toDouble();
      case _SortBy.name:
        return 0;
    }
  }

  List<ConsultantAnalysis> _sorted(List<ConsultantAnalysis> rows) {
    if (_sort == _SortBy.name) return rows;
    return rows.toList()..sort((a, b) => _metric(b).compareTo(_metric(a)));
  }

  @override
  Widget build(BuildContext context) {
    final team = AppData.barters;
    final teamStats = statsOf(team);
    final rows = _sorted(analysisByConsultant(team));
    final max = rows.isEmpty ? 0.0 : rows.map(_metric).reduce((a, b) => a > b ? a : b);

    return Scaffold(
      appBar: AppBar(
        title: const MainAppBarTitle('Análise'),
        actions: [
          const ChangePasswordButton(),
          const LogoutButton(),
          AppBarUserAvatar(user: widget.user),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primary,
        child: BoundedContent(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // O TIME INTEIRO primeiro: é contra ele que cada consultor se lê.
              StatStrip(cells: [
                StatStripCell(
                  icon: Icons.badge_outlined,
                  color: AppColors.primary,
                  value: '${rows.length}',
                  label: rows.length == 1 ? 'Consultor' : 'Consultores',
                ),
                StatStripCell(
                  icon: Icons.landscape_outlined,
                  color: AppColors.primary,
                  value: areaLabelOf(teamStats.area),
                  label: 'Área do time',
                  detail: 'em aprovadas',
                ),
                StatStripCell(
                  icon: Icons.straighten,
                  color: AppColors.primaryAccent,
                  value: formatInvestment(teamStats.investmentPerHa),
                  label: 'Investimento médio',
                ),
                StatStripCell(
                  icon: Icons.grass,
                  color: AppColors.grain,
                  value: formatSacks(teamStats.sacksReceivable),
                  label: 'Sacas',
                  detail: 'em aprovadas',
                ),
              ]),
              const SizedBox(height: 20),
              DashboardSectionTitle('Consultores'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Ordenar por', style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
                  for (final sort in _SortBy.values)
                    ChoiceChip(
                      label: Text(_sortLabel(sort), style: const TextStyle(fontSize: 12)),
                      selected: _sort == sort,
                      onSelected: (_) => setState(() => _sort = sort),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Nenhuma ${brand.copy.barter} do time chegou até você ainda.',
                      style: TextStyle(fontSize: 13, color: AppColors.textMedium),
                    ),
                  ),
                )
              else
                for (final row in rows)
                  _ConsultantCard(
                    analysis: row,
                    // A barra mede o número da ordenação contra o maior do time:
                    // é ela que deixa a comparação ser lida sem ler os números.
                    share: _sort == _SortBy.name || max <= 0 ? null : _metric(row) / max,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ConsultantAnalysisScreen(
                            consultantId: row.id,
                            consultantName: row.name,
                            user: widget.user,
                          ),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                  ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Um consultor na comparação: o funil, os três números e o tempo nas etapas.
class _ConsultantCard extends StatelessWidget {
  final ConsultantAnalysis analysis;

  /// A fração do maior do time no número da ordenação; null sem barra.
  final double? share;
  final VoidCallback onTap;

  const _ConsultantCard({required this.analysis, required this.share, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final stats = analysis.stats;
    final present = [
      for (final phase in backOfficePhases)
        if ((analysis.phases[phase] ?? 0) > 0) phase,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: AppShape.card,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(analysis.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  ),
                  Text(
                    '${analysis.barters.length} '
                    '${analysis.barters.length == 1 ? 'permuta' : 'permutas'}',
                    style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: AppColors.textLight),
                ],
              ),
              if (share != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: share,
                    minHeight: 5,
                    backgroundColor: AppColors.primarySurface,
                    valueColor: AlwaysStoppedAnimation(AppColors.primaryAccent),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [
                  _Metric(label: 'Área', value: areaLabelOf(stats.area)),
                  _Metric(label: 'Sacas', value: formatSacks(stats.sacksReceivable)),
                  _Metric(label: 'Investimento', value: formatInvestment(stats.investmentPerHa)),
                ],
              ),
              if (present.isNotEmpty) ...[
                const SizedBox(height: 10),
                PhaseBreakdown(counts: analysis.phases, phases: present, dense: true),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  for (final stage in _teamStages)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule, size: 12, color: AppColors.textLight),
                        const SizedBox(width: 3),
                        Text('${_shortStage(stage)} ',
                            style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
                        Text(formatDays(analysis.averageDays(stage)),
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A etapa num rótulo de uma palavra, para caber na linha do cartão.
String _shortStage(BarterStage stage) {
  switch (stage) {
    case BarterStage.assembly:
      return 'Montagem';
    case BarterStage.opinion:
      return 'Parecer';
    case BarterStage.decision:
      return 'Comitê';
    default:
      return stageLabel(stage);
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textDark)),
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
      ],
    );
  }
}

/// UM CONSULTOR ABERTO: os números dele contra os do time, o tempo de cada
/// etapa e as permutas que os compõem.
///
/// Recalcula a cada desenho a partir do cache, e não de uma fotografia passada
/// pela lista: o gerente abre uma permuta daqui, dá o parecer, e volta — o
/// funil e os tempos precisam já ter andado.
class ConsultantAnalysisScreen extends StatefulWidget {
  final String consultantId;
  final String consultantName;
  final UserModel user;

  const ConsultantAnalysisScreen({
    super.key,
    required this.consultantId,
    required this.consultantName,
    required this.user,
  });

  @override
  State<ConsultantAnalysisScreen> createState() => _ConsultantAnalysisScreenState();
}

class _ConsultantAnalysisScreenState extends State<ConsultantAnalysisScreen> {
  @override
  Widget build(BuildContext context) {
    final team = AppData.barters;
    final mine = ofConsultant(team, widget.consultantId)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final stats = statsOf(mine);
    final teamStats = statsOf(team);

    return Scaffold(
      appBar: AppBar(title: Text(widget.consultantName)),
      body: BoundedContent(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            StatStrip(cells: [
              StatStripCell(
                icon: Icons.swap_horiz,
                color: AppColors.primary,
                value: '${mine.length}',
                label: brand.copy.barterPluralTitle,
              ),
              StatStripCell(
                icon: Icons.landscape_outlined,
                color: AppColors.primary,
                value: areaLabelOf(stats.area),
                label: 'Área',
                detail: 'time: ${areaLabelOf(teamStats.area)}',
              ),
              StatStripCell(
                icon: Icons.straighten,
                color: AppColors.primaryAccent,
                value: formatInvestment(stats.investmentPerHa),
                label: 'Investimento médio',
                detail: 'time: ${formatInvestment(teamStats.investmentPerHa)}',
              ),
              StatStripCell(
                icon: Icons.grass,
                color: AppColors.grain,
                value: formatSacks(stats.sacksReceivable),
                label: 'Sacas',
                detail: 'time: ${formatSacks(teamStats.sacksReceivable)}',
              ),
            ]),
            const SizedBox(height: 20),
            DashboardSectionTitle('${brand.copy.barterPluralTitle} por Status'),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PhaseBreakdown(counts: phaseCounts(mine), phases: backOfficePhases),
              ),
            ),
            const SizedBox(height: 20),
            DashboardSectionTitle('Tempo nas Etapas'),
            const SizedBox(height: 12),
            _StageTimesCard(
              stages: BarterStage.values,
              mine: mine,
              team: team,
            ),
            const SizedBox(height: 20),
            DashboardSectionTitle('${brand.copy.barterPluralTitle} do Consultor'),
            const SizedBox(height: 12),
            if (mine.isEmpty)
              Text('Nenhuma permuta.', style: TextStyle(fontSize: 13, color: AppColors.textMedium))
            else
              for (final barter in mine)
                MiniBarterCard(
                  barter: barter,
                  isAdmin: true,
                  opinionManagerId: widget.user.can(Capability.bartersOpinion) ? widget.user.id : null,
                  onChanged: () {
                    if (mounted) setState(() {});
                  },
                ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// O TEMPO MÉDIO DE CADA ETAPA para o consultor, com o do time ao lado.
///
/// O número sozinho não diz se é muito: "4 dias no comitê" é lento num time em
/// que a média é 1 e rápido num em que é 10. As etapas por onde nenhuma
/// permuta dele passou ficam de fora.
class _StageTimesCard extends StatelessWidget {
  final List<BarterStage> stages;
  final List<BarterModel> mine;
  final List<BarterModel> team;

  const _StageTimesCard({required this.stages, required this.mine, required this.team});

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final stage in stages)
        (stage: stage, mine: averageStageDays(mine, stage), team: averageStageDays(team, stage)),
    ].where((r) => r.mine != null).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: rows.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Nenhuma permuta concluiu uma etapa ainda.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMedium)),
              )
            : Column(
                children: [
                  for (final (index, row) in rows.indexed) ...[
                    if (index > 0) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(stageLabel(row.stage),
                                style: TextStyle(fontSize: 13, color: AppColors.textDark)),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(formatDays(row.mine),
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: _paceColor(row.mine!, row.team))),
                              Text('time: ${formatDays(row.team)}',
                                  style: TextStyle(fontSize: 10, color: AppColors.textLight)),
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

  /// Mais lento que o time pinta de alerta; o resto, na cor de texto.
  static Color _paceColor(double mine, double? team) =>
      team != null && mine > team * 1.25 ? AppColors.pending : AppColors.textDark;
}
