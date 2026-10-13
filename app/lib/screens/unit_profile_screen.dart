import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/dashboard_stats.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/common_widgets.dart';
import 'consultant_profile_screen.dart';
import 'edit_forms.dart';
import 'staff_profile_screen.dart';

/// Perfil de uma UNIDADE, visto pelo admin na aba de cadastros: quem está
/// lotado nela, o gerente dela e as permutas retiradas lá.
///
/// É a mesma porta dos perfis de gente (ver [StaffProfileScreen]): tocar no
/// cartão mostra o que a unidade é e o que passa por ela, e a edição fica no
/// lápis.
class UnitProfileScreen extends StatefulWidget {
  final UnitModel unit;
  const UnitProfileScreen({super.key, required this.unit});

  @override
  State<UnitProfileScreen> createState() => _UnitProfileScreenState();
}

class _UnitProfileScreenState extends State<UnitProfileScreen> {
  late UnitModel unit = widget.unit;

  /// Todo mundo LOTADO nesta unidade, de qualquer papel — consultor primeiro,
  /// que é quem mais aparece, e o resto na ordem da linha de produção.
  List<UserModel> get _staff => [
        ...AppData.consultants,
        ...AppData.managers,
        if (AppData.committee != null) AppData.committee!,
        ...AppData.billers,
        ...AppData.emitters,
        ...AppData.admins,
      ].where((u) => u.unitId == unit.id).toList();

  Future<void> _edit() async {
    final updated = await Navigator.push<UnitModel>(
      context,
      MaterialPageRoute(builder: (_) => EditUnitScreen(unit: unit)),
    );
    if (updated != null) setState(() => unit = updated);
  }

  /// O servidor não trava a exclusão: as permutas guardam o nome da unidade, e
  /// quem estava lotado nela fica SEM unidade até o admin escolher outra — o
  /// formulário de cada um a exige no próximo salvamento. O diálogo diz quantos.
  void _delete() {
    final staff = _staff.length;
    confirmDeleteRegistration(
      context,
      title: 'Excluir Unidade',
      name: unit.name,
      barterCount: ofUnit(AppData.barters, unit.id).length,
      consequence: staff == 0
          ? null
          : '$staff pessoa(s) lotada(s) aqui ficam sem unidade até você escolher outra '
              'no cadastro de cada uma.',
      onConfirm: () async {
        await AppData.deleteUnit(unit.id);
        if (mounted) Navigator.pop(context);
      },
    );
  }

  Future<void> _open(UserModel u) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => u.role == UserRole.consultant
            ? ConsultantProfileScreen(consultant: u)
            : StaffProfileScreen(user: u, role: u.role),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final staff = _staff;
    final manager = AppData.managers.where((m) => m.unitId == unit.id).firstOrNull;
    final pickups = ofUnit(AppData.barters, unit.id)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final consultants = staff.where((u) => u.role == UserRole.consultant).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Unidade: ${unit.name}'),
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
                    backgroundColor: AppColors.primaryMedium,
                    radius: 40,
                    child: Text(unit.avatarInitials,
                        style: TextStyle(
                            color: AppColors.onPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Text(unit.name,
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark),
                      textAlign: TextAlign.center),
                  Text(unit.city,
                      style: TextStyle(fontSize: 13, color: AppColors.textMedium),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Column(
                children: [
                  InfoTile(icon: Icons.store_outlined, label: 'Nome', value: unit.name),
                  const Divider(height: 1),
                  InfoTile(icon: Icons.location_on_outlined, label: 'Município/UF', value: unit.city),
                  const Divider(height: 1),
                  // Cada unidade tem um gerente só — ver a regra no cadastro dele.
                  InfoTile(
                    icon: Icons.assignment_ind_outlined,
                    label: 'Gerente da unidade',
                    value: manager?.name ?? 'sem gerente',
                  ),
                  const Divider(height: 1),
                  InfoTile(
                    icon: Icons.calendar_today_outlined,
                    label: 'Cadastrada em',
                    value: formatDate(unit.createdAt),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Movimento',
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
                  title: 'Retiradas',
                  value: pickups.length.toString(),
                  icon: Icons.local_shipping_outlined,
                  color: AppColors.primary,
                ),
                SummaryCard(
                  title: 'Consultores Lotados',
                  value: consultants.toString(),
                  icon: Icons.badge_outlined,
                  color: AppColors.input,
                ),
              ],
            ),
            _sectionTitle('Pessoas lotadas (${staff.length})'),
            if (staff.isEmpty)
              _empty('Ninguém lotado nesta unidade')
            else
              ...staff.map((u) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => _open(u),
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primarySurface,
                        child: Text(u.avatarInitials,
                            style: TextStyle(
                                color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(u.name,
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                      subtitle: Text(u.role.label,
                          style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
                      trailing: Icon(Icons.chevron_right, size: 18, color: AppColors.textLight),
                    ),
                  )),
            _sectionTitle('Retiradas nesta unidade (${pickups.length})'),
            if (pickups.isEmpty)
              _empty('Nenhuma permuta retirada aqui')
            else
              ...pickups.map((b) => BarterLogItem(
                    barter: b,
                    subtitle: '${b.consultantName} • ${formatCurrency(b.inputCost)}',
                  )),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _delete,
              icon: Icon(Icons.delete_outline, color: AppColors.denied),
              label: Text('Excluir unidade', style: TextStyle(color: AppColors.denied)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.denied),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

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
}
