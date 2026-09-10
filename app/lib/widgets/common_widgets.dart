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

/// O INVESTIMENTO POR HECTARE: "2,10 sc/ha".
///
/// DUAS casas, e não uma como [formatQty]: esta é a única medida da tela feita
/// para COMPARAR duas permutas, e nessa comparação 2,09 e 2,14 são coisas
/// diferentes que uma casa decimal transformaria no mesmo "2,1". A régua não
/// pode ser mais grossa do que a diferença que ela existe para mostrar.
String formatSacksPerHa(double v) =>
    '${v.toStringAsFixed(2).replaceAll('.', ',')} sc/ha';

/// Data no padrão brasileiro: 16/08/2026.
String formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Data e hora curtas: 16/08 às 14:32. Usada onde a HORA importa tanto quanto o
/// dia — a idade da tabela com que se está simulando offline, por exemplo.
String formatDateTime(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} às '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Uma linha de "rótulo → valor" dentro de um diálogo, com uma variante em
/// destaque para a linha que interessa (o total de sacas).
///
/// Mora aqui, e não na tela, porque os dois momentos que precisam dela ficaram
/// em telas diferentes: o construtor guarda a simulação, e a aba de simulações é
/// que a envia — mas o resumo que o consultor lê é o mesmo nos dois.
class DialogLine extends StatelessWidget {
  final String label, value;
  final bool bold;
  const DialogLine(this.label, this.value, {super.key, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                  fontSize: 12,
                  color: bold ? AppColors.primary : AppColors.textMedium,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                )),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                fontSize: bold ? 15 : 12,
                color: bold ? AppColors.primary : AppColors.textDark,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              )),
        ],
      ),
    );
  }
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
        // "Aprovada" e não "Aprovada — a faturar": o selo é curto por
        // desenho, e a lista já separa as duas em abas. Quem precisa do
        // detalhe da etapa lê o [BarterModel.statusLabel], que vem do
        // servidor.
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
        label = 'No comitê';
        break;
      case BarterStatus.sentToManager:
        bg = AppColors.atManagerBg;
        fg = AppColors.atManager;
        icon = Icons.assignment_ind_outlined;
        label = 'No gerente';
        break;
      case BarterStatus.approvedWithConditions:
        bg = AppColors.approvedWithConditionsBg;
        fg = AppColors.approvedWithConditions;
        // Ícone PRÓPRIO, e não o mesmo da aprovação: o selo é o único lugar da
        // lista onde a exigência pode aparecer, e um segundo "check" a
        // esconderia atrás de uma palavra que ninguém lê inteira.
        icon = Icons.verified_outlined;
        label = 'Com ressalva';
        break;
      case BarterStatus.draft:
        bg = AppColors.draftBg;
        fg = AppColors.draft;
        icon = Icons.edit_note_rounded;
        label = 'Rascunho';
        break;
      case BarterStatus.invoiced:
        bg = AppColors.invoicedBg;
        fg = AppColors.invoiced;
        icon = Icons.receipt_long_outlined;
        label = 'Faturada';
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
        prefixIcon: Icon(Icons.search, size: 20, color: AppColors.textMedium),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClear)
            : null,
        isDense: true,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}

/// Resumo da permuta na narrativa correta do escambo: os INSUMOS retirados
/// formam um custo, e esse custo é convertido em SACAS do grão de pagamento.
/// O número de sacas a entregar é a estrela; o valor em R$ é secundário.
class BarterBalanceBar extends StatelessWidget {
  /// Custo total dos insumos retirados, na moeda da lente de quem chamou.
  final double inputCost;

  /// Quanto custa UMA SACA do grão de pagamento, na MESMA moeda de [inputCost]:
  /// a cotação em R$ para a retaguarda, e 1 para o consultor — que já recebe a
  /// tabela medida em sacas. 0 = grão ainda não escolhido.
  ///
  /// Os dois campos precisam vir na mesma moeda porque a divisão entre eles é
  /// que produz as sacas. Quem monta permuta passa
  /// [BarterVersionModel.costPerSack], que responde certo nas duas lentes.
  final double referenceValue;

