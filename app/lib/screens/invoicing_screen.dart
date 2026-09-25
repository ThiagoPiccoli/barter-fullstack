import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/common_widgets.dart';

/// O FATURAMENTO — a mesa do faturista.
///
/// Ela existe porque o posto dele mudou de conteúdo. Antes, faturar era abrir a
/// cédula, preencher quarenta campos e carimbar: a tela do faturamento ERA o
/// formulário da CPR. Nada daquilo era trabalho dele — a matrícula do imóvel, o
/// nome do cônjuge, o SCR do produtor são o que se traz da visita à fazenda, e
/// ele os obtinha por telefone com o consultor e digitava.
///
/// O que sobrou é o ofício de verdade, e ele cabe numa tela: as NOTAS FISCAIS
/// que saíram da permuta, com os arquivos, e o ato de faturar.
///
/// AS NOTAS SÃO VÁRIAS, e é a primeira coisa que esta tela afirma: a permuta sai
/// em mais de um carregamento, cada retirada gera a sua nota, e a cancelada é
/// reemitida. Enquanto o número foi um campo de texto dentro da cédula, a
/// segunda nota não tinha onde entrar — e a cédula citava uma como origem de
/// uma dívida formada por três.
///
/// NÃO SE FATURA SEM NOTA: o servidor recusa (422), e a tela diz isso antes, no
/// botão desligado. É ela que a cédula cita como origem da dívida (cláusula
/// VII), e uma permuta "faturada" sem nota nenhuma é um faturamento que não
/// aconteceu no mundo — ou que aconteceu e não deixou prova. As duas coisas
/// param a emissão do título dias depois, longe de quem pode resolver.
void openInvoicing(
  BuildContext context,
  BarterModel barter, {
  required ValueChanged<BarterModel> onInvoiced,
}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => InvoicingScreen(barter: barter, onInvoiced: onInvoiced),
  ));
}

class InvoicingScreen extends StatefulWidget {
  final BarterModel barter;

  /// Avisa quem abriu a tela que a permuta mudou — o faturamento a move, e as
  /// notas mudam o que a lista mostra sobre ela.
  final ValueChanged<BarterModel> onInvoiced;

  const InvoicingScreen({super.key, required this.barter, required this.onInvoiced});

  @override
  State<InvoicingScreen> createState() => _InvoicingScreenState();
}

class _InvoicingScreenState extends State<InvoicingScreen> {
  late BarterModel _barter = widget.barter;
  bool _busy = false;

