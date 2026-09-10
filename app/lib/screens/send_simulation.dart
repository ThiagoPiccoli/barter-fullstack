/// ENCAMINHAR A SIMULAÇÃO AO GERENTE — o único ponto do fluxo que fala com o
/// servidor, e o momento em que a permuta deixa de ser simulação.
///
/// Mora aqui, e não dentro de uma tela, porque agora tem DOIS pontos de partida:
/// o cartão da aba Simulações e o próprio construtor, logo depois de guardar.
/// Duas cópias deste caminho seria a receita para uma delas esquecer a
/// conferência do que mudou — que é justamente a parte que existe para o
/// consultor não registrar uma conta diferente da que combinou com o produtor.
library;

import 'package:flutter/material.dart';

import '../branding/active_brand.dart';
import '../data/app_data.dart';
import '../models/barter_simulation.dart';
import '../models/models.dart';
import '../services/api/api_client.dart';
import '../services/barter_pdf.dart';
import '../services/simulation_check.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Encaminha [simulation] ao gerente do consultor. Devolve `true` quando a
/// permuta foi registrada.
///
/// Acontece em três tempos, nesta ordem:
///
/// 1. **Serviço responde?** — `reviewSimulation` busca versão, carteira,
///    unidades e catálogo. Se não responder, nada foi enviado e a simulação
///    fica: o consultor tenta de novo de onde houver sinal.
/// 2. **O que mudou?** — Barter fechado, produtor fora da carteira, insumo que
///    saiu da tabela, sacas diferentes das simuladas. O que impede o envio é
///    dito e para por aqui; o que só mudou o número é MOSTRADO, e o consultor
///    decide.
/// 3. **Envia** — e só depois do sucesso a simulação some.
///
/// O resumo do passo 3 é mostrado SEMPRE, inclusive a quem vem do construtor e
/// acabou de dizer que quer mandar. Ele deixou de ser uma conferência do que já
/// está na tela: é lá que se escreve o PARECER do consultor e se escolhe entre
/// guardar o rascunho e encaminhar, e nenhuma das duas coisas está em outro
/// lugar do app.
Future<bool> sendSimulationToManager(
  BuildContext context, {
  required BarterSimulation simulation,
  required UserModel consultant,
  VoidCallback? onChanged,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  final SimulationCheck check;
  try {
    check = await AppData.reviewSimulation(simulation);
  } on ApiException catch (e) {
    if (!context.mounted) return false;
    // Nada saiu daqui: a simulação continua inteira, e é isso que a mensagem
    // precisa dizer — senão o consultor acha que perdeu o trabalho.
    showErrorOn(
      messenger,
      '${e.message} Sua simulação continua guardada — tente de novo quando tiver sinal.',
    );
    return false;
  }
  if (!context.mounted) return false;

  // O Barter virou enquanto a simulação esperava: ela é refeita com os mesmos
  // insumos na tabela vigente. Guardar a versão refeita ANTES de perguntar é o
  // que faz o trabalho não se perder se o consultor recuar agora.
  if (check.rebuilt.simulatedSacks != simulation.simulatedSacks ||
      check.rebuilt.versionCode != simulation.versionCode) {
    await AppData.saveSimulation(check.rebuilt);
    if (!context.mounted) return false;
    onChanged?.call();
  }

  // A porta do envio é `stopReason`, e não `blocker`: além do que impede
  // qualquer permuta hoje (Barter fechado, produtor fora da carteira), ela cobre
  // o insumo que saiu da tabela vigente. Esse item continua na simulação e o
  // servidor recusa a permuta inteira por causa dele — passar daqui gastaria a
  // viagem para receber um 422, depois de mostrar ao consultor um total de sacas
  // que já não o cobria. Repare que a conferência acima já foi salva: o trabalho
  // fica refeito na tabela de hoje, é só o envio que para.
  if (check.stopReason != null) {
    showErrorOn(messenger, check.stopReason!);
    return false;
  }

  // O RESUMO é SEMPRE mostrado agora, mesmo a quem acabou de confirmar no
  // construtor: ele deixou de ser só uma conferência do que já está na tela e
  // passou a pedir uma coisa que não está em lugar nenhum — o parecer do
  // consultor, e a escolha entre guardar o rascunho e encaminhar. Pular o
  // diálogo pularia a etapa.
  final choice = await _confirmSend(context, check, consultant);
  if (!context.mounted || choice == null) return false;

  final result = await AppData.sendSimulation(
    check.rebuilt,
    note: choice.note,
    forward: choice.forward,
  );
  if (!context.mounted) return false;

  if (result.isSent) {
    onChanged?.call();
    await _showSent(context, result);
    return true;
  }
  if (result.isUncertain) {
    await _showUncertain(context, result.uncertainReason!);
    return false;
  }
  showErrorOn(messenger, '${result.refusal!} A simulação continua guardada.');
  return false;
}

/// O QUE O CONSULTOR ESCOLHEU no resumo do envio: o parecer que ele escreveu, e
/// se a permuta sai da mesa dele agora.
///
/// São duas saídas, e não um "ok": registrar e encaminhar viraram dois atos, e é
/// aqui que a diferença aparece para quem usa. Quem já conversou com o produtor
/// escreve o parecer e manda; quem ainda não, guarda o registro — com os valores
/// do Barter de hoje congelados nele — e escreve depois.
class _SendChoice {
  final String note;
  final bool forward;
  const _SendChoice({required this.note, required this.forward});
}

/// O RESUMO antes de encaminhar — o momento em que a permuta deixa de ser
/// simulação. Mostra o que vai ser registrado, o que mudou desde que foi
/// montada, e pede o parecer de quem conhece o cliente.
Future<_SendChoice?> _confirmSend(
    BuildContext context, SimulationCheck check, UserModel consultant) {
  final sim = check.rebuilt;
  final noteCtrl = TextEditingController();
  return showDialog<_SendChoice>(
    context: context,
    // StatefulBuilder porque o botão de encaminhar LIGA com o que está sendo
    // digitado: sem redesenhar o diálogo a cada letra, ele só acordaria quando
    // alguém tocasse fora do campo.
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
      icon: Icon(Icons.send_outlined, color: AppColors.primary, size: 40),
      title: const Text('Encaminhar ao gerente?'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (check.needsReview) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.pendingBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 15, color: AppColors.pending),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              check.versionChanged
                                  ? 'O Barter mudou desde a simulação'
                                  : 'Os valores mudaram desde a simulação',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.pending,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        check.versionChanged
                            ? 'Ela foi montada no ${check.previousVersionCode} e foi refeita '
                                  'com os mesmos insumos no ${sim.versionCode}.'
                            : 'Os insumos são os mesmos; a conta é a do Barter de agora.',
                        style: TextStyle(fontSize: 11, color: AppColors.pending),
                      ),
                      if (check.sacksChanged) ...[
                        const SizedBox(height: 6),
                        // O número lado a lado, e não só o novo: é este valor
                        // que o consultor falou para o produtor, e é ele que
                        // vai precisar refazer a conversa se mudou.
                        Text(
                          'Simulado: ${formatSacks(check.simulatedSacks)}   →   '
                          'Agora: ${formatSacks(check.currentSacks)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.pending,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              DialogLine('Produtor', sim.producerName),
              DialogLine('Retirada em', sim.unitName),
              DialogLine('Barter', sim.versionCode),
              DialogLine(
                'Vai para',
                consultant.managerName.isEmpty ? 'seu gerente' : consultant.managerName,
              ),
              const SizedBox(height: 8),
              Text(
                'Insumos retirados',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    for (final item in sim.items)
                      DialogLine(
                        item.productName.isEmpty ? item.productId : item.productName,
                        '${formatQty(item.quantity)} ${item.unit}',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DialogLine(
                  'Vai entregar',
                  '${formatSacks(sim.simulatedSacks)} '
                      '${sim.grainName.toLowerCase()}',
                  bold: true,
                ),
              ),
              const SizedBox(height: 10),
              // O PARECER DO CONSULTOR — a peça que abre o processo, escrita por
              // quem conhece o cliente. Ela é pedida AQUI, e não numa tela
              // depois, porque é aqui que ele está pensando nesta permuta.
              //
              // O campo é opcional NA TELA e obrigatório NO ENVIO: sem texto o
              // botão de encaminhar não liga, e o de guardar continua ligado —
              // que é a saída de quem ainda vai conversar com o produtor.
              TextField(
                controller: noteCtrl,
                minLines: 2,
                maxLines: 5,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setLocal(() {}),
                decoration: const InputDecoration(
                  labelText: 'Seu parecer',
                  hintText: 'Safras anteriores, pontualidade, o que está plantado…',
                  alignLabelWithHint: true,
                  isDense: true,
                ),
              ),
              // O que ACONTECE COM ELE, e não como o sistema funciona por
              // dentro: "o servidor recalcula tudo ao registrar" era o app
              // contando a própria arquitetura a quem só quer encaminhar.
              Text(
                'Se algum mínimo não fechar, a simulação volta para você corrigir.',
                style: TextStyle(fontSize: 11, color: AppColors.textLight),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Revisar')),
        // GUARDAR não é cancelar: a permuta é registrada, com os valores de
        // hoje congelados, e fica como rascunho na lista dele. É o caminho de
        // quem montou a conta antes de ter a conversa.
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, _SendChoice(note: noteCtrl.text, forward: false)),
          child: const Text('Guardar rascunho'),
        ),
        ElevatedButton(
          onPressed: noteCtrl.text.trim().length < minOpinionLength
              ? null
              : () => Navigator.pop(ctx, _SendChoice(note: noteCtrl.text, forward: true)),
          child: const Text('Encaminhar'),
        ),
      ],
      ),
    ),
  );
}

