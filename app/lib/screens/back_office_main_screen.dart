import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../branding/brand_wordmark.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../services/api/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
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
  late final List<Widget> _screens = [
    _BackOfficeHomeTab(user: widget.user),
    // Retaguarda vê todas as permutas com valores (isAdmin), mas quem aprova
    // ou nega hoje é só o admin — daí canReview: false.
    const BartersScreen(isAdmin: true, consultantId: null, canReview: false),
  ];

  @override
  Widget build(BuildContext context) {
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
            icon: const Icon(Icons.swap_horiz_outlined),
            activeIcon: const Icon(Icons.swap_horiz),
            label: brand.copy.barterPluralTitle,
          ),
        ],
      ),
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
        return const _RoleBriefing(
          icon: Icons.insights,
          focus: 'Acompanhamento da operação: volumes, carteiras e filiais.',
          nextSteps: [
            'Etapa do gerente no fluxo de aprovação',
            'Alçadas: até onde o gerente decide sozinho',
            'Painel por filial e por consultor',
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
  const _BackOfficeHomeTab({required this.user});

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
  }

  @override
  Widget build(BuildContext context) {
    final briefing = _RoleBriefing.of(user.role);
    final approved = AppData.barters.where((b) => b.status == BarterStatus.approved).toList();
    final pending = AppData.barters.where((b) => b.status == BarterStatus.pending).toList();
    final sacksReceivable = approved.fold<double>(0, (s, b) => s + b.totalGrainQty);

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
              caption: briefing.focus,
              icon: briefing.icon,
            ),
            const SizedBox(height: 16),
            _SummaryStrip(
              pending: pending.length,
              approved: approved.length,
              sacks: sacksReceivable,
            ),
            const SizedBox(height: 20),
            if (briefing.nextSteps.isNotEmpty) ...[
              _NextStepsCard(role: user.role, steps: briefing.nextSteps),
              const SizedBox(height: 20),
            ],
            Text(
              '${brand.copy.barterPluralTitle} Recentes',
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
                  .map((b) => MiniBarterCard(barter: b, isAdmin: true, canReview: false)),
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

/// Três números para dar o tamanho da operação de hoje, sem repetir a lista.
class _SummaryStrip extends StatelessWidget {
  final int pending;
  final int approved;
  final double sacks;
  const _SummaryStrip({required this.pending, required this.approved, required this.sacks});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _SummaryCell(
                  icon: Icons.hourglass_top,
                  color: AppColors.pending,
                  value: '$pending',
                  label: 'Em análise',
                ),
              ),
              const VerticalDivider(width: 1, indent: 4, endIndent: 4),
              Expanded(
                child: _SummaryCell(
                  icon: Icons.check_circle_outline,
                  color: AppColors.approved,
                  value: '$approved',
                  label: 'Aprovadas',
                ),
              ),
              const VerticalDivider(width: 1, indent: 4, endIndent: 4),
              Expanded(
                child: _SummaryCell(
                  icon: Icons.grass,
                  color: AppColors.grain,
                  value: formatSacks(sacks),
                  label: 'A receber',
                ),
              ),
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
/// parece pronta: quem entra como gerente, comitê ou faturista precisa saber
/// que o acesso já existe e que as ações dele vêm na sequência.
class _NextStepsCard extends StatelessWidget {
  final UserRole role;
  final List<String> steps;
  const _NextStepsCard({required this.role, required this.steps});

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
                    'Acesso de ${role.label} liberado',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Por enquanto o acompanhamento é em modo leitura. Em construção:',
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
