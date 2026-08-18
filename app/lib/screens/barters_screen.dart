import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../widgets/common_widgets.dart';
import 'barter_detail_screen.dart';

class BartersScreen extends StatefulWidget {
  /// Visão de RETAGUARDA: todas as permutas, com os valores em R$.
  final bool isAdmin;
  final String? consultantId;

  /// Pode aprovar/negar. Ver [BarterDetailScreen.canReview]: gerente, comitê e
  /// faturista enxergam tudo, mas quem revisa hoje é só o admin.
  final bool canReview;

  /// Quem pode dar PARECER — o gerente logado. Quando preenchido, as permutas
  /// endereçadas a ele ganham o botão de parecer, e a aba "No gerente" abre
  /// primeiro: para ele, essa é a lista que pede ação.
  final String? opinionManagerId;

  /// Avisa a tela de cima que uma permuta mudou de estado.
  ///
  /// Existe por causa do selo de pendências na navegação: sem isto, dar um
  /// parecer por AQUI atualizava a lista e deixava o selo com o número velho —
  /// e um contador que mente é pior do que não ter contador.
  final VoidCallback? onChanged;

  const BartersScreen({
    super.key,
    required this.isAdmin,
    required this.consultantId,
    this.canReview = true,
    this.opinionManagerId,
    this.onChanged,
  });
  @override
  State<BartersScreen> createState() => _BartersScreenState();
}

class _BartersScreenState extends State<BartersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 5,
      vsync: this,
      // O gerente entra na fila dele; todo mundo entra em "Todas".
      initialIndex: widget.opinionManagerId != null ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Uma permuta mudou de estado: refaz a lista E avisa a tela de cima, que é
  /// quem desenha o selo de pendências da navegação.
  void _onChanged() {
    setState(() {});
    widget.onChanged?.call();
  }

  List<BarterModel> _filtered(BarterStatus? status) {
    var list = widget.isAdmin
        ? List<BarterModel>.from(AppData.barters)
        : AppData.barters.where((b) => b.consultantId == widget.consultantId).toList();
    if (status != null) list = list.where((b) => b.status == status).toList();
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((b) =>
              b.id.toLowerCase().contains(q) ||
              b.producerName.toLowerCase().contains(q) ||
              b.consultantName.toLowerCase().contains(q))
          .toList();
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin
            ? brand.copy.barterPluralTitle
            : 'Minhas ${brand.copy.barterPluralTitle}'),
        actions: const [LogoutButton()],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: 'Todas (${_filtered(null).length})'),
            // Na ordem do fluxo: a permuta passa pelo gerente ANTES da
            // revisão, e a lista lida da esquerda para a direita conta o
            // caminho dela.
            Tab(text: 'No gerente (${_filtered(BarterStatus.sentToManager).length})'),
            Tab(text: 'Revisão (${_filtered(BarterStatus.pending).length})'),
            Tab(text: 'Aprovadas (${_filtered(BarterStatus.approved).length})'),
            Tab(text: 'Negadas (${_filtered(BarterStatus.denied).length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: widget.isAdmin ? 'Buscar por código ou produtor...' : 'Buscar por código...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                for (final status in <BarterStatus?>[
                  null,
                  BarterStatus.sentToManager,
                  BarterStatus.pending,
                  BarterStatus.approved,
                  BarterStatus.denied,
                ])
                  _BarterList(
                    barters: _filtered(status),
                    isAdmin: widget.isAdmin,
                    canReview: widget.canReview,
                    opinionManagerId: widget.opinionManagerId,
                    onChanged: _onChanged,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarterList extends StatelessWidget {
  final List<BarterModel> barters;
  final bool isAdmin;
  final bool canReview;
  final String? opinionManagerId;
  final VoidCallback onChanged;
  const _BarterList({
    required this.barters,
    required this.isAdmin,
    required this.canReview,
    required this.onChanged,
    this.opinionManagerId,
  });

  @override
  Widget build(BuildContext context) {
    if (barters.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz, size: 64, color: AppColors.divider),
            const SizedBox(height: 12),
            Text('Nenhuma ${brand.copy.barter} encontrada', style: TextStyle(color: AppColors.textLight)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: barters.length,
      itemBuilder: (context, index) => _BarterCard(
        barter: barters[index],
        isAdmin: isAdmin,
        canReview: canReview,
        opinionManagerId: opinionManagerId,
        onChanged: onChanged,
      ),
    );
  }
}

class _BarterCard extends StatelessWidget {
  final BarterModel barter;
  final bool isAdmin;
  final bool canReview;
  final String? opinionManagerId;
  final VoidCallback onChanged;
  const _BarterCard({
    required this.barter,
    required this.isAdmin,
    required this.canReview,
    required this.onChanged,
    this.opinionManagerId,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BarterDetailScreen(
                barter: barter,
                isAdmin: isAdmin,
                canReview: canReview,
                opinionManagerId: opinionManagerId,
              ),
            ),
          );
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(barter.id,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const Spacer(),
                  StatusBadge(status: barter.status),
                ],
              ),
              if (isAdmin) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.person_outline, size: 14, color: AppColors.textLight),
                    const SizedBox(width: 4),
                    Text(barter.producerName,
                        style: TextStyle(fontSize: 12, color: AppColors.textMedium, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Vend.: ${barter.consultantName}',
                          style: TextStyle(fontSize: 11, color: AppColors.textLight),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              // Linha de troca: insumos retirados -> grãos que pagam
              Row(
                children: [
                  Expanded(
                    child: _SidePill(
                      icon: Icons.science_outlined,
                      accent: AppColors.input,
                      title: 'Insumos retirados',
                      value: isAdmin
                          ? formatCurrency(barter.inputCost)
                          : '${barter.inputs.length} item(ns)',
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward, size: 16, color: AppColors.textLight),
                  ),
                  Expanded(
                    child: _SidePill(
                      icon: Icons.grass,
                      accent: AppColors.grain,
                      title: 'Paga com ${barter.referenceGrainName.toLowerCase()}',
                      value: formatSacks(barter.sacksToDeliver),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.textLight),
                  const SizedBox(width: 4),
                  Text(formatDate(barter.createdAt),
                      style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
                  const SizedBox(width: 10),
                  Icon(Icons.store_outlined, size: 13, color: AppColors.textLight),
                  const SizedBox(width: 4),
                  // O local de retirada fica na linha da data porque é dele que
                  // vem a pergunta mais repetida do dia a dia — "onde esse
                  // produtor vai buscar?" — e ela não deveria custar abrir o
                  // detalhe de cada permuta da lista.
                  Expanded(
                    child: Text(barter.unitLabel,
                        style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              if (barter.awaitsOpinionFrom(opinionManagerId)) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => giveBarterOpinion(context, barter,
                        onGiven: (_) => onChanged()),
                    icon: const Icon(Icons.rate_review_outlined, size: 16),
                    label: const Text('Dar parecer', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.atManager,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
              if (isAdmin && canReview && barter.status == BarterStatus.pending) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => reviewBarter(context, barter, BarterStatus.denied,
                            onReviewed: (_) => onChanged()),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Negar', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.denied,
                          side: BorderSide(color: AppColors.denied),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => reviewBarter(context, barter, BarterStatus.approved,
                            onReviewed: (_) => onChanged()),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Aprovar', style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.approved,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SidePill extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String value;
  const _SidePill({required this.icon, required this.accent, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                    overflow: TextOverflow.ellipsis),
                Text(value,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
