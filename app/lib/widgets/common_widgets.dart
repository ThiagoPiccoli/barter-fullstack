import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/api/api_client.dart';
import '../screens/login_screen.dart';
import '../screens/barter_detail_screen.dart';
import '../screens/change_password_screen.dart';

/// SnackBar padrão de erro do app (usada por todos os fluxos que chamam a
/// API). [error] pode ser uma [ApiException] (mensagem legível do servidor)
/// ou uma String.
void showErrorSnack(BuildContext context, Object error) =>
    showErrorOn(ScaffoldMessenger.of(context), error.toString());

/// Mesma SnackBar de erro, a partir de um messenger já resolvido — para os
/// avisos que nascem fora da árvore de widgets (ex.: a sessão expirada
/// detectada na camada de dados, que não tem BuildContext à mão).
void showErrorOn(ScaffoldMessengerState? messenger, String message) {
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: AppColors.denied,
      behavior: SnackBarBehavior.floating,
    ));
}

/// Formata um valor monetário no padrão brasileiro: R$ 1.234,56
String formatCurrency(double v) {
  final s = v.toStringAsFixed(2);
  final parts = s.split('.');
  final intPart = parts[0]
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  return 'R\$ $intPart,${parts[1]}';
}

/// Formata uma quantidade sem casas decimais desnecessárias (vírgula decimal).
String formatQty(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1).replaceAll('.', ',');
}

/// Formata uma quantidade de sacas: "557 sc" ou "12,5 sc".
String formatSacks(double v) {
  final clean = v.abs() < 0.05 ? 0.0 : v;
  return '${formatQty(clean)} sc';
}

class StatusBadge extends StatelessWidget {
  final BarterStatus status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    IconData icon;
    String label;
    switch (status) {
      case BarterStatus.approved:
        bg = AppColors.approvedBg;
        fg = AppColors.approved;
        icon = Icons.check_circle_outline;
        label = 'Aprovada';
        break;
      case BarterStatus.denied:
        bg = AppColors.deniedBg;
        fg = AppColors.denied;
        icon = Icons.cancel_outlined;
        label = 'Negada';
        break;
      case BarterStatus.pending:
        bg = AppColors.pendingBg;
        fg = AppColors.pending;
        icon = Icons.hourglass_empty_rounded;
        label = 'Em Análise';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Distingue visualmente um grão entregue de um insumo retirado.
class TypeBadge extends StatelessWidget {
  final ProductType type;
  const TypeBadge({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final isGrain = type == ProductType.grain;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isGrain ? AppColors.grainBg : AppColors.inputBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isGrain ? Icons.grass : Icons.science_outlined,
              size: 12, color: isGrain ? AppColors.grain : AppColors.input),
          const SizedBox(width: 3),
          Text(
            isGrain ? 'Grão' : 'Insumo',
            style: TextStyle(
              color: isGrain ? AppColors.grain : AppColors.input,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo de busca padrão usado em listagens longas (cadastros, valores, etc).
class SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textMedium),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClear)
            : null,
        isDense: true,
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}

/// Resumo da permuta na narrativa correta do escambo: os INSUMOS retirados
/// formam um custo, e esse custo é convertido em SACAS do grão de pagamento.
/// O número de sacas a entregar é a estrela; o valor em R$ é secundário.
class BarterBalanceBar extends StatelessWidget {
  /// Custo total dos insumos retirados (R$).
  final double inputCost;

  /// Valor (R$) de uma saca do grão de pagamento. 0 = grão ainda não escolhido.
  final double referenceValue;

  /// Nome do grão de pagamento (ex.: "Soja").
  final String referenceGrainName;

  /// Quantos itens de insumo entram na permuta (para o resumo do consultor).
  final int inputCount;

  /// Se exibe os valores em R$ (admin). O consultor NUNCA vê valores: para ele a
  /// permuta é só "insumos retirados → sacas do grão".
  final bool showValue;

  const BarterBalanceBar({
    super.key,
    required this.inputCost,
    required this.referenceValue,
    required this.referenceGrainName,
    this.inputCount = 0,
    this.showValue = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasGrain = referenceValue > 0;
    final sacks = hasGrain ? inputCost / referenceValue : 0.0;
    final grainLabel = referenceGrainName.isEmpty ? '' : ' ${referenceGrainName.toLowerCase()}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hasGrain ? 'Você precisa entregar' : (showValue ? 'Custo dos insumos' : 'Pagamento em grãos'),
                        style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12)),
                    const SizedBox(height: 2),
                    if (hasGrain)
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: formatSacks(sacks),
                            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                          ),
                          TextSpan(
                            text: grainLabel,
                            style: const TextStyle(color: Color(0xDDFFFFFF), fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ]),
                      )
                    else if (showValue)
                      Text(formatCurrency(inputCost),
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800))
                    else
                      const Text('—',
                          style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      hasGrain
                          ? (showValue ? '≈ ${formatCurrency(inputCost)} em insumos' : 'para cobrir os insumos retirados')
                          : 'Escolha o grão de pagamento para ver as sacas',
                      style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.swap_horiz, color: Color(0x55FFFFFF), size: 36),
            ],
          ),
          if (showValue) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Insumos (custo)',
                    value: formatCurrency(inputCost),
                    sub: hasGrain ? '${formatSacks(sacks)}$grainLabel' : 'a converter',
                    icon: Icons.science_outlined,
                  ),
                ),
                Container(width: 1, height: 34, color: const Color(0x33FFFFFF)),
                Expanded(
                  child: _MiniStat(
                    label: 'Paga com',
                    value: hasGrain ? '${formatSacks(sacks)}$grainLabel' : '—',
                    sub: hasGrain ? '${formatCurrency(referenceValue)}/sc' : 'sem grão',
                    icon: Icons.grass,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final bool alignEnd;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: const Color(0xCCFFFFFF)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 10)),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        Text(sub, style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 10)),
      ],
    );
  }
}