  /// A permuta já pode ser faturada? Só com nota anexada — a mesma regra do
  /// servidor, repetida aqui pelo motivo de sempre: a tela não oferece um botão
  /// que levaria 422. Quem recusa de verdade continua sendo a API.
  bool get _canInvoice => _barter.awaitsInvoice && _barter.invoices.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_barter.awaitsInvoice ? 'Faturar ${_barter.id}' : 'Notas de ${_barter.id}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: StatusBadge(status: _barter.status)),
          ),
        ],
      ),
      body: BoundedContent(
        maxWidth: 900,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _Header(barter: _barter),
            const SizedBox(height: 18),
            Row(children: [
              Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'NOTAS FISCAIS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppColors.primary,
                ),
              ),
            ]),
            const SizedBox(height: 10),
            if (_barter.invoices.isEmpty)
              _EmptyInvoices(onAttach: _busy ? null : _attach)
            else ...[
              for (final nota in _barter.invoices)
                _InvoiceTile(
                  invoice: nota,
                  onDownload: nota.file == null ? null : () => _download(nota),
                  onRemove: _busy ? null : () => _remove(nota),
                ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _busy ? null : _attach,
                icon: const Icon(Icons.attach_file, size: 18),
                label: const Text('Anexar outra nota'),
              ),
            ],
            const SizedBox(height: 22),
            // A CÉDULA não abre daqui, e a ausência é a mudança: ela deixou de
            // ser trabalho deste posto. O que a tela diz é onde ela está.
            _CprNote(barter: _barter),
          ],
        ),
      ),
      bottomNavigationBar: _barter.awaitsInvoice ? _bottomBar() : null,
    );
  }

  Widget _bottomBar() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: Tooltip(
              message: _canInvoice
                  ? 'Fatura a permuta aprovada'
                  : 'Anexe ao menos uma nota fiscal antes de faturar',
              child: ElevatedButton.icon(
                onPressed: _canInvoice && !_busy ? _invoice : null,
                icon: _busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.onPrimary),
                      )
                    : const Icon(Icons.receipt_long_outlined, size: 21),
                label: Text(
                  _busy ? 'Faturando…' : 'Faturar permuta',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.invoiced,
                  foregroundColor: AppColors.onPrimary,
                ),
              ),
            ),
          ),
        ),
      );

  /// ANEXA UMA NOTA — o arquivo e os dados dele, num diálogo só.
  ///
  /// O ARQUIVO é escolhido PRIMEIRO, e de propósito: ele é o ato. Pedir o número
  /// antes deixaria a pessoa preencher um formulário para descobrir no fim que o
  /// PDF está em outra pasta — e o número que ela digitou some junto.
  Future<void> _attach() async {
    final arquivo = await FilePicker.pickFile(
      dialogTitle: 'Nota fiscal',
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'xml', 'png', 'jpg', 'jpeg'],
    );
    if (arquivo == null) return;
    // Os BYTES são lidos aqui: no Android/iOS o caminho do arquivo escolhido é
    // temporário e pode sumir antes do envio.
    final bytes = await arquivo.readAsBytes();
    if (!mounted) return;

    final dados = await _askInvoiceData(arquivo.name);
    if (dados == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final atualizada = await AppData.attachBarterInvoice(
        _barter.id,
        number: dados.number,
        series: dados.series,
        duplicateNumber: dados.duplicateNumber,
        issuedAt: dados.issuedAt,
        value: dados.value,
        filename: arquivo.name,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() {
        _barter = atualizada;
        _busy = false;
      });
      widget.onInvoiced(atualizada);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(context, error);
    }
  }

  /// O DIÁLOGO da nota: o que acompanha o arquivo.
  ///
  /// Só o NÚMERO é obrigatório. Série, duplicata, data e valor são o que a nota
  /// tem, e nem toda operação preenche os quatro — há praça que não usa série, e
  /// venda que não gera duplicata. Exigi-los produziria campos inventados.
  Future<_InvoiceData?> _askInvoiceData(String filename) async {
    final numberCtrl = TextEditingController();
    final seriesCtrl = TextEditingController();
    final dupCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    DateTime? emitida = DateTime.now();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Anexar nota fiscal'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.attach_file, size: 16, color: AppColors.textMedium),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        filename,
                        style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: numberCtrl,
                        autofocus: true,
                        decoration: const InputDecoration(
                            labelText: 'Nº da nota', isDense: true),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? 'Informe o número' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: seriesCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Série', isDense: true),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: dupCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nº da duplicata (se houver)',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: valueCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Valor (R\$)', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final escolhida = await showDatePicker(
                            context: ctx,
                            initialDate: emitida ?? DateTime.now(),
                            firstDate: DateTime(DateTime.now().year - 3),
                            lastDate: DateTime.now(),
                          );
                          if (escolhida != null) setDialogState(() => emitida = escolhida);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                              labelText: 'Emissão', isDense: true),
                          child: Text(
                            emitida == null ? 'sem data' : formatDate(emitida!),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.invoiced),
              child: const Text('Anexar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return null;

    return _InvoiceData(
      number: numberCtrl.text,
      series: seriesCtrl.text,
      duplicateNumber: dupCtrl.text,
      issuedAt: emitida,
      value: double.tryParse(valueCtrl.text.trim().replaceAll('.', '').replaceAll(',', '.')),
    );
  }

  /// REMOVE uma nota — a cancelada, ou a que subiu trocada.
  ///
  /// A confirmação diz o que a remoção CUSTA, e não só o que ela faz: tirar a
  /// nota de uma permuta faturada apaga a prova do faturamento, e a cédula que a
  /// cita passa a apontar para o vazio.
  Future<void> _remove(BarterInvoiceModel nota) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover a nota'),
        content: Text(
          '${nota.label} sai da permuta, e o arquivo dela vai junto. '
          '${_barter.invoices.length == 1 ? 'Era a única: a cédula volta a ficar sem a origem da dívida.' : ''}',
          style: TextStyle(fontSize: 13, color: AppColors.textMedium),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.denied),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final atualizada = await AppData.removeBarterInvoice(_barter.id, nota.id);
      if (!mounted) return;
      setState(() {
        _barter = atualizada;
        _busy = false;
      });
      widget.onInvoiced(atualizada);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(context, error);
    }
  }

  Future<void> _download(BarterInvoiceModel nota) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final arquivo = await AppData.downloadBarterInvoiceFile(_barter.id, nota.id);
      final ponto = arquivo.filename.lastIndexOf('.');
      await FileSaver.instance.saveFile(
        name: ponto > 0 ? arquivo.filename.substring(0, ponto) : arquivo.filename,
        bytes: Uint8List.fromList(arquivo.bytes),
        ext: ponto > 0 ? arquivo.filename.substring(ponto + 1) : 'pdf',
        mimeType: MimeType.other,
        customMimeType: arquivo.contentType,
      );
      messenger.showSnackBar(SnackBar(
        content: Text('${arquivo.filename} salvo.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (error) {
      if (!mounted) return;
      showErrorSnack(context, error);
    }
  }

  /// FATURAR — o ato do posto.
  ///
  /// A confirmação continua existindo porque o ato é IRREVERSÍVEL: não existe
  /// desfaturar, e corrigir faturamento é ato do sistema de nota fiscal, não
  /// deste. O diálogo é onde entra a observação, opcional — o faturamento normal
  /// não tem o que explicar.
  Future<void> _invoice() async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Faturar permuta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_barter.id} • ${_barter.producerName}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              '${_barter.invoices.length} nota(s) anexada(s). Depois de faturada, a '
              'permuta segue para o EMISSOR, que confere a cédula e emite o título.',
              style: TextStyle(fontSize: 12, color: AppColors.textMedium, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLength: 500,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observação (opcional)',
                hintText: 'Entrega parcial, combinação com o produtor…',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.invoiced),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final faturada = await AppData.invoiceBarter(_barter.id, noteCtrl.text);
      if (!mounted) return;
      setState(() {
        _barter = faturada;
        _busy = false;
      });
      widget.onInvoiced(faturada);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Permuta faturada. Ela seguiu para a emissão da CPR.'),
        backgroundColor: AppColors.invoiced,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(context, error);
    }
  }
}

