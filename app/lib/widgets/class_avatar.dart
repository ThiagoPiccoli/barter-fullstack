import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// A FIGURA de uma classe de produto.
///
/// Antes, todo insumo mostrava o mesmo frasco — 656 vezes na tabela de valores.
/// Um ícone que nunca muda não informa nada: ocupa a coluna onde o olho procura
/// diferença e não oferece nenhuma. Aqui cada classe tem a sua figura e a sua
/// cor, e a lista passa a ser varrida por bloco (herbicida, fungicida, adubo)
/// em vez de lida linha a linha.
///
/// A cor sai da paleta de séries da marca, indexada pela POSIÇÃO da classe: as
/// mesmas cores do painel, estáveis entre telas e entre sessões — a classe não
/// muda de cor porque a lista foi filtrada.
///
/// As classes vêm do arquivo do fornecedor, então esta tabela é por SLUG e tem
/// padrão: uma classe nova aparece com o ícone genérico de insumo, sem quebrar
/// nada, até alguém decidir a figura dela.
IconData iconForClass(String? slug) {
  switch (slug) {
    case 'herbicidas':
      return Icons.grass;
    case 'inseticidas':
      return Icons.pest_control;
    case 'fungicidas':
      return Icons.coronavirus_outlined;
    case 'fertilizantes':
      return Icons.grain;
    case 'fertilizantes-foliares':
      return Icons.spa_outlined;
    case 'oleos-e-adjuvantes':
      return Icons.water_drop_outlined;
    case 'inoculantes':
      return Icons.biotech_outlined;
    case 'sementes':
      return Icons.eco_outlined;
    case 'biologicos':
      return Icons.hive_outlined;
    case 'nutricao':
      return Icons.local_drink_outlined;
    case 'seguro-agricola':
      return Icons.verified_user_outlined;
    default:
      return Icons.science_outlined;
  }
}

/// A cor da classe. Sem classe (item ainda não classificado), o tom neutro de
/// insumo — o verde-azulado que o app já usa para "insumo em geral".
///
/// A `position` começa em 1 e a paleta em 0; classe sem posição definida cai no
/// primeiro tom, que é o que a paleta já usa para a primeira série.
Color colorForClass(ProductClassModel? productClass) {
  if (productClass == null) return AppColors.input;
  final index = productClass.position > 0 ? productClass.position - 1 : 0;
  return AppColors.series(index);
}

/// O quadrado com a figura da classe, do tamanho usado nas listas.
class ClassAvatar extends StatelessWidget {
  final ProductClassModel? productClass;
  final double size;

  const ClassAvatar({super.key, required this.productClass, this.size = 38});

  @override
  Widget build(BuildContext context) {
    final color = colorForClass(productClass);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      child: Icon(iconForClass(productClass?.slug), color: color, size: size * 0.52),
    );
  }
}
