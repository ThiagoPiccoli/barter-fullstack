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

  /// A ETAPA VIZINHA que esta pessoa acompanha, e que vira o segundo número do
  /// painel.
  ///
  /// Vizinha, e nunca uma etapa qualquer: para quem empurra a permuta adiante é
  /// a SEGUINTE (o gerente vê o que já mandou ao comitê); para o faturista, que
  /// é o fim da linha, é o que ele já faturou. O comitê é o único que olha para
  /// TRÁS — o que está no gerente é a fila que vai cair na mesa dele.
  ///
  /// Nenhum posto conta aqui uma etapa que ele não enxerga: o painel do
  /// faturista mostrava "No comitê" enquanto ele lia a operação inteira, e era
  /// um número que ele não podia abrir, conferir nem fazer nada a respeito.
  final BarterStatus followStatus;
  final String followLabel;
  final IconData followIcon;
  final Color followColor;

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
    required this.followStatus,
    required this.followLabel,
    required this.followIcon,
    required this.followColor,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    required this.emptyTitle,
    required this.emptyText,
  });

  /// Quantas permutas estão na etapa vizinha, dentro do que esta pessoa enxerga.
  int get followCount =>
      AppData.barters.where((b) => b.status == followStatus).length;

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
        // Adiante: o que ele já mandou ao comitê.
        followStatus: BarterStatus.pending,
        followLabel: 'No comitê',
        followIcon: Icons.groups_2_outlined,
        followColor: AppColors.pending,
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
        // O comitê é o único que olha para TRÁS: o que está no gerente é a fila
        // que vai cair na mesa dele, e saber o tamanho dela antes de ela chegar
        // é o começo de acompanhar a linha.
        followStatus: BarterStatus.sentToManager,
        followLabel: 'No gerente',
        followIcon: Icons.assignment_ind_outlined,
        followColor: AppColors.atManager,
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
        // O faturista é fim de linha: não há etapa adiante, e o número que dá
        // tamanho ao trabalho dele é o que ele já faturou.
        followStatus: BarterStatus.invoiced,
        followLabel: 'Faturadas',
        followIcon: Icons.receipt_long_outlined,
        followColor: AppColors.invoiced,
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

  /// A LEGENDA do cabeçalho: o TAMANHO do que é desta pessoa, não a descrição
  /// do cargo dela.
  ///
  /// Ela já dizia o que o papel faz ("Faturamento das permutas aprovadas pelo
  /// comitê"), e isso é o app explicando à pessoa o trabalho que ela conhece
  /// melhor do que ele. O que ela não sabe de cor é quantas permutas estão na
  /// mão dela agora.
  String get _scopeCaption {
    final total = AppData.barters.length;
    final plural = total == 1 ? 'permuta' : 'permutas';
    if (user.can(Capability.bartersReadTeam)) return '$total $plural do seu time';
    if (user.can(Capability.bartersReadInvoicing)) return '$total $plural no faturamento';
    return '$total $plural na operação';
  }

  @override
  Widget build(BuildContext context) {
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
              caption: _scopeCaption,
              icon: post?.icon ?? Icons.badge_outlined,
            ),
            const SizedBox(height: 16),
            _SummaryStrip(post: post, sacks: sacksReceivable),
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
            // O QUE VEM VINDO — só para quem decide. Depois da fila porque não
            // pede ação: é a leitura da etapa de trás, e ela informa a decisão
            // de hoje sem competir com ela.
            if (user.can(Capability.bartersReview)) ...[
              _UpstreamPanel(
                atManager: AppData.barters.where((b) => b.awaitsManager).toList(),
              ),
              const SizedBox(height: 20),
            ],
            Text(
              // O título diz o ESCOPO de quem olha, não o cargo: quem enxerga só
              // o próprio time tem `barters.readTeam`, e quem enxerga só o que
              // chegou ao faturamento tem `barters.readInvoicing`.
              user.can(Capability.bartersReadTeam)
                  ? '${brand.copy.barterPluralTitle} do Time'
                  : user.can(Capability.bartersReadInvoicing)
                      ? '${brand.copy.barterPluralTitle} no Faturamento'
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
/// O cartão é o mesmo para os três postos, e as palavras vêm do [_Post]: um
/// desenho diferente para cada fila só faria a pessoa reaprender a tela ao
/// trocar de papel.
///
/// Ele diz O QUE ESPERA e mais nada. Já trouxe também um parágrafo explicando o
/// que a etapa é ("o parecer não aprova nem nega", "só o que o comitê aprovou
/// chega até aqui") — texto escrito para quem nunca viu o app, parado na tela de
/// quem trabalha nele todo dia. Quem precisa de contexto abre a permuta, onde a
/// linha do tempo mostra por onde ela passou.
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
                  child: Text(
                    post.headline(post.queue.length),
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textDark),
                  ),
                ),
              ],
            ),
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

/// O QUE VEM VINDO: as permutas ainda na mesa dos gerentes, POR GERENTE.
///
/// É do COMITÊ e de mais ninguém — ele é o único posto que enxerga a etapa
/// anterior à sua (ver `barters.readAll` em policy.ts). Saber o tamanho da fila
/// antes de ela chegar é o que separa decidir de reagir: três permutas paradas
/// há duas semanas com o mesmo gerente são uma ligação hoje, e não uma surpresa
/// na semana que vem, quando caírem juntas na mesa.
///
/// Ele agrupa por GERENTE, e não lista permuta a permuta: a lista completa está
/// a um toque, na aba "No gerente". O que não está em lugar nenhum — e é o que
/// este painel existe para dar — é quem está segurando e há quanto tempo.
class _UpstreamPanel extends StatelessWidget {
  final List<BarterModel> atManager;
  const _UpstreamPanel({required this.atManager});

