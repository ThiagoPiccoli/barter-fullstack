/// A CÉDULA DE PRODUTO RURAL (CPR) — o documento que o faturista monta a partir
/// de uma permuta faturável.
///
/// O documento tem TRÊS FONTES, e a divisão é o que explica este arquivo
/// inteiro (a mesma de `api/src/barters/cpr.ts`):
///
/// 1. o que a PERMUTA já sabe — emitente, sacas, produto, preço, valor, safra.
///    Vem em [CprKnown], resolvido pelo servidor, e a tela mostra como LEITURA:
///    um número na cédula que discorde do registro é um título cobrando o que
///    não foi acordado;
/// 2. quem é a CREDORA — [CprCreditor], configuração da instalação. Aparece
///    em quatro cláusulas do documento e é sempre a mesma empresa;
/// 3. o que o FATURISTA preenche — [CprDraft]: a qualificação civil do
///    emitente, as lavouras dadas em penhor, o padrão do grão e os números da
///    nota e da duplicata.
///
/// Nada aqui calcula nada. Os quilos, o valor total e o que ainda falta chegam
/// prontos do servidor pelo mesmo motivo de `statusLabel` e `waitingFor`: a
/// regra do que a cédula exige mora num lugar só, e uma exigência nova aparece
/// nas telas já instaladas sem versão nova do app.
library;

double _asDouble(Object? value) => (value as num?)?.toDouble() ?? 0;

DateTime? _asDateOrNull(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

String _asText(Object? value) => (value ?? '').toString();

/// A parte que a permuta responde e ninguém digita.
class CprKnown {
  final String barterCode;
  final String emitterName;
  final String emitterDocument;
  final String grainName;

  /// Sacas do grão — a quantidade da cláusula III e a do penhor (cláusula VI).
  final double sacks;

  /// `sacas × peso da saca`: o "[QUANTIDADE] kg" do documento.
  final double quantityKg;
  final double sackPrice;

  /// `sacas × preço da saca` — o valor de emissão e o referencial da cédula.
  final double totalValue;

  /// A gestão em que a permuta foi fechada (`S2026.02`) — a safra do documento.
  final String versionCode;

  /// A UNIDADE DE RETIRADA da permuta — a SUGESTÃO para o local da entrega.
  ///
  /// Sugestão, e não o valor: retirar insumo na Filial 02 não obriga a entregar
  /// o grão lá. Ela existe porque é o palpite certo na maioria das vezes.
  final String pickupUnit;

  const CprKnown({
    this.barterCode = '',
    this.emitterName = '',
    this.emitterDocument = '',
    this.grainName = '',
    this.sacks = 0,
    this.quantityKg = 0,
    this.sackPrice = 0,
    this.totalValue = 0,
    this.versionCode = '',
    this.pickupUnit = '',
  });

  factory CprKnown.fromJson(Map<String, dynamic> json) => CprKnown(
        barterCode: _asText(json['barterCode']),
        emitterName: _asText(json['emitterName']),
        emitterDocument: _asText(json['emitterDocument']),
        grainName: _asText(json['grainName']),
        sacks: _asDouble(json['sacks']),
        quantityKg: _asDouble(json['quantityKg']),
        sackPrice: _asDouble(json['sackPrice']),
        totalValue: _asDouble(json['totalValue']),
        versionCode: _asText(json['versionCode']),
        pickupUnit: _asText(json['pickupUnit']),
      );
}

/// A empresa que recebe o grão, como o documento a nomeia — o CADASTRO dela.
///
/// Ela aparece em quatro cláusulas da CPR e é sempre a mesma, então não é do
/// formulário da cédula: é cadastro, mantido pelo admin **ou pelo faturista**
/// (ver `Capability.creditorManage`). O faturista está aí de propósito — quem
/// percebe que o CNPJ saiu com um dígito trocado é quem monta a cédula.
class CprCreditor {
  final String name;
  final String cnpj;
  final String address;
  final String addressNumber;
  final String city;

  /// O foro ELEITO (cláusula XX). Vazio não é lacuna: significa "a comarca da
  /// sede", que é o que quase toda credora elege.
  final String forum;

  /// O foro que VALE — o eleito, ou a cidade. Vem resolvido do servidor pelo
  /// mesmo motivo de `statusLabel`: a tela não deveria precisar conhecer a
  /// regra do vazio para saber o que sai impresso.
  final String effectiveForum;

  /// O que falta para uma cédula sair completa. Lista SEPARADA da pendência da
  /// cédula: quem resolve esta é quem tem o cadastro na mão.
  final List<String> gaps;

  final String updatedBy;
  final DateTime? updatedAt;

  const CprCreditor({
    this.name = '',
    this.cnpj = '',
    this.address = '',
    this.addressNumber = '',
    this.city = '',
    this.forum = '',
    this.effectiveForum = '',
    this.gaps = const [],
    this.updatedBy = '',
    this.updatedAt,
  });

  factory CprCreditor.fromJson(Map<String, dynamic> json) => CprCreditor(
        name: _asText(json['name']),
        cnpj: _asText(json['cnpj']),
        address: _asText(json['address']),
        addressNumber: _asText(json['addressNumber']),
        city: _asText(json['city']),
        forum: _asText(json['forum']),
        effectiveForum: _asText(json['effectiveForum']),
        gaps: ((json['gaps'] as List?) ?? const []).map((g) => '$g').toList(),
        updatedBy: _asText(json['updatedBy']),
        updatedAt: _asDateOrNull(json['updatedAt']),
      );

  /// O corpo do `PUT`. Vai INTEIRO, e campo vazio APAGA — ao contrário do
  /// rascunho da cédula. A diferença é o formulário: este é curto e lido de
  /// cima a baixo antes de salvar, e preservar o ausente tornaria impossível
  /// apagar um foro eleito que deixou de valer.
  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'cnpj': cnpj.trim(),
        'address': address.trim(),
        'addressNumber': addressNumber.trim(),
        'city': city.trim(),
        'forum': forum.trim(),
      };

  /// Já dá para emitir cédula com este cadastro?
  bool get isComplete => gaps.isEmpty;
}

