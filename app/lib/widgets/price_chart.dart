import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

const _months = ['', 'jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

/// Gráfico de linha da evolução do valor de um produto.
/// Em [mini] vira um sparkline (sem eixos/labels) para usar dentro de cards.
class PriceLineChart extends StatelessWidget {
  final List<PriceHistoryEntry> history;
  final Color color;
  final bool mini;
  final bool animate;
  const PriceLineChart({
    super.key,
    required this.history,
    required this.color,
    this.mini = false,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final values = history.map((e) => e.price).toList();
    if (!animate) {
      return CustomPaint(
        painter: _ChartPainter(history: history, color: color, mini: mini, progress: 1),
        child: const SizedBox.expand(),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 950),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => CustomPaint(
        painter: _ChartPainter(history: history, color: color, mini: mini, progress: t),
        child: const SizedBox.expand(),
      ),
      key: ValueKey(values.length),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<PriceHistoryEntry> history;
  final Color color;
  final bool mini;
  final double progress;

  _ChartPainter({
    required this.history,
    required this.color,
    required this.mini,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    final values = history.map((e) => e.price).toList();
    double lo = values.reduce((a, b) => a < b ? a : b);
    double hi = values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 0.0001) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.18;
    lo -= pad;
    hi += pad;

    final left = mini ? 0.0 : 46.0;
    final right = mini ? 0.0 : 14.0;
    final top = mini ? 4.0 : 14.0;
    final bottom = mini ? 4.0 : 26.0;
    final plotW = size.width - left - right;
    final plotH = size.height - top - bottom;
    final n = values.length;

    double xAt(int i) => n == 1 ? left + plotW / 2 : left + (i / (n - 1)) * plotW;
    double yAt(double v) => top + (1 - (v - lo) / (hi - lo)) * plotH;

    // Grade horizontal + labels do eixo Y (apenas modo completo)
    if (!mini) {
      final gridPaint = Paint()
        ..color = AppColors.divider.withValues(alpha: 0.25)
        ..strokeWidth = 1;
      const lines = 4;
      for (int g = 0; g <= lines; g++) {
        final v = lo + (hi - lo) * (g / lines);
        final y = yAt(v);
        canvas.drawLine(Offset(left, y), Offset(size.width - right, y), gridPaint);
        _text(canvas, _short(v), Offset(0, y - 6), 9, AppColors.textLight, maxWidth: left - 6, alignRight: true);
      }
      // Labels do eixo X (meses)
      for (int i = 0; i < n; i++) {
        if (n > 7 && i.isOdd) continue;
        final d = history[i].changedAt;
        _text(canvas, _months[d.month], Offset(xAt(i) - 12, size.height - 14), 9, AppColors.textLight,
            maxWidth: 24, center: true);
      }
    }

    // Pontos completos e ponto interpolado conforme progress
    final fullPoints = [for (int i = 0; i < n; i++) Offset(xAt(i), yAt(values[i]))];
    final drawn = _pointsUpTo(fullPoints, progress);

    // Área preenchida com gradiente
    if (drawn.length >= 2) {
      final areaPath = Path()..moveTo(drawn.first.dx, size.height - bottom);
      for (final p in drawn) {
        areaPath.lineTo(p.dx, p.dy);
      }
      areaPath.lineTo(drawn.last.dx, size.height - bottom);
      areaPath.close();
      final areaPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: mini ? 0.28 : 0.34), color.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTWH(0, top, size.width, plotH));
      canvas.drawPath(areaPath, areaPaint);
    }

    // Linha
    final linePath = Path();
    for (int i = 0; i < drawn.length; i++) {
      if (i == 0) {
        linePath.moveTo(drawn[i].dx, drawn[i].dy);
      } else {
        linePath.lineTo(drawn[i].dx, drawn[i].dy);
      }
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = mini ? 2.2 : 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Pontos
    final visibleCount = (progress * (n - 1)).floor() + 1;
    if (!mini) {
      for (int i = 0; i < visibleCount && i < n; i++) {
        final p = fullPoints[i];
        canvas.drawCircle(p, 3.5, Paint()..color = Colors.white);
        canvas.drawCircle(p, 3.5, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2);
      }
    }

    // Ponto atual destacado + balão de valor (modo completo)
    if (progress > 0.985) {
      final last = fullPoints.last;
      canvas.drawCircle(last, mini ? 3 : 5.5, Paint()..color = color);
      canvas.drawCircle(last, mini ? 3 : 5.5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
      if (!mini) {
        canvas.drawCircle(last, 9, Paint()..color = color.withValues(alpha: 0.18));
      }
    }
  }

  /// Pontos da polilinha até [progress] (0–1), com o último segmento interpolado.
  List<Offset> _pointsUpTo(List<Offset> pts, double progress) {
    final n = pts.length;
    if (n <= 1 || progress >= 1) return pts;
    if (progress <= 0) return [pts.first];
    final pos = progress * (n - 1);
    final idx = pos.floor();
    final frac = pos - idx;
    final result = pts.sublist(0, idx + 1);
    if (idx < n - 1) {
      final a = pts[idx];
      final b = pts[idx + 1];
      result.add(Offset(a.dx + (b.dx - a.dx) * frac, a.dy + (b.dy - a.dy) * frac));
    }
    return result;
  }

  void _text(Canvas canvas, String s, Offset at, double size, Color color,
      {double? maxWidth, bool alignRight = false, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth ?? double.infinity);
    var dx = at.dx;
    if (alignRight && maxWidth != null) dx = at.dx + (maxWidth - tp.width);
    if (center && maxWidth != null) dx = at.dx + (maxWidth - tp.width) / 2;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  String _short(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1).replaceAll('.', ',')}k';
    return v.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.progress != progress || old.history != history || old.color != color;
}
