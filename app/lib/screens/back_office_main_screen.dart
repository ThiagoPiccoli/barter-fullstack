import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../branding/brand_wordmark.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../services/api/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'barter_detail_screen.dart';
import 'barters_screen.dart';

/// Casa dos papéis de RETAGUARDA — gerente, comitê e faturista.
///
/// Os três são POSTOS da mesma linha de produção, e é por isso que continuam
/// numa tela só: o que muda entre eles é a fila que pede ação e a palavra da
/// etapa, não o desenho da tela. Quem descreve cada posto é [_Post], e o resto
/// daqui é igual para os três.
///
/// A visão é a mesma (a operação com valores em R$); o que cada um pode FAZER
/// vem das capacidades que o servidor concedeu — nunca de um `if` por papel.
class BackOfficeMainScreen extends StatefulWidget {
  final UserModel user;
  const BackOfficeMainScreen({super.key, required this.user});

  @override
  State<BackOfficeMainScreen> createState() => _BackOfficeMainScreenState();
}

class _BackOfficeMainScreenState extends State<BackOfficeMainScreen> {
  int _selectedIndex = 0;

  /// O PARECER é do gerente A QUEM a permuta foi enviada, então esta tela
  /// precisa saber quem está olhando — as outras duas etapas não têm
  /// destinatário (a fila delas é o estado da permuta), e por isso não passam
  /// nada adiante: quem decide se a ação aparece é a capacidade.
  String? get _opinionManagerId =>
      widget.user.can(Capability.bartersOpinion) ? widget.user.id : null;

  late final List<Widget> _screens = [
    _BackOfficeHomeTab(user: widget.user, onQueueChanged: () => setState(() {})),
    // A retaguarda vê as permutas com valores (isAdmin). QUAIS ela vê é decidido
    // pelo servidor — o gerente recebe só as do time dele —, e o que ela pode
    // fazer, pelas capacidades.
    BartersScreen(
      isAdmin: true,
      consultantId: null,
      opinionManagerId: _opinionManagerId,
      onChanged: () => setState(() {}),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // O que espera AÇÃO DE QUEM ESTÁ OLHANDO — o parecer do gerente, a decisão
    // do comitê, o faturamento do faturista. Vira o número do selo na navegação:
    // o trabalho precisa se anunciar de qualquer aba, e não só quando a pessoa
    // pensa em ir procurar.
    final post = _Post.of(widget.user);
    final waiting = post?.queue.length ?? 0;

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
          const BottomNavigationBarItem(
            icon: Icon(Icons.insights_outlined),
            activeIcon: Icon(Icons.insights),
            label: 'Início',
          ),
          BottomNavigationBarItem(
            icon: _PendingBadge(
                count: waiting, color: post?.color, child: const Icon(Icons.swap_horiz_outlined)),
            activeIcon: _PendingBadge(
                count: waiting, color: post?.color, child: const Icon(Icons.swap_horiz)),
            label: brand.copy.barterPluralTitle,
          ),
        ],
      ),
    );
  }
}

/// Selo com a contagem do que espera parecer. Some quando não há nada — um selo
/// zerado treina o olho a ignorá-lo, e é justamente o contrário do que ele
/// existe para fazer.
class _PendingBadge extends StatelessWidget {
  final int count;

  /// A cor da ETAPA de quem está olhando — o mesmo índigo/âmbar/verde-azulado
  /// que a permuta tem na lista. Um selo de cor fixa faria a fila do faturista
  /// parecer a do gerente.
  final Color? color;
  final Widget child;
  const _PendingBadge({required this.count, required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return child;
    return Badge(
      label: Text('$count'),
      backgroundColor: color ?? AppColors.atManager,
      textColor: AppColors.onPrimary,
      child: child,
    );
  }
}

/// O POSTO de quem está olhando: a fila que pede ação dele, com a palavra e a
/// cor da etapa.
///
/// Existe porque os três papéis de retaguarda fazem a MESMA coisa em lugares
/// diferentes da linha — recebem trabalho, agem sobre ele, empurram adiante. A
/// tela é uma só, e o que muda entre eles cabe nesta classe. A alternativa era
/// um `if (role == manager) ... else if (role == committee) ...` repetido em
/// cada bloco da tela, que é como a fila do gerente nasceu e o que não escala
/// para o terceiro posto.
///
/// Repare que a fila não vem do PAPEL, mas da CAPACIDADE: é o servidor que diz
/// quem decide e quem fatura, e mover uma etapa de um papel para outro não passa
/// por aqui.
class _Post {
  /// O que espera ação desta pessoa, agora.
  final List<BarterModel> queue;