/// O PROPRIETÁRIO de uma lavoura — que raramente é o emitente: a área
/// penhorada costuma ser arrendada, e é por isso que o documento nomeia o dono
/// do imóvel separadamente de quem planta.
class CprOwner {
  final String name;
  final String document;

  const CprOwner({this.name = '', this.document = ''});

  factory CprOwner.fromJson(Map<String, dynamic> json) => CprOwner(
        name: _asText(json['name']),
        document: _asText(json['document']),
      );

  Map<String, dynamic> toJson() => {'name': name.trim(), 'document': document.trim()};

  CprOwner copyWith({String? name, String? document}) =>
      CprOwner(name: name ?? this.name, document: document ?? this.document);
}

/// UMA LAVOURA dada em penhor — o "(i)", o "(ii)" e quantos mais houver.
///
/// É lista, e não dois blocos de campos, porque o documento é uma enumeração: o
/// produtor planta em quantas áreas plantar. A ORDEM é conteúdo — as áreas são
/// citadas por posição no texto.
class CprArea {
  final String locality;
  final String city;
  final double areaHa;

  /// O "dentro de uma área maior": o plantio ocupa parte do imóvel. Muda a
  /// frase do documento, e é a diferença entre penhorar a lavoura e parecer
  /// penhorar a fazenda inteira.
  final bool withinLargerArea;
  final String registryNumber;
  final String registryBook;
  final String registryDistrict;
  final List<CprOwner> owners;

  const CprArea({
    this.locality = '',
    this.city = '',
    this.areaHa = 0,
    this.withinLargerArea = false,
    this.registryNumber = '',
    this.registryBook = '',
    this.registryDistrict = '',
    this.owners = const [],
  });

