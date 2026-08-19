import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/api/api_client.dart';
import '../widgets/common_widgets.dart';
import '../branding/brand_wordmark.dart';
import 'barters_screen.dart';
import 'barter_screen.dart';

class ConsultantMainScreen extends StatefulWidget {
  final UserModel consultant;
  const ConsultantMainScreen({super.key, required this.consultant});
  @override
  State<ConsultantMainScreen> createState() => _ConsultantMainScreenState();
}

class _ConsultantMainScreenState extends State<ConsultantMainScreen> {
  int _selectedIndex = 0;
  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      _ConsultantDashboardTab(consultant: widget.consultant, onNavigate: _go),
      _bartersTab(),
      NewBarterScreen(consultant: widget.consultant),
      _ConsultantProfileTab(consultant: widget.consultant),
    ];
  }

  /// `consultant` (e não só o id) é o que liga a aba de SIMULAÇÕES: retomar uma
  /// simulação abre o construtor de permuta, que precisa da carteira e do
  /// gerente de quem está montando.
  Widget _bartersTab() => BartersScreen(
        isAdmin: false,
        consultantId: widget.consultant.id,
        consultant: widget.consultant,
      );

  /// Vai para uma aba, RECRIANDO as duas que leem o cache a cada abertura.
  ///
  /// O [IndexedStack] guarda a instância de cada aba viva, e o `build` de uma
  /// aba parada não roda de novo só porque ela voltou a aparecer. Enquanto as
  /// duas eram permutas do servidor isso não incomodava; com a simulação passou
  /// a incomodar muito: guardar em "Nova Permuta" e trocar para a lista mostraria
  /// a aba "Simulações" com a contagem anterior — e sem a que acabou de sair.
  void _go(int i) {
    setState(() {
      if (i == 1) _screens[1] = _bartersTab();
      // Construtor de permuta: estado limpo a cada acesso.
      if (i == 2) _screens[2] = NewBarterScreen(consultant: widget.consultant);
      _selectedIndex = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _go,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textLight,
        selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Início'),
          BottomNavigationBarItem(icon: Icon(Icons.swap_horiz_outlined), activeIcon: const Icon(Icons.swap_horiz), label: brand.copy.barterPluralTitle),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline), activeIcon: const Icon(Icons.add_circle), label: 'Nova ${brand.copy.barterTitle}'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outlined), activeIcon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}

class _ConsultantDashboardTab extends StatefulWidget {
  final UserModel consultant;
  final Function(int) onNavigate;
  const _ConsultantDashboardTab({required this.consultant, required this.onNavigate});

  @override
  State<_ConsultantDashboardTab> createState() => _ConsultantDashboardTabState();
}

class _ConsultantDashboardTabState extends State<_ConsultantDashboardTab> {
  UserModel get consultant => widget.consultant;
  Function(int) get onNavigate => widget.onNavigate;

