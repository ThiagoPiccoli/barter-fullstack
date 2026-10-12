import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../data/app_data.dart';
import '../services/work_post.dart';
import '../services/dashboard_stats.dart';
import '../models/models.dart';
import '../services/api/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/policy_dialog.dart';
import 'barter_detail_screen.dart';
import 'cpr_form_screen.dart';
import 'invoicing_screen.dart';
import 'barters_screen.dart';
import 'creditor_screen.dart';
import 'team_analysis_screen.dart';

/// Casa dos papéis de RETAGUARDA — gerente, comitê, SEGURADORA, faturista e
/// EMISSOR.
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
    _BackOfficeHomeTab(
      user: widget.user,
      onQueueChanged: () => setState(() {}),
      onNavigate: (i) => setState(() => _selectedIndex = i),
    ),
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

  bool get _hasTeam => widget.user.can(Capability.bartersReadTeam);

  @override
  Widget build(BuildContext context) {
    // O que espera AÇÃO DE QUEM ESTÁ OLHANDO — o parecer do gerente, a decisão
    // do comitê, o faturamento do faturista, a cédula do emissor. Vira o número
    // do selo na navegação:
    // o trabalho precisa se anunciar de qualquer aba, e não só quando a pessoa
    // pensa em ir procurar.
    final post = _Post.of(widget.user);
    final waiting = post?.queue.length ?? 0;

    return AdaptiveNavScaffold(
      user: widget.user,
      selectedIndex: _selectedIndex,
      onSelect: (i) => setState(() => _selectedIndex = i),
      body: IndexedStack(index: _selectedIndex, children: [
        ..._screens,
        // A ANÁLISE DO TIME — de quem enxerga um time. Pela capacidade, como
        // tudo aqui: é `barters.readTeam` que faz alguém ter consultores para
        // comparar. Criada a cada desenho (o estado, com a ordenação escolhida,
        // fica): um parecer dado na outra aba precisa já ter andado aqui.
        if (_hasTeam) TeamAnalysisTab(user: widget.user),
      ]),
      destinations: [
        const AdaptiveDestination(
          icon: Icons.insights_outlined,
          activeIcon: Icons.insights,
          label: 'Início',
        ),
        AdaptiveDestination(
          icon: Icons.swap_horiz_outlined,
          activeIcon: Icons.swap_horiz,
          label: brand.copy.barterPluralTitle,
          badgeCount: waiting,
          badgeColor: post?.color,
        ),
        if (_hasTeam)
          const AdaptiveDestination(
            icon: Icons.analytics_outlined,
            activeIcon: Icons.analytics,
            label: 'Análise',
          ),
      ],
    );
  }
}

/// O atalho para o cadastro da EMPRESA (a credora), no painel de quem o mantém.
///
/// Ele carrega o cadastro ao aparecer, e não usa cache, porque o dono é
/// compartilhado: admin e emissor escrevem a mesma linha, e uma cópia em
/// memória mostraria a versão de quem abriu o app primeiro.
///
/// Quando falta alguma coisa, o cartão DIZ o quê. É a mesma lista que a tela da
/// cédula mostra, do mesmo lugar — o emissor não deveria descobrir que o CNPJ
/// está faltando só ao montar a décima cédula do dia.
class _CreditorTile extends StatefulWidget {
  const _CreditorTile();

  @override
  State<_CreditorTile> createState() => _CreditorTileState();
}