Future<void> _showSent(BuildContext context, SendResult result) {
  final barter = result.barter!;
  final producer = AppData.producerById(barter.producerId);
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        barter.isDraft ? Icons.edit_note_rounded : Icons.swap_horiz,
        color: barter.isDraft ? AppColors.draft : AppColors.approved,
        size: 48,
      ),
      title: Text(
          barter.isDraft ? '${brand.copy.barterTitle} Guardada' : '${brand.copy.barterTitle} Enviada!'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (result.reconciled)
            // O envio anterior TINHA dado certo — o que se perdeu foi a
            // resposta. Dizer isso evita a pergunta seguinte, que seria por
            // que ele viu um erro e a permuta existe assim mesmo.
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Esta permuta já havia sido registrada no envio anterior — a '
                'resposta é que não chegou até você.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textMedium),
              ),
            ),
          Text(
            'Permuta ${barter.id} registrada com sucesso.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          // COM QUEM ela está agora — a única pergunta que o consultor faz
          // depois de enviar. No rascunho a resposta é "com você", e ela vem
          // com o que falta fazer: sem isso, uma permuta guardada some da
          // cabeça de quem a guardou.
          Text(
            barter.isDraft
                ? 'Está com você, como rascunho. Escreva o parecer e encaminhe '
                    'ao gerente quando estiver pronto.'
                : 'Está com ${barter.managerLabel}, esperando o parecer técnico.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMedium),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                DialogLine('Produtor', barter.producerName),
                DialogLine('Retirada em', barter.unitLabel),
                if (barter.versionCode.isNotEmpty) DialogLine('Barter', barter.versionCode),
                const Divider(height: 14),
                DialogLine(
                  'Vai entregar',
                  '${formatSacks(barter.totalGrainQty)} '
                      '${barter.referenceGrainName.toLowerCase()}',
                  bold: true,
                ),
              ],
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        // Comprovante para controle: PDF do consultor, sem valores em R$. Só
        // aparece com o produtor em cache — sem ele o PDF sairia sem os dados
        // da propriedade, que é metade do documento.
        if (producer != null)
          OutlinedButton.icon(
            onPressed: () => _sharePdf(ctx, barter, producer),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Gerar PDF'),
          ),
        ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}

