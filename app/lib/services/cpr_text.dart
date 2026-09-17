/// A CÉDULA DE PRODUTO RURAL, como TEXTO — o documento montado a partir do que
/// foi coletado.
///
/// Separado da geração do PDF de propósito, e pelo mesmo motivo de
/// `barter-math.ts` e `cpr.ts` no servidor: aqui mora a REDAÇÃO, e redação se
/// testa sem abrir um arquivo. O `cpr_docx.dart` só decide fonte, margem e
/// quebra de página; o que o documento DIZ está aqui, e é isso que precisa
/// continuar dizendo a mesma coisa depois de qualquer mexida no layout.
///
/// ─────────────────────────────────────────────────────────────────────────────
/// O CONTRATO COM O MODELO
///
/// As cláusulas fixas (VIII, X, XI, XII, XIII, XIV, XV, XVII, XVIII, XIX) são
/// transcritas literalmente do modelo recebido, com as referências de lei que
/// ele traz. Elas NÃO são parametrizadas: são a parte do documento que não
/// depende desta permuta, e um "gerador de cláusula" convidaria alguém a editar
/// texto jurídico por engano.
///
/// O que varia entra por [CprDesk] — e vem das três fontes de sempre: o que a
/// permuta já sabe (`known`), quem é a credora (`creditor`) e o que o faturista
/// preencheu (`cpr`).
///
/// ─────────────────────────────────────────────────────────────────────────────
/// TODO NÚMERO SAI DUAS VEZES
///
/// Algarismo e extenso, como a cédula exige — e os dois saem do MESMO valor,
/// via `extenso.dart`. É a correção do defeito que o modelo recebido trazia:
/// *"367 (quatrocentos e quarenta) sacas"*, com o algarismo e o extenso
/// discordando dentro de um título executável.
library;

import '../models/models.dart';
import 'extenso.dart';

/// Um parágrafo do documento: um título curto (a cláusula) e o corpo.
///
/// A separação existe para o PDF poder dar ênfase ao título sem procurar o
/// ponto onde ele acaba dentro de uma string — e para os testes poderem
/// apontar uma cláusula pelo nome em vez de por posição.
class CprParagraph {
  /// "I – EMITENTE/DEVEDOR:", "IV – VENCIMENTO:"… Vazio nos parágrafos que
  /// continuam a cláusula anterior.
  final String title;
  final String body;

  /// Um parágrafo de item — a alínea "a)", a lavoura "(i)" — que o PDF recua.
  final bool indented;

  const CprParagraph(this.title, this.body, {this.indented = false});
}

/// O texto inteiro da cédula, na ordem em que ele sai impresso.
class CprText {
  CprText._();

