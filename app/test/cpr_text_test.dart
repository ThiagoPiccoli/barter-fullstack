import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/services/cpr_text.dart';

/// A REDAÇÃO da cédula — o que o documento diz, testado sem abrir um PDF.
///
/// É a razão de `cpr_text.dart` existir separado de `cpr_docx.dart`: um ajuste
/// de margem não pode ter como alcançar o texto de uma cláusula, e o texto de
/// uma cláusula precisa poder ser conferido linha a linha.
void main() {
  final desk = CprDesk(
    known: const CprKnown(
      barterCode: 'PRM-2026-014',
      emitterName: 'João da Silva',
      emitterDocument: 'CPF 123.456.789-00',
      grainName: 'Soja',
      sacks: 440,
      quantityKg: 26400,
      sackPrice: 128.5,
      totalValue: 56540,
      versionCode: 'S2026.02',
    ),
    creditor: const CprCreditor(
      name: 'Cooperativa Exemplo Ltda.',
      cnpj: '12.345.678/0001-90',
      address: 'Avenida Colombo',
      addressNumber: '4750',
      city: 'Maringá/PR',
      forum: '',
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
      emitterCoopId: '4417',
      spouseName: 'Maria da Silva',
      spouseNationality: 'brasileira',
      spouseProfession: 'produtora rural',
      spouseDocument: '987.654.321-00',
      sackWeightKg: 60,
      cultivar: 'BMX Ativa RR',
      maxMoisture: 14,
      maxImpurities: 1,
      oilContent: 18,
      invoiceNumber: '00012345',
      duplicateNumber: '12345-A',
      deliveryPlace: 'Filial 02 — Granel Santa Tecla',
      areas: const [
        CprArea(
          locality: 'Água Boa',
          city: 'Maringá/PR',
          areaHa: 45.5,
          registryNumber: '12.345',
          registryBook: '2-RG',
          registryDistrict: 'Maringá/PR',
          owners: [
            CprOwner(name: 'Antônio Pereira', document: '111.222.333-44'),
            CprOwner(name: 'Rita Pereira', document: '555.666.777-88'),
          ],
        ),
      ],
    ),
    complete: true,
  );

  /// O documento inteiro, como uma string só — a forma mais direta de perguntar
  /// "esta frase saiu?".
  String textoDe(CprDesk d) => [
        CprText.heading(d),
        ...CprText.paragraphs(d).map((p) => '${p.title} ${p.body}'),
        CprText.closing(d),
      ].join('\n');

  test('o cabeçalho leva o número da cédula', () {
    expect(CprText.heading(desk), 'CÉDULA DE PRODUTO RURAL – CPR Nº CPR-2026-014');
  });

  /// A cláusula I é a qualificação civil — a parte que a permuta não sabia e que
  /// motivou o formulário inteiro.
  test('a cláusula I qualifica o emitente por inteiro', () {
    final texto = textoDe(desk);
    expect(
      texto,
      contains('João da Silva, brasileiro, casado, produtor rural, portador(a) da '
          'Carteira de Identidade RG nº 10.234.567-8, inscrito(a) no CPF sob o nº '
          '123.456.789-00, residente e domiciliado(a) na Rua das Acácias, nº 340, '
          'Maringá/PR.'),
    );
  });

  /// O rótulo "CPF" do cadastro não pode aparecer duas vezes: ele é gravado
  /// como o admin digitou ("CPF 123.456.789-00"), e a frase da cédula já traz a
  /// palavra.
  test('o documento do produtor entra sem o rótulo do cadastro', () {
    expect(textoDe(desk), isNot(contains('nº CPF 123.456.789-00')));
  });

  /// TODO NÚMERO SAI DUAS VEZES — algarismo e extenso, do mesmo valor. É a
  /// correção do defeito do modelo recebido ("367 (quatrocentos e quarenta)").
  test('quantidade, valor e preço saem com algarismo e extenso do mesmo número', () {
    final texto = textoDe(desk);
    expect(texto, contains('26.400 kg (quilos) que corresponde a 440 (quatrocentos e quarenta) sacas de Soja, de 60 kg cada'));
    expect(texto, contains('R\$ 56.540 (cinquenta e seis mil, quinhentos e quarenta reais)'));
    expect(texto, contains('R\$ 128,50 (cento e vinte e oito reais e cinquenta centavos)'));
  });

  /// A quantidade do PENHOR é a MESMA da entrega — e é exatamente aqui que o
  /// modelo recebido divergia.
  test('o penhor descreve a mesma quantidade da entrega', () {
    final garantia = CprText.paragraphs(desk)
        .firstWhere((p) => p.body.startsWith('a) Em Penhor Agrícola'));
    expect(garantia.body, contains('440 (quatrocentos e quarenta) sacas de Soja'));
  });

  test('o padrão do grão sai com os três percentuais por extenso', () {
    final texto = textoDe(desk);
    expect(texto, contains('cultivar BMX Ativa RR'));
    expect(texto, contains('máximo de 14% (catorze por cento) de Umidade'));
    expect(texto, contains('máximo de 1% (um por cento) de Impurezas'));
    expect(texto, contains('Teor de Óleo padrão no grão em 18% (dezoito por cento)'));
  });

  /// As lavouras são ENUMERADAS como o documento as enumera, e a cláusula VI se
  /// refere às mesmas áreas da V pela posição delas.
  group('as lavouras do penhor', () {
    test('uma lavoura, com os dois donos do imóvel', () {
      final texto = textoDe(desk);
      expect(
        texto,
        contains('(i) na localidade Água Boa, no município de Maringá/PR, tendo como '
            'área de plantio de 45,50 ha (quarenta e cinco vírgula cinquenta hectares), '
            'matrícula nº 12.345, Livro nº 2-RG, do Registro de Imóveis da Comarca de '
            'Maringá/PR, de propriedade de Antônio Pereira, CPF: 111.222.333-44 e '
            'Rita Pereira, CPF: 555.666.777-88.'),
      );
    });

    test('duas lavouras vêm ligadas por "; e", como no modelo', () {
      final duas = CprDesk(
        known: desk.known,
        creditor: desk.creditor,
        cpr: desk.cpr!.copyWith(areas: [
          desk.cpr!.areas.first,
          desk.cpr!.areas.first.copyWith(
            locality: 'Linha São João',
            withinLargerArea: true,
          ),
        ]),
      );
      final texto = textoDe(duas);
      expect(texto, contains('; e (ii) na localidade Linha São João'));
      // "dentro de uma área maior" é a diferença entre penhorar a lavoura e
      // parecer penhorar a fazenda inteira.
      expect(texto, contains('hectares) dentro de uma área maior, matrícula nº'));
    });

    test('a lavoura que não é área maior não ganha a frase', () {
      expect(textoDe(desk), isNot(contains('dentro de uma área maior')));
    });
  });

  test('a origem da dívida amarra a cédula à nota e à duplicata', () {
    expect(textoDe(desk), contains('Referente NF 00012345 e DUP 12345-A'));
  });

  /// O LOCAL DA ENTREGA é campo próprio: a planilha de proposta nomeia a filial,
  /// e o grão nem sempre é entregue na sede. A qualificação da credora continua
  /// junto — é ela que diz de quem é o armazém.
  group('o local da entrega', () {
    test('o preenchido substitui os "armazéns da credora"', () {
      expect(
        textoDe(desk),
        contains('d) Local da Entrega: Filial 02 — Granel Santa Tecla, da empresa '
            'Cooperativa Exemplo Ltda., com sede na Avenida Colombo'),
      );
    });

    /// Em branco, cai na redação original do modelo — que é verdadeira, só
    /// genérica.
    test('em branco, cai na redação do modelo', () {
      final semLocal = CprDesk(
        known: desk.known,
        creditor: desk.creditor,
        cpr: desk.cpr!.copyWith(deliveryPlace: ''),
      );
      expect(textoDe(semLocal), contains('d) Local da Entrega: Nos armazéns da empresa'));
    });
  });

  /// A apólice só aparece quando há seguro: uma cláusula que afirma um seguro
  /// inexistente é pior do que uma cláusula a menos.
  group('a alínea do seguro', () {
    test('some quando não há apólice', () {
      expect(textoDe(desk), isNot(contains('valor do seguro contratado')));
    });

    test('aparece com o número quando há', () {
      final comSeguro = CprDesk(
        known: desk.known,
        creditor: desk.creditor,
        cpr: desk.cpr!.copyWith(insurancePolicy: 'AP-99887'),
      );
      expect(textoDe(comSeguro), contains('conforme apólice nº AP-99887'));
    });
  });

  /// A QUALIFICAÇÃO DA CREDORA sai TRÊS vezes, palavra por palavra — cláusula
  /// II, promessa de entrega e local de entrega (V-d). A quarta aparição da
  /// credora é o foro (XX), que leva só a comarca.
  ///
  /// O número é afirmado aqui de propósito: ele é a razão de a frase ser montada
  /// uma vez só no código. Três cópias soltas seriam três lugares para uma delas
  /// ficar para trás quando o endereço mudar.
  test('a qualificação da credora sai idêntica nas três vezes', () {
    final texto = textoDe(desk);
    const qualificacao = 'Cooperativa Exemplo Ltda., com sede na Avenida Colombo, nº 4750, '
        'na cidade de Maringá/PR, inscrita no CNPJ sob o nº 12.345.678/0001-90';
    expect(texto.split(qualificacao).length - 1, 3);
  });

  /// O foro em branco vale como a comarca da sede — e quem resolve isso é o
  /// servidor, em `effectiveForum`.
  test('o foro sai resolvido na cláusula XX', () {
    expect(textoDe(desk), contains('Produto Rural é o de Maringá/PR.'));
  });

  test('as datas saem por extenso na abertura e no fecho', () {
    final texto = textoDe(desk);
    expect(texto, contains('Aos 12 dias do mês de maio de 2026'));
    expect(texto, contains('com vencimento em 30/06/2026'));
    expect(CprText.closing(desk), 'Maringá/PR, 12 de maio de 2026.');
  });

  group('as assinaturas', () {
    test('emitente, fiel depositário e cônjuge — nesta ordem', () {
      final blocos = CprText.signatures(desk);
      expect(blocos.map((b) => b.role), [
        'EMITENTE DEVEDOR:',
        'FIEL DEPOSITÁRIO:',
        'ANUÊNCIA DO CÔNJUGE DO DEVEDOR:',
      ]);
    });

    /// O fiel depositário É o emitente — é o que a cláusula VII diz. Por isso o
    /// bloco é o mesmo com outro título, e não um segundo campo do formulário.
    test('o fiel depositário é o próprio emitente', () {
      final blocos = CprText.signatures(desk);
      expect(blocos[1].name, blocos[0].name);
      expect(blocos[1].document, blocos[0].document);
      expect(blocos[0].coopId, 'Matrícula Cooperativa: 4417');
    });

    /// O estado civil do cônjuge é o do emitente — é o que faz dele cônjuge —,
    /// e o endereço é o mesmo domicílio. Nenhum dos dois é campo do formulário,
    /// justamente para o casal não aparecer descasado no documento.
    test('o cônjuge herda o estado civil e o endereço do emitente', () {
      final conjuge = CprText.signatures(desk)[2];
      expect(conjuge.name, 'Maria da Silva');
      expect(conjuge.qualification, 'brasileira, casado, produtora rural');
      expect(conjuge.address, 'Rua das Acácias, nº 340 – Maringá/PR');
    });

    /// Sem cônjuge, o bloco não existe: uma linha de assinatura em branco num
    /// título de crédito é um convite a alguém achar que falta assinatura.
    test('sem cônjuge, o bloco não é impresso', () {
      final solteiro = CprDesk(
        known: desk.known,
        creditor: desk.creditor,
        cpr: desk.cpr!.copyWith(emitterMaritalStatus: 'solteiro', spouseName: ''),
      );
      expect(CprText.signatures(solteiro).length, 2);
    });
  });

  /// Uma cédula incompleta ainda gera texto — com lacunas visíveis, e não com
  /// "null" no meio de uma cláusula. A tela impede o botão de gerar; isto aqui é
  /// a rede embaixo dela.
  test('cédula vazia produz lacunas, e não "null"', () {
    const vazia = CprDesk();
    final texto = textoDe(vazia);
    expect(texto, isNot(contains('null')));
    expect(texto, contains('CPR Nº _______'));
    expect(texto, contains('__/__/____'));
  });
}