/// Os dados que acompanham o arquivo da nota.
class _InvoiceData {
  final String number;
  final String series;
  final String duplicateNumber;
  final DateTime? issuedAt;
  final double? value;

  const _InvoiceData({
    required this.number,
    required this.series,
    required this.duplicateNumber,
    required this.issuedAt,
    required this.value,
  });
}

/// O QUE CHEGOU DAS ETAPAS ANTERIORES — a decisão do comitê, que é o que
/// autoriza este faturamento.
class _Header extends StatelessWidget {
  final BarterModel barter;

  const _Header({required this.barter});

  @override
  Widget build(BuildContext context) {
    final esperando = barter.awaitsInvoice;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: esperando ? AppColors.approvedBg : AppColors.invoicedBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (esperando ? AppColors.approved : AppColors.invoiced).withValues(alpha: 0.35),
        ),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(
          esperando ? Icons.check_circle_outline : Icons.receipt_long_outlined,
          size: 19,
          color: esperando ? AppColors.approved : AppColors.invoiced,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              esperando ? 'Aprovada, aguardando faturamento' : 'Permuta faturada',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark),
            ),
            const SizedBox(height: 3),
            Text(
              esperando
                  ? '${barter.producerName}'
                      '${barter.hasDecision ? ' • aprovada por ${barter.reviewedBy}' : ''}'
                      '${barter.hasConditions ? ' COM RESSALVA: ${barter.reviewNote}' : ''}'
                  : 'Faturada por ${barter.invoicedBy ?? ''}. As notas continuam '
                      'editáveis: nota cancelada é reemitida, e a cédula cita o que '
                      'estiver aqui.',
              style: TextStyle(fontSize: 12, color: AppColors.textMedium, height: 1.35),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _EmptyInvoices extends StatelessWidget {
  final VoidCallback? onAttach;

  const _EmptyInvoices({required this.onAttach});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.pendingBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.pending.withValues(alpha: 0.35)),
      ),
      child: Column(children: [
        Icon(Icons.upload_file_outlined, size: 30, color: AppColors.pending),
        const SizedBox(height: 8),
        Text(
          'Nenhuma nota anexada',
          style:
              TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark),
        ),
        const SizedBox(height: 4),
        Text(
          'A nota é o que a cédula cita como origem da dívida. Sem ao menos uma, '
          'a permuta não pode ser faturada.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textMedium, height: 1.35),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: onAttach,
          icon: const Icon(Icons.attach_file, size: 18),
          label: const Text('Anexar nota fiscal'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.invoiced),
        ),
      ]),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  final BarterInvoiceModel invoice;
  final VoidCallback? onDownload;
  final VoidCallback? onRemove;

  const _InvoiceTile({
    required this.invoice,
    required this.onDownload,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final semArquivo = invoice.file == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(children: [
          Icon(
            semArquivo ? Icons.warning_amber_rounded : Icons.picture_as_pdf_outlined,
            size: 19,
            color: semArquivo ? AppColors.pending : AppColors.invoiced,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                invoice.label,
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textDark),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (invoice.duplicateNumber.isNotEmpty) 'DUP ${invoice.duplicateNumber}',
                  if (invoice.issuedAt != null) formatDate(invoice.issuedAt!),
                  // SEM ARQUIVO é o caso das notas HERDADAS do campo de texto
                  // que ficava dentro da cédula. A tela as mostra como pendentes
                  // em vez de escondê-las: o número existe, e a prova não.
                  if (semArquivo) 'sem arquivo' else invoice.file!.sizeLabel,
                ].join(' • '),
                style: TextStyle(fontSize: 11.5, color: AppColors.textMedium),
              ),
            ]),
          ),
          if (onDownload != null)
            IconButton(
              tooltip: 'Baixar',
              onPressed: onDownload,
              icon: const Icon(Icons.download_outlined, size: 19),
            ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remover',
              onPressed: onRemove,
              icon: Icon(Icons.delete_outline, size: 19, color: AppColors.denied),
            ),
        ]),
      ),
    );
  }
}

/// ONDE ESTÁ A CÉDULA — a linha que explica ao faturista o que ele deixou de
/// fazer, e para quem foi.
///
/// Ela existe porque a mudança é grande o suficiente para confundir quem usava o
/// sistema antes: o botão "Cédula de Produto Rural" sumiu desta tela, e sem uma
/// explicação isso se lê como coisa quebrada em vez de trabalho que mudou de
/// dono.
class _CprNote extends StatelessWidget {
  final BarterModel barter;

  const _CprNote({required this.barter});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.description_outlined, size: 18, color: AppColors.textLight),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            barter.wasInvoiced
                ? 'A CÉDULA (CPR) está com o emissor: ele confere o que o consultor '
                    'preencheu, emite o título, colhe as assinaturas e o leva a registro. '
                    'O andamento aparece no status da permuta.'
                : 'A CÉDULA (CPR) é preenchida pelo CONSULTOR — a qualificação do '
                    'produtor, as matrículas das lavouras e o SCR vêm da visita à fazenda. '
                    'Depois do faturamento, o EMISSOR confere e emite.',
            style: TextStyle(fontSize: 12, color: AppColors.textMedium, height: 1.4),
          ),
        ),
      ]),
    );
  }
}
