import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/barter_pdf.dart';
import '../widgets/common_widgets.dart';

class BarterDetailScreen extends StatefulWidget {
  final BarterModel barter;

  /// Visão de RETAGUARDA: enxerga a permuta de qualquer consultor e com os
  /// valores em R$ (o consultor vê a própria, sem valores).
  final bool isAdmin;

  /// Quem pode dar PARECER — o gerente logado. A ação só aparece se a permuta
  /// tiver sido endereçada a ele, que é a mesma regra que o servidor aplica.
  final String? opinionManagerId;

  const BarterDetailScreen({
    super.key,
    required this.barter,
    required this.isAdmin,
    this.opinionManagerId,
  });
  @override
  State<BarterDetailScreen> createState() => _BarterDetailScreenState();
}

class _BarterDetailScreenState extends State<BarterDetailScreen> {
  late BarterModel _barter;

  /// A LINHA DO TEMPO ainda está vindo do servidor?
  ///
  /// A permuta chega da lista, e a lista não carrega histórico — o detalhe pede
  /// a permuta de novo só por causa dele. O resto da tela não espera: ela abre
  /// com o que já se sabe, e a linha do tempo aparece quando chega.
  bool _loadingHistory = false;

  @override
  void initState() {
    super.initState();
    _barter = widget.barter;
    _loadHistory();
  }

