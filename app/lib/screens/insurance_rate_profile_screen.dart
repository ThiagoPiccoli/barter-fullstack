import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/common_widgets.dart';
import 'edit_forms.dart';
import 'producer_profile_screen.dart';

/// Perfil de uma PRAÇA da base de seguros, visto pelo admin na aba de
/// cadastros: o valor por hectare e os produtores que ele alcança, com quanto o
/// seguro custa para cada um.
///
/// A mesma porta dos outros cadastros: tocar no cartão mostra a praça, e a
/// edição fica no lápis.
class InsuranceRateProfileScreen extends StatefulWidget {
  final InsuranceRateModel rate;
  const InsuranceRateProfileScreen({super.key, required this.rate});

  @override
  State<InsuranceRateProfileScreen> createState() => _InsuranceRateProfileScreenState();
}

class _InsuranceRateProfileScreenState extends State<InsuranceRateProfileScreen> {
  late InsuranceRateModel rate = widget.rate;

  /// Os produtores desta praça — pela mesma regra que o servidor usa para
  /// cotar a permuta (`insuranceRateFor`), e não por comparação de texto aqui.
  List<ProducerModel> get _producers =>
      AppData.producers.where((p) => AppData.insuranceRateFor(p.city)?.id == rate.id).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  String get _valueLabel => rate.showsCurrency
      ? '${formatCurrency(rate.valuePerHa)}/ha'
      : '${rate.sacksPerHa.toStringAsFixed(2).replaceAll('.', ',')} sc/ha';

  Future<void> _edit() async {
    final updated = await Navigator.push<InsuranceRateModel>(
      context,
      MaterialPageRoute(builder: (_) => EditInsuranceRateScreen(rate: rate)),
    );
    if (updated != null) setState(() => rate = updated);
  }

  /// Excluir a praça não mexe nas permutas: a taxa está congelada em cada uma.
  /// O que some é a permuta NOVA dos produtores daqui enquanto o Barter levar
  /// seguro — e é isso que o diálogo avisa.
  void _delete() {
    final producers = _producers.length;
    confirmDeleteRegistration(
      context,
      title: 'Excluir Praça',
      name: rate.city,
      barterCount: 0,
      consequence: producers == 0
          ? null
          : '$producers produtor(es) desta praça ficam sem taxa: com o seguro ligado no '
              'lançamento, a permuta nova deles é recusada no registro.',
      onConfirm: () async {
        await AppData.deleteInsuranceRate(rate.id);
        if (mounted) Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final producers = _producers;

    return Scaffold(
      appBar: AppBar(
        title: Text('Praça: ${rate.city}'),
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
                    backgroundColor: AppColors.atManager,
                    radius: 40,
                    child: Icon(Icons.shield, color: AppColors.onPrimary, size: 34),
                  ),
                  const SizedBox(height: 12),
                  Text(rate.city,
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark),
                      textAlign: TextAlign.center),
                  Text('Seguro agrícola — $_valueLabel',
                      style: TextStyle(fontSize: 13, color: AppColors.textMedium),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Column(
                children: [
                  InfoTile(icon: Icons.location_on_outlined, label: 'Município/UF', value: rate.city),
                  const Divider(height: 1),
                  InfoTile(icon: Icons.shield_outlined, label: 'Valor por hectare', value: _valueLabel),
                  const Divider(height: 1),
                  InfoTile(
                    icon: Icons.notes_outlined,
                    label: 'Observação',
                    value: (rate.note ?? '').isEmpty ? '—' : rate.note!,
                  ),
                  if (rate.updatedAt != null) ...[
                    const Divider(height: 1),
                    InfoTile(
                      icon: Icons.update,
                      label: 'Atualizada em',
                      value: formatDate(rate.updatedAt!),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 12),
              child: Text('Produtores nesta praça (${producers.length})',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            ),
            if (producers.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Nenhum produtor cadastrado neste município',
                      style: TextStyle(color: AppColors.textLight)),
                ),
              )
            else
              ...producers.map((p) => Card(
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
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                      // A ÁREA não é mais do cadastro — o custo do seguro sai em
                      // cada permuta, sobre a área plantada dela.
                      subtitle: Text(
                        p.location,
                        style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(Icons.chevron_right, size: 18, color: AppColors.textLight),
                    ),
                  )),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _delete,
              icon: Icon(Icons.delete_outline, color: AppColors.denied),
              label: Text('Excluir praça', style: TextStyle(color: AppColors.denied)),
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
}
