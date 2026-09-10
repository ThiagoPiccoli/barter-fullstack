import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/services/cpr_docx.dart';

/// O PACOTE .docx — que ele é um OOXML válido, e que o texto chega inteiro
/// dentro dele.
///
/// O que estes testes protegem é o modo de falha do formato: um `.docx` com uma
/// parte faltando ou um `&` não escapado não dá erro na geração — ele gera, e o
/// Word recusa abrir na mão de quem ia assinar.
void main() {
  final desk = CprDesk(
    known: const CprKnown(
      barterCode: 'PRM-2026-014',
      emitterName: 'João da Silva & Filhos',
      emitterDocument: 'CPF 123.456.789-00',
      grainName: 'Soja',
      sacks: 440,
      quantityKg: 26400,
      sackPrice: 128.5,
      totalValue: 56540,
      versionCode: 'S2026.02',
      pickupUnit: 'Filial 02',
    ),
    creditor: const CprCreditor(
      name: 'Cooperativa Exemplo Ltda.',
      cnpj: '12.345.678/0001-90',
      address: 'Avenida Colombo',
      addressNumber: '4750',
      city: 'Maringá/PR',
      effectiveForum: 'Maringá/PR',
    ),
    cpr: CprDraft(
      number: 'CPR-2026-014',
      issuedAt: DateTime(2026, 5, 12),
      dueDate: DateTime(2026, 6, 30),
      emitterNationality: 'brasileiro',
      emitterMaritalStatus: 'casado',
      emitterProfession: 'produtor rural',
      emitterRg: '10.234.567-8',
      emitterAddress: 'Rua das Acácias',
      emitterAddressNumber: '340',
      emitterCity: 'Maringá/PR',
      spouseName: 'Maria da Silva',
      spouseNationality: 'brasileira',
      spouseProfession: 'produtora rural',
      spouseDocument: '987.654.321-00',
      deliveryPlace: 'Filial 02 — Granel Santa Tecla',
      cultivar: 'BMX Ativa RR',
      maxMoisture: 14,
      maxImpurities: 1,
      oilContent: 18,
      invoiceNumber: '00012345',
      duplicateNumber: '12345-A',
      areas: const [
        CprArea(
          locality: 'Água Boa',
          city: 'Maringá/PR',
          areaHa: 45.5,
          registryNumber: '12.345',
          registryBook: '2-RG',
          registryDistrict: 'Maringá/PR',
          owners: [CprOwner(name: 'Antônio Pereira', document: '111.222.333-44')],
        ),
      ],
    ),
    complete: true,
  );

  Archive abrir() => ZipDecoder().decodeBytes(CprDocx.build(desk));

  String parte(String caminho) =>
      utf8.decode(abrir().firstWhere((f) => f.name == caminho).content as List<int>);

  /// As quatro partes obrigatórias do pacote. Faltando qualquer uma, o Word
  /// recusa o arquivo inteiro — e o erro só aparece na mão de quem ia assinar.
  test('o pacote traz todas as partes que o OOXML exige', () {
    final nomes = abrir().map((f) => f.name).toSet();
    expect(nomes, containsAll(<String>{
      '[Content_Types].xml',
      '_rels/.rels',
      'word/document.xml',
      'word/_rels/document.xml.rels',
      'word/styles.xml',
      'word/footer1.xml',
    }));
  });

  test('o documento é XML bem formado e declara o namespace do Word', () {
    final xml = parte('word/document.xml');
    expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'));
    expect(xml, contains('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'));
    expect(xml, endsWith('</w:document>'));
    // Abre e fecha o corpo uma vez só.
    expect('<w:body>'.allMatches(xml).length, 1);
    expect('</w:body>'.allMatches(xml).length, 1);
  });

  /// O `&` no nome do produtor é o caso que quebra um gerador ingênuo: ele sai
  /// cru no XML, o pacote continua "gerando", e o Word recusa abrir.
  test('caracteres especiais do texto são escapados', () {
    final xml = parte('word/document.xml');
    expect(xml, contains('João da Silva &amp; Filhos'));
    expect(xml, isNot(contains('Silva & Filhos')));
  });

  /// O texto é o MESMO do PDF — os dois leem `CprText`. Uma amostra de cada
  /// bloco basta para provar que o corpo chegou inteiro.
  test('o conteúdo da cédula chega dentro do documento', () {
    final xml = parte('word/document.xml');
    expect(xml, contains('CÉDULA DE PRODUTO RURAL – CPR Nº CPR-2026-014'));
    expect(xml, contains('I – EMITENTE/DEVEDOR:'));
    expect(xml, contains('quatrocentos e quarenta'));
    expect(xml, contains('Filial 02 — Granel Santa Tecla'));
    expect(xml, contains('XX – DO FORO:'));
    expect(xml, contains('EMITENTE DEVEDOR:'));
    expect(xml, contains('ANUÊNCIA DO CÔNJUGE DO DEVEDOR:'));
  });

  /// `xml:space="preserve"` é o que impede o Word de comer os espaços das
  /// pontas — sem ele, frases montadas por concatenação perdem a separação.
  test('os espaços das pontas são preservados', () {
    expect(parte('word/document.xml'), contains('xml:space="preserve"'));
  });

  /// A numeração de página usa CAMPOS do Word (PAGE/NUMPAGES), que se
  /// recalculam quando alguém edita o texto — é o ponto de entregar .docx.
  test('o rodapé numera as páginas com campos, não com números fixos', () {
    final footer = parte('word/footer1.xml');
    expect(footer, contains('w:instr=" PAGE "'));
    expect(footer, contains('w:instr=" NUMPAGES "'));
    expect(parte('word/document.xml'), contains('<w:footerReference w:type="default"'));
  });

  test('a página é A4 e o texto sai justificado', () {
    final xml = parte('word/document.xml');
    expect(xml, contains('<w:pgSz w:w="11906" w:h="16838"/>'));
    expect(xml, contains('w:val="both"'));
  });

  group('o nome do arquivo', () {
    test('sai do número da cédula, em minúsculas', () {
      expect(CprDocx.filename(desk), 'cpr-2026-014');
    });

    /// Sem número ainda, cai no código da permuta — um arquivo sem nome é pior
    /// do que um arquivo com o nome do registro que o originou.
    test('sem número, cai no código da permuta', () {
      final semNumero = CprDesk(known: desk.known, creditor: desk.creditor);
      expect(CprDocx.filename(semNumero), 'prm-2026-014');
    });
  });
}