  static const _meses = [
    '',
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  /// O cabeçalho: "CÉDULA DE PRODUTO RURAL – CPR Nº 014".
  static String heading(CprDesk desk) =>
      'CÉDULA DE PRODUTO RURAL – CPR Nº ${_ou(desk.cpr?.number, '_______')}';

  /// O corpo inteiro, cláusula a cláusula.
  static List<CprParagraph> paragraphs(CprDesk desk) {
    final cpr = desk.cpr ?? const CprDraft();
    final known = desk.known;
    final credora = desk.creditor;

    // A QUALIFICAÇÃO DA CREDORA sai três vezes, palavra por palavra: na
    // cláusula II, na promessa de entrega e no local de entrega (V-d). Ela é
    // montada uma vez porque três cópias do mesmo texto são três lugares para
    // uma delas ficar para trás quando o endereço mudar. (A quarta aparição da
    // credora é o foro, na XX, e essa leva só a comarca.)
    final qualificacaoCredora =
        '${credora.name}, com sede na ${credora.address}, nº ${credora.addressNumber}, '
        'na cidade de ${credora.city}, inscrita no CNPJ sob o nº ${credora.cnpj}';

    final quantidade =
        '${_num(known.quantityKg)} kg (quilos) que corresponde a ${_num(known.sacks)} '
        '(${extensoDecimal(known.sacks)}) sacas de ${known.grainName}, de '
        '${_num(cpr.sackWeightKg)} kg cada';

    final valorTotal =
        'R\$ ${_num(known.totalValue)} (${extensoMoeda(known.totalValue)})';
    final precoSaca = 'R\$ ${_num(known.sackPrice)} (${extensoMoeda(known.sackPrice)})';

    return [
      CprParagraph(
        'I – EMITENTE/DEVEDOR:',
        // As flexões vão em "(a)" porque o emitente é tanto produtor quanto
        // produtora, e o modelo recebido traz o masculino fixo. Uma cédula que
        // chama a emitente de "portador… inscrito… domiciliado" está errada na
        // primeira linha, que é onde ela identifica quem se obriga.
        '${known.emitterName}, ${cpr.emitterNationality}, ${cpr.emitterMaritalStatus}, '
            '${cpr.emitterProfession}, portador(a) da Carteira de Identidade RG nº '
            '${cpr.emitterRg}, inscrito(a) no CPF sob o nº '
            '${_digitos(known.emitterDocument)}, residente e domiciliado(a) na '
            '${cpr.emitterAddress}, nº ${cpr.emitterAddressNumber}, ${cpr.emitterCity}.',
      ),
      CprParagraph('II – CREDOR:', '$qualificacaoCredora.'),
      CprParagraph(
        'III – QUANTIDADE DE PRODUTO:',
        '$quantidade, limpa e seca, tipo indústria, em grão.',
      ),
      // O VENCIMENTO vem da SAFRA — ele muda conforme a cultura, e vale para
      // todas as cédulas dela. `known` é onde o servidor o resolve.
      CprParagraph('IV – VENCIMENTO:', _data(known.dueDate)),
      CprParagraph(
        '',
        '${_aos(cpr.issuedAt)}, entregarei, por esta CÉDULA DE PRODUTO RURAL, a '
            '$qualificacaoCredora, ou a sua ordem, a quantidade de $quantidade, tipo '
            'indústria, limpa e seca, equivalente em moeda corrente nacional a '
            '$valorTotal, o qual será entregue conforme abaixo caracterizado:',
      ),
      const CprParagraph('V – CONDIÇÕES DO PRODUTO E DA ENTREGA:', ''),
      CprParagraph(
        '',
        'a) Safra – O produto comprometido refere-se ao produto a ser colhido na '
            'safra ${known.versionCode};',
        indented: true,
      ),
      CprParagraph(
        '',
        'b) Local da Lavoura – área de terra plantada pelo emitente nas seguintes '
            'áreas: ${_lavouras(cpr.areas)}',
        indented: true,
      ),
      CprParagraph(
        '',
        'c) Características do Produto: ${known.grainName} em grão, cultivar '
            '${cpr.cultivar}, safra ${known.versionCode}, limpo e seco, tipo indústria, '
            'com máximo de ${_num(cpr.maxMoisture)}% (${extensoPercentual(cpr.maxMoisture)}) '
            'de Umidade (Aparelho Modelo Eletrônico) e, máximo de '
            '${_num(cpr.maxImpurities)}% (${extensoPercentual(cpr.maxImpurities)}) de '
            'Impurezas; Teor de Óleo padrão no grão em ${_num(cpr.oilContent)}% '
            '(${extensoPercentual(cpr.oilContent)}).',
        indented: true,
      ),
      CprParagraph(
        '',
        // O LOCAL DA ENTREGA é campo (cláusula V, "d"): a planilha de proposta
        // nomeia a filial ("Filial 02 — Gran. Santa Tecla"), e o grão nem sempre
        // é entregue na sede. A qualificação da credora continua junto — é ela
        // que diz de quem é o armazém.
        //
        // Sem o campo preenchido, cai na redação original do modelo, que é
        // verdadeira e genérica: os armazéns da credora.
        cpr.deliveryPlace.trim().isEmpty
            ? 'd) Local da Entrega: Nos armazéns da empresa $qualificacaoCredora.'
            : 'd) Local da Entrega: ${cpr.deliveryPlace.trim()}, da empresa '
                '$qualificacaoCredora.',
        indented: true,
      ),
      CprParagraph(
        'VI – DESCRIÇÃO DOS BENS CEDULARMENTE VINCULADOS EM GARANTIA:',
        '',
      ),
      CprParagraph(
        '',
        'a) Em Penhor Agrícola de Primeiro Grau e sem concorrência de terceiros, nos '
            'termos do art. 1.431 e seguintes do Código Civil, Lei 492/37 e art. 7º da '
            'Lei nº 8.929/94, a quantidade de ${_num(known.sacks)} '
            // A quantidade do PENHOR é a MESMA da entrega, e por isso ela sai do
            // mesmo lugar. O modelo recebido trazia "367 (quatrocentos e
            // quarenta)" aqui — um número em algarismo e outro por extenso, na
            // cláusula que descreve a garantia.
            '(${extensoDecimal(known.sacks)}) sacas de ${known.grainName}, comercial em '
            'grãos tipo indústria, da safra ${known.versionCode}, de propriedade de '
            '${known.emitterName}, área de terra plantada pelo emitente nas seguintes '
            'áreas: ${_lavouras(cpr.areas)}',
        indented: true,
      ),
      CprParagraph(
        'VII – DA ORIGEM E DEPÓSITO:',
        'A presente cédula é emitida em garantia de pagamento do valor devido pelo '
            'emitente ao credor, referente a troca de insumos, cujo o preço bruto '
            'considerado da ${known.grainName} foi de $precoSaca. ${_notas(known.invoices)} '
            'Em consequência do penhor '
            'agrícola, ${known.emitterName} assume a condição de Fiel '
            'Depositário das ${_num(known.sacks)} (${extensoDecimal(known.sacks)}) sacas '
            'de ${known.grainName}, tipo indústria, sem qualquer remuneração, correndo as '
            'despesas de conservação por sua conta e risco até a entrega final, não sendo '
            'lícito dispor sem o consentimento expresso do Credor, responsabilizando-se '
            'pelos riscos e sujeitando-se às cominações impostas ao depositário infiel, '
            'inclusive na pena de prisão civil, preceituada no art. 652 do Código Civil, '
            'obrigando-me, portanto, a não gravar ou alienar, em favor de terceiros, os '
            'produtos ora vendidos e os bens vinculados em garantia, como dispõe o art. 18 '
            'da Lei 8.929/94.',
      ),
      const CprParagraph(
        'VIII – DO ACESSO ÀS LAVOURAS:',
        'O Emitente concede à CREDORA livre acesso à lavoura, para fins de fiscalização '
            'da mesma quando entender necessário e para fins de acompanhamento da colheita '
            'prevista e respectiva entrega do produto.',
      ),
      CprParagraph(
        'IX – FORMA E CONDIÇÃO DE LIQUIDAÇÃO:',
        'A presente Cédula de Produto Rural é confeccionada para pagamento em parcela '
            'única, com vencimento em ${_data(known.dueDate)}.',
      ),
      const CprParagraph(
        'X – INADIMPLEMENTO:',
        'A falta de entrega do produto no prazo convencionado acarretará ao emitente a '
            'incidência dos seguintes encargos:',
      ),
      const CprParagraph(
        '',
        'a) Pena de multa, estipulada em conformidade do artigo 409 do Código Civil e do '
            'artigo 71 do Decreto-Lei nº 167/67, com as alterações da Lei nº 13.986/2020, '
            'equivalente a 2% (dois por cento) do que restar devido, em físico;',
        indented: true,
      ),
      const CprParagraph(
        '',
        'b) Cláusula penal de 20% sobre o valor do presente instrumento, em físico, em '
            'observância aos artigos 408 a 416 do Código Civil e art. 809 do CPC;',
        indented: true,
      ),
      CprParagraph(
        '',
        'c) Juros moratórios de 12% (doze por cento) ao ano sobre o montante do produto '
            'devido. Em caso de não localização total ou parcial do produto, o saldo '
            'devedor será apurado pela quantidade de produto devida, e transformado para '
            'moeda corrente nacional considerando o preço do produto negociado de '
            '$precoSaca a saca, acrescida dos encargos de mora neste item definidos. A '
            'partir de então, incidirão juros de 12% ao ano, capitalizados mensalmente e '
            'correção monetária pelo IGP-M.',
        indented: true,
      ),
      CprParagraph(
        'XI – DECLARAÇÃO DE NÃO ESSENCIALIDADE:',
        'Declara o Emitente ${known.emitterName} que os bens cedularmente vinculados em '
            'garantia da presente Cédula de Produto Rural não são essenciais à sua '
            'atividade fim, em observância ao disposto no Parágrafo Único, do art. 5º da '
            'Lei 8.929/94.',
      ),
      const CprParagraph('XII – PROTEÇÃO DE DADOS:', ''),
      const CprParagraph(
        '',
        'a) O EMITENTE/DEVEDOR concorda que a entidade autorizada pelo Banco Central do '
            'Brasil exerça a atividade de registro ou depósito centralizado de ativos '
            'financeiros de que trata o artigo 12, caput, da Lei 8.929/1994, e compartilhe '
            'com a CREDORA todos os dados relacionados à presente Cédula, nos termos do '
            'artigo 7º, incisos I, II, V, VI, IX e X, da Lei nº 13.709/2018.',
        indented: true,
      ),
      const CprParagraph(
        '',
        'b) O EMITENTE/DEVEDOR consente que a CREDORA compartilhe os dados pessoais '
            'relacionados à presente CPR com outros agentes econômicos, tais como entidades '
            'financiadoras, instituições financeiras, com a finalidade de proteção do '
            'crédito, nos moldes do artigo 7º, inciso X, da Lei nº 13.709/2018, podendo, '
            'inclusive, compartilhar e divulgar circunstâncias negociais e informações '
            'sobre o cumprimento das obrigações constantes desta cédula.',
        indented: true,
      ),
      const CprParagraph(
        '',
        'c) O EMITENTE/DEVEDOR autoriza a CREDORA a realizar a consulta de que trata o '
            'artigo 2º, da RESOLUÇÃO BCB Nº 52, de 16 de dezembro de 2020, outorgando-lhe '
            'expressamente, neste ato, poderes para requerer informações sobre as Cédulas '
            'de Produto Rural de sua emissão, em atendimento ao § 1º do mesmo dispositivo, '
            'valendo o disposto na presente cláusula como instrumento de mandato, permitido '
            'o substabelecimento de iguais poderes a terceiros, a critério da CREDORA.',
        indented: true,
      ),
      const CprParagraph('XIII – REGISTROS:', ''),
      const CprParagraph(
        '',
        'a) A CREDORA, em atendimento ao artigo 12, da Lei 8.929/1994, com redação dada '
            'pela Lei nº 13.986/2020, obriga-se a registrar e/ou depositar esta CPR, após '
            'sua emissão ou aditamento, em entidade autorizada pelo Banco Central do Brasil '
            'a exercer a atividade de registro ou de depósito centralizado de ativos '
            'financeiros e valores mobiliários, ficando eleita a B3 S.A. – Brasil, Bolsa, '
            'Balcão para realizar referido ato.',
        indented: true,
      ),
      const CprParagraph(
        '',
        'b) Conforme previsto no artigo 9º da Lei 8.929/94, esta CPR poderá ser '
            'retificada, no todo ou em parte, através de aditivos que passarão a integrá-la, '
            'após a devida formalização pelo EMITENTE/DEVEDOR e pela CREDORA. A obrigação '
            'do EMITENTE/DEVEDOR, prevista neste item, aplicar-se-á a todos os aditamentos '
            'desta CPR, salvo disposição em contrário.',
        indented: true,
      ),
      const CprParagraph(
        '',
        'c) O EMITENTE/DEVEDOR, às suas expensas, autoriza a CREDORA, ou terceiro que esta '
            'indicar, a promover os atos administrativos e registrais previstos nesta CPR, '
            'conforme o caso, em especial, mas não se limitando, ao registro em sistemas de '
            'registro e de liquidação financeira de ativos devidamente autorizados pelo '
            'Banco Central do Brasil, tais como a B3 S/A – Brasil, Bolsa, Balcão. '
            'Declara-se ciente, ainda, de que a sua quitação dar-se-á de acordo com os '
            'trâmites estabelecidos pelos mesmos para tanto, comprometendo-se com todas e '
            'quaisquer providências razoáveis e justificadamente necessárias para a devida '
            'realização do registro mencionado nesta cláusula, de acordo com o regulamento '
            'oficial de tais sistemas.',
        indented: true,
      ),
      const CprParagraph(
        'XIV – ASSINATURA DIGITAL OU ELETRÔNICA:',
        'O EMITENTE/DEVEDOR ajusta que a presente Cédula e seus eventuais aditivos e/ou '
            'anexos poderão ser assinados digital ou eletronicamente. Nos termos do artigo '
            '10, inciso II, da Medida Provisória nº 2.200-2, as partes expressamente '
            'concordam em utilizar e reconhecem como válida qualquer forma de comprovação '
            'de anuência aos termos ora acordados em formato eletrônico, ainda que não '
            'utilizem de certificado digital emitido no padrão ICP-Brasil, incluindo '
            'emissão e assinaturas eletrônicas. Neste caso, as partes elegem as ferramentas '
            'e os recursos eletrônicos disponibilizados pela plataforma Docusign como meios '
            'para comprovar autenticidade e integridade das assinaturas. A formalização das '
            'avenças na maneira acordada será suficiente à validade integral da presente '
            'cédula, seus eventuais aditivos e/ou anexos.',
      ),
      const CprParagraph(
        'XV – DIGITALIZAÇÃO:',
        'Caso a presente CPR não seja assinada eletronicamente na forma do caput, vindo a '
            'ser materializada e assinada em formato físico, as partes convencionam, e o '
            'EMITENTE/DEVEDOR autoriza, que a CREDORA promova, por si e independentemente '
            'de formalidade adicional, a desmaterialização do título (digitalização), a fim '
            'de transformá-lo em documento digital, formato em que admitem como válido e '
            'atribuem, para todos os fins de direito, a mesma eficácia do documento '
            'original.',
      ),
      CprParagraph(
        'XVI – VALOR REFERENCIAL:',
        'Em atenção à Resolução CMN nº 4.870, de 27.11.2020, para o fim exclusivo de '
            'verificação da obrigatoriedade de registro ou do depósito da presente Cédula '
            'de Produto Rural, as "partes" declaram que o valor referencial de emissão desta '
            'cédula é de $valorTotal. O EMITENTE/DEVEDOR declara, ainda, que a presente '
            'cláusula é celebrada tão somente para preenchimento do requisito de que trata '
            '§ 6º (parágrafo sexto) do artigo 2º da referida normativa, de modo que o valor '
            'aqui apurado não poderá, sob hipótese alguma, ser considerado como parâmetro '
            'para qualquer outra finalidade, senão a de verificação das condições de '
            'dispensa de registro ou de depósito centralizado da presente Cédula de Produto '
            'Rural em entidade autorizada pelo Banco Central do Brasil.',
      ),
      const CprParagraph(
        'XVII – DECLARAÇÃO DE AUSÊNCIA DE ÔNUS:',
        'O EMITENTE/DEVEDOR declara, sob as penas da Lei, que o produto cedido para a '
            'CREDORA, e oferecido para pagamento desta CPR, encontra-se livre de quaisquer '
            'ônus ou gravames, nem comprometido por quaisquer outros créditos abertos, seja '
            'através de nota promissória rural, cédula rural pignoratícia ou hipotecária, '
            'financiamento agrícola, warrants, seja através de outra CPR, contratos '
            'particulares, ou ainda, em penhor judicial, nem pertencente a nenhum espólio, '
            'nem a meeiros, parceiros, empreiteiros ou porcenteiros, sendo, pois, de única '
            'e exclusiva propriedade sua.',
      ),
      const CprParagraph('XVIII – OUTRAS DISPOSIÇÕES:', ''),
      const CprParagraph(
        '',
        'a) Nos termos do art. 11 da Lei nº 8.929/94, não se sujeitarão aos efeitos de '
            'recuperação judicial os créditos e as garantias aqui vinculados.',
        indented: true,
      ),
      const CprParagraph(
        '',
        'b) A Cédula de Produto Rural é firmada em observância à liberdade contratual, '
            'prevista na regra do art. 421 do Código Civil Brasileiro, de modo que toda e '
            'qualquer interpretação deverá se dar a fim de preservar a autonomia de vontade '
            'das partes formalizada neste instrumento.',
        indented: true,
      ),
      const CprParagraph(
        '',
        'c) A CPR é título líquido, certo e exigível à luz da legislação vigente.',
        indented: true,
      ),
      const CprParagraph(
        '',
        'd) Nos termos da Lei 13.853/2019 (Lei Geral de Proteção de Dados), o Emitente '
            'e/ou Garantidor concorda com a utilização dos seus dados e informações, em '
            'qualquer órgão, repartição pública, serventias extrajudiciais, plataformas '
            'digitais, e/ou onde necessário for, pela Credora, em função deste instrumento.',
        indented: true,
      ),
      const CprParagraph(
        '',
        'e) Esta operação com garantia é ajustada em caráter irrevogável e irretratável, '
            'considera-se, portanto, desde já, perfeita e acabada, correndo por conta e '
            'risco do DEVEDOR todos os riscos decorrentes da evicção, de casos fortuitos '
            'e/ou força maior, até a efetiva entrega do produto à CREDORA, que o DEVEDOR se '
            'obriga a proceder, com o primeiro produto que colher e/ou receber, respeitados '
            'os prazos e condições supra estipulados.',
        indented: true,
      ),
      const CprParagraph(
        '',
        'f) Caso haja qualquer alteração na legislação tributária, seja por aumento de '
            'alíquotas já existentes ou pela criação de novos tributos, contribuições e '
            'encargos, ou até mesmo por alteração na base de cálculo aplicável à produção '
            'rural, tais como Funrural, Senar, Sat, DPI Monsanto, o valor correspondente a '
            'esta diferença financeira ou adicional de alíquota será de inteira e exclusiva '
            'responsabilidade do(a) DEVEDOR(A).',
        indented: true,
      ),
      const CprParagraph(
        '',
        'g) Declaração – Previdência Social – Declara-se, sob as penas da Lei, que não são '
            'as partes responsáveis pelo recolhimento de contribuições à Previdência Social, '
            'eis que não industrializam, não comercializam a adquirentes domiciliados no '
            'exterior, nem são vendidos os próprios produtos no varejo diretamente a '
            'consumidor.',
        indented: true,
      ),
      const CprParagraph(
        '',
        'h) O Emitente tem pleno conhecimento de que o produto objeto desta Cédula de '
            'Produto Rural já tem seu destino devidamente comprometido, visando sua '
            'colocação nos mercados interno e externo, a tempo certo e baseado no prazo que '
            'as partes fixarem para sua entrega.',
        indented: true,
      ),
      const CprParagraph(
        '',
        'i) O Emitente declara sob as penas da lei que o produto ora vendido está livre e '
            'desembaraçado de todo e qualquer ônus, não é objeto de penhor ou qualquer '
            'garantia a terceiros, não pertence a arrendadores, arrendatários ou parceiros, '
            'não dependendo sua comercialização de qualquer autorização judicial ou '
            'extrajudicial.',
        indented: true,
      ),
      // A alínea "j" só existe quando HÁ seguro. O modelo a traz sempre, com a
      // apólice em branco — e uma cláusula que afirma um seguro inexistente é
      // pior do que uma cláusula a menos.
      if (cpr.insurancePolicy.trim().isNotEmpty)
        CprParagraph(
          '',
          'j) No presente contrato está incluso o valor do seguro contratado conforme '
              'apólice nº ${cpr.insurancePolicy}.',
          indented: true,
        ),
      const CprParagraph(
        'XIX – DECLARAÇÃO DE ENDOSSO:',
        'O Emitente fica ciente que poderá a Credora ceder ou transferir a terceiros, via '
            'endosso, os direitos e obrigações estabelecidos na presente CPR, bem como o '
            'direito ao recebimento do Produto objeto deste instrumento, em conformidade '
            'com o disposto no art. 10 da Lei 8.929/94, dispensando-se qualquer comunicação '
            'por escrito ao Emitente.',
      ),
      CprParagraph(
        'XX – DO FORO:',
        'O foro competente para dirimir quaisquer dúvidas acerca da presente Cédula de '
            'Produto Rural é o de ${credora.effectiveForum}.',
      ),
    ];
  }

  /// O fecho: "Maringá/PR, 12 de maio de 2026." — a praça e a data de emissão.
  static String closing(CprDesk desk) =>
      '${desk.creditor.city}, ${_porExtensoData(desk.cpr?.issuedAt)}.';

  /// Os blocos de assinatura, na ordem do modelo.
  ///
  /// O do CÔNJUGE só existe quando há um: a anuência é exigida de quem é
  /// casado, e uma linha de assinatura em branco num título de crédito é um
  /// convite a alguém achar que falta assinatura.
  static List<CprSignature> signatures(CprDesk desk) {
    final cpr = desk.cpr ?? const CprDraft();
    final qualificacao =
        '${cpr.emitterNationality}, ${cpr.emitterMaritalStatus}, ${cpr.emitterProfession}';
    final endereco =
        '${cpr.emitterAddress}, nº ${cpr.emitterAddressNumber} – ${cpr.emitterCity}';

    final emitente = CprSignature(
      role: 'EMITENTE DEVEDOR:',
      name: desk.known.emitterName,
      qualification: qualificacao,
      address: endereco,
      document: 'CPF/MF: ${_digitos(desk.known.emitterDocument)}',
      coopId: cpr.emitterCoopId.trim().isEmpty
          ? null
          : 'Matrícula Cooperativa: ${cpr.emitterCoopId}',
    );

    return [
      emitente,
      // O FIEL DEPOSITÁRIO é o próprio emitente — é o que a cláusula VII diz —,
      // e por isso o bloco é o mesmo com outro título, e não um segundo campo
      // no formulário: dois campos permitiriam que ele deixasse de ser.
      CprSignature(
        role: 'FIEL DEPOSITÁRIO:',
        name: emitente.name,
        qualification: emitente.qualification,
        address: emitente.address,
        document: emitente.document,
        coopId: emitente.coopId,
      ),
      if (cpr.spouseName.trim().isNotEmpty)
        CprSignature(
          role: 'ANUÊNCIA DO CÔNJUGE DO DEVEDOR:',
          name: cpr.spouseName,
          // O estado civil e o endereço do cônjuge são os do emitente: o
          // primeiro é o que faz dele cônjuge, e o segundo é o mesmo domicílio
          // conjugal. Não são campos do formulário justamente para não haver
          // como o casal aparecer com estados civis diferentes no documento.
          qualification: '${cpr.spouseNationality}, ${cpr.emitterMaritalStatus}, '
              '${cpr.spouseProfession}',
          address: endereco,
          document: 'CPF/MF: ${cpr.spouseDocument}',
          coopId: null,
        ),
    ];
  }

  /* ── As peças ─────────────────────────────────────────────────────────── */

  /// As lavouras enumeradas como o documento as enumera: "(i) …; e (ii) …".
  ///
  /// A numeração é ROMANA MINÚSCULA porque é assim no modelo, e ela é conteúdo:
  /// a cláusula VI se refere às mesmas áreas da V pela posição delas.
  static String _lavouras(List<CprArea> areas) {
    if (areas.isEmpty) return '_______.';
    final partes = <String>[];
    for (var i = 0; i < areas.length; i++) {
      final area = areas[i];
      final maior = area.withinLargerArea ? ' dentro de uma área maior' : '';
      partes.add(
        '(${_romano(i + 1)}) na localidade ${area.locality}, no município de ${area.city}, '
        'tendo como área de plantio de ${_num(area.areaHa)} ha '
        '(${extensoDecimal(area.areaHa)} hectares)$maior, matrícula nº '
        '${area.registryNumber}, Livro nº ${area.registryBook}, do Registro de Imóveis da '
        'Comarca de ${area.registryDistrict}, de propriedade de ${_donos(area.owners)}',
      );
    }
    // "…; e (ii) …" — a conjunção antes do último item, como no modelo.
    if (partes.length == 1) return '${partes.first}.';
    return '${partes.sublist(0, partes.length - 1).join('; ')}; e ${partes.last}.';
  }

  /// "Fulano, CPF: 000 e Beltrano, CPF: 111" — os donos do imóvel.
  static String _donos(List<CprOwner> owners) {
    if (owners.isEmpty) return '_______';
    final partes = owners.map((o) => '${o.name}, CPF: ${o.document}').toList();
    if (partes.length == 1) return partes.first;
    return '${partes.sublist(0, partes.length - 1).join(', ')} e ${partes.last}';
  }

  /// "Aos 12 dias do mês de maio de 2026" — a abertura da promessa de entrega.
  static String _aos(DateTime? data) {
    if (data == null) return 'Aos ____ dias do mês de ________ de ____';
    return 'Aos ${data.day} dias do mês de ${_meses[data.month]} de ${data.year}';
  }

  /// "12 de maio de 2026" — a data do fecho.
  static String _porExtensoData(DateTime? data) {
    if (data == null) return '____ de ________ de ____';
    return '${data.day} de ${_meses[data.month]} de ${data.year}';
  }

  /// AS NOTAS FISCAIS que originaram a dívida (cláusula VII), como o documento
  /// as cita.
  ///
  /// São VÁRIAS, e o texto as enumera: a permuta sai em mais de um
  /// carregamento, e o modelo antigo citava uma só porque a cédula guardava um
  /// número de nota e um de duplicata, digitados à mão. As duplicatas entram na
  /// mesma frase, e só as que existem — nem toda venda gera uma.
  ///
  /// Sem nota nenhuma a frase SOME em vez de sair com o espaço em branco: uma
  /// cédula assim não é emitida (`cprGaps` a recusa), e um "Referente NF ____"
  /// impresso seria pior do que a ausência.
  static String _notas(List<CprInvoiceRef> notas) {
    if (notas.isEmpty) return '';
    final numeros = notas.map((n) => n.label).join(', ');
    final duplicatas =
        notas.where((n) => n.duplicateNumber.isNotEmpty).map((n) => n.duplicateNumber).join(', ');
    final plural = notas.length > 1;
    return duplicatas.isEmpty
        ? 'Referente ${plural ? 'às NFs' : 'à NF'} $numeros.'
        : 'Referente ${plural ? 'às NFs' : 'à NF'} $numeros e '
            '${duplicatas.contains(',') ? 'DUPs' : 'DUP'} $duplicatas.';
  }

  static String _data(DateTime? data) => data == null
      ? '__/__/____'
      : '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/'
          '${data.year}';

  /// Números na forma brasileira: milhar com ponto, decimal com vírgula, e sem
  /// casas decimais quando não há.
  static String _num(double valor) {
    final arredondado = (valor * 100).round() / 100;
    final inteiro = arredondado.truncate();
    final decimal = ((arredondado - inteiro) * 100).round().abs();

    final buffer = StringBuffer();
    final digitos = inteiro.abs().toString();
    for (var i = 0; i < digitos.length; i++) {
      if (i > 0 && (digitos.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digitos[i]);
    }
    final sinal = arredondado < 0 ? '-' : '';
    return decimal == 0
        ? '$sinal$buffer'
        : '$sinal$buffer,${decimal.toString().padLeft(2, '0')}';
  }

  /// O documento do produtor sem o rótulo que o cadastro pode carregar: ele é
  /// gravado como o admin digitou ("CPF 123.456.789-00"), e na cédula a palavra
  /// "CPF" já está na frase.
  static String _digitos(String documento) =>
      documento.replaceAll(RegExp(r'^\s*(CPF|CNPJ)\s*', caseSensitive: false), '').trim();

  static String _ou(String? valor, String vazio) =>
      (valor == null || valor.trim().isEmpty) ? vazio : valor.trim();

  static const _romanos = ['i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix', 'x'];

  static String _romano(int n) => n <= _romanos.length ? _romanos[n - 1] : '$n';
}

/// Um bloco de assinatura do documento.
class CprSignature {
  final String role;
  final String name;
  final String qualification;
  final String address;
  final String document;
  final String? coopId;

  const CprSignature({
    required this.role,
    required this.name,
    required this.qualification,
    required this.address,
    required this.document,
    required this.coopId,
  });
}