/// O DESFECHO INCERTO: o envio saiu, a resposta não voltou, e a conferência
/// no servidor também não respondeu.
///
/// A simulação FICA — apagá-la poderia jogar fora uma permuta que nunca foi
/// registrada. E o texto manda conferir antes de reenviar, porque a outra
/// metade do risco é o consultor mandar de novo e o gerente receber duas.
Future<void> _showUncertain(BuildContext context, String reason) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.help_outline, color: AppColors.pending, size: 44),
      title: const Text('Não deu para confirmar'),
      content: Text(
        '$reason\n\nA permuta PODE ter sido registrada — a conexão caiu antes de '
        'o servidor responder. Sua simulação continua guardada.\n\n'
        'Antes de enviar de novo, confira a aba "No gerente": se a permuta já '
        'estiver lá, descarte esta simulação em vez de reenviá-la.',
        style: const TextStyle(fontSize: 13),
      ),
      actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendi'))],
    ),
  );
}

/// Comprovante para controle: PDF do consultor, sem valores em R$.
///
/// O [context] é o do DIÁLOGO, não o de quem chamou. Quem chamou pode já ter
/// saído da árvore: o envio bem-sucedido apaga a simulação, e o cartão que abriu
/// este caminho desaparece da lista no quadro seguinte — enquanto o diálogo, que
/// é rota própria, continua de pé com este botão clicável. O `ScaffoldMessenger`
/// do `MaterialApp` está acima do `Navigator`, então a busca a partir daqui
/// acha o mesmo messenger.
Future<void> _sharePdf(BuildContext context, BarterModel barter, ProducerModel producer) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await BarterPdf.share(barter, producer: producer, showValues: false);
  } catch (e) {
    showErrorOn(messenger, 'Não foi possível gerar o PDF: $e');
  }
}