  /// Puxar para atualizar: recarrega permutas/carteira da API.
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
    final myBarters = AppData.barters.where((b) => b.consultantId == consultant.id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final approved = myBarters.where((b) => b.wasApproved).toList();
    final pending = myBarters.where((b) => b.status == BarterStatus.pending).length;
    final sacksDelivered = approved.fold<double>(0, (s, b) => s + b.totalGrainQty);

    return Scaffold(
      appBar: AppBar(
        title: const BrandWordmark(size: 32, showTagline: false),
        actions: [
          const LogoutButton(),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              backgroundColor: AppColors.primaryAccent,
              radius: 18,
              child: Text(consultant.avatarInitials,
                  style: TextStyle(color: AppColors.onPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
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
          // Antes de tudo: se o app abriu pelo pacote gravado, o consultor
          // precisa saber disso antes de ler qualquer número da tela.
          if (AppData.isOffline) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: OfflineBanner(),
            ),
          ],
          DashboardHeader(
            greetingName: consultant.name.split(' ')[0],
            subtitle: consultant.branch,
            caption: 'Registre permutas para seus produtores',
            icon: Icons.agriculture_outlined,
          ),
          const SizedBox(height: 16),
          GridView(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 160,
            ),
            physics: const NeverScrollableScrollPhysics(),
            children: [
              SummaryCard(
                title: 'Minhas ${brand.copy.barterPluralTitle}',
                value: myBarters.length.toString(),
                icon: Icons.swap_horiz,
                color: AppColors.primary,
              ),
              SummaryCard(
                title: 'Sacas Entregues',
                value: formatQty(sacksDelivered),
                icon: Icons.grass,
                color: AppColors.grain,
                subtitle: 'em permutas aprovadas',
              ),
              SummaryCard(
                title: 'Aprovadas',
                value: approved.length.toString(),
                icon: Icons.check_circle_outline,
                color: AppColors.approved,
              ),
              SummaryCard(
                title: 'No Comitê',
                value: pending.toString(),
                icon: Icons.hourglass_top,
                color: AppColors.pending,
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => onNavigate(2),
              icon: const Icon(Icons.swap_horiz),
              label: Text('Nova ${brand.copy.barterTitle}'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Uma simulação esquecida é uma permuta que o gerente nunca vai ver —
          // e que ninguém no sistema tem como cobrar, porque ela só existe neste
          // aparelho. O aviso é a única coisa que a torna visível.
          if (AppData.mySimulations.isNotEmpty) ...[
            InkWell(
              onTap: () => onNavigate(1),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.pendingBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.pending.withValues(alpha: 0.30)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.bookmark_border, size: 20, color: AppColors.pending),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${AppData.mySimulations.length} simulação(ões) guardada(s) neste '
                        'aparelho, ainda não encaminhada(s) ao gerente.',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.pending),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 20, color: AppColors.pending),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Últimas Permutas',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              TextButton(
                onPressed: () => onNavigate(1),
                child: Text('Ver todas', style: TextStyle(fontSize: 12, color: AppColors.primaryMedium)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (myBarters.isEmpty)
            Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhuma permuta ainda', style: TextStyle(color: AppColors.textLight)),
              ),
            )
          else
            ...myBarters.take(3).map((b) => MiniBarterCard(barter: b, isAdmin: false)),
          const SizedBox(height: 16),
        ],
        ),
      ),
    );
  }
}

class _ConsultantProfileTab extends StatelessWidget {
  final UserModel consultant;
  const _ConsultantProfileTab({required this.consultant});

  @override
  Widget build(BuildContext context) {
    final myBarters = AppData.barters.where((b) => b.consultantId == consultant.id).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu Perfil'),
        actions: const [LogoutButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary,
                  radius: 40,
                  child: Text(consultant.avatarInitials,
                      style: TextStyle(color: AppColors.onPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
                Text(consultant.name,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                Text(consultant.branch,
                    style: TextStyle(fontSize: 13, color: AppColors.textMedium)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Consultor',
                      style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                InfoTile(icon: Icons.email_outlined, label: 'E-mail', value: consultant.email),
                const Divider(height: 1),
                InfoTile(icon: Icons.phone_outlined, label: 'Telefone', value: consultant.phone),
                const Divider(height: 1),
                InfoTile(icon: Icons.store_outlined, label: 'Unidade', value: consultant.branch),
                const Divider(height: 1),
                // Saber A QUEM as próprias permutas vão é o que permite ao
                // consultor cobrar o parecer da pessoa certa em vez de
                // perguntar ao admin onde a permuta dele parou.
                InfoTile(
                  icon: Icons.assignment_ind_outlined,
                  label: 'Meu gerente',
                  value: consultant.managerName.isEmpty ? '—' : consultant.managerName,
                ),
                const Divider(height: 1),
                InfoTile(
                  icon: Icons.calendar_today_outlined,
                  label: 'Membro desde',
                  value: '${consultant.createdAt.month.toString().padLeft(2, '0')}/${consultant.createdAt.year}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Meu Histórico',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: SummaryCard(
                title: 'Total ${brand.copy.barterPluralTitle}',
                value: myBarters.length.toString(),
                icon: Icons.swap_horiz,
                color: AppColors.primary,
              )),
              const SizedBox(width: 12),
              Expanded(child: SummaryCard(
                title: 'Aprovadas',
                value: myBarters.where((b) => b.wasApproved).length.toString(),
                icon: Icons.check_circle_outline,
                color: AppColors.approved,
              )),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => openChangePassword(context),
            icon: Icon(Icons.lock_reset, color: AppColors.primary),
            label: Text('Alterar senha', style: TextStyle(color: AppColors.primary)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => confirmLogout(context),
            icon: Icon(Icons.logout, color: AppColors.denied),
            label: Text('Sair', style: TextStyle(color: AppColors.denied)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.denied),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

