import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class FilterChipData {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const FilterChipData({required this.label, required this.selected, required this.onTap});
}

/// Barra de filtros: os recortes como chips que rolam na horizontal e a
/// ordenação num menu à direita.
///
/// Chip e menu respondem a perguntas diferentes — "o que eu quero ver" e "em
/// que ordem" —, e é por isso que não são a mesma lista: misturar os dois num
/// seletor só obrigaria a escolher entre filtrar e ordenar.
class FilterBar<T> extends StatelessWidget {
  final List<FilterChipData> chips;
  final String sortLabel;
  final Map<T, String> sortOptions;
  final T current;
  final ValueChanged<T> onSort;

  const FilterBar({
    super.key,
    required this.chips,
    required this.sortLabel,
    required this.sortOptions,
    required this.current,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 6, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final chip in chips) ...[
                    ChoiceChip(
                      label: Text(chip.label, style: const TextStyle(fontSize: 12)),
                      selected: chip.selected,
                      onSelected: (_) => chip.onTap(),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          PopupMenuButton<T>(
            tooltip: 'Ordenar',
            initialValue: current,
            onSelected: onSort,
            itemBuilder: (_) => [
              for (final entry in sortOptions.entries)
                PopupMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_vert, size: 16, color: AppColors.primary),
                  const SizedBox(width: 2),
                  Text(sortLabel,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
