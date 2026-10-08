/// AS PEÇAS QUE OS PAINÉIS DIVIDEM — a barra de fases, a faixa de números e o
/// jeito de escrever dias e hectares.
///
/// Cada papel tem o seu painel, e eles se parecem de propósito: a área, o
/// investimento médio e as permutas por fase são lidos igual pelo admin, pelo
/// consultor, pelo comitê e pelo gerente. Um desenho por tela faria a mesma
/// barra ter cinco legendas diferentes. O que contar mora em
/// `services/dashboard_stats.dart`; aqui fica só como mostrar.
library;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/dashboard_stats.dart';
import '../theme/app_theme.dart';
import 'common_widgets.dart';

/// O nome da fase como se lê na legenda.
String phaseLabel(BarterPhase phase) {
  switch (phase) {
    case BarterPhase.draft:
      return 'Rascunho';
    case BarterPhase.atManager:
      return 'No gerente';
    case BarterPhase.atCommittee:
      return 'No comitê';
    case BarterPhase.requirements:
      return 'Exigências';
    case BarterPhase.atInsurer:
      return 'Na seguradora';
    case BarterPhase.toInvoice:
      return 'A faturar';
    case BarterPhase.invoiced:
      return 'Faturadas';
    case BarterPhase.registered:
      return 'CPR registrada';
    case BarterPhase.denied:
      return 'Negadas';
  }
}

/// A cor da fase — a mesma do selo da permuta na lista (ver [StatusBadge]).
Color phaseColor(BarterPhase phase) {
  switch (phase) {
    case BarterPhase.draft:
    case BarterPhase.requirements:
      return AppColors.draft;
    case BarterPhase.atManager:
      return AppColors.atManager;
    case BarterPhase.atCommittee:
      return AppColors.pending;
    case BarterPhase.atInsurer:
      return AppColors.atInsurer;
    case BarterPhase.toInvoice:
      return AppColors.approved;
    case BarterPhase.invoiced:
      return AppColors.invoiced;
    case BarterPhase.registered:
      return AppColors.primary;
    case BarterPhase.denied:
      return AppColors.denied;
  }
}

/// O nome da etapa como se lê — pelo POSTO que segura o relógio nela.
String stageLabel(BarterStage stage) {
  switch (stage) {
    case BarterStage.assembly:
      return 'Montagem (consultor)';
    case BarterStage.opinion:
      return 'Parecer (gerente)';
    case BarterStage.decision:
      return 'Decisão (comitê)';
    case BarterStage.policy:
      return 'Apólice (seguradora)';
    case BarterStage.invoicing:
      return 'Faturamento';
    case BarterStage.cprIssue:
      return 'Emitir a cédula';
    case BarterStage.cprSignature:
      return 'Colher assinaturas';
    case BarterStage.cprRegistration:
      return 'Registrar';
  }
}

/// As fases que a RETAGUARDA enxerga — todas menos o rascunho, que é do
/// consultor até ele encaminhar.
const backOfficePhases = [
  BarterPhase.atManager,
  BarterPhase.atCommittee,
  BarterPhase.requirements,
  BarterPhase.atInsurer,
  BarterPhase.toInvoice,
  BarterPhase.invoiced,
  BarterPhase.registered,
  BarterPhase.denied,
];

/// Dias como se lê: "menos de 1 dia", "1 dia", "2,5 dias". Null é "sem
/// medida" — a etapa por onde nenhuma permuta passou ainda.
String formatDays(double? days) {
  if (days == null) return '—';
  if (days < 1) return 'menos de 1 dia';
  final rounded = (days * 10).round() / 10;
  return rounded == 1 ? '1 dia' : '${formatQty(rounded)} dias';
}

/// O investimento médio, ou um traço quando não há o que dividir.
String formatInvestment(double? perHa) => perHa == null ? '—' : formatSacksPerHa(perHa);

/// A BARRA DAS FASES: as permutas da esquerda para a direita, na ordem da
/// linha, e a legenda com o número de cada uma.
///
/// [phases] diz quais fases a legenda mostra — inclusive as vazias, para a
/// legenda não mudar de forma de um dia para o outro. Quem não enxerga uma fase
/// (a retaguarda não vê rascunho) simplesmente não a recebe.
class PhaseBreakdown extends StatelessWidget {
  final Map<BarterPhase, int> counts;
  final List<BarterPhase> phases;

