import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/api/api_client.dart';
import '../widgets/common_widgets.dart';
import '../widgets/provisional_password_dialog.dart';
import 'edit_forms.dart';
import 'producer_profile_screen.dart';

/// Perfil de um consultor visto pelo admin: dados, desempenho e as permutas que
/// ele registrou (filtradas por consultantId).
class ConsultantProfileScreen extends StatefulWidget {
  final UserModel consultant;
  const ConsultantProfileScreen({super.key, required this.consultant});

  @override
  State<ConsultantProfileScreen> createState() => _ConsultantProfileScreenState();
}

class _ConsultantProfileScreenState extends State<ConsultantProfileScreen> {
  late UserModel consultant = widget.consultant;

  Future<void> _edit() async {
    final updated = await Navigator.push<UserModel>(
      context,
      MaterialPageRoute(
        builder: (_) => EditStaffScreen(user: consultant, role: UserRole.consultant),
      ),
    );
    if (updated != null) setState(() => consultant = updated);
  }

  /// Sorteia uma nova senha de primeira entrada para este consultor.
  ///
  /// É o caminho para os dois casos que acontecem de verdade: o consultor
  /// esqueceu a senha (não existe recuperação por e-mail — quem provisiona é o
  /// admin) ou a conta ficou com quem não devia. Nos dois, o reset derruba as
  /// sessões abertas, então a confirmação avisa isso antes.
  Future<void> _resetPassword() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.lock_reset, color: AppColors.pending, size: 40),
        title: const Text('Redefinir senha?'),
        content: Text(
          'Uma nova senha provisória será gerada para ${consultant.name.split(' ').first}, '
          'e a senha atual deixa de valer.\n\n'
          'Qualquer sessão aberta nesta conta será encerrada — inclusive no aparelho dele.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textMedium),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.lock_reset, size: 18),
            label: const Text('Redefinir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final provisioned = await AppData.resetConsultantPassword(consultant.id);
      if (!mounted) return;
      setState(() => consultant = provisioned.consultant);
      await showProvisionalPassword(context, provisioned, isReset: true);
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  void _delete() {
    confirmDeleteRegistration(
      context,
      title: 'Excluir Consultor',
      name: consultant.name,
      barterCount: AppData.barters.where((b) => b.consultantId == consultant.id).length,
      onConfirm: () async {
        // O servidor deixa a carteira sem dono e preserva o histórico.
        await AppData.deleteConsultant(consultant.id);
        if (mounted) Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = AppData.producersForConsultant(consultant.id);
    final barters = AppData.barters.where((b) => b.consultantId == consultant.id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final approvedList = barters.where((b) => b.status == BarterStatus.approved).toList();
    final pending = barters.where((b) => b.status == BarterStatus.pending).length;
    final denied = barters.where((b) => b.status == BarterStatus.denied).length;
    final atManager = barters.where((b) => b.awaitsManager).length;
    final sacks = approvedList.fold<double>(0, (s, b) => s + b.totalGrainQty);
    final inputsValue = approvedList.fold<double>(0, (s, b) => s + b.inputCost);

    return Scaffold(
      appBar: AppBar(
        title: Text('Consultor – ${consultant.name.split(' ')[0]}'),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: _edit),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.input,
                  radius: 40,
                  child: Text(consultant.avatarInitials,
                      style: TextStyle(color: AppColors.onPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
                Text(consultant.name,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                Text(consultant.branch,
                    style: TextStyle(fontSize: 13, color: AppColors.textMedium), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.inputBg, borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.badge_outlined, size: 13, color: AppColors.input),
                      SizedBox(width: 4),
                      Text('Consultor',
                          style: TextStyle(fontSize: 12, color: AppColors.input, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                InfoTile(icon: Icons.email_outlined, label: 'E-mail', value: consultant.email),
                const Divider(height: 1),
                InfoTile(icon: Icons.phone_outlined, label: 'Telefone', value: consultant.phone),
                const Divider(height: 1),
                InfoTile(icon: Icons.store_outlined, label: 'Unidade', value: consultant.branch),
                const Divider(height: 1),
                // A quem as permutas dele são enviadas. Fica junto do cadastro,
                // e não escondido na edição, porque é a resposta da pergunta
                // que traz o admin a esta tela.
                InfoTile(
                  icon: Icons.assignment_ind_outlined,
                  label: 'Gerente responsável',
                  value: consultant.managerName.isEmpty ? '—' : consultant.managerName,
                ),
                const Divider(height: 1),
                InfoTile(
                  icon: Icons.calendar_today_outlined,
                  label: 'Na empresa desde',
                  value: '${consultant.createdAt.month.toString().padLeft(2, '0')}/${consultant.createdAt.year}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Desempenho',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 12),
          GridView(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 140,
            ),
            physics: const NeverScrollableScrollPhysics(),
            children: [
              SummaryCard(
                title: '${brand.copy.barterPluralTitle} Criadas',
                value: barters.length.toString(),
                icon: Icons.swap_horiz,
                color: AppColors.primary,
              ),
              SummaryCard(
                title: 'Sacas Intermediadas',
                value: formatQty(sacks),
                icon: Icons.grass,
                color: AppColors.grain,
              ),
              SummaryCard(
                title: 'Insumos Movimentados',
                value: formatCurrency(inputsValue),
                icon: Icons.science_outlined,
                color: AppColors.input,
              ),
              SummaryCard(
                title: 'Em Revisão',
                value: pending.toString(),
                icon: Icons.hourglass_top,
                color: AppColors.pending,
              ),
              // Contagem própria: uma permuta que ainda não saiu da mesa do
              // gerente não é "em revisão", e juntar as duas esconderia
              // exatamente a etapa que acabou de ser criada.
              SummaryCard(
                title: 'No Gerente',
                value: atManager.toString(),
                icon: Icons.assignment_ind_outlined,
                color: AppColors.atManager,
              ),
            ],
          ),
          if (denied > 0) ...[
            const SizedBox(height: 8),
            Text('$denied permuta(s) negada(s)',
                style: TextStyle(fontSize: 12, color: AppColors.denied)),
          ],
          const SizedBox(height: 20),
          // Carteira de produtores: os clientes que só este consultor atende.
          Text('Carteira de Produtores (${wallet.length})',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 12),
          if (wallet.isEmpty)
            Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhum produtor na carteira', style: TextStyle(color: AppColors.textLight)),
              ),
            )
          else
            ...wallet.map((p) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ProducerProfileScreen(producer: p)),
                      );
                      if (mounted) setState(() {});
                    },
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primarySurface,
                      child: Text(p.avatarInitials,
                          style: TextStyle(
                              color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(p.name,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                    subtitle: Text('${p.location} • ${p.areaLabel}',
                        style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                        overflow: TextOverflow.ellipsis),
                    trailing: Icon(Icons.chevron_right, size: 18, color: AppColors.textLight),
                  ),
                )),
          const SizedBox(height: 20),
          Text('${brand.copy.barterPluralTitle} Registradas',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 12),
          if (barters.isEmpty)
            Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhuma permuta registrada', style: TextStyle(color: AppColors.textLight)),
              ),
            )
          else
            ...barters.map((b) => BarterLogItem(
                  barter: b,
                  subtitle: 'Produtor: ${b.producerName}',
                )),
          const SizedBox(height: 24),
          // Antes de excluir: quase sempre o problema é acesso, não cadastro.
          // Excluir desfaz a carteira inteira; redefinir a senha resolve o
          // caso comum sem tocar em nada disso.
          OutlinedButton.icon(
            onPressed: _resetPassword,
            icon: Icon(Icons.lock_reset, color: AppColors.pending),
            label: Text('Redefinir senha', style: TextStyle(color: AppColors.pending)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.pending),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          if (consultant.mustChangePassword) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.hourglass_top, size: 14, color: AppColors.textLight),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Ainda está com a senha provisória: vai defini-la ao entrar.',
                    style: TextStyle(fontSize: 12, color: AppColors.textLight),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _delete,
            icon: Icon(Icons.delete_outline, color: AppColors.denied),
            label: Text('Excluir consultor', style: TextStyle(color: AppColors.denied)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.denied),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

