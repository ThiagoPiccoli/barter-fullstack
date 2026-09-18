import 'dart:async';

import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/api/api_client.dart';
import '../services/barter_pdf.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/common_widgets.dart';
import 'barter_screen.dart';
import 'cpr_form_screen.dart';
import 'invoicing_screen.dart';

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Não foi possível gerar o PDF: $e')));
    }
  }

  /// Abre o FATURAMENTO desta permuta — as notas fiscais e o ato de faturar.
  ///
  /// Ela deixou de ser a tela da cédula, e a separação é a mudança inteira: o
  /// faturista anexa as notas e carimba; a cédula é do consultor (que a
  /// preenche) e do emissor (que a confere e emite).
  void _openInvoicing() =>
      openInvoicing(context, _barter, onInvoiced: (updated) => setState(() => _barter = updated));

  /// Abre a MESA DA CÉDULA — o formulário para quem preenche, a conferência
  /// para quem emite, o documento para quem só lê.
  void _openCpr() =>
      openCprDesk(context, _barter, onChanged: (updated) => setState(() => _barter = updated));

  /// O FATURISTA alcança a mesa dele daqui?
  ///
  /// Nos dois estados do trecho: a aprovada (o ato) e a já faturada (as notas
  /// continuam editáveis — nota cancelada é reemitida).
  bool get _canOpenInvoicing => AppData.can(Capability.bartersInvoice) && _barter.wasApproved;

  /// E a CÉDULA — quem a alcança daqui?
  ///
  /// Três papéis, com perguntas diferentes: o consultor que a preenche, o
  /// emissor que a confere e emite, e o admin que tira a segunda via. Quem
  /// responde quem é cada um é o servidor (`barters.cprRead`), e a tela só
  /// pergunta.
  ///
  /// O RASCUNHO fica de fora para quem só lê: uma cédula que ninguém começou não
  /// tem segunda via. Para quem PREENCHE ela abre desde o início — é a razão
  /// prática da mudança de dono, e a permuta demora semanas para ser faturada.
  ///
  /// O RASCUNHO NÃO PODE FICAR DE FORA PARA QUEM PREENCHE, e isto já esteve
  /// errado aqui: enquanto a condição do consultor era `!isDraft`, a permuta
  /// ficava presa num beco — o botão da cédula só aparecia depois de sair do
  /// rascunho, e só se sai do rascunho encaminhando, que é o que exige a cédula.
  bool get _canOpenCpr =>
      AppData.can(Capability.bartersCprRead) &&
      (AppData.can(Capability.bartersCprFill) || _barter.wasApproved);

  /// Quem EMITE a cédula, e a permuta está no trecho dele?
  bool get _canIssueCpr =>
      AppData.can(Capability.bartersCprIssue) && _barter.wasInvoiced && !_barter.isCprRegistered;

  @override
  Widget build(BuildContext context) {
    final producer = AppData.producerById(_barter.producerId);
    return Scaffold(
      appBar: AppBar(
        title: Text(_barter.id),
        actions: [
          // A CÉDULA vem primeiro para quem a preenche ou a emite, e com ícone
          // próprio. Enquanto ela e o comprovante dividiam o mesmo ícone de PDF,
          // chegar até ela exigia rolar a tela inteira até um botão no fim —
          // procurar, para fazer a coisa que se veio fazer.
          if (_canOpenCpr)
            IconButton(
              icon: const Icon(Icons.description_outlined),
              tooltip: 'Cédula de Produto Rural (CPR)',
              onPressed: _openCpr,
            ),
          // AS NOTAS, para quem fatura. Ícone próprio pelo mesmo motivo: o
          // documento do posto do faturista é a nota fiscal.
          if (_canOpenInvoicing)
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: 'Notas fiscais e faturamento',
              onPressed: _openInvoicing,
            ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Comprovante da permuta',
            onPressed: () => _sharePdf(producer),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: StatusBadge(status: _barter.status)),
          ),
        ],
      ),
      body: BoundedContent(
        maxWidth: 1400,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AdaptiveDetailLayout(blocks: _blocks(producer)),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Os blocos da tela, e a coluna de cada um quando há monitor.
  ///
  /// A ORDEM desta lista é a ordem do CELULAR, e é ela que carrega a prioridade
  /// pensada aqui: a ressalva antes dos pareceres, os pareceres antes dos itens.
  /// No largo, [AdaptiveDetailLayout] separa `main` de `side` preservando a
  /// ordem relativa dentro de cada coluna — o que a permuta É de um lado, o que
  /// se sabe sobre ela e o que se pode fazer do outro.
  ///
  /// O critério da coluna é a PERGUNTA que cada bloco responde, e não o tamanho
  /// dele: quem abre uma permuta no computador está decidindo, e os pareceres
  /// que justificam a decisão não podem estar a quatro rolagens do botão que a
  /// executa.
  List<DetailBlock> _blocks(ProducerModel? producer) => [
    // O SALDO abre a coluna do corpo: é o número que responde "quanto isto
    // custa em saca". Ele é o primeiro bloco do `main` e o cadastro é o
    // primeiro do `side`, então no monitor os dois nascem lado a lado — o
    // número à esquerda, de quem ele é à direita. No celular, o saldo
    // continua abrindo a tela, com o cadastro logo abaixo.
    DetailBlock.main(
      BarterBalanceBar(
        inputCost: _barter.inputCost,
        referenceValue: _barter.referenceValue,
        referenceGrainName: _barter.referenceGrainName,
        inputCount: _barter.inputs.length,
        showValue: widget.isAdmin,
        sacksPerHa: _barter.sacksPerHa,
        areaHa: _barter.producerAreaHa,
      ),
    ),

    // O CADASTRO: quem, onde, quando, sob qual Barter.
    DetailBlock.side(
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(label: 'Produtor', value: _barter.producerName),
              if (producer != null) _InfoRow(label: 'Propriedade', value: producer.location),
              // A RETIRADA vale para todo mundo, inclusive o consultor: é
              // onde o produtor dele vai buscar os insumos, e a primeira
              // pergunta que ele recebe de volta.
              _InfoRow(label: 'Retirada em', value: _barter.unitLabel),
              if (widget.isAdmin) ...[
                _InfoRow(label: 'Consultor', value: _barter.consultantName),
                _InfoRow(label: 'Filial', value: _barter.consultantBranch),
              ],
              // O INVESTIMENTO POR HECTARE — a régua que compara permutas
              // de tamanhos diferentes. Ela vem do servidor já dividida, e
              // só para quem pode compará-la (admin, comitê e faturista):
              // para o consultor e o gerente o campo simplesmente não chega,
              // e a linha não aparece. Ver `barters.investmentPerHa`.
              //
              // `null` com área presente é permuta anterior ao campo de
              // área: a linha some em vez de mostrar "0 sc/ha", que seria
              // uma afirmação, e falsa.
              if (_barter.sacksPerHa != null)
                _InfoRow(
                  label: 'Investimento',
                  value:
                      '${formatSacksPerHa(_barter.sacksPerHa!)}'
                      '${_barter.producerAreaHa != null && _barter.producerAreaHa! > 0 ? ' • ${formatQty(_barter.producerAreaHa!)} ha' : ''}',
                ),
              const Divider(height: 16),
              // Em qual gestão do Barter esta permuta foi fechada: é o que
              // explica os valores dela, que não mudam quando a versão
              // seguinte é publicada.
              if (_barter.versionCode.isNotEmpty)
                _InfoRow(label: 'Barter', value: _barter.versionCode),
              _InfoRow(label: 'Criada em', value: _formatDate(_barter.createdAt)),
              if (_barter.updatedAt != null)
                _InfoRow(label: 'Atualizada em', value: _formatDate(_barter.updatedAt!)),
              if (_barter.hasDecision) _InfoRow(label: 'Decidida por', value: _barter.reviewedBy!),
              if (_barter.invoicedBy != null) ...[
                _InfoRow(label: 'Faturada por', value: _barter.invoicedBy!),
                if (_barter.invoicedAt != null)
                  _InfoRow(label: 'Faturada em', value: _formatDate(_barter.invoicedAt!)),
                // AS NOTAS resumidas: a contagem, e não a lista. Quem quer os
                // números abre a tela do faturamento, onde elas têm o arquivo
                // ao lado — aqui a pergunta é "esta permuta tem prova?".
                if (_barter.invoices.isNotEmpty)
                  _InfoRow(
                    label: 'Notas fiscais',
                    value: _barter.invoices.map((n) => n.label).join(', '),
                  ),
              ],
              // A EMISSÃO DA CÉDULA — as três marcas do emissor, cada uma
              // aparecendo no dia em que ela acontece. Elas ficam aqui, e não só
              // na linha do tempo, porque "em que pé está a CPR?" é a pergunta
              // que a operação faz sobre a entrega, e a resposta não pode
              // depender de rolar até o histórico.
              if (_barter.cprEmittedBy != null) ...[
                _InfoRow(label: 'CPR emitida por', value: _barter.cprEmittedBy!),
                if (_barter.cprEmittedAt != null)
                  _InfoRow(label: 'CPR emitida em', value: _formatDate(_barter.cprEmittedAt!)),
              ],
              if (_barter.cprSignedAt != null)
                _InfoRow(label: 'CPR assinada em', value: _formatDate(_barter.cprSignedAt!)),
              if (_barter.cprRegistryNumber != null) ...[
                _InfoRow(label: 'Registro da CPR', value: _barter.cprRegistryNumber!),
                if (_barter.cprRegistryPlace != null && _barter.cprRegistryPlace!.isNotEmpty)
                  _InfoRow(label: 'Registrada em', value: _barter.cprRegistryPlace!),
              ],
              // A RESSALVA não entra aqui: ela tem bloco próprio, acima
              // dos itens, porque é a única linha da tela que pede AÇÃO de
              // quem lê. Repetida nos dois lugares, ela viraria paisagem.
              if (!_barter.hasConditions &&
                  _barter.reviewNote != null &&
                  _barter.reviewNote!.isNotEmpty)
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
              if (_barter.cprEmissionNote != null && _barter.cprEmissionNote!.isNotEmpty)
                _NoteBlock(
                  label: 'Observação da emissão',
                  text: _barter.cprEmissionNote!,
                  icon: Icons.description_outlined,
                ),
              if (_barter.cprSignatureNote != null && _barter.cprSignatureNote!.isNotEmpty)
                _NoteBlock(
                  label: 'Coleta de assinaturas',
                  text: _barter.cprSignatureNote!,
                  icon: Icons.draw_outlined,
                ),
            ],
          ),
        ),
      ),
    ),

    // O PEDIDO DE ALTERAÇÃO vem antes de tudo o que se lê sobre a permuta,
    // e antes até da ressalva: enquanto ele está aberto, os insumos podem
    // mudar — e dar parecer, decidir ou faturar sobre eles é trabalho que
    // pode ser jogado fora no minuto seguinte. Quem abre a permuta precisa
    // topar com isso antes de agir sobre ela.
    //
    // A RECUSA continua aparecendo depois de decidida, e só para quem tem o
    // que fazer com ela: quem pediu (para saber que ouviu não, e por quê) e
    // quem decide (para não decidir duas vezes o mesmo caso).
    if (_barter.hasOpenChangeRequest || (_barter.changeRequestDenied && _seesChangeReply))
      DetailBlock.side(
        ChangeRequestCard(
          barter: _barter,
          onAccept: _canDecideChange
              ? () => decideBarterChange(
                  context,
                  _barter,
                  accept: true,
                  onDecided: (updated) => setState(() => _barter = updated),
                )
              : null,
          onDeny: _canDecideChange
              ? () => decideBarterChange(
                  context,
                  _barter,
                  accept: false,
                  onDecided: (updated) => setState(() => _barter = updated),
                )
              : null,
          // A TERCEIRA saída, e a mais usada: a maior parte dos pedidos é de um
          // número. Ela fica ao lado das outras duas porque é a mesma decisão —
          // o que muda é o preço dela: aqui nada é refeito.
          onChangePrices: _canDecideChange && _barter.inputs.isNotEmpty
              ? () => changeBarterPrices(
                  context,
                  _barter,
                  onChanged: (updated) => setState(() => _barter = updated),
                )
              : null,
        ),
      ),

    // OS PEDIDOS DE FORA DO BARTER. Vêm logo depois do pedido de alteração,
    // e pelo mesmo motivo dele: enquanto um está em aberto, a lista de
    // insumos desta permuta está para crescer — e dar parecer, decidir ou
    // faturar sobre ela é trabalho que pode mudar de tamanho no minuto
    // seguinte.
    //
    // Os já decididos continuam na tela: o incluído é a ORIGEM de um item
    // que não está na tabela do Barter, e é a única coisa que explica o
    // valor dele.
    if (_barter.productRequests.isNotEmpty)
      DetailBlock.side(
        ProductRequestsCard(
          barter: _barter,
          onDecide: _canDecideProduct
              ? (request, {required accept}) => decideBarterProduct(
                  context,
                  _barter,
                  request,
                  accept: accept,
                  onDecided: (updated) => setState(() => _barter = updated),
                )
              : null,
        ),
      ),

    // A RESSALVA vem PRIMEIRO, e antes até dos pareceres: ela é a única
    // coisa na tela que alguém precisa fazer. Quem abre uma permuta
    // aprovada com exigência tem de topar com ela antes de qualquer
    // leitura.
    if (_barter.hasConditions) DetailBlock.side(ConditionsCard(barter: _barter)),

    // OS PARECERES vêm antes dos itens de propósito: quem abre uma permuta
    // que já passou pelo consultor e pelo gerente quer saber o que eles
    // disseram antes de conferir linha a linha o que ela tem dentro.
    //
    // Na ORDEM em que foram escritos, que é a ordem em que o comitê os lê:
    // primeiro quem conhece o cliente, depois quem responde pelo time.
    if (_barter.hasConsultantOpinion) DetailBlock.side(ConsultantOpinionCard(barter: _barter)),
    if (_barter.hasManagerOpinion)
      DetailBlock.side(ManagerOpinionCard(barter: _barter))
    else if (_barter.awaitsManager)
      DetailBlock.side(_AwaitingOpinionCard(managerLabel: _barter.managerLabel)),

    DetailBlock.main(
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
    ),

    DetailBlock.main(
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
    ),

    // Resumo do pagamento: quantas sacas o produtor entrega para pagar tudo
    DetailBlock.main(
      Card(
        color: AppColors.primarySurface,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Expanded pelo mesmo motivo de sempre nesta tela: numa `Row`
              // o texto solto não tem largura máxima, e a linha estoura
              // quando o outro lado cresce ("para 3 insumo(s) retirado(s)").
              Expanded(
                child: Text(
                  'TOTAL A ENTREGAR',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _barter.hasSacks
                          ? '${formatSacks(_barter.sacksToDeliver)} ${_barter.referenceGrainName.toLowerCase()}'
                          : '0 sc',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      widget.isAdmin
                          ? '≈ ${formatCurrency(_barter.inputCost)} em insumos'
                          : 'para ${_barter.inputs.length} insumo(s) retirado(s)',
                      style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                      textAlign: TextAlign.end,
                    ),
                  ],
                ),
              ),
            ],
          ),
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
    if (_barter.hasTax) DetailBlock.main(_TaxCard(barter: _barter, showsCurrency: widget.isAdmin)),

    // O PENHOR, logo depois do imposto e pelo mesmo motivo: é consequência do
    // total. As sacas que a permuta deve precisam nascer de algum lugar, e este
    // card diz de quanta terra.
    //
    // É AQUI que o consultor lê o número pela primeira vez — antes do formulário
    // da cédula, com o produtor ainda por perto. Descobrir "esta permuta pede
    // 34 ha" na tela da cédula já é tarde para renegociar o tamanho dela;
    // descobrir na emissão é tarde para tudo.
    if (_barter.hasPledge) DetailBlock.main(_PledgeCard(barter: _barter)),

    // O RASCUNHO — a etapa do consultor, e a única em que ele age depois
    // de registrar.
    if (_isMyDraft)
      DetailBlock.side(
        _ConsultantDraftCard(
          barter: _barter,
          onChanged: (updated) => setState(() => _barter = updated),
        ),
      ),

    if (_awaitsMyOpinion)
      DetailBlock.side(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ação do Gerente',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            // O FATO, e não a explicação da etapa: quem enviou e quando. O
            // que o parecer é, e para onde a permuta vai depois dele, o
            // gerente já sabe — é o trabalho dele.
            Text(
              '${_barter.consultantName} enviou esta permuta a você.',
              style: TextStyle(fontSize: 12, color: AppColors.textMedium),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => giveBarterOpinion(
                context,
                _barter,
                onGiven: (updated) => setState(() => _barter = updated),
              ),
              icon: const Icon(Icons.rate_review_outlined),
              label: const Text('Dar Parecer Técnico'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.atManager,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),

    // A DECISÃO — do comitê, e de mais ninguém. A pergunta é sobre a
    // capacidade que o servidor concedeu, não sobre o papel: mover a etapa
    // de um papel para outro é uma linha no servidor, e esta tela segue.
    if (AppData.can(Capability.bartersReview) && _barter.awaitsCommittee)
      DetailBlock.side(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Decisão do Comitê',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => reviewBarter(
                      context,
                      _barter,
                      BarterStatus.denied,
                      onReviewed: (updated) => setState(() => _barter = updated),
                    ),
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
                    onPressed: () => reviewBarter(
                      context,
                      _barter,
                      BarterStatus.approved,
                      onReviewed: (updated) => setState(() => _barter = updated),
                    ),
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
            const SizedBox(height: 12),
            // A TERCEIRA SAÍDA, em linha própria e mais discreta que as duas
            // acima: ela é uma aprovação, e não uma terceira coisa entre o
            // sim e o não — mas cobra um texto de quem a escolhe, então não
            // pode ser tão fácil de clicar quanto as outras duas.
            OutlinedButton.icon(
              onPressed: () => reviewBarter(
                context,
                _barter,
                BarterStatus.approvedWithConditions,
                onReviewed: (updated) => setState(() => _barter = updated),
              ),
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Aprovar com Ressalva'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.approvedWithConditions,
                side: BorderSide(color: AppColors.approvedWithConditions),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),

    // O FATURAMENTO — as notas fiscais e o carimbo. Uma ação só, porque a
    // etapa é uma só: o faturista não decide nada, ele fatura o que foi
    // aprovado e anexa a prova disso.
    if (AppData.can(Capability.bartersInvoice) && _barter.awaitsInvoice)
      DetailBlock.side(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Faturamento',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Aprovada pelo comitê${_barter.hasDecision ? ' por ${_barter.reviewedBy}' : ''}. '
              '${_barter.invoices.isEmpty ? 'Anexe a nota fiscal para faturar.' : '${_barter.invoices.length} nota(s) anexada(s).'}',
              style: TextStyle(fontSize: 12, color: AppColors.textMedium),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _openInvoicing,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Notas e Faturamento'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.invoiced,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),

    // AS NOTAS de uma permuta já faturada: elas continuam editáveis, porque
    // nota cancelada é reemitida. Contorno, e não botão cheio — o ato do
    // posto já foi praticado.
    if (_canOpenInvoicing && !_barter.awaitsInvoice)
      DetailBlock.side(
        OutlinedButton.icon(
          onPressed: _openInvoicing,
          icon: const Icon(Icons.receipt_long_outlined),
          label: Text('Notas Fiscais (${_barter.invoices.length})'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.invoiced,
            side: BorderSide(color: AppColors.invoiced),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),

    // A EMISSÃO DA CÉDULA — o posto do EMISSOR, e o bloco que diz qual dos
    // três atos é o da vez. Botão cheio porque é ação de posto: a permuta
    // está parada esperando ele.
    if (_canIssueCpr)
      DetailBlock.side(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Emissão da CPR',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _barter.awaitsCprIssue
                  ? 'Faturada por ${_barter.invoicedBy ?? ''}. Confira a cédula que o '
                      'consultor preencheu e emita o título.'
                  : _barter.awaitsSignatures
                      ? 'Emitida por ${_barter.cprEmittedBy ?? ''}. Falta a coleta de '
                          'assinaturas.'
                      : 'Assinada. Falta o registro — é ele que faz a garantia valer '
                          'contra terceiros.',
              style: TextStyle(fontSize: 12, color: AppColors.textMedium),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _openCpr,
              icon: const Icon(Icons.description_outlined),
              label: Text(_barter.awaitsCprIssue
                  ? 'Conferir e Emitir CPR'
                  : _barter.awaitsSignatures
                      ? 'Registrar Assinaturas'
                      : 'Registrar Cédula'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.invoiced,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),

    // A CÉDULA para quem NÃO tem ato nela agora: o consultor que a preenche
    // (ou já preencheu) e o admin que tira a segunda via. Contorno, pelo
    // mesmo critério — não é ação de posto nesta permuta.
    if (_canOpenCpr && !_canIssueCpr)
      DetailBlock.side(
        OutlinedButton.icon(
          onPressed: _openCpr,
          icon: const Icon(Icons.description_outlined),
          label: Text(AppData.can(Capability.bartersCprFill) && !_barter.isCprIssued
              ? 'Preencher a Cédula (CPR)'
              : 'Cédula de Produto Rural (CPR)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.invoiced,
            side: BorderSide(color: AppColors.invoiced),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),

    // O PEDIDO DE ALTERAÇÃO — a ação do consultor sobre a permuta que já
    // saiu da mão dele, e a única que ele tem depois de encaminhar.
    //
    // Contorno, e não botão cheio: ela não é o caminho normal da permuta. O
    // normal é ela andar; pedir alteração é interromper isso, e custa o
    // trabalho de quem já opinou ou decidiu.
    if (_canRequestChange)
      DetailBlock.side(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: () => requestBarterChange(
                context,
                _barter,
                onRequested: (updated) => setState(() => _barter = updated),
              ),
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Solicitar Alteração'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.pending,
                side: BorderSide(color: AppColors.pending),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'O administrador avalia. Liberada, ela volta a ser rascunho seu e '
              'percorre a linha de novo.',
              style: TextStyle(fontSize: 11, color: AppColors.textLight),
            ),
          ],
        ),
      ),

    // O PEDIDO DE FORA DO BARTER — a outra coisa que o consultor pede ao
    // admin, e a única que ele pode pedir JÁ NO RASCUNHO.
    //
    // Ela fica ao lado do pedido de alteração, e não dentro da tela de
    // montagem da permuta, porque é sobre ESTA permuta: o item vai entrar
    // nela, com um valor acertado para ela.
    if (_canRequestProduct)
      DetailBlock.side(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: () => requestBarterProduct(
                context,
                _barter,
                onRequested: (updated) => setState(() => _barter = updated),
              ),
              icon: const Icon(Icons.add_shopping_cart_outlined),
              label: const Text('Pedir Produto de Fora'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.input,
                side: BorderSide(color: AppColors.input),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Para o que a tabela desta gestão não tem. O administrador acerta o '
              'valor e inclui o item nesta permuta.',
              style: TextStyle(fontSize: 11, color: AppColors.textLight),
            ),
          ],
        ),
      ),

    // O ANDAMENTO fecha a lista — e fica na coluna do ESTADO, não na do
    // corpo.
    //
    // Ele já esteve em `main`, e era escolha pelo tamanho: a esteira é alta,
    // e a coluna larga a acomodava melhor. Só que a pergunta que ele responde
    // — por onde a permuta passou, com quem ela está, o que falta — é a mesma
    // do cadastro e dos pareceres, e não a dos itens e totais. Em `main` ele
    // ficava a três rolagens do "Com o gerente" que diz a mesma coisa em uma
    // linha, enquanto a direita terminava cedo e sobrava tela.
    //
    // Último da lista nos dois desenhos: no estreito, quem abre a permuta vem
    // primeiro pelo que ela É, e o histórico se lê depois. Trocar de coluna
    // não mexeu nisso — é a ordem desta lista que manda no celular.
    DetailBlock.side(_ProgressSection(barter: _barter, loading: _loadingHistory)),
  ];

  bool get _awaitsMyOpinion => _barter.awaitsOpinionFrom(widget.opinionManagerId);

  /// Este usuário DECIDE o pedido de alteração? É o admin — e a pergunta é
  /// sobre a capacidade, não sobre o papel, pela mesma razão da decisão do
  /// comitê: mover a etapa de um papel para outro é uma linha no servidor.
  bool get _canDecideChange => AppData.can(Capability.bartersChangeReview);

  /// Este usuário PEDE alteração desta permuta? Só quem a registrou, e só
  /// enquanto ela não foi faturada — a mesma regra que o servidor aplica.
  bool get _canRequestChange =>
      AppData.can(Capability.bartersChangeRequest) &&
      _barter.canBeChangedBy(AppData.currentUser?.id);

  /// Este usuário ATENDE o pedido de fora do Barter? É o admin — quem publica a
  /// tabela de valores é quem diz por quanto entra o que ficou fora dela.
  bool get _canDecideProduct => AppData.can(Capability.bartersProductReview);

  /// Este usuário PEDE um produto de fora para esta permuta? Só quem a
  /// registrou, e só até o comitê decidir — a mesma janela do servidor.
  bool get _canRequestProduct =>
      AppData.can(Capability.bartersProductRequest) &&
      _barter.canRequestProductBy(AppData.currentUser?.id);

  /// Este usuário tem o que fazer com a RECUSA de um pedido já decidido? Quem
  /// pediu e quem decide. Para os demais ela é ruído: um assunto encerrado
  /// entre outras duas pessoas.
  bool get _seesChangeReply => _canDecideChange || _barter.consultantId == AppData.currentUser?.id;

  /// É um RASCUNHO MEU? Só quem registrou escreve o parecer e encaminha — a
  /// mesma conferência do servidor, repetida aqui para a tela não oferecer um
  /// botão que levaria 403.
  bool get _isMyDraft =>
      _barter.isDraft &&
      AppData.can(Capability.bartersRegister) &&
      _barter.consultantId == AppData.currentUser?.id;

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// O RASCUNHO na mão do consultor: o parecer dele, e o botão que encaminha.
///
/// Ele é um formulário, e não um diálogo, porque é a etapa que ACONTECE EM DOIS
/// MOMENTOS — foi para isso que o rascunho existe. O consultor monta a permuta
/// hoje, conversa com o produtor amanhã e escreve o que sabe dele; um diálogo
/// que só fecha enviando forçaria os dois momentos a serem um só, que era
/// exatamente o problema.
///
/// Por isso as duas ações são separadas e desiguais: *Salvar* é ordinário
/// (guarda e não move nada) e *Encaminhar* é o ato — ele tira a permuta da mesa
/// dele e não tem volta. O segundo só liga quando há parecer suficiente, que é
/// a mesma regra do servidor.
class _ConsultantDraftCard extends StatefulWidget {
  final BarterModel barter;
  final ValueChanged<BarterModel> onChanged;

  const _ConsultantDraftCard({required this.barter, required this.onChanged});

  @override
  State<_ConsultantDraftCard> createState() => _ConsultantDraftCardState();
}

class _ConsultantDraftCardState extends State<_ConsultantDraftCard> {
  late final TextEditingController _note = TextEditingController(
    text: widget.barter.consultantNote ?? '',
  );
  bool _saving = false;
  bool _forwarding = false;

  /// O texto salvo no servidor, para saber se há o que salvar. Ele acompanha as
  /// respostas: gravou, virou o novo "salvo".
  late String _saved = widget.barter.consultantNote ?? '';

  /// O QUE FALTA NA CÉDULA para esta permuta poder ser encaminhada.
  ///
  /// Vem de [CprDesk.consultantGaps] — a mesma lista com que o servidor recusa
  /// o encaminhamento —, e por isso o aviso daqui nunca diverge da recusa de lá.
  ///
  /// `null` é "ainda não sei": a consulta está no ar, ou falhou. E não saber NÃO
  /// desliga o botão. O portão de verdade é o do servidor, e travar a esteira
  /// porque uma consulta de aviso não voltou transformaria um problema de rede
  /// numa permuta que ninguém consegue encaminhar.
  List<String>? _cprGaps;

  @override
  void initState() {
    super.initState();
    _loadCprGaps();
  }

  /// Busca as pendências da cédula. Silenciosa nos dois sentidos: não mostra
  /// "carregando" (é informação de apoio, não o assunto da tela) e engole o erro
  /// (ver [_cprGaps]).
  Future<void> _loadCprGaps() async {
    try {
      final desk = await AppData.barterCpr(widget.barter.id);
      if (mounted) setState(() => _cprGaps = desk.consultantGaps);
    } catch (_) {
      if (mounted) setState(() => _cprGaps = null);
    }
  }

  /// A cédula está travando o encaminhamento?
  bool get _cprBlocks => (_cprGaps ?? const []).isNotEmpty;

  /// Abre a mesa da cédula e, na volta, confere de novo o que falta.
  Future<void> _openCpr() async {
    await openCprDesk(context, widget.barter, onChanged: widget.onChanged);
    await _loadCprGaps();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _busy => _saving || _forwarding;
  String get _text => _note.text.trim();
  bool get _enough => _text.length >= minOpinionLength;
  bool get _dirty => _text != _saved.trim();

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = await AppData.saveBarterNote(widget.barter.id, _note.text);
      if (!mounted) return;
      setState(() {
        _saved = updated.consultantNote ?? '';
        _saving = false;
      });
      widget.onChanged(updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rascunho salvo. A permuta continua com você.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnack(context, e);
    }
  }

  /// Abre o CONSTRUTOR desta permuta para remontar os insumos dela.
  ///
  /// A mesma tela da permuta nova, com produtor e unidade congelados: remontar é
  /// escolher insumos contra as mesmas regras de mínimo, e uma segunda tela para
  /// isso seria uma segunda cópia da lista, dos filtros e da conta em sacas. Ver
  /// `NewBarterScreen.draft`.
  Future<void> _editInputs() async {
    final me = AppData.currentUser;
    if (me == null) return;
    final updated = await Navigator.push<BarterModel>(
      context,
      MaterialPageRoute(
        builder: (_) => NewBarterScreen(consultant: me, draft: widget.barter),
      ),
    );
    if (updated == null || !mounted) return;
    widget.onChanged(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Insumos atualizados. A permuta continua rascunho até você encaminhar.'),
      ),
    );
  }

  Future<void> _forward() async {
    // O ENCAMINHAMENTO não tem volta: a permuta sai da mesa dele e vai para a
    // do gerente. Perguntar antes é o que se faz com um ato que não se desfaz.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encaminhar ao gerente'),
        content: Text(
          'A permuta ${widget.barter.id} vai para o gerente com o seu parecer e '
          'com a cédula (CPR) que você preencheu. Depois disso, o parecer não '
          'pode mais ser alterado.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Encaminhar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _forwarding = true);
    try {
      final updated = await AppData.forwardBarter(widget.barter.id, _note.text);
      if (!mounted) return;
      setState(() => _forwarding = false);
      widget.onChanged(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Permuta encaminhada a ${updated.managerLabel}.'),
          backgroundColor: AppColors.atManager,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _forwarding = false);
      // A CÉDULA FALTANDO não é um erro qualquer: é trabalho a fazer, e ele tem
      // uma tela. Mostrar só a mensagem deixaria a pessoa lendo uma lista de
      // campos sem saber onde preenchê-los — então a recusa vira um convite.
      //
      // CHEGAR AQUI é a exceção, e não o caminho: o cartão de pendências acima
      // desliga o botão antes disso. Quem cai aqui é quem tinha a tela aberta
      // enquanto a cédula mudou do outro lado — e aí a lista local está velha,
      // e o certo é refazê-la com o que o servidor acabou de dizer.
      if (e.message.contains('cédula')) {
        unawaited(_loadCprGaps());
        // A ANTERIOR SAI antes de esta entrar. Sem isso elas se ENFILEIRAM: cada
        // tentativa põe mais oito segundos de faixa vermelha na fila, e três
        // cliques cobrem o rodapé da tela por meio minuto — que foi como este
        // aviso passou a parecer permanente.
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.denied,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Preencher',
              textColor: Colors.white,
              onPressed: _openCpr,
            ),
          ));
        return;
      }
      showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.draftBg,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.draft.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 18, color: AppColors.draft),
              const SizedBox(width: 6),
              Text(
                'Seu parecer',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // O PORQUÊ, e não a instrução: o consultor sabe escrever um parágrafo.
          // O que ele não sabe é quem vai ler — e é isso que muda o que ele
          // escreve.
          Text(
            'O gerente e o comitê leem isto antes de opinar e decidir. '
            'Enquanto você não encaminhar, a permuta é um rascunho e ninguém mais a vê.',
            style: TextStyle(fontSize: 12, color: AppColors.textMedium),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            enabled: !_busy,
            minLines: 4,
            maxLines: 8,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Parecer do consultor',
              hintText: 'Safras anteriores, pontualidade, o que está plantado…',
              alignLabelWithHint: true,
              filled: true,
            ),
          ),
          // A CÉDULA, antes dos botões e não depois da recusa.
          //
          // Ela entrou na esteira como pré-requisito do encaminhamento, e um
          // pré-requisito que só se descobre clicando é uma armadilha: a pessoa
          // escreve o parecer, clica em *Encaminhar* e leva de volta uma lista
          // de catorze campos. Aqui ela está visível desde que a tela abre, com
          // o botão que a resolve dentro do próprio aviso.
          if (_cprBlocks) ...[
            const SizedBox(height: 4),
            _CprGapsCard(gaps: _cprGaps!, onFill: _busy ? null : _openCpr),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || !_dirty ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Salvar'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy || !_enough || _cprBlocks ? null : _forward,
                  icon: _forwarding
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onPrimary,
                          ),
                        )
                      : const Icon(Icons.send_outlined),
                  label: const Text('Encaminhar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.atManager,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          if (!_enough)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Escreva o parecer para poder encaminhar.',
                style: TextStyle(fontSize: 11, color: AppColors.textMedium),
              ),
            ),
          // OS INSUMOS, que só o rascunho deixa mexer.
          //
          // É a razão de o pedido de alteração existir: a permuta volta a ser
          // rascunho justamente para os itens poderem mudar. O botão fica aqui,
          // abaixo do parecer, porque a ordem é essa — remonta-se a permuta e
          // depois se explica ao gerente o que mudou.
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _editInputs,
            icon: const Icon(Icons.tune),
            label: const Text('Alterar insumos'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// O AVISO DE CÉDULA INCOMPLETA, dentro do rascunho do consultor.
///
/// Ele é ÂMBAR e não vermelho porque não é uma recusa: é trabalho que falta, com
/// o botão que o resolve ao lado. O vermelho é do que deu errado — e não deu
/// nada errado em preencher uma cédula pela metade, que é como ela passa a maior
/// parte do tempo (a matrícula chega por e-mail, o SCR sai depois da consulta).
///
/// A LISTA SAI RESUMIDA, na mesma forma da recusa do servidor: as primeiras e a
/// contagem do resto. Catorze frases empilhadas num cartão de aviso viram um
/// muro que ninguém lê, e o lugar de ver a lista inteira é o formulário, onde
/// cada uma fica ao lado do campo que a resolve.
class _CprGapsCard extends StatelessWidget {
  final List<String> gaps;

  /// `null` enquanto outro ato do cartão está no ar — abrir a cédula no meio de
  /// um encaminhamento deixaria a resposta dele chegar numa tela que saiu.
  final VoidCallback? onFill;

  const _CprGapsCard({required this.gaps, required this.onFill});

  /// Quantas pendências cabem numa frase antes de ela virar um parágrafo. É o
  /// mesmo número da recusa do servidor, de propósito: as duas frases falam da
  /// mesma cédula, e quem vê as duas não deveria ver duas listas diferentes.
  static const int _shown = 4;

  String get _summary {
    final first = gaps.take(_shown).join(', ');
    final rest = gaps.length - _shown;
    return rest > 0 ? '$first e mais $rest campo(s)' : first;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.pendingBg,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.pending.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description_outlined, size: 18, color: AppColors.pending),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Cédula (CPR) incompleta',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // O QUE FALTA e POR QUE ISSO IMPORTA, nesta ordem. Sem a segunda
          // frase, o aviso parece uma sugestão — e o botão desligado logo
          // abaixo, um defeito.
          Text(
            'Falta $_summary.',
            style: TextStyle(fontSize: 12, color: AppColors.textDark),
          ),
          const SizedBox(height: 2),
          Text(
            'O gerente só recebe a permuta com a cédula preenchida.',
            style: TextStyle(fontSize: 12, color: AppColors.textMedium),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onFill,
              icon: const Icon(Icons.edit_document, size: 18),
              label: const Text('Preencher a cédula'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textDark,
                side: BorderSide(color: AppColors.pending),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
                Text(
                  'Com o gerente',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.atManager,
                  ),
                ),
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
        child: Center(
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
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
                Text(
                  'Andamento',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
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
                _HistoryStep(event: barter.events[i], last: i == barter.events.length - 1),
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
                    Text(step.note!, style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
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
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
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
              if (!last) Expanded(child: Container(width: 2, color: AppColors.divider)),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${event.actorName}'
                    '${event.actorRoleLabel.isEmpty ? '' : ' • ${event.actorRoleLabel}'}'
                    ' • ${formatDateTime(event.at)}',
                    style: TextStyle(fontSize: 11, color: AppColors.textLight),
                  ),
                  if (event.note != null && event.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(event.note!, style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
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
                Text(
                  'Funrural + Senar (${barter.taxRateLabel})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
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
          Text(
            value,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textDark),
          ),
        ],
      ),
    );
  }
}

/// A ÁREA DE PENHOR que esta permuta exige — e de onde o número saiu.
///
/// Vai para TODO MUNDO, inclusive o consultor, pelo mesmo motivo do imposto: é
/// hectare e percentual, não é R\$.
///
/// A BASE DO CÁLCULO sai por extenso ("produção estimada de 60 sc/ha + 20% de
/// margem de segurança") porque a primeira reação a uma exigência de área é
/// contestá-la — e as duas taxas moram no lançamento do Barter, que é tela do
/// admin. Sem a frase, a única resposta possível a "por que 34 ha?" seria pedir
/// a alguém que abrisse outra tela.
class _PledgeCard extends StatelessWidget {
  final BarterModel barter;

  const _PledgeCard({required this.barter});

  @override
  Widget build(BuildContext context) {
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
          Icon(Icons.map_outlined, size: 18, color: AppColors.textLight),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lavoura em penhor',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${barter.pledgeBasisLabel}. As matrículas informadas na cédula '
                  'precisam somar esta área para a permuta ser encaminhada.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            barter.pledgeAreaLabel,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textDark),
          ),
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
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 8),
            // Expanded, e não Column solta: numa `Row` sem ele o texto recebe
            // largura infinita e `ellipsis` não tem onde cortar — é o mesmo
            // defeito dos 33 pixels do rodapé do construtor, e aqui ele
            // aparecia no subtítulo da seção do grão num telefone estreito.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: AppColors.textLight),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              // OS ITENS LADO A LADO, e não um por linha.
              //
              // Uma permuta real tem dezenas de insumos, e uma linha inteira por
              // item transformava a conferência numa rolagem longa em que o
              // total — que é o que fecha a leitura — ficava sempre fora da
              // tela. Cada item ocupa pouco: nome, código, quantidade e o
              // equivalente. Dois cabem lado a lado até num celular, e a
              // conferência passa a caber de uma vez.
              //
              // A largura mínima é o que decide quantas colunas, e não o nome do
              // aparelho: no monitor a mesma regra dá três ou quatro, sem
              // nenhuma faixa escrita à mão.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const minTileWidth = 168.0;
                    const gap = 10.0;
                    final columns = ((constraints.maxWidth + gap) / (minTileWidth + gap))
                        .floor()
                        .clamp(1, 4);
                    final tileWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final item in items)
                          SizedBox(
                            width: tileWidth,
                            child: _ItemTile(
                              item: item,
                              accent: accent,
                              showValue: showValue,
                              referenceValue: referenceValue,
                              sacks: sacksOf(item),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Pelo mesmo motivo do cabeçalho acima: "Total a entregar" e
                    // um total em sacas com o nome do grão não cabem juntos numa
                    // linha de telefone sem alguém poder encolher.
                    Expanded(
                      child: Text(
                        totalLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          totalSacks != null
                              ? '${formatSacks(totalSacks!)} ${referenceGrainName.toLowerCase()}'
                              : (showValue ? formatCurrency(total) : ''),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                        if (referenceValue > 0 && showValue)
                          Text(
                            '≈ ${formatCurrency(total)}',
                            style: TextStyle(fontSize: 10, color: AppColors.textLight),
                          ),
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

/// UM ITEM da permuta, do tamanho de meia tela — a peça que se repete lado a
/// lado na seção.
///
/// O CÓDIGO vem primeiro, acima do nome, e é isso que a conferência usa: é por
/// ele que o insumo é achado no depósito e batido contra a nota, e dois
/// produtos de nomes parecidos ("Glifosato 480 SL" e "Glifosato 480 WG") só se
/// distinguem por ele. Some quando não há nenhum a mostrar — nem congelado no
/// item nem no catálogo (ver [AppData.skuOf]) —, em vez de imprimir um traço no
/// lugar mais visível do cartão.
class _ItemTile extends StatelessWidget {
  final BarterItem item;
  final Color accent;
  final bool showValue;
  final double referenceValue;

  /// Quantas sacas este item representa, ou null quando não dá para dizer —
  /// ver `sacksOf` em [_ItemsSection].
  final double? sacks;

  const _ItemTile({
    required this.item,
    required this.accent,
    required this.showValue,
    required this.referenceValue,
    required this.sacks,
  });

  @override
  Widget build(BuildContext context) {
    final sku = AppData.skuOf(item);
    final value = sacks != null
        ? formatSacks(sacks!)
        : (showValue ? formatCurrency(item.total) : '');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sku != null)
            Text(
              sku,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: accent,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            item.productName,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.15),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  showValue
                      ? '${formatQty(item.quantity)} ${item.unit} × ${formatCurrency(item.unitValue)}'
                      : '${formatQty(item.quantity)} ${item.unit}',
                  style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (value.isNotEmpty) ...[
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accent),
                    ),
                    if (referenceValue > 0 && showValue)
                      Text(
                        '≈ ${formatCurrency(item.total)}',
                        style: TextStyle(fontSize: 10, color: AppColors.textLight),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
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
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