  /// A legenda compacta — rótulo e número numa linha só, para caber dentro de
  /// um cartão que já tem outro assunto (o total de permutas do consultor).
  final bool dense;

  const PhaseBreakdown({
    super.key,
    required this.counts,
    this.phases = BarterPhase.values,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final shown = [for (final phase in phases) (phase: phase, count: counts[phase] ?? 0)];
    final total = shown.fold(0, (sum, e) => sum + e.count);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: dense ? 8 : 12,
            child: total == 0
                ? Container(color: AppColors.primarySurface)
                : Row(
                    children: [
                      for (final e in shown)
                        if (e.count > 0)
                          Expanded(flex: e.count, child: Container(color: phaseColor(e.phase))),
                    ],
                  ),
          ),
        ),
        SizedBox(height: dense ? 8 : 12),
        Wrap(
          alignment: dense ? WrapAlignment.start : WrapAlignment.spaceAround,
          spacing: dense ? 14 : 12,
          runSpacing: dense ? 4 : 8,
          children: [
            for (final e in shown)
              dense
                  ? _DenseLegendItem(phase: e.phase, count: e.count)
                  : _LegendItem(phase: e.phase, count: e.count),
          ],
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final BarterPhase phase;
  final int count;
  const _LegendItem({required this.phase, required this.count});

  @override
  Widget build(BuildContext context) {
    final color = phaseColor(phase);
    // `MainAxisSize.min` nos dois eixos: o [Wrap] entrega a cada item a largura
    // inteira do cartão como folga, e um `Row` esticado cairia sozinho numa
    // linha, empurrando o número para o meio.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(phaseLabel(phase), style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
        ]),
        const SizedBox(height: 4),
        Text('$count', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }
}

class _DenseLegendItem extends StatelessWidget {
  final BarterPhase phase;
  final int count;
  const _DenseLegendItem({required this.phase, required this.count});

  @override
  Widget build(BuildContext context) {
    final color = phaseColor(phase);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(phaseLabel(phase), style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
        const SizedBox(width: 4),
        Text('$count',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: count == 0 ? AppColors.textLight : AppColors.textDark)),
      ],
    );
  }
}

/// Um número da [StatStrip].
class StatStripCell {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  /// A conta por trás do número ("4.000 sc ÷ 320 ha"), em letra pequena.
  final String? detail;

  const StatStripCell({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.detail,
  });
}

/// A FAIXA DE NÚMEROS — três ou quatro indicadores lado a lado, num cartão só,
/// separados por divisórias.
class StatStrip extends StatelessWidget {
  final List<StatStripCell> cells;
  const StatStrip({super.key, required this.cells});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: IntrinsicHeight(
          child: Row(
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) const VerticalDivider(width: 1, indent: 4, endIndent: 4),
                Expanded(child: _StatStripCellView(cell: cells[i])),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatStripCellView extends StatelessWidget {
  final StatStripCell cell;
  const _StatStripCellView({required this.cell});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(cell.icon, color: cell.color, size: 18),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(cell.value,
                maxLines: 1,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textDark)),
          ),
          const SizedBox(height: 2),
          Text(cell.label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
          if (cell.detail != null) ...[
            const SizedBox(height: 2),
            Text(cell.detail!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: AppColors.textLight)),
          ],
        ],
      ),
    );
  }
}

/// A conta do investimento médio, escrita: "4.000 sc ÷ 320 ha". Só as permutas
/// que trazem o número entram nela — as mesmas de [investmentPerHaOf].
String investmentBasisOf(Iterable<BarterModel> barters) {
  final measured = barters.where((b) => b.sacksPerHa != null && b.plantedAreaHa > 0);
  return '${formatSacks(sacksOf(measured))} ÷ ${areaLabelOf(areaOf(measured))}';
}

/// Um título de bloco do painel.
class DashboardSectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const DashboardSectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final title = Text(text,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark));
    if (trailing == null) return title;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Flexible(child: title), trailing!],
    );
  }
}