class BarterLogo extends StatelessWidget {
  final double size;
  final bool showText;
  const BarterLogo({super.key, this.size = 40, this.showText = true});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              'BT',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: size * 0.4,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
        if (showText) ...[
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'BARTER',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: size * 0.45,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              Text(
                'Permuta de Grãos',
                style: TextStyle(
                  color: const Color(0xCCFFFFFF),
                  fontSize: size * 0.24,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Encerra a sessão a partir de qualquer tela, sempre pedindo confirmação antes
/// de voltar à tela de login. Centralizado aqui para que todas as telas usem o
/// mesmo fluxo de saída (mesmo texto, mesma confirmação, mesmo destino).
Future<void> confirmLogout(BuildContext context) async {
  final shouldLogout = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.logout, color: AppColors.denied, size: 40),
      title: const Text('Sair da conta'),
      content: const Text(
        'Deseja encerrar a sessão e voltar à tela de login?',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: AppColors.textMedium),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Sair'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.denied),
        ),
      ],
    ),
  );

  if (shouldLogout == true && context.mounted) {
    // Revoga o token e limpa o cache; a saída local nunca fica bloqueada.
    await AppData.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }
}

/// Abre a troca de senha voluntária do usuário logado. Diferente da troca
/// obrigatória (primeira entrada), aqui dá para desistir e voltar.
void openChangePassword(BuildContext context) {
  final user = AppData.currentUser;
  if (user == null) return;
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ChangePasswordScreen(user: user)),
  );
}

/// Botão de "Alterar senha" para a AppBar das telas de nível principal.
class ChangePasswordButton extends StatelessWidget {
  const ChangePasswordButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.lock_reset),
      tooltip: 'Alterar senha',
      onPressed: () => openChangePassword(context),
    );
  }
}

/// Botão de "Sair" padrão para a AppBar de qualquer tela de nível principal
/// (abas do admin e do consultor). Garante o mesmo ícone, rótulo e confirmação
/// em todo o app.
class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.logout),
      tooltip: 'Sair',
      onPressed: () => confirmLogout(context),
    );
  }
}

/// Cor do trilho/indicador de um status de permuta. Compartilhada por todos os
/// cards de histórico (perfil do produtor e do consultor).
Color statusColor(BarterStatus s) {
  switch (s) {
    case BarterStatus.approved:
      return AppColors.approved;
    case BarterStatus.denied:
      return AppColors.denied;
    case BarterStatus.pending:
      return AppColors.pending;
  }
}

/// Linha de informação (ícone + rótulo + valor) usada nos cartões de perfil
/// (consultor, produtor) em todo o app.
class InfoTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const InfoTile({super.key, required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
      subtitle: Text(value,
          style: const TextStyle(fontSize: 13, color: AppColors.textDark, fontWeight: FontWeight.w500)),
    );
  }
}

