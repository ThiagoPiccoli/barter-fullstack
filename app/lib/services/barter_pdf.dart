import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/models.dart';
import '../widgets/common_widgets.dart' show formatCurrency, formatQty, formatSacks;

/// Comprovante de permuta em PDF, para controle e assinatura das partes.
///
/// [showValues] segue a mesma regra de privacidade das telas: o ADMIN vê os
/// valores em R$ (custo dos insumos, valor de referência do grão); o VENDEDOR
/// vê apenas quantidades e sacas — para ele a permuta é "insumos retirados
/// viram sacas do grão", sem dinheiro envolvido.
class BarterPdf {
  BarterPdf._();

  static final PdfColor _green = PdfColor.fromInt(0xFF1B5E20);
  static final PdfColor _greenSurface = PdfColor.fromInt(0xFFE8F5E9);
  static final PdfColor _grain = PdfColor.fromInt(0xFFE65100);
  static final PdfColor _input = PdfColor.fromInt(0xFF00695C);
  static final PdfColor _textMedium = PdfColor.fromInt(0xFF616161);
  static final PdfColor _line = PdfColor.fromInt(0xFFBDBDBD);

  /// Gera o PDF e abre a folha de compartilhamento nativa (salvar, enviar por
  /// WhatsApp/e-mail, imprimir...). Nome do arquivo: permuta-PRM-2026-001.pdf.
  static Future<void> share(
    BarterModel barter, {
    ProducerModel? producer,
    required bool showValues,
  }) async {
    final bytes = await build(barter, producer: producer, showValues: showValues);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'permuta-${barter.id.toLowerCase()}.pdf',
    );
  }

  /// Monta o documento e devolve os bytes do PDF.
  static Future<Uint8List> build(
    BarterModel barter, {
    ProducerModel? producer,
    required bool showValues,
  }) async {
    final doc = pw.Document(
      title: 'Comprovante de Permuta ${barter.id}',
      author: 'Barter - Permuta de Graos',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
        footer: (ctx) => _footer(ctx),
        build: (ctx) => [
          _header(barter),
          pw.SizedBox(height: 18),
          _parties(barter, producer),
          pw.SizedBox(height: 18),
          _sectionTitle('INSUMOS RETIRADOS', _input),
          pw.SizedBox(height: 6),
          _inputsTable(barter, showValues),
          pw.SizedBox(height: 16),
          _sectionTitle('PAGAMENTO EM GRÃOS', _grain),
          pw.SizedBox(height: 6),
          _grainsTable(barter, showValues),
          pw.SizedBox(height: 18),
          _totalBox(barter, showValues),
          if (barter.adminNote != null && barter.adminNote!.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _adminNote(barter),
          ],
          pw.SizedBox(height: 44),
          _signatures(barter, producer),
        ],
      ),
    );

    return doc.save();
  }

  /// As fontes padrão do PDF (Helvetica) só cobrem Latin-1: troca os poucos
  /// caracteres fora dela usados no app (– • etc.) por equivalentes seguros.
  static String _s(String text) => text
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('•', '-')
      .replaceAll('≈', '~')
      .replaceAll('→', '->');

  static pw.Widget _header(BarterModel barter) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _green,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('BARTER',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 2,
                  )),
              pw.Text('Permuta de Grãos por Insumos',
                  style: const pw.TextStyle(color: PdfColor.fromInt(0xCCFFFFFF), fontSize: 9)),
            ],
          ),
          pw.Spacer(),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('COMPROVANTE DE PERMUTA',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  )),
              pw.SizedBox(height: 2),
              pw.Text(barter.id,
                  style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
              pw.SizedBox(height: 4),
              _statusChip(barter),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _statusChip(BarterModel barter) {
    final PdfColor color;
    switch (barter.status) {
      case BarterStatus.approved:
        color = PdfColor.fromInt(0xFFA5D6A7);
        break;
      case BarterStatus.denied:
        color = PdfColor.fromInt(0xFFEF9A9A);
        break;
      case BarterStatus.pending:
        color = PdfColor.fromInt(0xFFFFE082);
        break;
    }
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Text(barter.statusLabel,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _green)),
    );
  }

  /// Bloco com as duas partes da permuta (vendedor e produtor) e as datas.
  static pw.Widget _parties(BarterModel barter, ProducerModel? producer) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line, width: 0.5),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _partyLabel('VENDEDOR'),
                    _kv('Nome', barter.sellerName),
                    _kv('Filial', barter.sellerBranch),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _partyLabel('PRODUTOR'),
                    _kv('Nome', barter.producerName),
                    if (producer != null) ...[
                      _kv('Documento', producer.document),
                      _kv('Propriedade', producer.location),
                      _kv('Área cultivável', producer.areaLabel),
                    ],
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(color: _line, height: 4, thickness: 0.5),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              _kvInline('Criada em', _date(barter.createdAt)),
              if (barter.updatedAt != null) ...[
                pw.SizedBox(width: 18),
                _kvInline('Atualizada em', _date(barter.updatedAt!)),
              ],
              if (barter.reviewedBy != null) ...[
                pw.SizedBox(width: 18),
                _kvInline('Revisada por', barter.reviewedBy!),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _partyLabel(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _textMedium, letterSpacing: 1)),
      );

  static pw.Widget _kv(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(text: '$label: ', style: pw.TextStyle(fontSize: 9, color: _textMedium)),
              pw.TextSpan(
                  text: _s(value),
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
      );

  static pw.Widget _kvInline(String label, String value) => pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(text: '$label: ', style: pw.TextStyle(fontSize: 8, color: _textMedium)),
            pw.TextSpan(text: _s(value), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  static pw.Widget _sectionTitle(String text, PdfColor color) => pw.Text(text,
      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: color, letterSpacing: 1));

  /// Tabela dos insumos retirados. Sempre mostra quantidade e o equivalente em
  /// sacas do grão de pagamento; as colunas de R$ só entram para o admin.
  static pw.Widget _inputsTable(BarterModel barter, bool showValues) {
    final hasRef = barter.referenceValue > 0;
    final grain = barter.referenceGrainName.toLowerCase();
    final headers = [
      'Insumo',
      'Qtd.',
      'Unidade',
      if (hasRef) 'Equiv. ($grain)',
      if (showValues) 'Valor unit.',
      if (showValues) 'Subtotal',
    ];
    final rows = barter.inputs
        .map((i) => [
              _s(i.productName),
              formatQty(i.quantity),
              _s(i.unit),
              if (hasRef) formatSacks(i.total / barter.referenceValue),
              if (showValues) formatCurrency(i.unitValue),
              if (showValues) formatCurrency(i.total),
            ])
        .toList();
    // Linha de total da seção.
    rows.add([
      'TOTAL',
      formatQty(barter.totalInputQty),
      '',
      if (hasRef) formatSacks(barter.inputCostInSacks),
      if (showValues) '',
      if (showValues) formatCurrency(barter.inputCost),
    ]);
    return _table(headers, rows, accent: _input);
  }

  /// Tabela do grão de pagamento (normalmente uma linha só).
  static pw.Widget _grainsTable(BarterModel barter, bool showValues) {
    final headers = [
      'Grão',
      'Sacas',
      'Unidade',
      if (showValues) 'Ref. por saca',
      if (showValues) 'Total',
    ];
    final rows = barter.grains
        .map((g) => [
              _s(g.productName),
              formatSacks(g.quantity),
              _s(g.unit),
              if (showValues) formatCurrency(g.unitValue),
              if (showValues) formatCurrency(g.total),
            ])
        .toList();
    return _table(headers, rows, accent: _grain);
  }

  static pw.Widget _table(List<String> headers, List<List<String>> rows, {required PdfColor accent}) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: pw.BoxDecoration(color: accent),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      border: pw.TableBorder.all(color: _line, width: 0.5),
      cellAlignments: {
        for (var i = 1; i < headers.length; i++) i: pw.Alignment.centerRight,
      },
      oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F5F5)),
    );
  }

  /// Destaque final: o compromisso da permuta — quantas sacas o produtor
  /// entrega na colheita para pagar os insumos retirados.
  static pw.Widget _totalBox(BarterModel barter, bool showValues) {
    final hasRef = barter.referenceValue > 0;
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _greenSurface,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _green, width: 0.8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: pw.Text('TOTAL A ENTREGAR NA COLHEITA',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                hasRef
                    ? '${formatSacks(barter.sacksToDeliver)} de ${barter.referenceGrainName.toLowerCase()}'
                    : '-',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _green),
              ),
              pw.Text(
                showValues
                    ? 'equivale a ${formatCurrency(barter.inputCost)} em insumos'
                    : 'para cobrir os ${barter.inputs.length} insumo(s) retirado(s)',
                style: pw.TextStyle(fontSize: 8, color: _textMedium),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _adminNote(BarterModel barter) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line, width: 0.5),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('OBSERVAÇÃO DO ADMINISTRADOR',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _textMedium)),
          pw.SizedBox(height: 4),
          pw.Text(_s(barter.adminNote!), style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  /// Linhas de assinatura das duas partes, para o comprovante impresso valer
  /// como registro de controle.
  static pw.Widget _signatures(BarterModel barter, ProducerModel? producer) {
    pw.Widget line(String role, String name) => pw.Expanded(
          child: pw.Column(
            children: [
              pw.Container(height: 0.8, color: PdfColors.black),
              pw.SizedBox(height: 4),
              pw.Text(_s(name), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text(role, style: pw.TextStyle(fontSize: 8, color: _textMedium)),
            ],
          ),
        );
    return pw.Row(
      children: [
        line('Produtor', barter.producerName),
        pw.SizedBox(width: 40),
        line('Vendedor', barter.sellerName),
      ],
    );
  }

  static pw.Widget _footer(pw.Context ctx) {
    return pw.Column(
      children: [
        pw.Divider(color: _line, thickness: 0.5),
        pw.Row(
          children: [
            pw.Text('Documento gerado em ${_date(DateTime.now())} - Barter App',
                style: pw.TextStyle(fontSize: 7, color: _textMedium)),
            pw.Spacer(),
            pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 7, color: _textMedium)),
          ],
        ),
      ],
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