  /// A cor da etapa — a mesma da permuta na lista.
  final Color color;
  final Color surface;
  final IconData icon;

  /// "3 permutas esperando o seu parecer" — a manchete da fila.
  final String Function(int count) headline;

  /// Por que elas não andam sem esta pessoa.
  final String urgency;

  /// O que a etapa é, em uma frase.
  final String explanation;

  /// O atalho de cada linha da fila.
  final String actionLabel;
  final IconData actionIcon;

  /// O que o atalho faz. Recebe o contexto, a permuta e o aviso de "mudou".
  final void Function(BuildContext, BarterModel, VoidCallback) onAction;

  final String emptyTitle;
  final String emptyText;

  const _Post({
    required this.queue,
    required this.color,
    required this.surface,
    required this.icon,
    required this.headline,
    required this.urgency,
    required this.explanation,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    required this.emptyTitle,
    required this.emptyText,
  });

  /// O posto desta pessoa — null para quem não tem etapa na linha (o admin, que
  /// administra o sistema e não decide permuta).
  static _Post? of(UserModel user) {
    if (user.can(Capability.bartersOpinion)) {
      return _Post(
        // A do gerente é a única fila com DESTINATÁRIO: o parecer é dele, e a
        // permuta de outro time não é assunto dele.
        queue: AppData.opinionQueueFor(user.id),
        color: AppColors.atManager,
        surface: AppColors.atManagerBg,
        icon: Icons.assignment_ind,
        headline: (count) => count == 1
            ? '1 permuta esperando o seu parecer'
            : '$count permutas esperando o seu parecer',
        urgency: 'Elas não seguem para o comitê até você escrever.',
        explanation:
            'O parecer técnico não aprova nem nega — ele segue com a permuta para o '
            'comitê, que o lê antes de decidir.',
        actionLabel: 'Parecer',
        actionIcon: Icons.rate_review_outlined,
        onAction: (context, barter, onChanged) =>
            giveBarterOpinion(context, barter, onGiven: (_) => onChanged()),
        emptyTitle: 'Nenhum parecer pendente',
        emptyText: 'Nada do seu time esperando você agora. Puxe para atualizar.',
      );
    }

    if (user.can(Capability.bartersReview)) {
      return _Post(
        queue: AppData.committeeQueue,
        color: AppColors.pending,
        surface: AppColors.pendingBg,
        icon: Icons.groups_2,
        headline: (count) => count == 1
            ? '1 permuta esperando a decisão do comitê'
            : '$count permutas esperando a decisão do comitê',
        urgency: 'Nada é faturado antes daqui.',
        explanation:
            'O comitê lê o pedido do consultor e o parecer do gerente, e decide: '
            'aprovada segue para o faturamento, negada encerra ali.',
        // "Analisar" e não "Aprovar": a decisão tem duas saídas, e escolher uma
        // delas num botão de lista seria decidir antes de ler.
        actionLabel: 'Analisar',
        actionIcon: Icons.gavel_outlined,
        onAction: (context, barter, onChanged) =>
            _openDetail(context, barter, onChanged),
        emptyTitle: 'Nenhuma permuta esperando decisão',
        emptyText: 'A fila do comitê está vazia. Puxe para atualizar.',
      );
    }

    if (user.can(Capability.bartersInvoice)) {
      return _Post(
        queue: AppData.invoiceQueue,
        color: AppColors.approved,
        surface: AppColors.approvedBg,
        icon: Icons.receipt_long,
        headline: (count) => count == 1
            ? '1 permuta aprovada a faturar'
            : '$count permutas aprovadas a faturar',
        urgency: 'É a última etapa: daqui elas não andam mais.',
        explanation:
            'Só o que o comitê aprovou chega até aqui. O parecer do gerente e a '
            'decisão vêm junto com a permuta — abra para lê-los antes de faturar.',
        actionLabel: 'Faturar',
        actionIcon: Icons.receipt_long_outlined,
        onAction: (context, barter, onChanged) =>
            invoiceBarter(context, barter, onInvoiced: (_) => onChanged()),
        emptyTitle: 'Nada a faturar',
        emptyText: 'Nenhuma permuta aprovada esperando faturamento. Puxe para atualizar.',
      );
    }

    return null;
  }

