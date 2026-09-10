import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/models.dart';
import 'cpr_text.dart';

/// A CÉDULA DE PRODUTO RURAL em **.docx** — o documento que sai para assinar.
///
/// É o formato principal, e não o PDF, porque a cédula ainda passa por gente: o
/// jurídico revisa, o cartório pede um ajuste de redação, a cláusula de um
/// negócio específico entra à mão. Um PDF obrigaria a redigitar o documento
/// inteiro fora do sistema para mudar uma linha — e é exatamente aí que a versão
/// que vai a registro deixa de ser a que o sistema conhece.
///
/// ─────────────────────────────────────────────────────────────────────────────
/// COMO ELE É MONTADO
///
/// Um `.docx` é um ZIP de XML (OOXML). Ele é escrito à mão aqui, com o
/// `archive` fechando o pacote, e não por um pacote de template, por dois
/// motivos: um template seria um segundo lugar onde o texto da cédula mora — e
/// o texto mora em [CprText], um só —, e a redação de um título de crédito não
/// deve depender de um binário que ninguém revisa em code review.
///
/// As quatro partes obrigatórias do pacote:
///
/// - `[Content_Types].xml` — o que é cada arquivo;
/// - `_rels/.rels` — aponta para o documento principal;
/// - `word/document.xml` — o texto;
/// - `word/_rels/document.xml.rels` — aponta para estilos e rodapé.
///
/// ─────────────────────────────────────────────────────────────────────────────
/// O TEXTO É O MESMO DO PDF
///
/// Os dois leem [CprText]. Este arquivo decide fonte, margem e recuo; o que o
/// documento DIZ está lá, testado em `cpr_text_test.dart`. Sem essa separação
/// haveria duas redações da mesma cédula, e elas divergiriam na primeira
/// correção feita com pressa.
class CprDocx {
  CprDocx._();

  /// Twips (1/1440 de polegada) — a unidade de tudo em OOXML.
  static const _margem = 1134; // 2 cm
  static const _recuoAlinea = 425; // 0,75 cm

  /// Gera o .docx e entrega ao usuário (download no navegador, arquivo no
  /// aparelho). O nome sai do número da cédula: `cpr-2026-014.docx`.
  static Uint8List build(CprDesk desk) {
    final corpo = StringBuffer();

    // O CABEÇALHO, centralizado e em negrito.
    corpo.write(_p(CprText.heading(desk), bold: true, center: true, after: 240));

    for (final paragrafo in CprText.paragraphs(desk)) {
      final recuo = paragrafo.indented ? _recuoAlinea : 0;
      if (paragrafo.title.isNotEmpty) {
        corpo.write(_p(paragrafo.title, bold: true, indent: recuo, after: 60));
      }
      if (paragrafo.body.isNotEmpty) {
        corpo.write(_p(paragrafo.body, justify: true, indent: recuo, after: 160));
      }
    }

    corpo.write(_p('', after: 240));
    corpo.write(_p(CprText.closing(desk), after: 360));

    for (final assinatura in CprText.signatures(desk)) {
      corpo.write(_p(assinatura.role, bold: true, after: 480));
      // A linha de assinatura é uma régua de sublinhados, e não uma borda de
      // parágrafo: ela sobrevive a qualquer editor que abra o arquivo, que é o
      // que importa num documento feito para circular.
      corpo.write(_p('_' * 56, after: 60));
      corpo.write(_p('Nome: ${assinatura.name}', after: 20));
      corpo.write(_p('Qualificação: ${assinatura.qualification}', after: 20));
      corpo.write(_p('Endereço: ${assinatura.address}', after: 20));
      corpo.write(_p(assinatura.document, after: 20));
      if (assinatura.coopId != null) corpo.write(_p(assinatura.coopId!, after: 20));
      corpo.write(_p('', after: 360));
    }

    return _zip({
      '[Content_Types].xml': _contentTypes,
      '_rels/.rels': _rels,
      'word/_rels/document.xml.rels': _documentRels,
      'word/styles.xml': _styles,
      'word/footer1.xml': _footer,
      'word/document.xml': _document(corpo.toString()),
    });
  }