  /// Busca o detalhe (é ele que traz `events`). Falha em silêncio de propósito:
  /// o histórico é contexto, e um erro de rede não pode impedir a pessoa de ver
  /// a permuta — nem de agir sobre ela, que é o que ela veio fazer.
  Future<void> _loadHistory() async {
    if (_barter.hasHistory) return;
    // Sem setState: isto roda no initState, antes do primeiro build.
    _loadingHistory = true;
    try {
      final detail = await AppData.barterDetail(_barter.id);
      if (!mounted) return;
      setState(() {
        // Enquanto isto voltava, uma AÇÃO pode ter trocado a permuta por uma
        // mais nova — a resposta de um ato já vem com a linha do tempo dentro.
        // A que está em mãos aqui é ANTERIOR a ela, e aplicá-la desfaria na tela
        // a decisão que a pessoa acabou de tomar.
        if (!_barter.hasHistory) _barter = detail;
        _loadingHistory = false;
      });
    } catch (_) {
      // Sem histórico na tela; o resto continua de pé.
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  /// Comprovante em PDF para controle. Segue a regra das telas: o admin recebe
  /// o documento com valores em R$; o consultor, só quantidades e sacas.
  Future<void> _sharePdf(ProducerModel? producer) async {
    try {
      await BarterPdf.share(_barter, producer: producer, showValues: widget.isAdmin);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível gerar o PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final producer = AppData.producerById(_barter.producerId);
    return Scaffold(
      appBar: AppBar(
        title: Text(_barter.id),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Gerar PDF',
            onPressed: () => _sharePdf(producer),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: StatusBadge(status: _barter.status)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          BarterBalanceBar(
            inputCost: _barter.inputCost,
            referenceValue: _barter.referenceValue,
            referenceGrainName: _barter.referenceGrainName,
            inputCount: _barter.inputs.length,
            showValue: widget.isAdmin,
          ),
          const SizedBox(height: 16),

          // Meta info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(label: 'Produtor', value: _barter.producerName),
                  if (producer != null)
                    _InfoRow(label: 'Propriedade', value: producer.location),
                  // A RETIRADA vale para todo mundo, inclusive o consultor: é
                  // onde o produtor dele vai buscar os insumos, e a primeira
                  // pergunta que ele recebe de volta.
                  _InfoRow(label: 'Retirada em', value: _barter.unitLabel),
                  if (widget.isAdmin) ...[
                    _InfoRow(label: 'Consultor', value: _barter.consultantName),
                    _InfoRow(label: 'Filial', value: _barter.consultantBranch),
                  ],
                  const Divider(height: 16),
                  // Em qual gestão do Barter esta permuta foi fechada: é o que
                  // explica os valores dela, que não mudam quando a versão
                  // seguinte é publicada.
                  if (_barter.versionCode.isNotEmpty)
                    _InfoRow(label: 'Barter', value: _barter.versionCode),
                  _InfoRow(label: 'Criada em', value: _formatDate(_barter.createdAt)),
                  if (_barter.updatedAt != null)
                    _InfoRow(label: 'Atualizada em', value: _formatDate(_barter.updatedAt!)),
                  if (_barter.hasDecision)
                    _InfoRow(label: 'Decidida por', value: _barter.reviewedBy!),
                  if (_barter.invoicedBy != null) ...[
                    _InfoRow(label: 'Faturada por', value: _barter.invoicedBy!),
                    if (_barter.invoicedAt != null)
                      _InfoRow(label: 'Faturada em', value: _formatDate(_barter.invoicedAt!)),
                  ],
                  if (_barter.reviewNote != null && _barter.reviewNote!.isNotEmpty)
                    _NoteBlock(
                      label: 'Observação do comitê',
                      text: _barter.reviewNote!,
                      icon: Icons.gavel_outlined,
                    ),
                  if (_barter.invoiceNote != null && _barter.invoiceNote!.isNotEmpty)
                    _NoteBlock(
                      label: 'Observação do faturamento',
                      text: _barter.invoiceNote!,
                      icon: Icons.receipt_long_outlined,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // O PARECER vem antes dos itens de propósito: quem abre uma permuta
          // que já passou pelo gerente quer saber o que ele disse antes de
          // conferir linha a linha o que ela tem dentro.
          if (_barter.hasManagerOpinion) ...[
            ManagerOpinionCard(barter: _barter),
            const SizedBox(height: 16),
          ] else if (_barter.awaitsManager) ...[
            _AwaitingOpinionCard(managerLabel: _barter.managerLabel),
            const SizedBox(height: 16),
          ],

          _ItemsSection(
            title: 'Insumos Retirados',
            subtitle: 'O que o produtor retira na unidade',
            icon: Icons.science_outlined,
            accent: AppColors.input,
            items: _barter.inputs,
            totalLabel: widget.isAdmin ? 'Custo total' : 'Total retirado',
            total: _barter.inputCost,
            referenceValue: _barter.referenceValue,
            referenceGrainName: _barter.referenceGrainName,
            showValue: widget.isAdmin,
            // O equivalente em sacas de UM insumo exige o valor unitário dele,
            // que só chega a quem vê R$. O total da seção, não: ele é a permuta
            // inteira, e o servidor já o gravou na linha do grão.
            sacksOf: (item) => _barter.showsCurrency && _barter.referenceValue > 0
                ? item.total / _barter.referenceValue
                : null,
            totalSacks: _barter.hasSacks ? _barter.sacksToDeliver : null,
          ),
          const SizedBox(height: 16),

          _ItemsSection(
            title: 'Pagamento em ${brand.copy.grainPluralTitle}',
            subtitle: 'Sacas a entregar para cobrir os insumos',
            icon: Icons.grass,
            accent: AppColors.grain,
            items: _barter.grains,
            totalLabel: 'Total a entregar',
            total: _barter.grainCredit,
            referenceValue: _barter.referenceValue,
            referenceGrainName: _barter.referenceGrainName,
            showValue: widget.isAdmin,
            // Aqui a conversão não existe: a linha do grão JÁ é medida em sacas,
            // nas duas lentes. É por isso que a API não converte estes itens.
            sacksOf: (item) => item.quantity,
            totalSacks: _barter.totalGrainQty,
          ),
          const SizedBox(height: 16),

          // Resumo do pagamento: quantas sacas o produtor entrega para pagar tudo
          Card(
            color: AppColors.primarySurface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('TOTAL A ENTREGAR',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _barter.hasSacks
                            ? '${formatSacks(_barter.sacksToDeliver)} ${_barter.referenceGrainName.toLowerCase()}'
                            : '0 sc',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                      Text(
                          widget.isAdmin
                              ? '≈ ${formatCurrency(_barter.inputCost)} em insumos'
                              : 'para ${_barter.inputs.length} insumo(s) retirado(s)',
                          style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // O IMPOSTO da entrega. Fica depois do total porque é consequência
          // dele: a entrega de grão é comercialização de produção rural, e sobre
          // ela incidem Funrural e Senar.
          //
          // Só aparece quando a permuta tem alíquota registrada — as fechadas
          // antes deste campo não têm, e mostrar a de hoje nelas seria afirmar
          // um imposto que ninguém aplicou.
          if (_barter.hasTax) ...[
            const SizedBox(height: 12),
            _TaxCard(barter: _barter, showsCurrency: widget.isAdmin),
          ],
          const SizedBox(height: 20),

          if (_awaitsMyOpinion) ...[
            Text('Ação do Gerente',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 4),
            // O FATO, e não a explicação da etapa: quem enviou e quando. O que
            // o parecer é, e para onde a permuta vai depois dele, o gerente já
            // sabe — é o trabalho dele.
            Text(
              '${_barter.consultantName} enviou esta permuta a você.',
              style: TextStyle(fontSize: 12, color: AppColors.textMedium),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => giveBarterOpinion(context, _barter,
                    onGiven: (updated) => setState(() => _barter = updated)),
                icon: const Icon(Icons.rate_review_outlined),
                label: const Text('Dar Parecer Técnico'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.atManager,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],

          // A DECISÃO — do comitê, e de mais ninguém. A pergunta é sobre a
          // capacidade que o servidor concedeu, não sobre o papel: mover a etapa
          // de um papel para outro é uma linha no servidor, e esta tela segue.
          if (AppData.can(Capability.bartersReview) && _barter.awaitsCommittee) ...[
            Text('Decisão do Comitê',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => reviewBarter(context, _barter, BarterStatus.denied,
                        onReviewed: (updated) => setState(() => _barter = updated)),
                    icon: const Icon(Icons.close),
                    label: const Text('Negar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.denied,
                      side: BorderSide(color: AppColors.denied),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => reviewBarter(context, _barter, BarterStatus.approved,
                        onReviewed: (updated) => setState(() => _barter = updated)),
                    icon: const Icon(Icons.check),
                    label: const Text('Aprovar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.approved,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // O FATURAMENTO — o último posto. Uma ação só, porque a etapa é uma
          // só: o faturista não decide nada, ele fatura o que foi aprovado.
          if (AppData.can(Capability.bartersInvoice) && _barter.awaitsInvoice) ...[
            Text('Faturamento',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 4),
            Text(
              'Aprovada pelo comitê${_barter.hasDecision ? ' por ${_barter.reviewedBy}' : ''}.',
              style: TextStyle(fontSize: 12, color: AppColors.textMedium),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => invoiceBarter(context, _barter,
                    onInvoiced: (updated) => setState(() => _barter = updated)),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Faturar Permuta'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.invoiced,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
          // O ANDAMENTO fecha a tela: quem abre a permuta vem primeiro pelo que
          // ela É — por onde ela passou e o que ainda falta se lê depois. Para o
          // faturista, é aqui que estão as peças das etapas anteriores; para o
          // consultor, é a resposta ao "e a minha permuta?".
          _ProgressSection(barter: _barter, loading: _loadingHistory),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  bool get _awaitsMyOpinion => _barter.awaitsOpinionFrom(widget.opinionManagerId);

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// A permuta está na mesa do gerente e o parecer ainda não veio.
///
/// Dizer isso por extenso — e com o NOME de quem está com ela — importa para o
/// consultor: sem este bloco, uma permuta registrada há três dias parecia
/// parada sem motivo, e a pergunta ("cadê a minha permuta?") ia para o admin,
/// que também não tinha o que responder.
class _AwaitingOpinionCard extends StatelessWidget {
  final String managerLabel;
  const _AwaitingOpinionCard({required this.managerLabel});

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.assignment_ind_outlined, size: 18, color: AppColors.atManager),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Com o gerente',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.atManager)),
                const SizedBox(height: 2),
                Text(
                  'Aguardando o parecer técnico de $managerLabel para seguir para o comitê.',
                  style: TextStyle(fontSize: 12, color: AppColors.textDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Um texto de etapa (a observação do comitê, a do faturamento) dentro do
/// cartão de informações — mesmo desenho para os dois, porque são a mesma coisa
/// vista em postos diferentes.
class _NoteBlock extends StatelessWidget {
  final String label;
  final String text;
  final IconData icon;
  const _NoteBlock({required this.label, required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.textLight),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: AppColors.textLight)),
                  const SizedBox(height: 2),
                  Text(text, style: TextStyle(fontSize: 13, color: AppColors.textDark)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// O ANDAMENTO da permuta: a esteira INTEIRA — do registro ao faturamento —
/// com o que já aconteceu preenchido.
///
/// É linha do tempo e CHECKLIST na mesma lista, e a segunda metade é a que
/// faltava. Os eventos contam o que houve, e só: uma permuta parada no comitê
/// mostrava dois passos, e nada neles dizia que faltavam dois nem com quem eles
/// estavam — que é exatamente a pergunta que o produtor faz ao consultor, e a
/// que ele não tinha como responder sem ligar para alguém.
///
/// Quem monta a lista é o SERVIDOR (`steps`), pelo motivo de sempre: o caminho
/// mora lá, e uma etapa nova aparece aqui sem versão nova do app. [_HistoryStep]
/// ficou como plano B — quando o andamento não vem (servidor anterior a ele, ou
/// um estado que ele não sabe encaixar na esteira), a tela ainda mostra os
/// eventos, que são fato gravado.
///
/// Nos dois casos o desenho sai dos EVENTOS, e não dos campos da permuta: os
/// campos são sobrescritos a cada etapa, os eventos não. É essa diferença que
/// faz uma permuta decidida continuar mostrando o parecer que a antecedeu.
class _ProgressSection extends StatelessWidget {
  final BarterModel barter;
  final bool loading;
  const _ProgressSection({required this.barter, required this.loading});

  /// Quantas etapas já foram cumpridas — a leitura de relance da checklist.
  ///
  /// Some quando a linha PAROU: numa permuta negada, "3 de 4" se leria como
  /// "falta uma", e não falta — não vem mais nenhuma.
  String? get _tally {
    if (!barter.hasProgress || barter.steps.any((step) => step.isHalted)) return null;
    final done = barter.steps.where((step) => step.isDone).length;
    return '$done de ${barter.steps.length} etapas';
  }

  @override
  Widget build(BuildContext context) {
    if (!barter.hasProgress && !barter.hasHistory) {
      // Nada veio e nada está vindo: o servidor não mandou (resposta antiga ou
      // falha de rede). A seção some em vez de mostrar um vazio que pareceria
      // "esta permuta não tem história" — toda permuta tem.
      if (!loading) return const SizedBox.shrink();
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: SizedBox(
          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    final tally = _tally;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.checklist_rounded, size: 18, color: AppColors.textMedium),
                const SizedBox(width: 8),
                Text('Andamento',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                if (tally != null) ...[
                  const Spacer(),
                  Text(tally, style: TextStyle(fontSize: 11, color: AppColors.textLight)),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (barter.hasProgress)
              for (var i = 0; i < barter.steps.length; i++)
                _ProgressStep(
                  step: barter.steps[i],
                  // A cor do estado de AGORA é a mesma do crachá lá em cima —
                  // a etapa de agora é onde a permuta está.
                  liveColor: statusColor(barter.status),
                  // O trilho não desce do último passo: ele marca o que veio
                  // DEPOIS, e depois do último não há nada.
                  last: i == barter.steps.length - 1,
                )
            else
              for (var i = 0; i < barter.events.length; i++)
                _HistoryStep(
                  event: barter.events[i],
                  last: i == barter.events.length - 1,
                ),
          ],
        ),
      ),
    );
  }
}

/// Uma etapa da checklist: o marcador, o nome da etapa e — conforme ela já
/// tenha acontecido ou não — quem a cumpriu ou o que ela ainda espera.
class _ProgressStep extends StatelessWidget {
  final BarterStepModel step;
  final Color liveColor;
  final bool last;

  const _ProgressStep({required this.step, required this.liveColor, required this.last});

  /// A cor do passo.
  ///
  /// A etapa cumprida usa o estado que ela ALCANÇOU — é o que distingue no
  /// desenho a decisão que aprovou da que negou, sem depender de ler o texto. As
  /// que ainda não aconteceram ficam em cinza de propósito: com cor, pesariam
  /// igual às cumpridas e a checklist perderia o contraste que a faz ser lida de
  /// relance.
  Color get _color {
    if (step.isCurrent) return liveColor;
    if (step.isDone) {
      return step.toStatus == null ? AppColors.textMedium : statusColor(step.toStatus!);
    }
    return AppColors.textLight;
  }

  /// A ASSINATURA da etapa: quem, com que papel e quando.
  ///
  /// Montada por partes porque nem toda etapa tem todas. A que ainda não
  /// aconteceu tem só o papel de quem vai cumpri-la ("Faturista"), que é o que
  /// há para dizer; e a permuta anterior à linha do tempo tem a etapa cumprida
  /// sem autor gravado — aí sobra o papel, que é verdade, em vez de um traço no
  /// lugar do nome.
  String get _byline {
    final actorRole = step.actorRoleLabel.isNotEmpty ? step.actorRoleLabel : step.roleLabel;
    return [
      if (step.actorName != null && step.actorName!.isNotEmpty) step.actorName!,
      if (actorRole.isNotEmpty) actorRole,
      if (step.at != null) formatDateTime(step.at!),
    ].join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final walked = step.isDone || step.isCurrent;
    // A etapa de agora é o que a pessoa veio ver: ela puxa o olho, e as que
    // ainda não chegaram recuam para o cinza.
    final subtitle = step.stateNote ?? _byline;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              _marker(color),
              if (!last)
                Expanded(
                  // O trecho JÁ ANDADO fica colorido, o que falta fica cinza: o
                  // trilho sozinho já mostra até onde a permuta chegou.
                  child: Container(
                    width: 2,
                    color: step.isDone ? color.withValues(alpha: 0.35) : AppColors.divider,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          step.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: step.isCurrent ? FontWeight.w800 : FontWeight.w700,
                            color: walked ? AppColors.textDark : AppColors.textLight,
                          ),
                        ),
                      ),
                      if (step.outcomeLabel != null) ...[
                        const SizedBox(width: 6),
                        _OutcomeTag(label: step.outcomeLabel!, color: color),
                      ],
                    ],
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: step.isCurrent ? AppColors.textMedium : AppColors.textLight,
                      ),
                    ),
                  ],
                  if (step.note != null && step.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(step.note!,
                        style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// O marcador, que é o que dá à seção a cara de checklist: visto na cumprida,
  /// anel na de agora, círculo vazio na que ainda vem e traço na que não vem.
  Widget _marker(Color color) {
    switch (step.state) {
      case BarterStepState.done:
        return Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 12, color: Colors.white),
        );
      case BarterStepState.current:
        return Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color, width: 2.5),
          ),
        );
      case BarterStepState.halted:
        return Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.divider, width: 1.5),
          ),
          child: Icon(Icons.remove, size: 10, color: AppColors.textLight),
        );
      case BarterStepState.ahead:
        return Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.divider, width: 1.5),
          ),
        );
    }
  }
}

/// COMO a etapa terminou, quando ela podia terminar de mais de um jeito. Hoje só
/// a decisão do comitê tem — e é ela que o crachá precisa dizer, porque
/// "Decisão do comitê" sozinho não conta se foi sim ou não.
class _OutcomeTag extends StatelessWidget {
  final String label;
  final Color color;
  const _OutcomeTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// Um passo da linha do tempo: o marcador colorido, o que houve, quem fez e o
/// que escreveu.
class _HistoryStep extends StatelessWidget {
  final BarterEventModel event;
  final bool last;
  const _HistoryStep({required this.event, required this.last});

  @override
  Widget build(BuildContext context) {
    final color = statusColor(event.toStatus);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 2, color: AppColors.divider),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title,
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const SizedBox(height: 2),
                  Text(
                    '${event.actorName}'
                    '${event.actorRoleLabel.isEmpty ? '' : ' • ${event.actorRoleLabel}'}'
                    ' • ${formatDateTime(event.at)}',
                    style: TextStyle(fontSize: 11, color: AppColors.textLight),
                  ),
                  if (event.note != null && event.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(event.note!,
                        style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// FUNRURAL E SENAR da entrega de grão desta permuta.
///
/// O valor é uma CONTA, não uma cobrança do sistema: quem recolhe é o produtor
/// (ou o adquirente, por sub-rogação), e o que a permuta faz é dizer sobre
/// quanto. Ele aparece aqui para a conversa acontecer no fechamento, e não na
/// nota — a alíquota é a que foi registrada com a permuta.
///
/// Em R$ para a retaguarda; em SACAS para o consultor, que não vê moeda em lugar
/// nenhum do app. É a mesma alíquota nos dois casos: percentual sobre a entrega.
class _TaxCard extends StatelessWidget {
  final BarterModel barter;
  final bool showsCurrency;

  const _TaxCard({required this.barter, required this.showsCurrency});

  @override
  Widget build(BuildContext context) {
    final value = showsCurrency
        ? formatCurrency(barter.taxAmount)
        : '${formatSacks(barter.taxInSacks)} ${barter.referenceGrainName.toLowerCase()}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.textLight),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Funrural + Senar (${barter.taxRateLabel})',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                const SizedBox(height: 2),
                Text(
                  // A FORMA escolhida no fechamento, por extenso: é ela que
                  // explica por que o percentual é este e não o outro.
                  '${barter.taxRegime.label} • incide sobre a entrega de grão, que '
                  'é comercialização de produção rural. Recolhimento por conta do '
                  'produtor.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textDark)),
        ],
      ),
    );
  }
}

class _ItemsSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<BarterItem> items;
  final String totalLabel;
  final double total;
  final double referenceValue;
  final String referenceGrainName;
  final bool showValue;

  /// Quantas sacas ESTE item representa, ou null quando não dá para dizer.
  ///
  /// É uma função e não um número porque a resposta depende da seção: na do grão
  /// a própria quantidade do item JÁ é a resposta, e na dos insumos ela exige o
  /// valor unitário — que a lente de valor da API não manda ao consultor. Null
  /// aí é honesto, e é o que substituiu o "0 sc" que a tela dele imprimia em
  /// cada linha quando isto era uma divisão por uma cotação zerada.
  final double? Function(BarterItem item) sacksOf;

  /// As sacas da seção inteira, ou null quando não dá para dizer.
  final double? totalSacks;

  const _ItemsSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.items,
    required this.totalLabel,
    required this.total,
    required this.referenceValue,
    required this.referenceGrainName,
    required this.showValue,
    required this.sacksOf,
    required this.totalSacks,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: AppColors.textLight)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ...items.asMap().entries.map((entry) {
                final i = entry.key;
                final item = entry.value;
                return Column(
                  children: [
                    if (i > 0) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.productName,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  showValue
                                      ? '${formatQty(item.quantity)} ${item.unit} × ${formatCurrency(item.unitValue)}'
                                      : '${formatQty(item.quantity)} ${item.unit}',
                                  style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Builder(builder: (_) {
                                final sacks = sacksOf(item);
                                return Text(
                                  sacks != null
                                      ? formatSacks(sacks)
                                      : (showValue ? formatCurrency(item.total) : ''),
                                  style: TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w700, color: accent),
                                );
                              }),
                              if (referenceValue > 0 && showValue)
                                Text('≈ ${formatCurrency(item.total)}',
                                    style: TextStyle(fontSize: 10, color: AppColors.textLight)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(totalLabel,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          totalSacks != null
                              ? '${formatSacks(totalSacks!)} ${referenceGrainName.toLowerCase()}'
                              : (showValue ? formatCurrency(total) : ''),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: accent),
                        ),
                        if (referenceValue > 0 && showValue)
                          Text('≈ ${formatCurrency(total)}',
                              style: TextStyle(fontSize: 10, color: AppColors.textLight)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 12, color: AppColors.textLight)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 13, color: AppColors.textDark, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