  /// Nome do grão de pagamento (ex.: "Soja").
  final String referenceGrainName;

  /// Quantos itens de insumo entram na permuta (para o resumo do consultor).
  final int inputCount;

  /// Se exibe os valores em R$ (admin). O consultor NUNCA vê valores: para ele a
  /// permuta é só "insumos retirados → sacas do grão".
  final bool showValue;

  /// O INVESTIMENTO POR HECTARE desta permuta e a área que o produz — `null`
  /// para quem não pode compará-lo, e na tela de montar uma permuta, onde ela
  /// ainda não existe.
  ///
  /// Ele fica no PAINEL, junto do custo e das sacas, porque é a terceira leitura
  /// do mesmo negócio: quanto se retira, com quanto se paga, e quanto isso pesa
  /// por hectare. Só a terceira responde "esta permuta é grande?" — as duas
  /// primeiras dizem o tamanho, e tamanho sem área é um número solto.
  final double? sacksPerHa;
  final double? areaHa;

  const BarterBalanceBar({
    super.key,
    required this.inputCost,
    required this.referenceValue,
    required this.referenceGrainName,
    this.inputCount = 0,
    this.showValue = true,
    this.sacksPerHa,
    this.areaHa,
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
                        style: TextStyle(color: AppColors.onPrimaryMuted, fontSize: 12)),
                    const SizedBox(height: 2),
                    if (hasGrain)
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: formatSacks(sacks),
                            style: TextStyle(color: AppColors.onPrimary, fontSize: 28, fontWeight: FontWeight.w800),
                          ),
                          TextSpan(
                            text: grainLabel,
                            style: TextStyle(color: AppColors.onPrimaryMuted, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ]),
                      )
                    else if (showValue)
                      Text(formatCurrency(inputCost),
                          style: TextStyle(color: AppColors.onPrimary, fontSize: 28, fontWeight: FontWeight.w800))
                    else
                      Text('—',
                          style: TextStyle(color: AppColors.onPrimary, fontSize: 28, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      hasGrain
                          ? (showValue ? '≈ ${formatCurrency(inputCost)} em insumos' : 'para cobrir os insumos retirados')
                          : 'Escolha o grão de pagamento para ver as sacas',
                      style: TextStyle(color: AppColors.onPrimarySubtle, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.swap_horiz, color: AppColors.onPrimaryFaint, size: 36),
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
                Container(width: 1, height: 34, color: AppColors.onPrimaryOverlay),
                Expanded(
                  child: _MiniStat(
                    label: 'Paga com',
                    value: hasGrain ? '${formatSacks(sacks)}$grainLabel' : '—',
                    sub: hasGrain ? '${formatCurrency(referenceValue)}/sc' : 'sem grão',
                    icon: Icons.grass,
                    alignEnd: sacksPerHa == null,
                  ),
                ),
                // A TERCEIRA leitura do mesmo negócio: quanto ele pesa por
                // hectare. Só aparece para quem recebe o número do servidor —
                // admin, comitê e faturista.
                if (sacksPerHa != null) ...[
                  Container(width: 1, height: 34, color: AppColors.onPrimaryOverlay),
                  Expanded(
                    child: _MiniStat(
                      label: 'Investimento',
                      value: formatSacksPerHa(sacksPerHa!),
                      sub: areaHa != null && areaHa! > 0 ? '${formatQty(areaHa!)} ha' : 'sem área',
                      icon: Icons.straighten,
                      alignEnd: true,
                    ),
                  ),
                ],
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
            Icon(icon, size: 12, color: AppColors.onPrimaryMuted),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: AppColors.onPrimaryMuted, fontSize: 10)),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: AppColors.onPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
        Text(sub, style: TextStyle(color: AppColors.onPrimarySubtle, fontSize: 10)),
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
      icon: Icon(Icons.logout, color: AppColors.denied, size: 40),
      title: const Text('Sair da conta'),
      content: Text(
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
/// A faixa de MODO OFFLINE: o app está rodando com o pacote gravado no
/// aparelho, sem ter falado com o servidor nesta abertura.
///
/// Ela mostra a DATA da tabela, e não só o aviso de que não há rede. É a
/// diferença entre "estou sem sinal" e "estou simulando com os valores de terça"
/// — e é a segunda que o consultor precisa saber antes de dizer um número ao
/// produtor. Sem a data, uma tabela de três semanas atrás parece a de hoje.
///
/// Some sozinha: só aparece com [AppData.isOffline], que a primeira
/// sincronização bem-sucedida desliga.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppData.isOffline) return const SizedBox.shrink();
    final at = AppData.lastSyncAt;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.pendingBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.pending.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.pending),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Trabalhando offline',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.pending)),
                Text(
                  at == null
                      ? 'Você pode simular, mas não encaminhar ao gerente.'
                      : 'Tabela de ${formatDateTime(at)}. Dá para simular; '
                          'encaminhar ao gerente exige sinal.',
                  style: TextStyle(fontSize: 11, color: AppColors.pending),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
    case BarterStatus.sentToManager:
      return AppColors.atManager;
    case BarterStatus.approvedWithConditions:
      return AppColors.approvedWithConditions;
    case BarterStatus.draft:
      return AppColors.draft;
    case BarterStatus.invoiced:
      return AppColors.invoiced;
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
      title: Text(label, style: TextStyle(fontSize: 11, color: AppColors.textLight)),
      subtitle: Text(value,
          style: TextStyle(fontSize: 13, color: AppColors.textDark, fontWeight: FontWeight.w500)),
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
                    style: TextStyle(color: AppColors.onPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: AppColors.onPrimaryMuted, fontSize: 12)),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(caption!, style: TextStyle(color: AppColors.onPrimarySubtle, fontSize: 11)),
                ],
              ],
            ),
          ),
          Icon(icon, color: AppColors.onPrimaryFaint, size: 48),
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

  /// O gerente logado, repassado ao detalhe.
  ///
  /// Sem isto, a MESMA permuta abria com a ação de parecer pela aba de permutas
  /// e sem ela por este cartão — e a lista do painel é justamente por onde o
  /// gerente entra primeiro. Uma tela que oferece a ação e outra que a esconde,
  /// para o mesmo registro e a mesma pessoa, é o app se contradizendo.
  final String? opinionManagerId;

  /// Avisa a tela de cima quando a permuta volta alterada (parecer dado,
  /// revisão feita) — é o que mantém contadores e selos honestos.
  final VoidCallback? onChanged;

  const MiniBarterCard({
    super.key,
    required this.barter,
    required this.isAdmin,
    this.opinionManagerId,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BarterDetailScreen(
                barter: barter,
                isAdmin: isAdmin,
                opinionManagerId: opinionManagerId,
              ),
            ),
          );
          onChanged?.call();
        },
        leading: CircleAvatar(
          backgroundColor: AppColors.primarySurface,
          child: isAdmin
              ? Text(
                  barter.consultantName.split(' ').map((e) => e[0]).take(2).join(),
                  style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
                )
              : Icon(Icons.swap_horiz, color: AppColors.primary, size: 20),
        ),
        title: Text(barter.id,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
        // O INVESTIMENTO POR HECTARE entra na linha de baixo do cartão do
        // PAINEL pelo mesmo motivo de estar na lista: é a régua que compara, e
        // o painel é onde se olha várias permutas de uma vez. Ele só aparece
        // para quem o recebe do servidor — admin, comitê e faturista.
        subtitle: Text(
            [
              if (isAdmin) barter.consultantName,
              '${barter.inputs.length} insumo(s)',
              if (!isAdmin) barter.producerName,
              if (barter.sacksPerHa != null) formatSacksPerHa(barter.sacksPerHa!),
            ].join(' • '),
            style: TextStyle(fontSize: 11, color: AppColors.textMedium),
            overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StatusBadge(status: barter.status),
            const SizedBox(height: 2),
            Text(
                barter.hasSacks
                    ? '${formatSacks(barter.sacksToDeliver)} ${barter.referenceGrainName.toLowerCase()}'
                    : '—',
                style: TextStyle(fontSize: 10, color: AppColors.textMedium)),
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
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                        const Spacer(),
                        StatusBadge(status: barter.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(subtitle,
                              style: TextStyle(fontSize: 11, color: AppColors.textLight),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        Text(
                            barter.hasSacks
                                ? '${formatSacks(barter.sacksToDeliver)} ${barter.referenceGrainName.toLowerCase()}'
                                : '—',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: AppColors.textLight),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quantas letras o servidor exige num parecer e no motivo de uma decisão
/// (ver `BarterOpinionDto` e `ReviewBarterDto`, na API).
///
/// A conferência é repetida aqui porque a tela precisa saber ANTES de enviar
/// se o botão liga — quem valida de verdade continua sendo o servidor, e a
/// mensagem dele é a que apareceria se este número divergisse.
const int minOpinionLength = 10;

/// O que o comitê tem a dizer sobre cada desfecho da decisão — o título do
/// diálogo, o rótulo do campo, o do botão e a cor de tudo isso.
///
/// Ele existe porque as três saídas NÃO são a mesma tela com uma palavra
/// trocada: numa o texto é opcional e nas outras duas é o conteúdo do ato, e o
/// que se pede a quem escreve é diferente em cada uma ("a exigência", "a razão
/// da negativa"). Um `if (aprovando)` com dois casos foi o que existiu enquanto
/// as saídas eram duas, e a terceira não caberia nele sem virar um encadeado
/// que ninguém lê.
class _ReviewCopy {
  final String title;
  final String noteLabel;
  final String noteHint;
  final String button;
  final String done;
  final Color color;

  /// O texto é obrigatório? Nas duas saídas que criam trabalho para outra
  /// pessoa, sim — ver `ReviewBarterDto` na API.
  final bool requiresNote;

  const _ReviewCopy({
    required this.title,
    required this.noteLabel,
    required this.noteHint,
    required this.button,
    required this.done,
    required this.color,
    required this.requiresNote,
  });
}

_ReviewCopy _copyFor(BarterStatus status) {
  switch (status) {
    case BarterStatus.approvedWithConditions:
      return _ReviewCopy(
        title: 'Aprovar com Ressalva',
        // O rótulo diz O QUE se espera do campo. "Observação" deixaria a
        // exigência virar um comentário, e é ela que alguém vai ter de cumprir
        // antes de a entrega ser cobrada.
        noteLabel: 'Ressalva exigida',
        noteHint: 'Garantia real, seguro obrigatório, aval…',
        button: 'Confirmar com Ressalva',
        done: 'Permuta aprovada com ressalva.',
        color: AppColors.approvedWithConditions,
        requiresNote: true,
      );
    case BarterStatus.denied:
      return _ReviewCopy(
        title: 'Negar Permuta',
        noteLabel: 'Motivo da negativa',
        noteHint: 'É o que o consultor vai levar ao produtor…',
        button: 'Confirmar Negação',
        done: 'Permuta negada.',
        color: AppColors.denied,
        requiresNote: true,
      );
    // A APROVAÇÃO LIMPA é a única com texto opcional: ela não tem o que
    // explicar, e exigi-lo produziria quinhentos "ok" no histórico.
    default:
      return _ReviewCopy(
        title: 'Aprovar Permuta',
        // A ATA vai aqui, e o rótulo diz isso. Quem chega a este diálogo é o
        // comitê, e o acesso dele é compartilhado por quem participa da
        // reunião: a trilha registra "Comitê", não quem estava na sala. Este
        // campo é o lugar de guardar isso, e chamá-lo de "observação"
        // escondia a única oportunidade de fazê-lo.
        noteLabel: 'Ata da reunião (opcional)',
        noteHint: 'Quem participou, o que foi acordado...',
        button: 'Confirmar Aprovação',
        done: 'Permuta aprovada com sucesso!',
        color: AppColors.approved,
        requiresNote: false,
      );
  }
}

/// Diálogo único da DECISÃO do comitê — aprovar, aprovar com ressalva ou negar.
///
/// A decisão é enviada à API (que grava o revisor e o momento) e a permuta
/// atualizada volta via [onReviewed], usado tanto na lista quanto no detalhe.
///
/// O botão só liga quando o desfecho tem o que precisa: nas duas saídas que
/// exigem texto, ele fica desligado até o motivo estar escrito. É a mesma regra
/// do servidor, repetida aqui para a recusa não ser a primeira notícia dela.
void reviewBarter(
  BuildContext context,
  BarterModel barter,
  BarterStatus newStatus, {
  required ValueChanged<BarterModel> onReviewed,
}) {
  final copy = _copyFor(newStatus);
  showDialog(
    context: context,
    builder: (ctx) {
      final noteCtrl = TextEditingController();
      var submitting = false;
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final enough =
              !copy.requiresNote || noteCtrl.text.trim().length >= minOpinionLength;
          return AlertDialog(
            title: Text(copy.title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Permuta: ${barter.id}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  if (copy.requiresNote) ...[
                    const SizedBox(height: 8),
                    Text(
                      newStatus == BarterStatus.denied
                          ? 'A razão fica no registro e é o que o consultor leva ao produtor.'
                          : 'A permuta segue para o faturamento com esta exigência anotada.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    autofocus: copy.requiresNote,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 1000,
                    onChanged: (_) => setLocal(() {}),
                    decoration: InputDecoration(
                      labelText: copy.noteLabel,
                      hintText: copy.noteHint,
                      alignLabelWithHint: true,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: submitting || !enough
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
                            content: Text(copy.done),
                            backgroundColor: copy.color,
                          ));
                        } on ApiException catch (e) {
                          if (!ctx.mounted) return;
                          setLocal(() => submitting = false);
                          showErrorSnack(ctx, e);
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: copy.color),
                child: submitting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.onPrimary))
                    : Text(copy.button),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Diálogo do PARECER TÉCNICO do gerente.
///
/// Ele é irmão de [reviewBarter] e deliberadamente diferente num ponto: não há
/// "aprovar" nem "negar". O gerente diz o que pensa da negociação que um
/// consultor do time dele registrou, e quem decide é quem revisa, lendo isto
/// antes. Por isso há um botão só, e o texto é obrigatório — um parecer em
/// branco seria um botão de "seguir" disfarçado.
void giveBarterOpinion(
  BuildContext context,
  BarterModel barter, {
  required ValueChanged<BarterModel> onGiven,
}) {
  showDialog(
    context: context,
    builder: (ctx) {
      final noteCtrl = TextEditingController();
      var submitting = false;
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final enough = noteCtrl.text.trim().length >= minOpinionLength;
          return AlertDialog(
            title: const Text('Parecer Técnico'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Permuta: ${barter.id}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text('${barter.consultantName} • retirada em ${barter.unitLabel}',
                      style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
                  const SizedBox(height: 12),
                  Text(
                    'Sua avaliação da negociação, para o comitê ler antes de decidir.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    autofocus: true,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setLocal(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Parecer',
                      hintText: 'Estoque, prazo de retirada, histórico do produtor…',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: submitting || !enough
                    ? null
                    : () async {
                        setLocal(() => submitting = true);
                        try {
                          final updated =
                              await AppData.giveOpinion(barter.id, noteCtrl.text);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          onGiven(updated);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: const Text('Parecer registrado. A permuta seguiu para o comitê.'),
                            backgroundColor: AppColors.atManager,
                          ));
                        } on ApiException catch (e) {
                          if (!ctx.mounted) return;
                          setLocal(() => submitting = false);
                          showErrorSnack(ctx, e);
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.atManager),
                child: submitting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                    : const Text('Registrar Parecer'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// O parecer do gerente, como bloco de leitura. Aparece no detalhe da permuta e
/// no cartão da fila — nos dois lugares com o mesmo desenho, porque é o mesmo
/// texto e quem lê quer reconhecê-lo à primeira vista.
class ManagerOpinionCard extends StatelessWidget {
  final BarterModel barter;
  const ManagerOpinionCard({super.key, required this.barter});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.atManagerBg,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.atManager.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_ind_outlined, size: 16, color: AppColors.atManager),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Parecer técnico • ${barter.managerName ?? 'Gerente'}',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.atManager),
                ),
              ),
              if (barter.managerReviewedAt != null)
                Text(
                  formatDate(barter.managerReviewedAt!),
                  style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            barter.managerNote ?? '',
            style: TextStyle(fontSize: 13, color: AppColors.textDark, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// O parecer do CONSULTOR, como bloco de leitura — irmão de
/// [ManagerOpinionCard], e desenhado igual de propósito.
///
/// Os dois textos aparecem um sob o outro no detalhe, na ordem em que foram
/// escritos, e o comitê decide lendo os dois. O que os distingue é a cor e a
/// assinatura: este é de quem conhece o cliente, aquele é de quem responde pelo
/// time. Desenhá-los diferente sugeriria que um vale mais que o outro.
class ConsultantOpinionCard extends StatelessWidget {
  final BarterModel barter;
  const ConsultantOpinionCard({super.key, required this.barter});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_pin_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Parecer do consultor • ${barter.consultantName}',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ),
              // A data é a do ENCAMINHAMENTO. Ela falta enquanto a permuta é
              // rascunho — o texto existe, o envio não —, e o bloco não inventa
              // uma: é a diferença entre "escrito" e "mandado".
              if (barter.consultantSentAt != null)
                Text(
                  formatDate(barter.consultantSentAt!),
                  style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            barter.consultantNote ?? '',
            style: TextStyle(fontSize: 13, color: AppColors.textDark, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// A RESSALVA da aprovação — a exigência que o comitê pendurou na permuta.
///
/// Ela tem bloco próprio, e não é só o `reviewNote` no rodapé, porque é a única
/// informação da tela que pede AÇÃO de quem lê: alguém precisa providenciar a
/// garantia, a apólice ou o aval antes de a entrega ser cobrada. Enquanto o
/// texto da decisão morava junto com os outros, ela chegava ao faturista como
/// mais um parágrafo depois de dois pareceres.
class ConditionsCard extends StatelessWidget {
  final BarterModel barter;
  const ConditionsCard({super.key, required this.barter});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.approvedWithConditionsBg,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.approvedWithConditions.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_outlined,
                  size: 16, color: AppColors.approvedWithConditions),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Aprovada com ressalva${barter.hasDecision ? ' • ${barter.reviewedBy}' : ''}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.approvedWithConditions),
                ),
              ),
              if (barter.updatedAt != null)
                Text(
                  formatDate(barter.updatedAt!),
                  style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            barter.reviewNote ?? '',
            style: TextStyle(fontSize: 13, color: AppColors.textDark, height: 1.35),
          ),
          const SizedBox(height: 8),
          Text(
            'Exigência a cumprir antes da entrega.',
            style: TextStyle(
                fontSize: 11,
                color: AppColors.approvedWithConditions,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
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
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textDark)),
            const SizedBox(height: 2),
            Text(title, style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: TextStyle(fontSize: 11, color: AppColors.textLight)),
            ],
          ],
        ),
      ),
    );
  }
}