  static Future<void> _openDetail(
    BuildContext context,
    BarterModel barter,
    VoidCallback onChanged,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BarterDetailScreen(barter: barter, isAdmin: true),
      ),
    );
    onChanged();
  }
}

/// O que cada papel de retaguarda acompanha, na linguagem da cooperativa.
class _RoleBriefing {
  final IconData icon;
  final String focus;
  final List<String> nextSteps;
  const _RoleBriefing({required this.icon, required this.focus, required this.nextSteps});

  static _RoleBriefing of(UserRole role) {
    switch (role) {
      case UserRole.manager:
        // O gerente já não está "em construção": a etapa dele existe. O que
        // sobra na lista é o que ainda não existe — e ela encurtou de propósito.
        return const _RoleBriefing(
          icon: Icons.assignment_ind,
          focus: 'Parecer técnico das permutas do seu time, antes do comitê.',
          nextSteps: [
            'Alçadas: até onde o gerente decide sozinho',
            'Painel por consultor do time',
          ],
        );
      case UserRole.committee:
        // A etapa do comitê existe: ele decide. O que sobra na lista é o que
        // ainda não existe — e ela encurtou pelo mesmo motivo que a do gerente.
        return const _RoleBriefing(
          icon: Icons.groups_2,
          focus: 'Decisão das permutas que já têm parecer do gerente.',
          nextSteps: [
            'Alçadas: até que valor cada instância decide',
            'Voto por membro do comitê',
            'Devolução ao consultor com pendências',
          ],
        );
      case UserRole.biller:
        return const _RoleBriefing(
          icon: Icons.receipt_long,
          focus: 'Faturamento das permutas aprovadas pelo comitê.',
          nextSteps: [
            'Emissão da nota a partir da permuta',
            'Conferência de itens e quantidades',
          ],
        );
      case UserRole.admin:
      case UserRole.consultant:
        // Estes papéis têm tela própria; o caso existe para o switch ficar
        // exaustivo — se um papel novo aparecer, o compilador cobra aqui.
        return const _RoleBriefing(
          icon: Icons.badge_outlined,
          focus: 'Acompanhamento da operação.',
          nextSteps: [],
        );
    }
  }
}

class _BackOfficeHomeTab extends StatefulWidget {
  final UserModel user;

  /// Avisa a casca quando a fila muda, para o selo da navegação acompanhar.
  final VoidCallback onQueueChanged;
  const _BackOfficeHomeTab({required this.user, required this.onQueueChanged});

  @override
  State<_BackOfficeHomeTab> createState() => _BackOfficeHomeTabState();
}

class _BackOfficeHomeTabState extends State<_BackOfficeHomeTab> {
  UserModel get user => widget.user;

