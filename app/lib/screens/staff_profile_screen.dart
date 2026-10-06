import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/dashboard_stats.dart';
import '../services/api/api_client.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/common_widgets.dart';
import '../widgets/provisional_password_dialog.dart';
import 'consultant_profile_screen.dart';
import 'edit_forms.dart';

/// Perfil de quem trabalha na RETAGUARDA — gerente, comitê, faturista, emissor
/// e admin — visto pelo admin na aba de cadastros.
///
/// É a mesma porta do consultor ([ConsultantProfileScreen]): tocar no cartão
/// abre o que a pessoa É e o que ela FEZ, e a edição fica no lápis. Antes estes
/// cinco abriam direto no formulário, e conferir o time de um gerente ou o que
/// um faturista faturou exigia entrar no modo de edição para ler.
///
/// Uma tela para os cinco porque o esqueleto é o mesmo — cadastro, números,
/// listas, senha e exclusão —, e o que muda é o TRABALHO de cada posto, que
/// cada um deixa na permuta de um jeito (ver `opinionsOf`, `invoicedBy`,
/// `issuedBy` em `services/dashboard_stats.dart`).
class StaffProfileScreen extends StatefulWidget {
  final UserModel user;
  final UserRole role;
  const StaffProfileScreen({super.key, required this.user, required this.role});

  @override
  State<StaffProfileScreen> createState() => _StaffProfileScreenState();
}

class _StaffProfileScreenState extends State<StaffProfileScreen> {
  late UserModel user = widget.user;

  UserRole get _role => widget.role;
  bool get _isCommittee => _role == UserRole.committee;

  /// A PRÓPRIA CONTA não tem senha nem exclusão aqui: a senha dela se troca por
  /// "Alterar senha", e o servidor recusa excluí-la.
  bool get _isSelf => user.id == AppData.currentUser?.id;

  Color get _accent => switch (_role) {
        UserRole.manager => AppColors.atManager,
        UserRole.committee => AppColors.pending,
        UserRole.insurer => AppColors.atInsurer,
        UserRole.biller || UserRole.emitter => AppColors.invoiced,
        UserRole.admin => AppColors.primaryAccent,
        UserRole.consultant => AppColors.input,
      };

  IconData get _icon => switch (_role) {
        UserRole.manager => Icons.assignment_ind_outlined,
        UserRole.committee => Icons.groups_2_outlined,
        UserRole.insurer => Icons.shield_outlined,
        UserRole.biller => Icons.receipt_long_outlined,
        UserRole.emitter => Icons.description_outlined,
        UserRole.admin => Icons.admin_panel_settings_outlined,
        UserRole.consultant => Icons.badge_outlined,
      };

  Future<void> _edit() async {
    final updated = await Navigator.push<UserModel>(
      context,
      MaterialPageRoute(builder: (_) => EditStaffScreen(user: user, role: _role)),
    );
    if (updated != null) setState(() => user = updated);
  }

