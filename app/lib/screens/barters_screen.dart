import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../theme/app_theme.dart';
import '../models/barter_simulation.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../widgets/common_widgets.dart';
import 'barter_detail_screen.dart';
import 'barter_screen.dart';
import 'send_simulation.dart';

class BartersScreen extends StatefulWidget {
  /// Visão de RETAGUARDA: todas as permutas, com os valores em R$.
  final bool isAdmin;
  final String? consultantId;

  /// O CONSULTOR LOGADO, quando esta é a tela dele.
  ///
  /// Preenchido, liga a aba de SIMULAÇÕES — as permutas que ele montou e ainda
  /// não enviou. Vem como usuário inteiro, e não só o id, porque retomar uma
  /// simulação abre o construtor de permuta, e ele precisa saber a carteira e o
  /// gerente de quem está montando.
  ///
  /// Só o consultor tem simulações: elas moram NESTE aparelho e a permuta nasce
  /// em nome de quem a envia. Gerente e admin nunca veem trabalho que ainda não
  /// foi entregue.
  final UserModel? consultant;

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
    this.consultant,
    this.opinionManagerId,
    this.onChanged,
  });
  @override
  State<BartersScreen> createState() => _BartersScreenState();
}

class _BartersScreenState extends State<BartersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _search = '';

  /// A aba de simulações só existe para o consultor logado — ver
  /// [BartersScreen.consultant].
  bool get _hasSimulations => widget.consultant != null;

  /// AS ABAS DESTA PESSOA: uma por etapa que ela ENXERGA, na ordem da linha de
  /// produção. `null` é a aba "Todas".
  ///
  /// Não são as mesmas para todo mundo. O faturista alcança só o que chegou ao
  /// faturamento (`barters.readInvoicing` no servidor), e abas "No gerente" e
  /// "No comitê" na tela dele eram portas para cômodos onde ele não entra: o
  /// servidor responde vazio, e quem olha não sabe se não há permuta nenhuma ou
  /// se o app não carregou. "Todas" sai junto — com duas etapas, ela seria a
  /// soma das duas que estão ao lado.
  ///
  /// Quem decide o recorte continua sendo o servidor; esta lista só evita
  /// desenhar o que ele não vai responder.
  late final List<BarterStatus?> _statuses = AppData.can(Capability.bartersReadInvoicing)
      ? const [BarterStatus.approved, BarterStatus.invoiced]
      : const [
          null,
          // Na ordem da LINHA DE PRODUÇÃO: gerente → comitê → faturamento. A
          // lista lida da esquerda para a direita conta o caminho da permuta, e
          // é por isso que "Negadas" fica no fim: ela é saída lateral, não um
          // degrau adiante.
          BarterStatus.sentToManager,
          BarterStatus.pending,
          BarterStatus.approved,
          BarterStatus.invoiced,
          BarterStatus.denied,
        ];

  String _tabLabel(BarterStatus? status) => switch (status) {
        null => 'Todas',
        BarterStatus.sentToManager => 'No gerente',
        BarterStatus.pending => 'No comitê',
        BarterStatus.approved => 'A faturar',
        BarterStatus.invoiced => 'Faturadas',
        BarterStatus.denied => 'Negadas',
      };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _statuses.length + (_hasSimulations ? 1 : 0),
      vsync: this,
      initialIndex: _initialTab(),
    );
  }

  /// A aba em que cada um ENTRA: a lista que pede ação dele.
  ///
  /// O gerente cai na fila de pareceres, o comitê na de decisões, o faturista no
  /// que há para faturar e o consultor nas simulações que ainda precisa enviar.
  /// Quem não tem posto na linha entra em "Todas" — abrir numa lista vazia seria
  /// esconder o histórico atrás de uma tela em branco, que é o caso do admin.
  ///
  /// A ordem das perguntas segue a da linha de produção, e nenhum papel tem duas
  /// (ver a tabela de capacidades no servidor).
  int _initialTab() {
    // A aba de simulações, quando existe, vem antes de "Todas" e empurra todas
    // as outras uma casa.
    final offset = _hasSimulations ? 1 : 0;
    if (_hasSimulations && AppData.mySimulations.isNotEmpty) return 0;

    final BarterStatus? mine = widget.opinionManagerId != null
        ? BarterStatus.sentToManager
        : AppData.can(Capability.bartersReview)
            ? BarterStatus.pending
            : AppData.can(Capability.bartersInvoice)
                ? BarterStatus.approved
                : null;
    // A posição vem da LISTA de abas, e não de um número contado à mão: quem
    // tem menos abas continua entrando na etapa dele.
    final at = _statuses.indexOf(mine);
    return at < 0 ? offset : offset + at;
  }

  /// Simulações do consultor, filtradas pela mesma busca das outras abas.
  List<BarterSimulation> get _filteredSimulations {
    final all = AppData.mySimulations;
    if (_search.isEmpty) return all;
    final query = _search.toLowerCase();
    return all
        .where(
          (item) =>
              item.producerName.toLowerCase().contains(query) ||
              item.unitName.toLowerCase().contains(query),
        )
        .toList();
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
          .where(
            (b) =>
                b.id.toLowerCase().contains(q) ||
                b.producerName.toLowerCase().contains(q) ||
                b.consultantName.toLowerCase().contains(q),
          )
          .toList();
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isAdmin ? brand.copy.barterPluralTitle : 'Minhas ${brand.copy.barterPluralTitle}',
        ),
        actions: const [LogoutButton()],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: [
            // Antes de "Todas" porque é onde o fluxo COMEÇA: a permuta é
            // montada, guardada e só então enviada ao gerente. A fila lida da
            // esquerda para a direita conta o caminho dela.
            if (_hasSimulations) Tab(text: 'Simulações (${_filteredSimulations.length})'),
            for (final status in _statuses)
              Tab(text: '${_tabLabel(status)} (${_filtered(status).length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_hasSimulations) const OfflineBanner(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Buscar por código ou produtor...',
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
                if (_hasSimulations)
                  _SimulationList(
                    simulations: _filteredSimulations,
                    consultant: widget.consultant!,
                    onChanged: _onChanged,
                  ),
                for (final status in _statuses)
                  _BarterList(
                    barters: _filtered(status),
                    isAdmin: widget.isAdmin,
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
  final String? opinionManagerId;
  final VoidCallback onChanged;
  const _BarterList({
    required this.barters,
    required this.isAdmin,
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
            Text(
              'Nenhuma ${brand.copy.barter} encontrada',
              style: TextStyle(color: AppColors.textLight),
            ),
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
        opinionManagerId: opinionManagerId,
        onChanged: onChanged,
      ),
    );
  }
}

class _BarterCard extends StatelessWidget {
  final BarterModel barter;
  final bool isAdmin;
  final String? opinionManagerId;
  final VoidCallback onChanged;
  const _BarterCard({
    required this.barter,
    required this.isAdmin,
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
                  Text(
                    barter.id,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
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
                    Text(
                      barter.producerName,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMedium,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Vend.: ${barter.consultantName}',
                        style: TextStyle(fontSize: 11, color: AppColors.textLight),
                        overflow: TextOverflow.ellipsis,
                      ),
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
                  Text(
                    formatDate(barter.createdAt),
                    style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.store_outlined, size: 13, color: AppColors.textLight),
                  const SizedBox(width: 4),
                  // O local de retirada fica na linha da data porque é dele que
                  // vem a pergunta mais repetida do dia a dia — "onde esse
                  // produtor vai buscar?" — e ela não deveria custar abrir o
                  // detalhe de cada permuta da lista.
                  Expanded(
                    child: Text(
                      barter.unitLabel,
                      style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (barter.awaitsOpinionFrom(opinionManagerId)) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        giveBarterOpinion(context, barter, onGiven: (_) => onChanged()),
                    icon: const Icon(Icons.rate_review_outlined, size: 16),
                    label: const Text('Dar parecer', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.atManager,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
              // A DECISÃO e o FATURAMENTO, cada um oferecido a quem tem a
              // capacidade e só quando a permuta está no posto certo. Quem
              // responde às duas perguntas é o servidor: a primeira pelas
              // capacidades do usuário, a segunda pelo estado da permuta.
              if (AppData.can(Capability.bartersReview) && barter.awaitsCommittee) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => reviewBarter(
                          context,
                          barter,
                          BarterStatus.denied,
                          onReviewed: (_) => onChanged(),
                        ),
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
                        onPressed: () => reviewBarter(
                          context,
                          barter,
                          BarterStatus.approved,
                          onReviewed: (_) => onChanged(),
                        ),
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
              if (AppData.can(Capability.bartersInvoice) && barter.awaitsInvoice) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        invoiceBarter(context, barter, onInvoiced: (_) => onChanged()),
                    icon: const Icon(Icons.receipt_long_outlined, size: 16),
                    label: const Text('Faturar', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.invoiced,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
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
  const _SidePill({
    required this.icon,
    required this.accent,
    required this.title,
    required this.value,
  });

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
                Text(
                  title,
                  style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A aba de SIMULAÇÕES: as permutas que o consultor montou e ainda não enviou.
///
/// É a única lista destas telas que não vem da API — ela é lida do aparelho, e
/// por isso continua respondendo sem sinal. O vazio dela explica para que serve,
/// em vez de só informar que não há nada: quem chega aqui pela primeira vez não
/// tem como saber que toda permuta agora começa como simulação.
class _SimulationList extends StatelessWidget {
  final List<BarterSimulation> simulations;
  final UserModel consultant;
  final VoidCallback onChanged;

  const _SimulationList({
    required this.simulations,
    required this.consultant,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (simulations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmark_border, size: 64, color: AppColors.divider),
              const SizedBox(height: 12),
              Text(
                'Nenhuma simulação guardada',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Monte a permuta em "Nova ${brand.copy.barterTitle}" e guarde. A '
                'simulação fica neste aparelho e funciona sem internet — o envio '
                'ao gerente pode ser feito na hora ou aqui, quando você tiver sinal.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textMedium),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: simulations.length,
      itemBuilder: (context, index) => _SimulationCard(
        simulation: simulations[index],
        consultant: consultant,
        onChanged: onChanged,
      ),
    );
  }
}

class _SimulationCard extends StatefulWidget {
  final BarterSimulation simulation;
  final UserModel consultant;
  final VoidCallback onChanged;

  const _SimulationCard({
    required this.simulation,
    required this.consultant,
    required this.onChanged,
  });

  @override
  State<_SimulationCard> createState() => _SimulationCardState();
}

class _SimulationCardState extends State<_SimulationCard> {
  bool _busy = false;

  BarterSimulation get simulation => widget.simulation;

  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewBarterScreen(consultant: widget.consultant, simulation: simulation),
      ),
    );
    if (changed == true) widget.onChanged();
  }

  /// Encaminha esta simulação ao gerente. O caminho inteiro — conferir o que
  /// mudou, confirmar, registrar — mora em `send_simulation.dart`, porque o
  /// construtor de permuta oferece o mesmo envio logo depois de guardar.
  Future<void> _send() async {
    setState(() => _busy = true);
    await sendSimulationToManager(
      context,
      simulation: simulation,
      consultant: widget.consultant,
      onChanged: widget.onChanged,
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_outline, color: AppColors.denied, size: 40),
        title: const Text('Descartar simulação?'),
        content: Text(
          'A permuta de ${simulation.producerName} que você montou será apagada '
          'deste aparelho. Não dá para desfazer.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Descartar', style: TextStyle(color: AppColors.denied)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppData.deleteSimulation(simulation.id);
    if (mounted) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    // Os primeiros itens direto no cartão: a simulação é o que o consultor abre
    // na frente do produtor, e obrigá-lo a entrar na tela de edição para ler o
    // que montou custaria uma tela em branco quando não houver sinal.
    const preview = 3;
    final shown = simulation.items.take(preview).toList();
    final rest = simulation.items.length - shown.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy ? null : _edit,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      simulation.producerName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.pendingBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Não enviada',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.pending,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    for (final item in shown)
                      DialogLine(
                        item.productName.isEmpty ? item.productId : item.productName,
                        '${formatQty(item.quantity)} ${item.unit}',
                      ),
                    if (rest > 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '+ $rest insumo(s)',
                            style: TextStyle(fontSize: 11, color: AppColors.textLight),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.grass, size: 13, color: AppColors.grain),
                  const SizedBox(width: 4),
                  // "Simulado" e não "Total": este número é o do dia em que ela
                  // foi montada, e o envio pode devolver outro. Chamá-lo de
                  // total seria prometer o que só o servidor decide.
                  Expanded(
                    child: Text(
                      'Simulado: ${formatSacks(simulation.simulatedSacks)}'
                      '${simulation.grainName.isEmpty ? '' : ' ${simulation.grainName.toLowerCase()}'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.store_outlined, size: 13, color: AppColors.textLight),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      simulation.unitName.isEmpty ? '—' : simulation.unitName,
                      style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.schedule, size: 13, color: AppColors.textLight),
                  const SizedBox(width: 4),
                  Text(
                    formatDate(simulation.updatedAt),
                    style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  IconButton(
                    onPressed: _busy ? null : _delete,
                    icon: Icon(Icons.delete_outline, size: 20, color: AppColors.denied),
                    tooltip: 'Descartar',
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _edit,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Editar', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _send,
                      icon: _busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_outlined, size: 16),
                      label: Text(
                        _busy ? 'Conferindo...' : 'Encaminhar',
                        style: const TextStyle(fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.atManager,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
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
