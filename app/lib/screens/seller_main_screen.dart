import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/mock_data.dart';
import '../widgets/common_widgets.dart';
import 'barters_screen.dart';
import 'barter_screen.dart';

class SellerMainScreen extends StatefulWidget {
  final UserModel seller;
  const SellerMainScreen({super.key, required this.seller});
  @override
  State<SellerMainScreen> createState() => _SellerMainScreenState();
}

class _SellerMainScreenState extends State<SellerMainScreen> {
  int _selectedIndex = 0;
  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      _SellerDashboardTab(seller: widget.seller, onNavigate: _go),
      BartersScreen(isAdmin: false, sellerId: widget.seller.id),
      NewBarterScreen(seller: widget.seller),
      _SellerProfileTab(seller: widget.seller),
    ];
  }

  void _go(int i) => setState(() => _selectedIndex = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) {
          if (i == 2) {
            // Recria o construtor de permuta a cada acesso (estado limpo).
            setState(() {
              _screens[2] = NewBarterScreen(seller: widget.seller);
              _selectedIndex = i;
            });
          } else {
            setState(() => _selectedIndex = i);
          }
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textLight,
        selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Início'),
          BottomNavigationBarItem(icon: Icon(Icons.swap_horiz_outlined), activeIcon: Icon(Icons.swap_horiz), label: 'Permutas'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline), activeIcon: Icon(Icons.add_circle), label: 'Nova Permuta'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outlined), activeIcon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}

class _SellerDashboardTab extends StatelessWidget {
  final UserModel seller;
  final Function(int) onNavigate;
  const _SellerDashboardTab({required this.seller, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final myBarters = mockBarters.where((b) => b.sellerId == seller.id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final approved = myBarters.where((b) => b.status == BarterStatus.approved).toList();
    final pending = myBarters.where((b) => b.status == BarterStatus.pending).length;
    final sacksDelivered = approved.fold<double>(0, (s, b) => s + b.totalGrainQty);

    return Scaffold(
      appBar: AppBar(
        title: const BarterLogo(size: 32),
        actions: [
          const LogoutButton(),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              backgroundColor: AppColors.primaryAccent,
              radius: 18,
              child: Text(seller.avatarInitials,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DashboardHeader(
            greetingName: seller.name.split(' ')[0],
            subtitle: seller.branch,
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
                title: 'Minhas Permutas',
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
                title: 'Em Análise',
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
              label: const Text('Nova Permuta'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Últimas Permutas',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              TextButton(
                onPressed: () => onNavigate(1),
                child: const Text('Ver todas', style: TextStyle(fontSize: 12, color: AppColors.primaryMedium)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (myBarters.isEmpty)
            const Center(
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
    );
  }
}

class _SellerProfileTab extends StatelessWidget {
  final UserModel seller;
  const _SellerProfileTab({required this.seller});

  @override
  Widget build(BuildContext context) {
    final myBarters = mockBarters.where((b) => b.sellerId == seller.id).toList();
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
                  child: Text(seller.avatarInitials,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
                Text(seller.name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                Text(seller.branch,
                    style: const TextStyle(fontSize: 13, color: AppColors.textMedium)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Vendedor',
                      style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                InfoTile(icon: Icons.email_outlined, label: 'E-mail', value: seller.email),
                const Divider(height: 1),
                InfoTile(icon: Icons.phone_outlined, label: 'Telefone', value: seller.phone),
                const Divider(height: 1),
                InfoTile(icon: Icons.store_outlined, label: 'Filial', value: seller.branch),
                const Divider(height: 1),
                InfoTile(
                  icon: Icons.calendar_today_outlined,
                  label: 'Membro desde',
                  value: '${seller.createdAt.month.toString().padLeft(2, '0')}/${seller.createdAt.year}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Meu Histórico',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: SummaryCard(
                title: 'Total Permutas',
                value: myBarters.length.toString(),
                icon: Icons.swap_horiz,
                color: AppColors.primary,
              )),
              const SizedBox(width: 12),
              Expanded(child: SummaryCard(
                title: 'Aprovadas',
                value: myBarters.where((b) => b.status == BarterStatus.approved).length.toString(),
                icon: Icons.check_circle_outline,
                color: AppColors.approved,
              )),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => confirmLogout(context),
            icon: const Icon(Icons.logout, color: AppColors.denied),
            label: const Text('Sair', style: TextStyle(color: AppColors.denied)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.denied),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