class _CreditorTileState extends State<_CreditorTile> {
  CprCreditor? _creditor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final creditor = await AppData.creditor();
      if (mounted) setState(() => _creditor = creditor);
    } on ApiException {
      // Silêncio de propósito: este é um atalho, não o conteúdo da tela. Um erro
      // aqui não pode encher de vermelho o painel de quem veio ver a própria
      // fila — o cartão simplesmente fica sem o resumo, e a tela de dentro
      // mostra a falha com o "tentar novamente" dela.
    }
  }

  @override
  Widget build(BuildContext context) {
    final creditor = _creditor;
    final pending = creditor != null && !creditor.isComplete;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          pending ? Icons.domain_disabled_outlined : Icons.domain,
          color: pending ? AppColors.pending : AppColors.primary,
        ),
        title: const Text('Empresa (credora)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(
          creditor == null
              ? 'Os dados que saem nas cédulas emitidas'
              : pending
                  ? 'Falta: ${creditor.gaps.join(', ')}'
                  : creditor.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: pending ? AppColors.pending : AppColors.textMedium,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CreditorScreen()),
          );
          await _load();
        },
      ),
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

  /// QUAL POSTO é este. A regra — fila, etapa vizinha, quem ocupa — mora em
  /// `services/work_post.dart`; o que está nesta classe é a aparência dela.
  final WorkPost post;

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
    required this.post,
    required this.color,
    required this.surface,
    required this.icon,
    required this.headline,
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
  int get followCount => followCountOf(post, AppData.barters);

  /// A APARÊNCIA do posto desta pessoa — null para quem não tem etapa na linha.
  ///
  /// Quem responde QUAL é o posto e o que há na fila dele é
  /// `services/work_post.dart`; este `switch` só veste o que veio de lá.
  static _Post? of(UserModel user) {
    final post = workPostOf(user);
    if (post == null) return null;
    return forPost(post, user);
  }

  /// A aparência de um posto qualquer. [anyManager] troca a fila do parecer
  /// pela de TODOS os gerentes — a de quem pode opinar em qualquer permuta.
  static _Post forPost(WorkPost post, UserModel user, {bool anyManager = false}) {
    switch (post) {
      case WorkPost.manager:
      return _Post(
        post: post,
        // A do gerente é a única fila com DESTINATÁRIO: o parecer é dele, e a
        // permuta de outro time não é assunto dele.
        queue: queueOf(post, AppData.barters, managerId: anyManager ? null : user.id),
        color: AppColors.atManager,
        surface: AppColors.atManagerBg,
        icon: Icons.assignment_ind,
        headline: (count) => count == 1
            ? '1 permuta esperando o seu parecer'
            : '$count permutas esperando o seu parecer',
        // Adiante: o que ele já mandou ao comitê.
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

      case WorkPost.committee:
      return _Post(
        post: post,
        queue: queueOf(post, AppData.barters),
        color: AppColors.pending,
        surface: AppColors.pendingBg,
        icon: Icons.groups_2,
        headline: (count) => count == 1
            ? '1 permuta esperando a decisão do comitê'
            : '$count permutas esperando a decisão do comitê',
        // O comitê é o único que olha para TRÁS: o que está no gerente é a fila
        // que vai cair na mesa dele, e saber o tamanho dela antes de ela chegar
        // é o começo de acompanhar a linha.
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

      // A SEGURADORA — entre a decisão e o faturista, só para as permutas com
      // seguro.
      case WorkPost.insurer:
      return _Post(
        post: post,
        queue: queueOf(post, AppData.barters),
        color: AppColors.atInsurer,
        surface: AppColors.atInsurerBg,
        icon: Icons.shield_outlined,
        headline: (count) => count == 1
            ? '1 permuta aprovada esperando a apólice'
            : '$count permutas aprovadas esperando a apólice',
        // Adiante: o que ela já liberou ao faturista e ainda não foi faturado.
        followLabel: 'A faturar',
        followIcon: Icons.receipt_long_outlined,
        followColor: AppColors.approved,
        actionLabel: 'Apólice',
        actionIcon: Icons.upload_file_outlined,
        onAction: (context, barter, onChanged) =>
            informBarterPolicy(context, barter, onInsured: (_) => onChanged()),
        emptyTitle: 'Nenhuma apólice pendente',
        emptyText: 'Nenhuma permuta com seguro esperando a apólice. Puxe para atualizar.',
      );

      case WorkPost.biller:
      return _Post(
        post: post,
        queue: queueOf(post, AppData.barters),
        color: AppColors.approved,
        surface: AppColors.approvedBg,
        icon: Icons.receipt_long,
        headline: (count) => count == 1
            ? '1 permuta aprovada a faturar'
            : '$count permutas aprovadas a faturar',
        // O faturista é fim de linha: não há etapa adiante, e o número que dá
        // tamanho ao trabalho dele é o que ele já faturou.
        followLabel: 'Faturadas',
        followIcon: Icons.receipt_long_outlined,
        followColor: AppColors.invoiced,
        actionLabel: 'Faturar',
        actionIcon: Icons.receipt_long_outlined,
        onAction: (context, barter, onChanged) =>
            openInvoicing(context, barter, onInvoiced: (_) => onChanged()),
        emptyTitle: 'Nada a faturar',
        emptyText: 'Nenhuma permuta aprovada esperando faturamento. Puxe para atualizar.',
      );

      // O EMISSOR — o posto que vem depois do faturamento.
      case WorkPost.emitter:
      return _Post(
        post: post,
        queue: queueOf(post, AppData.barters),
        color: AppColors.invoiced,
        surface: AppColors.invoicedBg,
        icon: Icons.description_outlined,
        headline: (count) => count == 1
            ? '1 cédula em aberto'
            : '$count cédulas em aberto',
        // O número que dá tamanho ao trabalho dele é o que já foi REGISTRADO:
        // é o fim da linha, e o único estado em que a garantia vale contra
        // terceiros.
        followLabel: 'Registradas',
        followIcon: Icons.verified_outlined,
        followColor: AppColors.approved,
        actionLabel: 'Abrir cédula',
        actionIcon: Icons.description_outlined,
        onAction: (context, barter, onChanged) =>
            openCprDesk(context, barter, onChanged: (_) => onChanged()),
        emptyTitle: 'Nenhuma cédula em aberto',
        emptyText: 'Nada faturado esperando emissão, assinatura ou registro. '
            'Puxe para atualizar.',
      );
    }
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

  /// Leva a outra aba — é para onde os cartões de número se abrem.
  final ValueChanged<int> onNavigate;
  const _BackOfficeHomeTab({
    required this.user,
    required this.onQueueChanged,
    required this.onNavigate,
  });

  @override
  State<_BackOfficeHomeTab> createState() => _BackOfficeHomeTabState();
}

class _BackOfficeHomeTabState extends State<_BackOfficeHomeTab> {
  UserModel get user => widget.user;

  /// Sobe a cada "puxar para atualizar" — é o que faz o cartão de avisos
  /// buscar de novo, junto com o resto da tela.
  int _refreshes = 0;

  Future<void> _refresh() async {
    try {
      await AppData.refreshAll();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
    if (mounted) setState(() => _refreshes++);
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
    if (user.can(Capability.bartersReadInsurance)) return '$total $plural com seguro';
    if (user.can(Capability.bartersReadInvoicing)) return '$total $plural no faturamento';
    return '$total $plural na operação';
  }

  @override
  Widget build(BuildContext context) {
    // O POSTO de quem está olhando, e a fila dele. Ver [_Post].
    final post = _Post.of(user);

    return Scaffold(
      appBar: AppBar(
        title: const MainAppBarTitle('Início'),
        actions: [
          const ChangePasswordButton(),
          const LogoutButton(),
          AppBarUserAvatar(user: user),
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
              greetingName: user.name.split(' ')[0],
              subtitle: '${user.role.label} • ${_todayDate()}',
              caption: _scopeCaption,
              icon: post?.icon ?? Icons.badge_outlined,
            ),
            const SizedBox(height: 16),
            // OS NÚMEROS DO POSTO, cada um com o seu desdobramento ao lado: a
            // fila com o tamanho dela, a área com o investimento, as sacas com
            // as safras. É o que cada um precisa saber antes de abrir qualquer
            // lista — e ficava espalhado em faixas e painéis pela tela.
            _PostTiles(
              post: post,
              user: user,
              barters: AppData.barters,
              onNavigate: widget.onNavigate,
              onChanged: _onQueueChanged,
            ),
            const SizedBox(height: 20),
            // OS AVISOS vêm antes da fila: são poucos, são novidade, e somem
            // quando dispensados. É por aqui que o gerente fica sabendo que o
            // comitê devolveu uma permuta do time dele ao consultor — e que ela
            // voltou ao comitê sem passar pela mesa dele.
            _NoticesCard(refreshes: _refreshes, onChanged: _onQueueChanged),
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
            // A EMPRESA — só para quem mantém o timbre dos documentos, que na
            // retaguarda é o faturista. Fica depois da fila pelo mesmo critério
            // do painel abaixo: não pede ação, é cadastro que se visita quando
            // algo está errado nele. Aparece antes só quando ESTÁ errado.
            if (user.can(Capability.creditorManage)) ...[
              const _CreditorTile(),
              const SizedBox(height: 20),
            ],
            // O QUE VEM VINDO — só para quem decide. Depois da fila porque não
            // pede ação: é a leitura da etapa de trás, e ela informa a decisão
            // de hoje sem competir com ela.
            if (user.can(Capability.bartersReview)) ...[
              _UpstreamPanel(
                atManager: statsOf(AppData.barters).atManager,
              ),
              const SizedBox(height: 20),
            ],
            Text(
              // O título diz o ESCOPO de quem olha, não o cargo: quem enxerga só
              // o próprio time tem `barters.readTeam`, e quem enxerga só o que
              // chegou ao faturamento tem `barters.readInvoicing`.
              user.can(Capability.bartersReadTeam)
                  ? '${brand.copy.barterPluralTitle} do Time'
                  : user.can(Capability.bartersReadInsurance)
                  ? '${brand.copy.barterPluralTitle} com Seguro'
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
      ),
    );
  }
}

/// OS AVISOS de quem está olhando — o que aconteceu numa permuta que ele
/// acompanha e não pede ação dele. Ver `Notice` na API.
///
/// Some quando não há aviso: é novidade, e um cartão vazio todo dia ensinaria
/// a pessoa a não olhar para ele. Também some quando a busca falha — é apoio,
/// não o assunto da tela, e o erro não pode encher de vermelho o painel.
class _NoticesCard extends StatefulWidget {
  /// Muda a cada atualização da tela, e aí os avisos são buscados de novo.
  final int refreshes;
  final VoidCallback onChanged;

  const _NoticesCard({required this.refreshes, required this.onChanged});

  @override
  State<_NoticesCard> createState() => _NoticesCardState();
}

class _NoticesCardState extends State<_NoticesCard> {
  List<NoticeModel> _notices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_NoticesCard old) {
    super.didUpdateWidget(old);
    if (old.refreshes != widget.refreshes) _load();
  }

  Future<void> _load() async {
    try {
      final notices = await AppData.notices();
      if (mounted) setState(() => _notices = notices);
    } on ApiException {
      // Silêncio de propósito — ver a documentação da classe.
    }
  }

  Future<void> _dismiss(NoticeModel notice) async {
    setState(() => _notices = _notices.where((n) => n.id != notice.id).toList());
    try {
      await AppData.dismissNotice(notice.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
      await _load();
    }
  }

  /// Abre a permuta do aviso, quando ela está no que esta pessoa enxerga.
  Future<void> _open(NoticeModel notice) async {
    BarterModel? barter;
    for (final b in AppData.barters) {
      if (b.id == notice.barterCode) barter = b;
    }
    if (barter == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BarterDetailScreen(barter: barter!, isAdmin: true)),
    );
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_notices.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  children: [
                    Icon(Icons.notifications_active_outlined,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      _notices.length == 1 ? '1 aviso' : '${_notices.length} avisos',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
              for (final notice in _notices)
                ListTile(
                  dense: true,
                  onTap: () => _open(notice),
                  title: Text(notice.message, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    _formatNoticeDate(notice.createdAt),
                    style: TextStyle(fontSize: 11, color: AppColors.textLight),
                  ),
                  trailing: IconButton(
                    tooltip: 'Dispensar',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _dismiss(notice),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatNoticeDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _todayDate() {
  final now = DateTime.now();
  const months = ['', 'jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  return '${now.day} ${months[now.month]} ${now.year}';
}

/// Quantas permutas esperam ação desta pessoa, somando TODOS os postos dela.
int workQueuesCount(UserModel user) => workPostsOf(user)
    .map((post) => _Post.forPost(post, user, anyManager: true).queue.length)
    .fold(0, (a, b) => a + b);

/// AS FILAS DE TODOS OS POSTOS numa tela só — para quem acumula as etapas da
/// linha (o admin). Cada posto aparece com o mesmo cartão que o seu dono vê no
/// próprio painel, e a fila do parecer é a de todos os gerentes.
class WorkQueuesTab extends StatefulWidget {
  final UserModel user;
  final VoidCallback? onQueueChanged;
  const WorkQueuesTab({super.key, required this.user, this.onQueueChanged});

  @override
  State<WorkQueuesTab> createState() => _WorkQueuesTabState();
}

class _WorkQueuesTabState extends State<WorkQueuesTab> {
  Future<void> _refresh() async {
    try {
      await AppData.refreshAll();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
    _onQueueChanged();
  }

  void _onQueueChanged() {
    if (mounted) setState(() {});
    widget.onQueueChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final posts = workPostsOf(widget.user)
        .map((post) => _Post.forPost(post, widget.user, anyManager: true))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const MainAppBarTitle('Filas'),
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
              for (final post in posts) ...[
                if (post.queue.isEmpty)
                  _EmptyQueueCard(post: post)
                else
                  _WorkQueueCard(post: post, onChanged: _onQueueChanged),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
                  BarterIdentity(barter: barter),
                  Text(
                    'Retirada em ${barter.unitLabel}',
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
    // QUEM ESTÁ SEGURANDO HÁ MAIS TEMPO primeiro: a ordem alfabética esconderia
    // justamente a linha que se quer ler. O agrupamento e a espera são de
    // `services/dashboard_stats.dart` — a tela desenha a ordem que recebe.
    final groups = byManagerOldestFirst(atManager);
    final sacks = sacksOf(atManager);

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
                  sacks: sacksOf(group.value),
                  days: waitingDays(group.value),
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

/// OS NÚMEROS DE CADA POSTO — a grade do topo do painel da retaguarda.
///
/// Cada posto lê a sua: o gerente e o comitê, a fila e a operação (fases,
/// área, sacas); a seguradora, a apólice; o faturista, a nota; o emissor, a
/// cédula. Os cartões que eles dividem são os mesmos, e nenhum conta etapa que
/// quem olha não enxerga — as fases aparecem só quando têm permuta, e o
/// servidor só entrega o que é do escopo de cada um.
class _PostTiles extends StatelessWidget {
  final _Post? post;
  final UserModel user;
  final List<BarterModel> barters;
  final ValueChanged<int> onNavigate;
  final VoidCallback onChanged;

  const _PostTiles({
    required this.post,
    required this.user,
    required this.barters,
    required this.onNavigate,
    required this.onChanged,
  });

  static String _days(int days) => days == 1 ? '1 dia' : '$days dias';

  /// A FILA de quem olha: quantas, o tamanho delas e há quanto tempo a mais
  /// antiga espera.
  Widget _queueTile(_Post post, {String label = 'Esperando você', List<KpiFact> extra = const []}) {
    final queue = post.queue;
    final oldest = queue.isEmpty ? 0 : queue.map(daysWaiting).reduce((a, b) => a > b ? a : b);
    return KpiTile(
      icon: post.icon,
      color: post.color,
      label: label,
      value: '${queue.length}',
      caption: queue.isEmpty ? post.emptyTitle : 'a mais antiga espera há ${_days(oldest)}',
      onTap: () => onNavigate(1),
      child: KpiFacts(facts: [
        KpiFact('Sacas na fila', formatSacks(sacksOf(queue))),
        KpiFact('Área na fila', areaLabelOf(areaOf(queue))),
        ...extra,
        KpiFact(post.followLabel, '${post.followCount}', dot: post.followColor),
      ]),
    );
  }

  Widget _statusTile() {
    final phases = phaseCounts(barters);
    final visible = backOfficePhases.where((p) => (phases[p] ?? 0) > 0).toList();
    return KpiTile(
      icon: Icons.swap_horiz,
      color: AppColors.primary,
      label: '${brand.copy.barterPluralTitle} por status',
      value: '${visible.fold(0, (sum, p) => sum + phases[p]!)}',
      caption: user.can(Capability.bartersReadTeam) ? 'do seu time' : 'na operação',
      onTap: () => onNavigate(1),
      child: visible.isEmpty ? null : PhaseBreakdown(counts: phases, phases: visible, dense: true),
    );
  }

  Widget _areaTile(BarterStats stats) => KpiTile(
        icon: Icons.landscape_outlined,
        color: AppColors.primary,
        label: 'Área total',
        value: areaLabelOf(stats.area),
        caption: 'em permutas aprovadas',
        child: KpiFacts(facts: [
          KpiFact('Investimento médio', formatInvestment(stats.investmentPerHa)),
          if (stats.investmentPerHa != null) KpiFact('Conta', investmentBasisOf(stats.closed)),
          KpiFact('Área média', areaLabelOf(stats.averageArea)),
        ]),
      );

  Widget _sacksTile(BarterStats stats) => KpiTile(
        icon: Icons.grass,
        color: AppColors.grain,
        label: 'Sacas a receber',
        value: formatSacks(stats.sacksReceivable),
        caption: 'ticket médio ${formatSacks(stats.averageSacks)} • por safra',
        child: seasonSacksBars(barters, take: 3),
      );

  @override
  Widget build(BuildContext context) {
    final post = this.post;
    final stats = statsOf(barters);

    switch (post?.post) {
      // O GERENTE: a fila do parecer, o time e quem do time mais fecha.
      case WorkPost.manager:
        final team = analysisByConsultant(barters)
          ..sort((a, b) => b.stats.sacksReceivable.compareTo(a.stats.sacksReceivable));
        return KpiGrid(tiles: [
          _queueTile(post!),
          _statusTile(),
          _areaTile(stats),
          _sacksTile(stats),
          KpiTile(
            icon: Icons.badge_outlined,
            color: AppColors.primaryAccent,
            label: 'Consultores do time',
            value: '${team.length}',
            caption: 'os que mais fecharam • abra a Análise',
            onTap: () => onNavigate(2),
            child: KpiBars(
              color: AppColors.primaryAccent,
              empty: 'Nenhuma permuta do time ainda.',
              bars: [
                for (final c in team.take(3))
                  KpiBar(c.name, c.stats.sacksReceivable, formatSacks(c.stats.sacksReceivable),
                      detail: '${areaLabelOf(c.stats.area)} • ${formatInvestment(c.stats.investmentPerHa)}'),
              ],
            ),
          ),
          // O TEMPO DO TIME em cada etapa — inclusive a dele, o parecer. É o
          // número que diz se a fila dele está segurando o time.
          KpiTile(
            icon: Icons.schedule,
            color: AppColors.atManager,
            label: 'Tempo nas etapas',
            value: formatDays(averageStageDays(barters, BarterStage.opinion)),
            caption: 'o seu parecer, em média',
            child: KpiFacts(facts: [
              for (final stage in const [
                BarterStage.assembly,
                BarterStage.opinion,
                BarterStage.decision,
              ])
                KpiFact(stageLabel(stage), formatDays(averageStageDays(barters, stage))),
            ]),
          ),
        ]);

      // O COMITÊ: a fila da decisão e a operação com a régua dos outros painéis.
      case WorkPost.committee:
        return KpiGrid(maxColumns: 4, tiles: [
          _queueTile(post!),
          _statusTile(),
          _areaTile(stats),
          _sacksTile(stats),
        ]);

      // A SEGURADORA: o que espera a apólice, quanto ela leva e quanta área já
      // segurou, por cultura.
      case WorkPost.insurer:
        final insured = barters.where((b) => b.hasPolicy).toList();
        final slices = insuredAreaByGrain(barters);
        return KpiGrid(tiles: [
          _queueTile(post!, label: 'Pendentes de apólice'),
          KpiTile(
            icon: Icons.schedule,
            color: AppColors.primaryMedium,
            label: 'Tempo médio',
            value: formatDays(averageStageDays(barters, BarterStage.policy)),
            caption: 'da aprovação à apólice',
            child: KpiFacts(facts: [
              KpiFact('Apólices informadas', '${insured.length}'),
              KpiFact('Esperando agora', '${post.queue.length}'),
            ]),
          ),
          KpiTile(
            icon: Icons.shield_outlined,
            color: AppColors.approved,
            label: 'Área segurada',
            value: areaLabelOf(insured.fold(0.0, (sum, b) => sum + insuredAreaOf(b))),
            caption: '${insured.length} com apólice • por cultura',
            child: KpiBars(
              color: AppColors.approved,
              colorOf: AppColors.series,
              empty: 'Nenhuma apólice informada ainda.',
              bars: [for (final s in slices) KpiBar(s.label, s.value, areaLabelOf(s.value))],
            ),
          ),
        ]);

      // O FATURISTA: o que espera a nota, o que já saiu e quanto vale cada lado.
      case WorkPost.biller:
        final invoiced = barters.where((b) => b.wasInvoiced).toList();
        return KpiGrid(maxColumns: 4, tiles: [
          _queueTile(post!, extra: [
            KpiFact('Valor a faturar',
                formatCompactCurrency(post.queue.fold(0.0, (sum, b) => sum + b.inputCost))),
          ]),
          KpiTile(
            icon: Icons.receipt_long_outlined,
            color: AppColors.invoiced,
            label: 'Faturamento',
            value: formatCompactCurrency(invoiced.fold(0.0, (sum, b) => sum + b.inputCost)),
            caption: '${invoiced.length} permutas com nota',
            child: KpiFacts(facts: [
              KpiFact('Tempo médio até a nota',
                  formatDays(averageStageDays(barters, BarterStage.invoicing))),
              KpiFact('Notas anexadas',
                  '${invoiced.fold(0, (sum, b) => sum + b.invoices.length)}'),
            ]),
          ),
          _areaTile(stats),
          _sacksTile(stats),
        ]);

      // O EMISSOR: as cédulas por estado, o tempo de cada ato, os vencimentos
      // e as que estão paradas.
      case WorkPost.emitter:
        final bySeason = openCprsBySeason(barters);
        final stalled = oldestWaitingFirst(bySeason.expand((g) => g.barters)).take(3).toList();
        const acts = [BarterStage.cprIssue, BarterStage.cprSignature, BarterStage.cprRegistration];
        double? total;
        for (final act in acts) {
          final days = averageStageDays(barters, act);
          if (days != null) total = (total ?? 0) + days;
        }
        return KpiGrid(maxColumns: 4, tiles: [
          KpiTile(
            icon: post!.icon,
            color: post.color,
            label: 'Cédulas em aberto',
            value: '${post.queue.length}',
            caption: 'por estado',
            onTap: () => onNavigate(1),
            child: KpiFacts(facts: [
              KpiFact('A emitir', '${countWithStatus(barters, BarterStatus.invoiced)}',
                  dot: AppColors.invoiced),
              KpiFact('Emitidas', '${countWithStatus(barters, BarterStatus.cprIssued)}',
                  dot: AppColors.invoiced),
              KpiFact('Assinadas', '${countWithStatus(barters, BarterStatus.cprSigned)}',
                  dot: AppColors.invoiced),
              KpiFact('Registradas', '${countWithStatus(barters, BarterStatus.cprRegistered)}',
                  dot: AppColors.approved),
            ]),
          ),
          KpiTile(
            icon: Icons.schedule,
            color: AppColors.primaryMedium,
            label: 'Tempo médio por ato',
            value: formatDays(total),
            caption: 'da nota ao registro',
            child: KpiFacts(facts: [
              for (final act in acts) KpiFact(stageLabel(act), formatDays(averageStageDays(barters, act))),
            ]),
          ),
          KpiTile(
            icon: Icons.event_outlined,
            color: AppColors.pending,
            label: 'Prazos',
            value: '${bySeason.length}',
            caption: bySeason.length == 1 ? 'safra com cédula em aberto' : 'safras com cédula em aberto',
            child: bySeason.isEmpty
                ? Text('Nenhuma cédula em aberto.',
                    style: TextStyle(fontSize: 12, color: AppColors.textLight))
                : Column(
                    children: [
                      for (final group in bySeason)
                        _DeadlineRow(
                          label: group.label,
                          open: group.barters.length,
                          dueDate: AppData.versionForSeason(group.seasonId)?.cprDueDate,
                        ),
                    ],
                  ),
          ),
          KpiTile(
            icon: Icons.report_outlined,
            color: AppColors.denied,
            label: 'Pendências',
            value: stalled.isEmpty ? '0' : 'há ${_days(daysWaiting(stalled.first))}',
            caption: stalled.isEmpty ? 'nada parado' : 'a mais parada • toque para abrir',
            child: stalled.isEmpty
                ? null
                : Column(
                    children: [
                      for (final barter in stalled) _StalledCprRow(barter: barter, onChanged: onChanged),
                    ],
                  ),
          ),
        ]);

      // Sem posto: a operação.
      case null:
        return KpiGrid(tiles: [_statusTile(), _areaTile(stats), _sacksTile(stats)]);
    }
  }
}

/// Uma safra com cédula em aberto e o vencimento dela.
class _DeadlineRow extends StatelessWidget {
  final String label;
  final int open;
  final DateTime? dueDate;
  const _DeadlineRow({required this.label, required this.open, required this.dueDate});

  @override
  Widget build(BuildContext context) {
    final due = dueDate;
    final today = DateUtils.dateOnly(DateTime.now());
    final days = due == null ? null : DateUtils.dateOnly(due).difference(today).inDays;
    // Vencido em vermelho, a um mês em alerta; sem data, alerta também — é uma
    // pendência do cadastro da safra, e a cédula não sai sem ela.
    final color = days == null
        ? AppColors.pending
        : days < 0
            ? AppColors.denied
            : days <= 30
                ? AppColors.pending
                : AppColors.textMedium;
    final when = days == null
        ? 'vencimento não informado'
        : days < 0
            ? 'venceu há ${-days} dia${days == -1 ? '' : 's'} (${formatDate(due!)})'
            : days == 0
                ? 'vence hoje'
                : 'vence em $days dia${days == 1 ? '' : 's'} (${formatDate(due!)})';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(Icons.event_outlined, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                Text(when, style: TextStyle(fontSize: 11, color: color)),
              ],
            ),
          ),
          Text('$open em aberto',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.invoiced)),
        ],
      ),
    );
  }
}

/// Uma cédula parada: em que degrau ela está e há quanto tempo.
class _StalledCprRow extends StatelessWidget {
  final BarterModel barter;
  final VoidCallback onChanged;
  const _StalledCprRow({required this.barter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final days = daysWaiting(barter);
    final stage = currentStageOf(barter);
    final urgency = _UpstreamPanel._urgencyOf(days);

    return InkWell(
      onTap: () => openCprDesk(context, barter, onChanged: (_) => onChanged()),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
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
                  Text('${barter.cprNumber.isEmpty ? barter.id : barter.cprNumber} • ${barter.producerName}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                  Text(stage == null ? barter.statusLabel : stageLabel(stage),
                      style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(_UpstreamPanel._waitLabel(days),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: urgency)),
          ],
        ),
      ),
    );
  }
}