  Future<void> _refresh() async {
    try {
      await AppData.refreshAll();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
    if (mounted) setState(() {});
    widget.onQueueChanged();
  }

  /// Um parecer dado muda a fila — e o selo da navegação precisa saber.
  void _onQueueChanged() {
    if (mounted) setState(() {});
    widget.onQueueChanged();
  }

  @override
  Widget build(BuildContext context) {
    final briefing = _RoleBriefing.of(user.role);
    final approved = AppData.barters.where((b) => b.awaitsInvoice).toList();
    final pending = AppData.barters.where((b) => b.status == BarterStatus.pending).toList();
    // As SACAS A RECEBER contam as aprovadas E as faturadas: faturar não desfaz
    // a entrega combinada — a permuta continua devendo as sacas dela.
    final sacksReceivable =
        AppData.barters.where((b) => b.wasApproved).fold<double>(0, (s, b) => s + b.totalGrainQty);
    // O POSTO de quem está olhando, e a fila dele. Ver [_Post].
    final post = _Post.of(user);

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
              child: Text(
                user.avatarInitials,
                style: TextStyle(
                    color: AppColors.onPrimary, fontSize: 13, fontWeight: FontWeight.bold),
              ),
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
              greetingName: user.name.split(' ')[0],
              subtitle: '${user.role.label} • ${_todayDate()}',
              // Para o gerente, a legenda conta o TAMANHO do que é dele: quantas
              // permutas do time passaram por ele. "Acompanhamento da operação"
              // era verdade quando ele via tudo — hoje ele vê o time.
              caption: user.can(Capability.bartersReadTeam)
                  ? '${AppData.barters.length} permuta(s) do seu time'
                  : briefing.focus,
              icon: briefing.icon,
            ),
            const SizedBox(height: 16),
            _SummaryStrip(
              // O PRIMEIRO NÚMERO é o de quem está olhando: o que espera ação
              // dele. Os outros dois dão o tamanho da operação em volta.
              waiting: post?.queue.length,
              waitingColor: post?.color,
              pending: pending.length,
              approved: approved.length,
              sacks: sacksReceivable,
            ),
            const SizedBox(height: 20),
            // A fila vem ANTES de tudo o mais: é a única coisa desta tela que
            // pede ação de quem está olhando, e o resto é acompanhamento.
            //
            // Vazia, ela vira um "tudo em dia" em vez de sumir. O bloco que
            // aparece e some conforme o dia deixa a tela mudando de forma, e o
            // gerente sem saber se ele não tem trabalho ou se o app não
            // carregou — dizer "nada esperando" responde as duas coisas.
            if (post != null) ...[
              if (post.queue.isEmpty)
                _EmptyQueueCard(post: post)
              else
                _WorkQueueCard(post: post, onChanged: _onQueueChanged),
              const SizedBox(height: 20),
            ],
            if (briefing.nextSteps.isNotEmpty) ...[
              _NextStepsCard(role: user.role, steps: briefing.nextSteps),
              const SizedBox(height: 20),
            ],
            Text(
              // "do Time" é sobre o ESCOPO de quem olha, não sobre o cargo: quem
              // enxerga só o próprio time é quem tem `barters.readTeam`.
              user.can(Capability.bartersReadTeam)
                  ? '${brand.copy.barterPluralTitle} do Time'
                  : '${brand.copy.barterPluralTitle} Recentes',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark),
            ),
            const SizedBox(height: 12),
            if (AppData.barters.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Nenhuma ${brand.copy.barter} registrada até agora.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMedium),
                  ),
                ),
              )
            else
              ...AppData.barters
                  .take(5)
                  .map((b) => MiniBarterCard(
                        barter: b,
                        isAdmin: true,
                        // A permuta abre com a MESMA ação que teria pela aba de
                        // permutas: é o mesmo registro e a mesma pessoa.
                        opinionManagerId:
                            user.can(Capability.bartersOpinion) ? user.id : null,
                        onChanged: _onQueueChanged,
                      )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

String _todayDate() {
  final now = DateTime.now();
  const months = ['', 'jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  return '${now.day} ${months[now.month]} ${now.year}';
}

/// A FILA DO POSTO de quem está olhando — o que espera ação dele.
///
/// Ela abre a tela porque é a única coisa aqui que pede ação: o resto do painel
/// é acompanhamento, e uma permuta parada não deveria depender de alguém pensar
/// em procurá-la numa aba.
///
/// O cartão é o mesmo para os três postos, e as palavras vêm do [_Post]: a fila
/// do faturista tem a mesma urgência que a do gerente, e um desenho diferente
/// para cada uma só faria a pessoa reaprender a tela ao trocar de papel.
class _WorkQueueCard extends StatelessWidget {
  final _Post post;
  final VoidCallback onChanged;
  const _WorkQueueCard({required this.post, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      // Borda na cor da etapa: é o único cartão desta tela que pede ação, e ele
      // precisa se separar dos que só informam.
      shape: RoundedRectangleBorder(
        borderRadius: AppShape.card,
        side: BorderSide(color: post.color.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: post.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(post.icon, size: 20, color: post.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.headline(post.queue.length),
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textDark),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        post.urgency,
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: post.color),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(post.explanation, style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
            const Divider(height: 20),
            for (final barter in post.queue.take(4))
              _QueueRow(barter: barter, post: post, onChanged: onChanged),
            if (post.queue.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'e mais ${post.queue.length - 4} na aba de permutas.',
                  style: TextStyle(fontSize: 12, color: AppColors.textLight),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A fila vazia — e ela aparece, em vez de sumir.
///
/// Um bloco que some conforme o dia deixa a tela mudando de forma e a pessoa sem
/// saber se ela está em dia ou se o app não carregou. Dizer "nada esperando"
/// responde as duas coisas de uma vez.
class _EmptyQueueCard extends StatelessWidget {
  final _Post post;
  const _EmptyQueueCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.approvedBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.check_circle_outline, size: 20, color: AppColors.approved),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(post.emptyTitle,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                  const SizedBox(height: 2),
                  Text(post.emptyText,
                      style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final BarterModel barter;
  final _Post post;
  final VoidCallback onChanged;
  const _QueueRow({required this.barter, required this.post, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // A linha inteira abre a permuta: agir sem ler o que tem dentro seria
          // assinar no escuro, e o botão ao lado é o atalho para quem já sabe do
          // que se trata.
          Expanded(
            child: InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BarterDetailScreen(
                      barter: barter,
                      isAdmin: true,
                      opinionManagerId: barter.managerId,
                    ),
                  ),
                );
                onChanged();
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${barter.id} • ${barter.producerName}',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${barter.consultantName} • retirada em ${barter.unitLabel}',
                    style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => post.onAction(context, barter, onChanged),
            icon: Icon(post.actionIcon, size: 16),
            label: Text(post.actionLabel, style: const TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: post.color,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

/// Três números para dar o tamanho do que está na mão de quem olha.
///
/// [waiting] é o do POSTO de quem está olhando: o que espera ação dele. Quando
/// vem preenchido, ele toma o lugar de "aprovadas" na faixa — a tela de quem tem
/// trabalho a fazer precisa mostrá-lo entre os três números, não escondido
/// embaixo. Ele vem com a COR da etapa pelo mesmo motivo do selo.
class _SummaryStrip extends StatelessWidget {
  final int? waiting;
  final Color? waitingColor;
  final int pending;
  final int approved;
  final double sacks;
  const _SummaryStrip({
    required this.pending,
    required this.approved,
    required this.sacks,
    this.waiting,
    this.waitingColor,
  });

  @override
  Widget build(BuildContext context) {
    final cells = [
      if (waiting != null)
        _SummaryCell(
          icon: Icons.pending_actions_outlined,
          color: waitingColor ?? AppColors.atManager,
          value: '$waiting',
          label: 'Esperando você',
        ),
      _SummaryCell(
        icon: Icons.hourglass_top,
        color: AppColors.pending,
        value: '$pending',
        label: 'No comitê',
      ),
      if (waiting == null)
        _SummaryCell(
          icon: Icons.check_circle_outline,
          color: AppColors.approved,
          value: '$approved',
          label: 'A faturar',
        ),
      _SummaryCell(
        icon: Icons.grass,
        color: AppColors.grain,
        value: formatSacks(sacks),
        label: 'A receber',
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: IntrinsicHeight(
          child: Row(
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) const VerticalDivider(width: 1, indent: 4, endIndent: 4),
                Expanded(child: cells[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _SummaryCell({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textDark),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
      ],
    );
  }
}

/// Diz, na cara, o que este papel AINDA não faz. É preferível a uma tela que
/// parece pronta: quem entra como comitê ou faturista precisa saber que o
/// acesso já existe e que as ações dele vêm na sequência.
///
/// Para o GERENTE o texto é outro, e a diferença importa: ele JÁ trabalha aqui.
/// Dizer-lhe "por enquanto é modo leitura" logo abaixo da fila que pede o
/// parecer dele seria a tela contradizendo a si mesma.
class _NextStepsCard extends StatelessWidget {
  final UserRole role;
  final List<String> steps;
  const _NextStepsCard({required this.role, required this.steps});

  bool get _alreadyWorks => role == UserRole.manager;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.construction, size: 18, color: AppColors.pending),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _alreadyWorks
                        ? 'Ainda vem por aí'
                        : 'Acesso de ${role.label} liberado',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _alreadyWorks
                  ? 'Além do parecer técnico, estas são as próximas do seu papel:'
                  : 'Por enquanto o acompanhamento é em modo leitura. Em construção:',
              style: TextStyle(fontSize: 12, color: AppColors.textMedium),
            ),
            const SizedBox(height: 10),
            for (final step in steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration:
                            BoxDecoration(color: AppColors.primaryMedium, shape: BoxShape.circle),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(step,
                          style: TextStyle(fontSize: 12.5, color: AppColors.textDark)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