/// Cabeçalho de saudação dos dashboards ("Olá, Fulano!") com o gradiente padrão.
/// [caption] é uma terceira linha opcional (usada no painel do consultor).
class DashboardHeader extends StatelessWidget {
  final String greetingName;
  final String subtitle;
  final String? caption;
  final IconData icon;
  const DashboardHeader({
    super.key,
    required this.greetingName,
    required this.subtitle,
    this.caption,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Olá, $greetingName!',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12)),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(caption!, style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 11)),
                ],
              ],
            ),
          ),
          Icon(icon, color: const Color(0x44FFFFFF), size: 48),
        ],
      ),
    );
  }
}

/// Card compacto de permuta usado nos dashboards (admin e consultor). No modo
/// admin mostra as iniciais do consultor; no modo consultor, um ícone de troca.
class MiniBarterCard extends StatelessWidget {
  final BarterModel barter;
  final bool isAdmin;
  const MiniBarterCard({super.key, required this.barter, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BarterDetailScreen(barter: barter, isAdmin: isAdmin)),
        ),
        leading: CircleAvatar(
          backgroundColor: AppColors.primarySurface,
          child: isAdmin
              ? Text(
                  barter.consultantName.split(' ').map((e) => e[0]).take(2).join(),
                  style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
                )
              : const Icon(Icons.swap_horiz, color: AppColors.primary, size: 20),
        ),
        title: Text(barter.id,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
        subtitle: Text(
            isAdmin
                ? '${barter.consultantName} • ${barter.inputs.length} insumo(s)'
                : '${barter.inputs.length} insumo(s) • ${barter.producerName}',
            style: const TextStyle(fontSize: 11, color: AppColors.textMedium),
            overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StatusBadge(status: barter.status),
            const SizedBox(height: 2),
            Text(
                barter.referenceValue > 0
                    ? '${formatSacks(barter.sacksToDeliver)} ${barter.referenceGrainName.toLowerCase()}'
                    : '—',
                style: const TextStyle(fontSize: 10, color: AppColors.textMedium)),
          ],
        ),
      ),
    );
  }
}

/// Item de histórico de permuta (trilho colorido por status) usado nos perfis de
/// produtor e de consultor vistos pelo admin. [subtitle] é a linha contextual.
class BarterLogItem extends StatelessWidget {
  final BarterModel barter;
  final String subtitle;
  const BarterLogItem({super.key, required this.barter, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BarterDetailScreen(barter: barter, isAdmin: true)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 50,
                decoration: BoxDecoration(color: statusColor(barter.status), borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(barter.id,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                        const Spacer(),
                        StatusBadge(status: barter.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(subtitle,
                              style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        Text(
                            barter.referenceValue > 0
                                ? '${formatSacks(barter.sacksToDeliver)} ${barter.referenceGrainName.toLowerCase()}'
                                : '—',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textLight),
            ],
          ),
        ),
      ),
    );
  }
}

/// Diálogo único de revisão de permuta (aprovar/negar) com observação opcional.
/// A decisão é enviada à API (que grava o revisor e o momento) e a permuta
/// atualizada volta via [onReviewed], usado tanto na lista quanto no detalhe.
void reviewBarter(
  BuildContext context,
  BarterModel barter,
  BarterStatus newStatus, {
  required ValueChanged<BarterModel> onReviewed,
}) {
  final approving = newStatus == BarterStatus.approved;
  showDialog(
    context: context,
    builder: (ctx) {
      final noteCtrl = TextEditingController();
      var submitting = false;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(approving ? 'Aprovar Permuta' : 'Negar Permuta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Permuta: ${barter.id}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                  hintText: 'Adicione uma nota...',
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      setLocal(() => submitting = true);
                      try {
                        final updated = await AppData.reviewBarter(
                            barter.id, newStatus, noteCtrl.text);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        onReviewed(updated);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(approving
                              ? 'Permuta aprovada com sucesso!'
                              : 'Permuta negada.'),
                          backgroundColor:
                              approving ? AppColors.approved : AppColors.denied,
                        ));
                      } on ApiException catch (e) {
                        if (!ctx.mounted) return;
                        setLocal(() => submitting = false);
                        showErrorSnack(ctx, e);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: approving ? AppColors.approved : AppColors.denied,
              ),
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(approving ? 'Confirmar Aprovação' : 'Confirmar Negação'),
            ),
          ],
        ),
      );
    },
  );
}

class SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  const SummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textDark)),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textMedium)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
            ],
          ],
        ),
      ),
    );
  }
}