  /// Há quantos dias a mais antiga do grupo espera. A conta é sobre a CRIAÇÃO
  /// porque a permuta chega ao gerente no instante em que nasce: entre registrar
  /// e o parecer não há outra etapa que segure o relógio.
  static int _waitOf(List<BarterModel> barters) {
    final now = DateTime.now();
    return barters
        .map((b) => now.difference(b.createdAt).inDays)
        .fold(0, (a, b) => a > b ? a : b);
  }

  /// Quanto mais antiga, mais quente — os mesmos cortes do painel do admin.
  static Color _urgencyOf(int days) => days >= 14
      ? AppColors.denied
      : days >= 7
          ? AppColors.pending
          : AppColors.primaryMedium;

  static String _waitLabel(int days) =>
      days <= 0 ? 'entrou hoje' : 'há $days dia${days == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) {
    final byManager = <String, List<BarterModel>>{};
    for (final barter in atManager) {
      byManager.putIfAbsent(barter.managerLabel, () => []).add(barter);
    }
    // QUEM ESTÁ SEGURANDO HÁ MAIS TEMPO primeiro: a ordem alfabética esconderia
    // justamente a linha que se quer ler.
    final groups = byManager.entries.toList()
      ..sort((a, b) => _waitOf(b.value).compareTo(_waitOf(a.value)));
    final sacks = atManager.fold<double>(0, (s, b) => s + b.totalGrainQty);

    return Card(
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
                    color: AppColors.atManagerBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.assignment_ind_outlined,
                      size: 20, color: AppColors.atManager),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('No gerente',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                ),
                if (atManager.isNotEmpty)
                  Text(
                    '${atManager.length} • ${formatSacks(sacks)}',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.atManager),
                  ),
              ],
            ),
            // Vazio, o painel FICA e diz que está vazio. Um bloco que some
            // conforme o dia deixa a tela mudando de forma, e quem olha sem
            // saber se não há nada vindo ou se o app não carregou — é o mesmo
            // motivo do cartão de fila vazia.
            if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Nenhuma permuta esperando parecer agora.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
              )
            else ...[
              const Divider(height: 20),
              for (final group in groups)
                _UpstreamRow(
                  manager: group.key,
                  count: group.value.length,
                  sacks: group.value.fold<double>(0, (s, b) => s + b.totalGrainQty),
                  days: _waitOf(group.value),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Um gerente na fila de trás: quantas ele tem, quanto elas somam e há quanto
/// tempo a mais antiga espera.
class _UpstreamRow extends StatelessWidget {
  final String manager;
  final int count;
  final double sacks;
  final int days;
  const _UpstreamRow({
    required this.manager,
    required this.count,
    required this.sacks,
    required this.days,
  });

  @override
  Widget build(BuildContext context) {
    final urgency = _UpstreamPanel._urgencyOf(days);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          // A barra de cor é a leitura rápida da linha: dá para varrer o painel
          // e achar o vermelho sem ler número nenhum.
          Container(
            width: 4,
            height: 34,
            decoration: BoxDecoration(color: urgency, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  manager,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$count ${count == 1 ? 'permuta' : 'permutas'} • ${formatSacks(sacks)}',
                  style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: urgency.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: 11, color: urgency),
                const SizedBox(width: 3),
                Text(
                  _UpstreamPanel._waitLabel(days),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: urgency),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Três números para dar o tamanho do que está na mão de quem olha.
///
/// Todos os três saem do POSTO de quem está olhando (ver [_Post]): o que espera
/// ação dele, a etapa vizinha que ele acompanha e as sacas a receber. Nenhum
/// deles conta permuta de uma etapa que a pessoa não enxerga — a faixa trazia
/// "No comitê" fixo, e no painel do faturista isso era um número de um lugar
/// onde ele não entra.
///
/// Sem posto (o admin, que administra o sistema e não decide permuta) a faixa
/// volta a ser o retrato da operação: o que espera decisão e o que espera nota.
class _SummaryStrip extends StatelessWidget {
  final _Post? post;
  final double sacks;
  const _SummaryStrip({required this.post, required this.sacks});

  @override
  Widget build(BuildContext context) {
    final post = this.post;
    final cells = [
      if (post != null) ...[
        _SummaryCell(
          icon: Icons.pending_actions_outlined,
          color: post.color,
          value: '${post.queue.length}',
          label: 'Esperando você',
        ),
        _SummaryCell(
          icon: post.followIcon,
          color: post.followColor,
          value: '${post.followCount}',
          label: post.followLabel,
        ),
      ] else ...[
        _SummaryCell(
          icon: Icons.hourglass_top,
          color: AppColors.pending,
          value: '${AppData.barters.where((b) => b.status == BarterStatus.pending).length}',
          label: 'No comitê',
        ),
        _SummaryCell(
          icon: Icons.check_circle_outline,
          color: AppColors.approved,
          value: '${AppData.barters.where((b) => b.awaitsInvoice).length}',
          label: 'A faturar',
        ),
      ],
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
