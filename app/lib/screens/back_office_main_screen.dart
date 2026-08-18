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
/// Os três entram com a mesma visão hoje: acompanham a operação inteira em
/// modo LEITURA. O que vai separá-los é o fluxo de aprovação que ainda será
/// desenhado, e é por isso que existe uma tela só, parametrizada pelo papel,
/// em vez de três telas iguais: quando cada um ganhar as próprias ações, a
/// separação acontece com o comportamento em mãos — não por antecipação.
class BackOfficeMainScreen extends StatefulWidget {
  final UserModel user;
  const BackOfficeMainScreen({super.key, required this.user});

  @override
  State<BackOfficeMainScreen> createState() => _BackOfficeMainScreenState();
}

class _BackOfficeMainScreenState extends State<BackOfficeMainScreen> {
  int _selectedIndex = 0;

  /// O gerente é o único da retaguarda que AGE sobre a permuta: ele dá o
  /// parecer técnico das que os consultores do time dele enviaram. Passar o id
  /// dele adiante é o que liga o botão de parecer nas permutas endereçadas a
  /// ele — e nas outras, não.
  String? get _opinionManagerId =>
      widget.user.role == UserRole.manager ? widget.user.id : null;

  late final List<Widget> _screens = [
    _BackOfficeHomeTab(user: widget.user, onQueueChanged: () => setState(() {})),
    // Retaguarda vê as permutas com valores (isAdmin), mas quem aprova ou nega
    // hoje é só o admin — daí canReview: false. QUAIS permutas cada um vê é
    // decidido pelo servidor: o gerente recebe só as do time dele.
    BartersScreen(
      isAdmin: true,
      consultantId: null,
      canReview: false,
      opinionManagerId: _opinionManagerId,
      onChanged: () => setState(() {}),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // O que espera o parecer DESTE gerente. Vira o número do selo na navegação:
    // o trabalho dele precisa se anunciar de qualquer aba, e não só quando ele
    // pensa em ir procurar.
    final waiting = AppData.opinionQueueFor(widget.user.id).length;

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
            icon: _PendingBadge(count: waiting, child: const Icon(Icons.swap_horiz_outlined)),
            activeIcon: _PendingBadge(count: waiting, child: const Icon(Icons.swap_horiz)),
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
  final Widget child;
  const _PendingBadge({required this.count, required this.child});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return child;
    return Badge(
      label: Text('$count'),
      backgroundColor: AppColors.atManager,
      textColor: AppColors.onPrimary,
      child: child,
    );
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
          focus: 'Parecer técnico das permutas do seu time, antes da revisão.',
          nextSteps: [
            'Alçadas: até onde o gerente decide sozinho',
            'Painel por consultor do time',
          ],
        );
      case UserRole.committee:
        return const _RoleBriefing(
          icon: Icons.groups_2,
          focus: 'Análise das permutas que sobem para o comitê.',
          nextSteps: [
            'Fila de análise do comitê',
            'Parecer e voto por permuta',
            'Devolução ao consultor com pendências',
          ],
        );
      case UserRole.biller:
        return const _RoleBriefing(
          icon: Icons.receipt_long,
          focus: 'Faturamento das permutas aprovadas.',
          nextSteps: [
            'Fila de faturamento das aprovadas',
            'Baixa de faturamento por permuta',
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
    final approved = AppData.barters.where((b) => b.status == BarterStatus.approved).toList();
    final pending = AppData.barters.where((b) => b.status == BarterStatus.pending).toList();
    final sacksReceivable = approved.fold<double>(0, (s, b) => s + b.totalGrainQty);
    // A FILA do gerente logado: o que espera o parecer dele, e só dele. Para
    // comitê e faturista a lista é vazia e o bloco não aparece.
    final queue = AppData.opinionQueueFor(user.id);

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
              caption: user.role == UserRole.manager
                  ? '${AppData.barters.length} permuta(s) do seu time'
                  : briefing.focus,
              icon: briefing.icon,
            ),
            const SizedBox(height: 16),
            _SummaryStrip(
              // Para o GERENTE o primeiro número é o dele: o que espera o
              // parecer. Para comitê e faturista, que não têm etapa própria
              // ainda, continua sendo a fila de revisão.
              waiting: user.role == UserRole.manager ? queue.length : null,
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
            if (user.role == UserRole.manager) ...[
              if (queue.isEmpty)
                const _EmptyQueueCard()
              else
                _OpinionQueueCard(queue: queue, onChanged: _onQueueChanged),
              const SizedBox(height: 20),
            ],
            if (briefing.nextSteps.isNotEmpty) ...[
              _NextStepsCard(role: user.role, steps: briefing.nextSteps),
              const SizedBox(height: 20),
            ],
            Text(
              user.role == UserRole.manager
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
                        canReview: false,
                        // A permuta abre com a MESMA ação que teria pela aba de
                        // permutas: é o mesmo registro e a mesma pessoa.
                        opinionManagerId:
                            user.role == UserRole.manager ? user.id : null,
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

/// A FILA DE PARECER do gerente logado — o que os consultores do time dele
/// enviaram e ainda espera a palavra dele.
///
/// Ela abre a tela porque é a única coisa aqui que pede ação: o resto do painel
/// é acompanhamento, e uma permuta parada esperando parecer não deveria depender
/// de alguém pensar em procurá-la numa aba.
class _OpinionQueueCard extends StatelessWidget {
  final List<BarterModel> queue;
  final VoidCallback onChanged;
  const _OpinionQueueCard({required this.queue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      // Borda na cor da etapa: é o único cartão desta tela que pede ação, e ele
      // precisa se separar dos que só informam.
      shape: RoundedRectangleBorder(
        borderRadius: AppShape.card,
        side: BorderSide(color: AppColors.atManager.withValues(alpha: 0.45), width: 1.5),
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
                    color: AppColors.atManagerBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.assignment_ind, size: 20, color: AppColors.atManager),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        queue.length == 1
                            ? '1 permuta esperando o seu parecer'
                            : '${queue.length} permutas esperando o seu parecer',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textDark),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Elas não seguem para a revisão até você escrever.',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.atManager),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'O parecer técnico não aprova nem nega — ele segue com a permuta para '
              'quem revisa, que o lê antes de decidir.',
              style: TextStyle(fontSize: 12, color: AppColors.textMedium),
            ),
            const Divider(height: 20),
            for (final barter in queue.take(4)) _QueueRow(barter: barter, onChanged: onChanged),
            if (queue.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'e mais ${queue.length - 4} na aba de permutas.',
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
/// Um bloco que some conforme o dia deixa a tela mudando de forma e o gerente
/// sem saber se ele está em dia ou se o app não carregou. Dizer "nada
/// esperando" responde as duas coisas de uma vez.
class _EmptyQueueCard extends StatelessWidget {
  const _EmptyQueueCard();

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
                  Text('Nenhum parecer pendente',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                  const SizedBox(height: 2),
                  Text(
                    'Nada do seu time esperando você agora. Puxe para atualizar.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMedium),
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

class _QueueRow extends StatelessWidget {
  final BarterModel barter;
  final VoidCallback onChanged;
  const _QueueRow({required this.barter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // A linha inteira abre a permuta: dar parecer sem ler o que tem
          // dentro seria assinar no escuro, e o botão ao lado é o atalho para
          // quem já sabe do que se trata.
          Expanded(
            child: InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BarterDetailScreen(
                      barter: barter,
                      isAdmin: true,
                      canReview: false,
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
            onPressed: () => giveBarterOpinion(context, barter, onGiven: (_) => onChanged()),
            icon: const Icon(Icons.rate_review_outlined, size: 16),
            label: const Text('Parecer', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.atManager,
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
/// [waiting] é do GERENTE: o que espera o parecer dele. Quando vem preenchido,
/// ele toma o lugar de "aprovadas" na faixa — a tela dele tem um trabalho a
/// fazer, e ele precisa estar entre os três números, não escondido embaixo.
class _SummaryStrip extends StatelessWidget {
  final int? waiting;
  final int pending;
  final int approved;
  final double sacks;
  const _SummaryStrip({
    required this.pending,
    required this.approved,
    required this.sacks,
    this.waiting,
  });

  @override
  Widget build(BuildContext context) {
    final cells = [
      if (waiting != null)
        _SummaryCell(
          icon: Icons.assignment_ind_outlined,
          color: AppColors.atManager,
          value: '$waiting',
          label: 'Esperando você',
        ),
      _SummaryCell(
        icon: Icons.hourglass_top,
        color: AppColors.pending,
        value: '$pending',
        label: 'Aguardando revisão',
      ),
      if (waiting == null)
        _SummaryCell(
          icon: Icons.check_circle_outline,
          color: AppColors.approved,
          value: '$approved',
          label: 'Aprovadas',
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