  /// O nome do arquivo, a partir do número da cédula — ou do código da permuta
  /// enquanto ela ainda não tem número.
  static String filename(CprDesk desk) {
    final numero = desk.cpr?.number.trim() ?? '';
    final base = numero.isEmpty ? desk.known.barterCode : numero;
    return base.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\-]+'), '-');
  }

  /* ── As peças do OOXML ────────────────────────────────────────────────── */

  /// Um parágrafo. `after` é o espaço depois dele, em twips.
  static String _p(
    String texto, {
    bool bold = false,
    bool justify = false,
    bool center = false,
    int indent = 0,
    int after = 120,
  }) {
    final alinhamento = center ? 'center' : (justify ? 'both' : 'left');
    final recuo = indent > 0 ? '<w:ind w:left="$indent"/>' : '';
    final negrito = bold ? '<w:rPr><w:b/></w:rPr>' : '';
    // `xml:space="preserve"` é obrigatório: sem ele o Word come os espaços das
    // pontas, e frases montadas por concatenação perdem a separação.
    final run = texto.isEmpty
        ? ''
        : '<w:r>$negrito<w:t xml:space="preserve">${_escape(texto)}</w:t></w:r>';
    return '<w:p><w:pPr><w:jc w:val="$alinhamento"/>$recuo'
        '<w:spacing w:after="$after" w:line="276" w:lineRule="auto"/>'
        '</w:pPr>$run</w:p>';
  }

  /// Escapa o que o XML não aceita cru. Aspas incluídas: o texto entra em
  /// elementos, mas o mesmo escape serve a atributos e não custa nada.
  static String _escape(String texto) => texto
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static const _cabecalhoXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

  static String _document(String corpo) => '$_cabecalhoXml'
      '<w:document '
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<w:body>$corpo'
      // A4 em twips, com o rodapé de numeração amarrado à seção.
      '<w:sectPr>'
      '<w:footerReference w:type="default" r:id="rId2"/>'
      '<w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="$_margem" w:right="$_margem" w:bottom="$_margem" '
      'w:left="$_margem" w:header="720" w:footer="720" w:gutter="0"/>'
      '</w:sectPr>'
      '</w:body></w:document>';

  /// "Página X de Y" — a numeração que o modelo traz, e que uma via física
  /// precisa para se provar completa. `PAGE` e `NUMPAGES` são campos do Word:
  /// eles se recalculam sozinhos quando alguém edita o texto, que é o ponto de
  /// entregar um .docx em vez de um PDF.
  static const _footer = '$_cabecalhoXml'
      '<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
      '<w:r><w:rPr><w:sz w:val="18"/></w:rPr><w:t xml:space="preserve">Página </w:t></w:r>'
      '<w:fldSimple w:instr=" PAGE ">'
      '<w:r><w:rPr><w:sz w:val="18"/></w:rPr><w:t>1</w:t></w:r></w:fldSimple>'
      '<w:r><w:rPr><w:sz w:val="18"/></w:rPr><w:t xml:space="preserve"> de </w:t></w:r>'
      '<w:fldSimple w:instr=" NUMPAGES ">'
      '<w:r><w:rPr><w:sz w:val="18"/></w:rPr><w:t>1</w:t></w:r></w:fldSimple>'
      '</w:p></w:ftr>';

  /// Times New Roman 11pt (`w:sz` é meio-ponto). É a fonte convencional de
  /// instrumento no Brasil — o documento vai a cartório, e parecer um contrato
  /// é parte de ser lido como um.
  static const _styles = '$_cabecalhoXml'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:docDefaults><w:rPrDefault><w:rPr>'
      '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" '
      'w:eastAsia="Times New Roman" w:cs="Times New Roman"/>'
      '<w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="pt-BR"/>'
      '</w:rPr></w:rPrDefault></w:docDefaults>'
      '</w:styles>';

  static const _contentTypes = '$_cabecalhoXml'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" '
      'ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-'
      'officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-'
      'officedocument.wordprocessingml.styles+xml"/>'
      '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-'
      'officedocument.wordprocessingml.footer+xml"/>'
      '</Types>';

  static const _rels = '$_cabecalhoXml'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
      'relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';

  static const _documentRels = '$_cabecalhoXml'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
      'relationships/styles" Target="styles.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
      'relationships/footer" Target="footer1.xml"/>'
      '</Relationships>';

  /// Fecha o pacote. UTF-8 explícito: o documento é em português, e um "ç"
  /// gravado em latin-1 abre como caractere trocado no Word de outra máquina.
  static Uint8List _zip(Map<String, String> partes) {
    final archive = Archive();
    partes.forEach((caminho, conteudo) {
      final bytes = utf8.encode(conteudo);
      archive.addFile(ArchiveFile(caminho, bytes.length, bytes));
    });
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}