  factory CprArea.fromJson(Map<String, dynamic> json) => CprArea(
        locality: _asText(json['locality']),
        city: _asText(json['city']),
        areaHa: _asDouble(json['areaHa']),
        withinLargerArea: json['withinLargerArea'] == true,
        registryNumber: _asText(json['registryNumber']),
        registryBook: _asText(json['registryBook']),
        registryDistrict: _asText(json['registryDistrict']),
        owners: ((json['owners'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(CprOwner.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'locality': locality.trim(),
        'city': city.trim(),
        'areaHa': areaHa,
        'withinLargerArea': withinLargerArea,
        'registryNumber': registryNumber.trim(),
        'registryBook': registryBook.trim(),
        'registryDistrict': registryDistrict.trim(),
        'owners': owners.map((o) => o.toJson()).toList(),
      };

  CprArea copyWith({
    String? locality,
    String? city,
    double? areaHa,
    bool? withinLargerArea,
    String? registryNumber,
    String? registryBook,
    String? registryDistrict,
    List<CprOwner>? owners,
  }) =>
      CprArea(
        locality: locality ?? this.locality,
        city: city ?? this.city,
        areaHa: areaHa ?? this.areaHa,
        withinLargerArea: withinLargerArea ?? this.withinLargerArea,
        registryNumber: registryNumber ?? this.registryNumber,
        registryBook: registryBook ?? this.registryBook,
        registryDistrict: registryDistrict ?? this.registryDistrict,
        owners: owners ?? this.owners,
      );
}

/// O AVALISTA — quem garante a obrigação do emitente com o próprio patrimônio.
///
/// Ele vem da PLANILHA DE PROPOSTA, e não do modelo de cédula: o texto que a
/// operação usa hoje não tem cláusula de aval nem bloco de assinatura para ele.
/// Por isso é COLETADO e não IMPRESSO — o dado fica guardado, e o documento
/// continua sendo exatamente o modelo aprovado.
///
/// A forma é a mesma da qualificação do emitente, campo por campo: para o
/// direito os dois são a mesma coisa — pessoas que se obrigam.
class CprGuarantor {
  final String name;
  final String document;
  final String rg;
  final String cnh;
  final String nationality;
  final String profession;
  final String maritalStatus;
  final String fatherName;
  final String motherName;
  final String email;
  final String address;
  final String addressNumber;
  final String city;
  final String spouseName;
  final String spouseDocument;
  final String spouseRg;
  final String spouseNationality;
  final String spouseProfession;

  const CprGuarantor({
    this.name = '',
    this.document = '',
    this.rg = '',
    this.cnh = '',
    this.nationality = '',
    this.profession = '',
    this.maritalStatus = '',
    this.fatherName = '',
    this.motherName = '',
    this.email = '',
    this.address = '',
    this.addressNumber = '',
    this.city = '',
    this.spouseName = '',
    this.spouseDocument = '',
    this.spouseRg = '',
    this.spouseNationality = '',
    this.spouseProfession = '',
  });

  factory CprGuarantor.fromJson(Map<String, dynamic> json) => CprGuarantor(
        name: _asText(json['name']),
        document: _asText(json['document']),
        rg: _asText(json['rg']),
        cnh: _asText(json['cnh']),
        nationality: _asText(json['nationality']),
        profession: _asText(json['profession']),
        maritalStatus: _asText(json['maritalStatus']),
        fatherName: _asText(json['fatherName']),
        motherName: _asText(json['motherName']),
        email: _asText(json['email']),
        address: _asText(json['address']),
        addressNumber: _asText(json['addressNumber']),
        city: _asText(json['city']),
        spouseName: _asText(json['spouseName']),
        spouseDocument: _asText(json['spouseDocument']),
        spouseRg: _asText(json['spouseRg']),
        spouseNationality: _asText(json['spouseNationality']),
        spouseProfession: _asText(json['spouseProfession']),
      );

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'document': document.trim(),
        'rg': rg.trim(),
        'cnh': cnh.trim(),
        'nationality': nationality.trim(),
        'profession': profession.trim(),
        'maritalStatus': maritalStatus.trim(),
        'fatherName': fatherName.trim(),
        'motherName': motherName.trim(),
        'email': email.trim(),
        'address': address.trim(),
        'addressNumber': addressNumber.trim(),
        'city': city.trim(),
        'spouseName': spouseName.trim(),
        'spouseDocument': spouseDocument.trim(),
        'spouseRg': spouseRg.trim(),
        'spouseNationality': spouseNationality.trim(),
        'spouseProfession': spouseProfession.trim(),
      };

  /// O bloco do cônjuge do avalista só é pedido de quem é casado — a mesma
  /// regra do emitente, e pelo mesmo motivo (regime de bens).
  bool get needsSpouse {
    final n = maritalStatus.toLowerCase();
    return n.contains('casad') || n.contains('uniao estavel') || n.contains('união está');
  }

  CprGuarantor copyWith({
    String? name,
    String? document,
    String? rg,
    String? cnh,
    String? nationality,
    String? profession,
    String? maritalStatus,
    String? fatherName,
    String? motherName,
    String? email,
    String? address,
    String? addressNumber,
    String? city,
    String? spouseName,
    String? spouseDocument,
    String? spouseRg,
    String? spouseNationality,
    String? spouseProfession,
  }) =>
      CprGuarantor(
        name: name ?? this.name,
        document: document ?? this.document,
        rg: rg ?? this.rg,
        cnh: cnh ?? this.cnh,
        nationality: nationality ?? this.nationality,
        profession: profession ?? this.profession,
        maritalStatus: maritalStatus ?? this.maritalStatus,
        fatherName: fatherName ?? this.fatherName,
        motherName: motherName ?? this.motherName,
        email: email ?? this.email,
        address: address ?? this.address,
        addressNumber: addressNumber ?? this.addressNumber,
        city: city ?? this.city,
        spouseName: spouseName ?? this.spouseName,
        spouseDocument: spouseDocument ?? this.spouseDocument,
        spouseRg: spouseRg ?? this.spouseRg,
        spouseNationality: spouseNationality ?? this.spouseNationality,
        spouseProfession: spouseProfession ?? this.spouseProfession,
      );
}

/// O RASCUNHO da cédula — o que o faturista preencheu até agora.
///
/// Ele é salvável pela metade de propósito: a qualificação o faturista tem na
/// mão quando pega o documento, o número da nota só existe depois de ela ser
/// emitida, e a matrícula da lavoura costuma vir por e-mail no dia seguinte. O
/// vazio aqui significa "ainda não preenchido", e quem diz o que falta é o
/// servidor, em [CprDesk.gaps].
class CprDraft {
  final String number;
  final DateTime? issuedAt;
  final DateTime? dueDate;

  final String emitterNationality;
  final String emitterMaritalStatus;
  final String emitterProfession;
  final String emitterRg;
  final String emitterAddress;
  final String emitterAddressNumber;
  final String emitterCity;
  final String emitterCoopId;

  /// O QUE A PROPOSTA PEDE E A CÉDULA NÃO IMPRIME.
  ///
  /// CNH, filiação e e-mail não aparecem em cláusula nenhuma do modelo — quem
  /// os pede é a planilha de proposta, e por trás dela o cartório (a filiação
  /// individualiza um homônimo no registro) e a operação (o e-mail é por onde a
  /// assinatura eletrônica chega). Eles são coletados e NÃO entram em
  /// [CprDesk.gaps]: quem decide o que falta é o documento.
  final String emitterCnh;
  final String emitterFatherName;
  final String emitterMotherName;
  final String emitterEmail;

  /// O LOCAL DA ENTREGA do grão (cláusula V, "d"). Este SAI no documento, e por
  /// isso É cobrado. É campo próprio, e não a unidade da permuta: retirar
  /// insumo na Filial 02 não obriga a entregar o grão lá.
  final String deliveryPlace;

  /// Hipotecas oferecidas, como a proposta as pede: texto livre. Coletadas, não
  /// impressas — o modelo não tem cláusula para elas.
  final String mortgages;

  /// Os AVALISTAS. Coletados, não impressos. Ver [CprGuarantor].
  final List<CprGuarantor> guarantors;

  /// A ANUÊNCIA DO CÔNJUGE. Vazio é o caso comum, e não uma pendência: só o
  /// emitente casado assina acompanhado. O estado civil e o endereço do cônjuge
  /// não são campos — o primeiro é o do emitente (é o que faz dele cônjuge) e o
  /// segundo é o mesmo domicílio.
  final String spouseName;
  final String spouseNationality;
  final String spouseProfession;
  final String spouseDocument;

  /// RG do cônjuge — da proposta; o modelo qualifica o cônjuge por CPF.
  final String spouseRg;

  final double sackWeightKg;
  final String cultivar;
  final double maxMoisture;
  final double maxImpurities;
  final double oilContent;

  final String invoiceNumber;
  final String duplicateNumber;
  final String insurancePolicy;

  final List<CprArea> areas;

  /// Quem mexeu por último, e quando. Dois faturistas dividem a fila, e "isto
  /// está como eu deixei?" é a primeira pergunta de quem reabre um rascunho.
  final String filledBy;
  final DateTime? updatedAt;

  const CprDraft({
    this.number = '',
    this.issuedAt,
    this.dueDate,
    this.emitterNationality = '',
    this.emitterMaritalStatus = '',
    this.emitterProfession = '',
    this.emitterRg = '',
    this.emitterAddress = '',
    this.emitterAddressNumber = '',
    this.emitterCity = '',
    this.emitterCoopId = '',
    this.emitterCnh = '',
    this.emitterFatherName = '',
    this.emitterMotherName = '',
    this.emitterEmail = '',
    this.deliveryPlace = '',
    this.mortgages = '',
    this.guarantors = const [],
    this.spouseName = '',
    this.spouseNationality = '',
    this.spouseProfession = '',
    this.spouseDocument = '',
    this.spouseRg = '',
    this.sackWeightKg = 60,
    this.cultivar = '',
    this.maxMoisture = 0,
    this.maxImpurities = 0,
    this.oilContent = 0,
    this.invoiceNumber = '',
    this.duplicateNumber = '',
    this.insurancePolicy = '',
    this.areas = const [],
    this.filledBy = '',
    this.updatedAt,
  });

  factory CprDraft.fromJson(Map<String, dynamic> json) => CprDraft(
        number: _asText(json['number']),
        issuedAt: _asDateOrNull(json['issuedAt']),
        dueDate: _asDateOrNull(json['dueDate']),
        emitterNationality: _asText(json['emitterNationality']),
        emitterMaritalStatus: _asText(json['emitterMaritalStatus']),
        emitterProfession: _asText(json['emitterProfession']),
        emitterRg: _asText(json['emitterRg']),
        emitterAddress: _asText(json['emitterAddress']),
        emitterAddressNumber: _asText(json['emitterAddressNumber']),
        emitterCity: _asText(json['emitterCity']),
        emitterCoopId: _asText(json['emitterCoopId']),
        emitterCnh: _asText(json['emitterCnh']),
        emitterFatherName: _asText(json['emitterFatherName']),
        emitterMotherName: _asText(json['emitterMotherName']),
        emitterEmail: _asText(json['emitterEmail']),
        deliveryPlace: _asText(json['deliveryPlace']),
        mortgages: _asText(json['mortgages']),
        guarantors: ((json['guarantors'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(CprGuarantor.fromJson)
            .toList(),
        spouseName: _asText(json['spouseName']),
        spouseNationality: _asText(json['spouseNationality']),
        spouseProfession: _asText(json['spouseProfession']),
        spouseDocument: _asText(json['spouseDocument']),
        // O RG do cônjuge é lido como todos os outros, e a linha existe porque
        // já faltou: o campo estava no construtor, no `toJson` e no `copyWith`,
        // e só não aqui. O efeito não era o RG "não aparecer" — era a tela
        // reabrir o campo VAZIO e a gravação seguinte mandar `''` por cima do
        // que estava guardado. Campo que se envia e não se lê apaga o próprio
        // dado no salvamento seguinte.
        spouseRg: _asText(json['spouseRg']),
        // O peso da saca só cai no padrão do mercado quando o servidor não
        // mandou nenhum: zero aqui viraria uma cédula prometendo zero quilo.
        sackWeightKg: _asDouble(json['sackWeightKg']) > 0 ? _asDouble(json['sackWeightKg']) : 60,
        cultivar: _asText(json['cultivar']),
        maxMoisture: _asDouble(json['maxMoisture']),
        maxImpurities: _asDouble(json['maxImpurities']),
        oilContent: _asDouble(json['oilContent']),
        invoiceNumber: _asText(json['invoiceNumber']),
        duplicateNumber: _asText(json['duplicateNumber']),
        insurancePolicy: _asText(json['insurancePolicy']),
        areas: ((json['areas'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(CprArea.fromJson)
            .toList(),
        filledBy: _asText(json['filledBy']),
        updatedAt: _asDateOrNull(json['updatedAt']),
      );

  /// O corpo do `PUT`. Vai INTEIRO — a tela devolve o formulário todo, e é o
  /// servidor que trata campo ausente como "mantém o que está gravado".
  ///
  /// `filledBy` e `updatedAt` não vão: quem preencheu é quem está com a sessão
  /// aberta, e o servidor não pergunta isso ao cliente.
  Map<String, dynamic> toJson() => {
        'number': number.trim(),
        if (issuedAt != null) 'issuedAt': issuedAt!.toUtc().toIso8601String(),
        if (dueDate != null) 'dueDate': dueDate!.toUtc().toIso8601String(),
        'emitterNationality': emitterNationality.trim(),
        'emitterMaritalStatus': emitterMaritalStatus.trim(),
        'emitterProfession': emitterProfession.trim(),
        'emitterRg': emitterRg.trim(),
        'emitterAddress': emitterAddress.trim(),
        'emitterAddressNumber': emitterAddressNumber.trim(),
        'emitterCity': emitterCity.trim(),
        'emitterCoopId': emitterCoopId.trim(),
        'emitterCnh': emitterCnh.trim(),
        'emitterFatherName': emitterFatherName.trim(),
        'emitterMotherName': emitterMotherName.trim(),
        'emitterEmail': emitterEmail.trim(),
        'deliveryPlace': deliveryPlace.trim(),
        'mortgages': mortgages.trim(),
        'guarantors': guarantors.map((g) => g.toJson()).toList(),
        'spouseName': spouseName.trim(),
        'spouseNationality': spouseNationality.trim(),
        'spouseProfession': spouseProfession.trim(),
        'spouseDocument': spouseDocument.trim(),
        'spouseRg': spouseRg.trim(),
        'sackWeightKg': sackWeightKg,
        'cultivar': cultivar.trim(),
        'maxMoisture': maxMoisture,
        'maxImpurities': maxImpurities,
        'oilContent': oilContent,
        'invoiceNumber': invoiceNumber.trim(),
        'duplicateNumber': duplicateNumber.trim(),
        'insurancePolicy': insurancePolicy.trim(),
        'areas': areas.map((a) => a.toJson()).toList(),
      };

  /// O rascunho com a SUGESTÃO do servidor por cima — o que a tela abre quando
  /// ainda não há cédula.
  ///
  /// A sugestão vem da última cédula do mesmo produtor, e é sugestão mesmo: ela
  /// só chega quando não há rascunho nenhum (o servidor a omite depois disso),
  /// justamente para não sobrescrever uma correção que alguém acabou de fazer.
  factory CprDraft.fromSuggestion(Map<String, dynamic> suggestion) =>
      CprDraft.fromJson(suggestion);

  CprDraft copyWith({
    String? number,
    DateTime? issuedAt,
    DateTime? dueDate,
    String? emitterNationality,
    String? emitterMaritalStatus,
    String? emitterProfession,
    String? emitterRg,
    String? emitterAddress,
    String? emitterAddressNumber,
    String? emitterCity,
    String? emitterCoopId,
    String? emitterCnh,
    String? emitterFatherName,
    String? emitterMotherName,
    String? emitterEmail,
    String? deliveryPlace,
    String? mortgages,
    List<CprGuarantor>? guarantors,
    String? spouseName,
    String? spouseNationality,
    String? spouseProfession,
    String? spouseDocument,
    String? spouseRg,
    double? sackWeightKg,
    String? cultivar,
    double? maxMoisture,
    double? maxImpurities,
    double? oilContent,
    String? invoiceNumber,
    String? duplicateNumber,
    String? insurancePolicy,
    List<CprArea>? areas,
  }) =>
      CprDraft(
        number: number ?? this.number,
        issuedAt: issuedAt ?? this.issuedAt,
        dueDate: dueDate ?? this.dueDate,
        emitterNationality: emitterNationality ?? this.emitterNationality,
        emitterMaritalStatus: emitterMaritalStatus ?? this.emitterMaritalStatus,
        emitterProfession: emitterProfession ?? this.emitterProfession,
        emitterRg: emitterRg ?? this.emitterRg,
        emitterAddress: emitterAddress ?? this.emitterAddress,
        emitterAddressNumber: emitterAddressNumber ?? this.emitterAddressNumber,
        emitterCity: emitterCity ?? this.emitterCity,
        emitterCoopId: emitterCoopId ?? this.emitterCoopId,
        emitterCnh: emitterCnh ?? this.emitterCnh,
        emitterFatherName: emitterFatherName ?? this.emitterFatherName,
        emitterMotherName: emitterMotherName ?? this.emitterMotherName,
        emitterEmail: emitterEmail ?? this.emitterEmail,
        deliveryPlace: deliveryPlace ?? this.deliveryPlace,
        mortgages: mortgages ?? this.mortgages,
        guarantors: guarantors ?? this.guarantors,
        spouseName: spouseName ?? this.spouseName,
        spouseNationality: spouseNationality ?? this.spouseNationality,
        spouseProfession: spouseProfession ?? this.spouseProfession,
        spouseDocument: spouseDocument ?? this.spouseDocument,
        spouseRg: spouseRg ?? this.spouseRg,
        sackWeightKg: sackWeightKg ?? this.sackWeightKg,
        cultivar: cultivar ?? this.cultivar,
        maxMoisture: maxMoisture ?? this.maxMoisture,
        maxImpurities: maxImpurities ?? this.maxImpurities,
        oilContent: oilContent ?? this.oilContent,
        invoiceNumber: invoiceNumber ?? this.invoiceNumber,
        duplicateNumber: duplicateNumber ?? this.duplicateNumber,
        insurancePolicy: insurancePolicy ?? this.insurancePolicy,
        areas: areas ?? this.areas,
        filledBy: filledBy,
        updatedAt: updatedAt,
      );

  /// O ESTADO CIVIL que exige a anuência do cônjuge. Espelha `requiresSpouse`
  /// da API — aqui só para a tela mostrar ou esconder o bloco; quem cobra o
  /// preenchimento continua sendo o servidor, em [CprDesk.gaps].
  bool get needsSpouse {
    final normalized = emitterMaritalStatus.toLowerCase();
    return normalized.contains('casad') ||
        normalized.contains('uniao estavel') ||
        normalized.contains('união estável') ||
        normalized.contains('união estavel') ||
        normalized.contains('uniao estável');
  }
}

/// A MESA DA CÉDULA: tudo o que a tela do faturista precisa, numa resposta só.
class CprDesk {
  /// O rascunho gravado. Null quando ninguém começou a preencher.
  final CprDraft? cpr;
  final CprKnown known;
  final CprCreditor creditor;

  /// O que falta CONFIGURAR (a credora) e o que falta PREENCHER (a cédula).
  ///
  /// São listas separadas porque quem resolve cada uma é outra pessoa: a
  /// segunda é do faturista, ali mesmo; a primeira é de quem administra o
  /// servidor. Somadas, a tela mandaria o faturista procurar um campo de CNPJ
  /// que não existe no formulário dele.
  final List<String> creditorGaps;
  final List<String> gaps;

  final bool complete;

  /// A sugestão de preenchimento, vinda da última cédula do mesmo produtor.
  /// Vazia quando já existe rascunho.
  final CprDraft? suggestion;

  const CprDesk({
    this.cpr,
    this.known = const CprKnown(),
    this.creditor = const CprCreditor(),
    this.creditorGaps = const [],
    this.gaps = const [],
    this.complete = false,
    this.suggestion,
  });

  factory CprDesk.fromJson(Map<String, dynamic> json) {
    final suggestion = (json['suggestion'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CprDesk(
      cpr: json['cpr'] == null
          ? null
          : CprDraft.fromJson((json['cpr'] as Map).cast<String, dynamic>()),
      known: CprKnown.fromJson((json['known'] as Map?)?.cast<String, dynamic>() ?? const {}),
      creditor:
          CprCreditor.fromJson((json['creditor'] as Map?)?.cast<String, dynamic>() ?? const {}),
      creditorGaps: ((json['creditorGaps'] as List?) ?? const []).map((g) => '$g').toList(),
      gaps: ((json['gaps'] as List?) ?? const []).map((g) => '$g').toList(),
      complete: json['complete'] == true,
      suggestion: suggestion.isEmpty ? null : CprDraft.fromSuggestion(suggestion),
    );
  }

  /// O rascunho com que a tela ABRE: o gravado, ou a sugestão, ou o vazio.
  ///
  /// A data de emissão de uma cédula que ainda não existe é HOJE — é a resposta
  /// certa na esmagadora maioria das vezes, e é editável nas outras.
  CprDraft get startingPoint {
    if (cpr != null) return cpr!;
    final base = (suggestion ?? const CprDraft()).copyWith(issuedAt: DateTime.now());
    // O LOCAL DA ENTREGA nasce com a unidade de retirada da permuta. É sugestão
    // — o campo continua editável, e a cédula anterior não o traz de propósito:
    // ele é da negociação, não da pessoa.
    return base.deliveryPlace.isEmpty && known.pickupUnit.isNotEmpty
        ? base.copyWith(deliveryPlace: known.pickupUnit)
        : base;
  }
}