  /// Nova senha de primeira entrada. Derruba as sessões abertas do titular no
  /// servidor — a confirmação diz isso antes.
  Future<void> _resetPassword() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.lock_reset, color: AppColors.pending, size: 40),
        title: const Text('Redefinir senha?'),
        content: Text(
          _isCommittee
              // Na conta compartilhada a frase é outra porque o efeito é outro:
              // a senha circula entre quem participa da reunião, e trocá-la tira
              // o acesso de TODO MUNDO que estava com a anterior.
              ? 'Uma nova senha provisória será gerada para o ${user.name}, e a atual '
                  'deixa de valer para todos que a tinham.\n\n'
                  'Qualquer sessão aberta nesta conta será encerrada.'
              : 'Uma nova senha provisória será gerada para ${user.name.split(' ').first}, '
                  'e a senha atual deixa de valer.\n\n'
                  'Qualquer sessão aberta nesta conta será encerrada.',
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
    if (ok != true || !mounted) return;

    try {
      final provisioned = await switch (_role) {
        // O comitê não tem id na rota: o cadastro é um só.
        UserRole.committee => AppData.resetCommitteePassword(),
        UserRole.insurer => AppData.resetInsurerPassword(user.id),
        UserRole.biller => AppData.resetBillerPassword(user.id),
        UserRole.emitter => AppData.resetEmitterPassword(user.id),
        UserRole.admin => AppData.resetAdminPassword(user.id),
        UserRole.manager => AppData.resetManagerPassword(user.id),
        UserRole.consultant => AppData.resetConsultantPassword(user.id),
      };
      if (!mounted) return;
      setState(() => user = provisioned.consultant);
      await showProvisionalPassword(context, provisioned, isReset: true);
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// Exclusão de GERENTE, SEGURADORA, FATURISTA, EMISSOR e ADMIN.
  ///
  /// No gerente o servidor RECUSA enquanto ele tiver consultores no time ou
  /// permutas esperando o parecer dele, e a mensagem diz qual dos dois falta — a
  /// tela só a exibe, em vez de repetir a regra aqui e arriscar divergir dela.
  ///
  /// O COMITÊ não tem este botão, e nem rota: o cadastro é a ETAPA, e sem ele
  /// nenhuma permuta é decidida. Para tirar o acesso, redefine-se a senha.
  void _delete() {
    confirmDeleteRegistration(
      context,
      title: 'Excluir ${_role.label}',
      name: user.name,
      barterCount: switch (_role) {
        UserRole.insurer => insuredBy(AppData.barters, user.name),
        UserRole.biller => invoicedBy(AppData.barters, user.name),
        UserRole.emitter => issuedBy(AppData.barters, user.name),
        UserRole.manager => opinionsOf(AppData.barters, user.id),
        _ => 0,
      },
      onConfirm: () async {
        await switch (_role) {
          UserRole.insurer => AppData.deleteInsurer(user.id),
          UserRole.biller => AppData.deleteBiller(user.id),
          UserRole.emitter => AppData.deleteEmitter(user.id),
          UserRole.admin => AppData.deleteAdmin(user.id),
          _ => AppData.deleteManager(user.id),
        };
        if (mounted) Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final since = '${user.createdAt.month.toString().padLeft(2, '0')}/${user.createdAt.year}';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCommittee ? user.name : '${_role.label}: ${user.name.split(' ')[0]}'),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: _edit),
        ],
      ),
      body: BoundedContent(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    backgroundColor: _accent,
                    radius: 40,
                    child: Text(user.avatarInitials,
                        style: TextStyle(
                            color: AppColors.onPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Text(user.name,
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark),
                      textAlign: TextAlign.center),
                  Text(user.branch,
                      style: TextStyle(fontSize: 13, color: AppColors.textMedium),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_icon, size: 13, color: _accent),
                        const SizedBox(width: 4),
                        Text(_isSelf ? '${_role.label} • você' : _role.label,
                            style: TextStyle(
                                fontSize: 12, color: _accent, fontWeight: FontWeight.w600)),
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
                  InfoTile(icon: Icons.email_outlined, label: 'E-mail', value: user.email),
                  const Divider(height: 1),
                  InfoTile(icon: Icons.phone_outlined, label: 'Telefone', value: user.phone),
                  const Divider(height: 1),
                  InfoTile(
                    icon: Icons.store_outlined,
                    label: _isCommittee ? 'Onde se reúne' : 'Unidade',
                    value: user.branch,
                  ),
                  const Divider(height: 1),
                  InfoTile(
                    icon: Icons.calendar_today_outlined,
                    label: _isCommittee ? 'Cadastrado em' : 'Na empresa desde',
                    value: since,
                  ),
                ],
              ),
            ),
            ..._work(),
            const SizedBox(height: 24),
            if (!_isSelf) ..._accessButtons(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// O TRABALHO do posto: os números e as listas que respondem à pergunta que
  /// traz o admin até aqui. O admin não tem fila nem assinatura em permuta, e
  /// por isso não tem esta parte.
  List<Widget> _work() => switch (_role) {
        UserRole.manager => _managerWork(),
        UserRole.committee => _committeeWork(),
        UserRole.insurer => _signedWork(
            title: 'Apólices informadas',
            count: 'Apólices',
            icon: Icons.shield,
            barters: AppData.barters.where((b) => b.insuredBy == user.name),
            empty: 'Nenhuma apólice informada',
          ),
        UserRole.biller => _signedWork(
            title: 'Faturadas por ele',
            count: 'Faturadas',
            icon: Icons.receipt_long,
            barters: AppData.barters.where((b) => b.invoicedBy == user.name),
            empty: 'Nenhuma permuta faturada',
          ),
        UserRole.emitter => _signedWork(
            title: 'CPRs emitidas',
            count: 'CPRs Emitidas',
            icon: Icons.description,
            barters: AppData.barters.where((b) => b.cprEmittedBy == user.name),
            empty: 'Nenhuma CPR emitida',
          ),
        UserRole.admin || UserRole.consultant => const [],
      };

  /// O GERENTE: o time dele e a fila esperando parecer — as duas coisas que o
  /// servidor confere antes de deixá-lo sair.
  List<Widget> _managerWork() {
    final team = AppData.consultants.where((c) => c.managerId == user.id).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final queue = AppData.opinionQueueFor(user.id)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return [
      ..._numbers([
        SummaryCard(
          title: 'Consultores no Time',
          value: team.length.toString(),
          icon: Icons.groups_outlined,
          color: AppColors.input,
        ),
        SummaryCard(
          title: 'Esperando Parecer',
          value: queue.length.toString(),
          icon: Icons.assignment_ind_outlined,
          color: AppColors.atManager,
        ),
        SummaryCard(
          title: 'Permutas Recebidas',
          value: opinionsOf(AppData.barters, user.id).toString(),
          icon: Icons.swap_horiz,
          color: AppColors.primary,
        ),
      ]),
      _sectionTitle('Consultores do time (${team.length})'),
      if (team.isEmpty)
        _empty('Nenhum consultor no time ainda')
      else
        ...team.map((c) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ConsultantProfileScreen(consultant: c)),
                  );
                  if (mounted) setState(() {});
                },
                leading: CircleAvatar(
                  backgroundColor: AppColors.inputBg,
                  child: Text(c.avatarInitials,
                      style: TextStyle(
                          color: AppColors.input, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                title: Text(c.name,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                subtitle: Text(c.branch,
                    style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                    overflow: TextOverflow.ellipsis),
                trailing: Icon(Icons.chevron_right, size: 18, color: AppColors.textLight),
              ),
            )),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'O time se monta no cadastro de cada consultor, escolhendo o gerente dele.',
          style: TextStyle(fontSize: 11, color: AppColors.textLight),
        ),
      ),
      _sectionTitle('Esperando parecer (${queue.length})'),
      ..._barterList(queue, 'Nada esperando o parecer dele'),
    ];
  }

  /// O COMITÊ é um órgão: não há nome para contar, há decisão. A fila é o
  /// ESTADO da permuta, a mesma para quem participar da reunião.
  List<Widget> _committeeWork() {
    final queue = AppData.committeeQueue..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [
      ..._numbers([
        SummaryCard(
          title: 'Esperando Decisão',
          value: queue.length.toString(),
          icon: Icons.hourglass_top,
          color: AppColors.pending,
        ),
        SummaryCard(
          title: 'Decididas',
          value: decidedCount(AppData.barters).toString(),
          icon: Icons.gavel,
          color: AppColors.approved,
        ),
      ]),
      _sectionTitle('Esperando decisão (${queue.length})'),
      ..._barterList(queue, 'Nada esperando decisão'),
    ];
  }

  /// FATURISTA e EMISSOR: o que ficou ASSINADO com o nome deles na permuta.
  List<Widget> _signedWork({
    required String title,
    required String count,
    required IconData icon,
    required Iterable<BarterModel> barters,
    required String empty,
  }) {
    final list = barters.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [
      ..._numbers([
        SummaryCard(title: count, value: list.length.toString(), icon: icon, color: _accent),
      ]),
      _sectionTitle('$title (${list.length})'),
      ..._barterList(list, empty),
    ];
  }

  List<Widget> _numbers(List<Widget> cards) => [
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
          children: cards,
        ),
      ];

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 12),
        child: Text(text,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
      );

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, style: TextStyle(color: AppColors.textLight)),
        ),
      );

  List<Widget> _barterList(List<BarterModel> list, String empty) => list.isEmpty
      ? [_empty(empty)]
      : list
          .map((b) => BarterLogItem(
                barter: b,
                subtitle: '${b.consultantName} • ${formatCurrency(b.inputCost)}',
              ))
          .toList();

  /// Senha e exclusão — os mesmos dois botões do perfil do consultor.
  List<Widget> _accessButtons() => [
        // Antes de excluir: quase sempre o problema é acesso, não cadastro.
        OutlinedButton.icon(
          onPressed: _resetPassword,
          icon: Icon(Icons.lock_reset, color: AppColors.pending),
          label: Text('Redefinir senha', style: TextStyle(color: AppColors.pending)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppColors.pending),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        if (user.mustChangePassword) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.hourglass_top, size: 14, color: AppColors.textLight),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Ainda está com a senha provisória: vai defini-la ao entrar.',
                  style: TextStyle(fontSize: 12, color: AppColors.textLight),
                ),
              ),
            ],
          ),
        ],
        // O COMITÊ não se exclui: o cadastro é a ETAPA. Não há rota para isso no
        // servidor, e a tela não oferece um botão que levaria a um 422.
        if (!_isCommittee) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _delete,
            icon: Icon(Icons.delete_outline, color: AppColors.denied),
            label: Text('Excluir ${_role.label.toLowerCase()}',
                style: TextStyle(color: AppColors.denied)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.denied),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ];
}
