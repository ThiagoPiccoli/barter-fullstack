import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_data.dart';
import '../models/models.dart';
import '../services/api/api_client.dart';
import '../services/cpr_docx.dart';
import 'package:file_saver/file_saver.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'creditor_screen.dart';

/// O PREENCHIMENTO DA CÉDULA DE PRODUTO RURAL (CPR) — a tela do faturista.
///
/// A cédula é o título que formaliza a entrega do grão: o produtor emite, a
/// empresa é a credora, e o documento é registrado na B3. Ela é o desfecho
/// jurídico do que a permuta já acordou — e por isso esta tela é dividida em
/// TRÊS BLOCOS, que são as três fontes do documento:
///
/// 1. **O que a permuta já sabe** (o cartão do topo): emitente, CPF, sacas,
///    produto, preço, valor, safra. É LEITURA, não campo. Um número na cédula
///    que discorde do registro é um título cobrando o que não foi acordado;
/// 2. **A credora**: configuração da instalação, mostrada para conferência. Se
///    faltar, a pendência é endereçada a quem administra o servidor — e não ao
///    faturista, que não tem onde resolvê-la;
/// 3. **O que falta preencher**: tudo o mais. A qualificação civil do emitente
///    (a lei pede nacionalidade, estado civil, profissão, RG e endereço), as
///    lavouras dadas em penhor com as matrículas, o padrão de qualidade do grão
///    e os números da nota e da duplicata.
///
/// O RASCUNHO É SALVÁVEL PELA METADE, e isso é a decisão de desenho da tela: a
/// qualificação o faturista tem quando pega o documento na mão, o número da
/// nota só existe depois de ela ser emitida, a matrícula costuma vir por e-mail
/// no dia seguinte. Um formulário que só aceitasse tudo de uma vez recusaria
/// exatamente o estado em que o trabalho passa a maior parte do tempo — e o
/// rascunho voltaria para o papel ao lado do computador.
///
/// QUEM DIZ O QUE FALTA é o servidor ([CprDesk.gaps]), e não uma validação
/// local: a regra do que o documento exige mora em um lugar só, e uma exigência
/// nova aparece nas telas já instaladas sem versão nova do app. As validações
/// daqui são de FORMATO (número onde se espera número), não de completude.
/// Abre o FATURAMENTO de uma permuta — que é esta tela.
///
/// Existe como função porque o ato é chamado de três lugares (o detalhe, a fila
/// do painel e a lista de permutas), e os três precisam saber da permuta
/// atualizada quando ela volta faturada.
void openInvoicing(
  BuildContext context,
  BarterModel barter, {
  required ValueChanged<BarterModel> onInvoiced,
}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => CprFormScreen(barter: barter, onInvoiced: onInvoiced),
  ));
}

/// A SEGUNDA VIA da cédula: busca a mesa e entrega o .docx, sem abrir formulário.
///
/// É o caminho de quem LÊ a cédula sem preenchê-la — hoje, o admin. Ele não
/// passa pela tela do faturista de propósito: aquela tela é a mesa de trabalho
/// de um posto (tem *Faturar*, tem rascunho, tem campo de matrícula), e abri-la
/// para quem não fatura ofereceria botões que o servidor recusaria.
///
/// A regra de completude é a MESMA da tela: cédula com lacuna não vira arquivo.
/// Um documento que parece pronto e não é seria pior do que não gerar — e o que
/// falta é dito por extenso, porque quem lê aqui não é quem preenche, e precisa
/// saber a quem pedir.
Future<void> generateCprDocument(BuildContext context, BarterModel barter) async {
  final messenger = ScaffoldMessenger.of(context);
  void fail(String message) => messenger.showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );

  try {
    final desk = await AppData.barterCpr(barter.id);
    if (!desk.complete) {
      // As duas listas continuam separadas aqui pelo mesmo motivo da tela: a
      // credora é do admin e a cédula é do faturista, e juntá-las mandaria a
      // pessoa procurar o campo errado.
      final pending = [
        if (desk.creditorGaps.isNotEmpty) 'na credora: ${desk.creditorGaps.join(', ')}',
        if (desk.gaps.isNotEmpty) 'na cédula: ${desk.gaps.join(', ')}',
      ].join(' • ');
      fail('A cédula de ${barter.id} ainda tem lacunas: $pending.');
      return;
    }

    await FileSaver.instance.saveFile(
      name: 'cpr-${CprDocx.filename(desk)}',
      bytes: CprDocx.build(desk),
      ext: 'docx',
      mimeType: MimeType.microsoftWord,
    );
    messenger.showSnackBar(SnackBar(
      content: const Text('CPR gerada em Word.'),
      backgroundColor: AppColors.approved,
      behavior: SnackBarBehavior.floating,
    ));
  } on ApiException catch (e) {
    fail(e.message);
  } catch (e) {
    fail('Não foi possível gerar a CPR: $e');
  }
}

class CprFormScreen extends StatefulWidget {
  /// A permuta que está sendo faturada — ou cuja cédula já emitida se corrige.
  final BarterModel barter;

  /// Avisa quem abriu a tela que a permuta mudou de estado. Null quando ela é
  /// aberta só para ver/corrigir a cédula de uma permuta já faturada.
  final ValueChanged<BarterModel>? onInvoiced;

  const CprFormScreen({super.key, required this.barter, this.onInvoiced});

  @override
  State<CprFormScreen> createState() => _CprFormScreenState();
}

class _CprFormScreenState extends State<CprFormScreen> {
  final _formKey = GlobalKey<FormState>();

  CprDesk? _desk;
  Object? _loadError;
  bool _saving = false;
  bool _generating = false;
  bool _invoicing = false;

  /// A permuta como ela está AGORA. Ela muda de estado dentro desta tela — é
  /// aqui que o faturamento acontece —, e o rodapé lê isto para saber se o ato
  /// que falta é faturar ou apenas gerar o documento de novo.
  late BarterModel _barter = widget.barter;

  /// As lavouras vivem em estado, e não em controllers: elas entram e saem da
  /// lista, e um `TextEditingController` por campo de uma lista que muda de
  /// tamanho é a receita de campo colado no índice errado depois de uma
  /// remoção. Cada linha da lista se redesenha a partir daqui.
  List<CprArea> _areas = const [];

  /// Os AVALISTAS, pelo mesmo motivo das lavouras: a lista muda de tamanho, e
  /// controller por campo de lista variável cola texto no índice errado depois
  /// de uma remoção.
  List<CprGuarantor> _guarantors = const [];

  DateTime? _issuedAt;
  DateTime? _dueDate;

  final _number = TextEditingController();
  final _nationality = TextEditingController();
  final _maritalStatus = TextEditingController();
  final _profession = TextEditingController();
  final _rg = TextEditingController();
  final _address = TextEditingController();
  final _addressNumber = TextEditingController();
  final _city = TextEditingController();
  final _coopId = TextEditingController();
  final _cnh = TextEditingController();
  final _fatherName = TextEditingController();
  final _motherName = TextEditingController();
  final _email = TextEditingController();
  final _deliveryPlace = TextEditingController();
  final _mortgages = TextEditingController();
  final _spouseRg = TextEditingController();
  final _spouseName = TextEditingController();
  final _spouseNationality = TextEditingController();
  final _spouseProfession = TextEditingController();
  final _spouseDocument = TextEditingController();
  final _sackWeight = TextEditingController();
  final _cultivar = TextEditingController();
  final _moisture = TextEditingController();
  final _impurities = TextEditingController();
  final _oil = TextEditingController();
  final _invoiceNumber = TextEditingController();
  final _duplicateNumber = TextEditingController();
  final _insurancePolicy = TextEditingController();

  List<TextEditingController> get _all => [
        _number,
        _nationality,
        _maritalStatus,
        _profession,
        _rg,
        _address,
        _addressNumber,
        _city,
        _coopId,
        _cnh,
        _fatherName,
        _motherName,
        _email,
        _deliveryPlace,
        _mortgages,
        _spouseRg,
        _spouseName,
        _spouseNationality,
        _spouseProfession,
        _spouseDocument,
        _sackWeight,
        _cultivar,
        _moisture,
        _impurities,
        _oil,
        _invoiceNumber,
        _duplicateNumber,
        _insurancePolicy,
      ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _all) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _desk = null;
      _loadError = null;
    });
    try {
      final desk = await AppData.barterCpr(_barter.id);
      if (!mounted) return;
      setState(() {
        _desk = desk;
        _fill(desk.startingPoint);
      });
      // O `catch` é LARGO de propósito, e não só de `ApiException`: aqui a tela
      // fica invisível enquanto `_desk` e `_loadError` são os dois nulos, e uma
      // falha de outra natureza (um formato inesperado na resposta, digamos)
      // deixava o rodinha girando para sempre — sem mensagem e sem o botão de
      // tentar de novo. `_Retry` já sabe falar de erro que não é da API.
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  /// Escreve o rascunho nos campos. É por aqui que a SUGESTÃO entra — ela vem
  /// no mesmo formato do rascunho, e o servidor só a manda quando ainda não há
  /// cédula começada (ver `startingPoint`).
  void _fill(CprDraft draft) {
    _number.text = draft.number;
    _issuedAt = draft.issuedAt;
    _dueDate = draft.dueDate;
    _nationality.text = draft.emitterNationality;
    _maritalStatus.text = draft.emitterMaritalStatus;
    _profession.text = draft.emitterProfession;
    _rg.text = draft.emitterRg;
    _address.text = draft.emitterAddress;
    _addressNumber.text = draft.emitterAddressNumber;
    _city.text = draft.emitterCity;
    _coopId.text = draft.emitterCoopId;
    _cnh.text = draft.emitterCnh;
    _fatherName.text = draft.emitterFatherName;
    _motherName.text = draft.emitterMotherName;
    _email.text = draft.emitterEmail;
    _deliveryPlace.text = draft.deliveryPlace;
    _mortgages.text = draft.mortgages;
    _spouseRg.text = draft.spouseRg;
    _spouseName.text = draft.spouseName;
    _spouseNationality.text = draft.spouseNationality;
    _spouseProfession.text = draft.spouseProfession;
    _spouseDocument.text = draft.spouseDocument;
    _sackWeight.text = _number0(draft.sackWeightKg);
    _cultivar.text = draft.cultivar;
    _moisture.text = _number0(draft.maxMoisture);
    _impurities.text = _number0(draft.maxImpurities);
    _oil.text = _number0(draft.oilContent);
    _invoiceNumber.text = draft.invoiceNumber;
    _duplicateNumber.text = draft.duplicateNumber;
    _insurancePolicy.text = draft.insurancePolicy;
    _areas = draft.areas;
    _guarantors = draft.guarantors;
  }

  /// Zero vira campo VAZIO, e não "0": nos percentuais o zero significa "ainda
  /// não preenchido" (uma umidade máxima de 0% recusaria a colheita inteira), e
  /// mostrar o número faria a pendência parecer resolvida.
  static String _number0(double value) => value == 0 ? '' : _decimal(value);

  static String _decimal(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  static double _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;

  CprDraft _collect() => CprDraft(
        number: _number.text,
        issuedAt: _issuedAt,
        dueDate: _dueDate,
        emitterNationality: _nationality.text,
        emitterMaritalStatus: _maritalStatus.text,
        emitterProfession: _profession.text,
        emitterRg: _rg.text,
        emitterAddress: _address.text,
        emitterAddressNumber: _addressNumber.text,
        emitterCity: _city.text,
        emitterCoopId: _coopId.text,
        emitterCnh: _cnh.text,
        emitterFatherName: _fatherName.text,
        emitterMotherName: _motherName.text,
        emitterEmail: _email.text,
        deliveryPlace: _deliveryPlace.text,
        mortgages: _mortgages.text,
        guarantors: _guarantors,
        spouseName: _spouseName.text,
        spouseNationality: _spouseNationality.text,
        spouseProfession: _spouseProfession.text,
        spouseDocument: _spouseDocument.text,
        spouseRg: _spouseRg.text,
        sackWeightKg: _parse(_sackWeight.text) > 0 ? _parse(_sackWeight.text) : 60,
        cultivar: _cultivar.text,
        maxMoisture: _parse(_moisture.text),
        maxImpurities: _parse(_impurities.text),
        oilContent: _parse(_oil.text),
        invoiceNumber: _invoiceNumber.text,
        duplicateNumber: _duplicateNumber.text,
        insurancePolicy: _insurancePolicy.text,
        areas: _areas,
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final desk = await AppData.saveBarterCpr(_barter.id, _collect());
      if (!mounted) return;
      setState(() {
        _desk = desk;
        _saving = false;
        // Reescreve os campos com o que o SERVIDOR gravou, e não com o que foi
        // digitado: se ele normalizar algo, a tela precisa mostrar o que ficou
        // guardado — senão a próxima gravação parte de um texto que não existe
        // no banco.
        if (desk.cpr != null) _fill(desk.cpr!);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(desk.complete
            ? 'CPR completa, pronta para gerar.'
            : 'Rascunho salvo. Faltam ${desk.gaps.length} campo(s).'),
        backgroundColor: desk.complete ? AppColors.approved : AppColors.pending,
        behavior: SnackBarBehavior.floating,
      ));
      // Largo pelo mesmo motivo do `_load`, e com um agravante: `_saving` trava
      // o botão de salvar e os dois de faturar enquanto for verdadeiro. Uma
      // falha que escapasse daqui deixaria a tela inteira sem ação, com o
      // preenchimento na mão de quem não teria mais como gravá-lo.
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnack(context, error);
    }
  }

  /// Abre o cadastro da CREDORA e recarrega a mesa ao voltar.
  ///
  /// O faturista chega aqui pelo mesmo caminho do admin, e não por um atalho de
  /// segunda classe: ele TEM a capacidade (`creditor.manage`), porque a credora
  /// é o timbre dos documentos que ele emite. Mandá-lo abrir chamado para
  /// corrigir o CNPJ do próprio empregador trocaria um campo de texto por um
  /// processo.
  ///
  /// Recarregar ao voltar não é zelo: `complete` depende do cadastro, e a tela
  /// que continuasse dizendo "falta a credora" depois de a pessoa tê-la
  /// preenchido estaria mentindo sobre o trabalho que ela acabou de fazer.
  Future<void> _openCreditor() async {
    if (!AppData.can(Capability.creditorManage)) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreditorScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      // A cédula vence na colheita, e é reemitida por safras seguidas: a janela
      // é larga o suficiente para uma retificação de emissão antiga e para um
      // vencimento a duas safras de distância.
      firstDate: DateTime(DateTime.now().year - 3),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // O TÍTULO diz o ato, e não a tela: quem chega aqui vindo de "Faturar
        // Permuta" veio faturar, e a cédula é o que ele preenche para isso.
        // Depois de faturada, o que resta é o documento.
        title: Text(_barter.awaitsInvoice
            ? 'Faturar ${_barter.id}'
            : 'Cédula de Produto Rural'),
        actions: [
          if (_desk != null) ...[
            // SALVAR mora aqui, e não no rodapé, porque o rodapé é das DUAS
            // opções de faturamento — e três botões lado a lado não caberiam
            // num celular. Ele também é secundário de verdade: os dois caminhos
            // de faturamento salvam a CPR antes de carimbar, então este botão é
            // o "guardo e volto depois".
            _saving
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                    ),
                  )
                : IconButton(
                    tooltip: 'Salvar o preenchimento',
                    onPressed: _invoicing || _generating ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                  ),
            IconButton(
              tooltip: 'Recarregar',
              onPressed: _saving || _invoicing ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ],
      ),
      body: _body(),
      bottomNavigationBar: _desk == null ? null : _saveBar(),
    );
  }

  Widget _body() {
    if (_loadError != null) {
      return _Retry(error: _loadError!, onRetry: _load);
    }
    final desk = _desk;
    if (desk == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (_barter.awaitsInvoice) ...[
            _InvoicingHeader(barter: _barter),
            const SizedBox(height: 14),
          ],
          _KnownCard(known: desk.known),
          const SizedBox(height: 16),
          _GapsCard(gaps: desk.gaps, complete: desk.complete),
          if (desk.creditorGaps.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CreditorGapsCard(gaps: desk.creditorGaps, onFix: _openCreditor),
          ],
          const SizedBox(height: 12),
          _CreditorCard(creditor: desk.creditor, onEdit: _openCreditor),
          if (desk.cpr == null && desk.suggestion != null) ...[
            const SizedBox(height: 12),
            const _SuggestionNote(),
          ],
          const SizedBox(height: 20),

          _section('IDENTIFICAÇÃO DA CÉDULA', Icons.description_outlined),
          _textField(_number, 'Nº da CPR', hint: 'Como a credora numera'),
          Row(children: [
            Expanded(
              child: _DateField(
                label: 'Data de emissão',
                value: _issuedAt,
                onTap: () => _pickDate(
                  current: _issuedAt,
                  onPicked: (d) => setState(() => _issuedAt = d),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DateField(
                label: 'Vencimento',
                value: _dueDate,
                onTap: () => _pickDate(
                  current: _dueDate,
                  onPicked: (d) => setState(() => _dueDate = d),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 14),

          _section('EMITENTE: QUALIFICAÇÃO', Icons.badge_outlined),
          Row(children: [
            Expanded(child: _textField(_nationality, 'Nacionalidade')),
            const SizedBox(width: 12),
            Expanded(child: _textField(_maritalStatus, 'Estado civil', onChanged: (_) => setState(() {}))),
          ]),
          _textField(_profession, 'Profissão'),
          _textField(_rg, 'RG'),
          Row(children: [
            Expanded(flex: 3, child: _textField(_address, 'Logradouro')),
            const SizedBox(width: 12),
            Expanded(child: _textField(_addressNumber, 'Nº')),
          ]),
          Row(children: [
            Expanded(child: _textField(_city, 'Município/UF', hint: 'Maringá/PR')),
            const SizedBox(width: 12),
            Expanded(child: _textField(_coopId, 'Matrícula na coop.')),
          ]),
          Row(children: [
            Expanded(child: _textField(_cnh, 'CNH', caps: false)),
            const SizedBox(width: 12),
            Expanded(child: _textField(_email, 'E-mail', caps: false)),
          ]),
          Row(children: [
            Expanded(child: _textField(_fatherName, 'Filiação: pai')),
            const SizedBox(width: 12),
            Expanded(child: _textField(_motherName, 'Filiação: mãe')),
          ]),
          const SizedBox(height: 14),

          // O bloco do cônjuge só aparece para quem é casado — é o que o
          // documento pede, e mostrá-lo sempre encheria a tela de campos que a
          // maioria das cédulas deixa em branco.
          if (_collect().needsSpouse) ...[
            _section('ANUÊNCIA DO CÔNJUGE', Icons.people_outline),
            _textField(_spouseName, 'Nome do cônjuge'),
            Row(children: [
              Expanded(child: _textField(_spouseDocument, 'CPF do cônjuge')),
              const SizedBox(width: 12),
              Expanded(child: _textField(_spouseRg, 'RG do cônjuge')),
            ]),
            Row(children: [
              Expanded(child: _textField(_spouseNationality, 'Nacionalidade')),
              const SizedBox(width: 12),
              Expanded(child: _textField(_spouseProfession, 'Profissão')),
            ]),
            const SizedBox(height: 14),
          ],

          _section('LOCAL DA ENTREGA', Icons.warehouse_outlined),
          _textField(
            _deliveryPlace,
            'Onde o grão será entregue',
            hint: desk.known.pickupUnit.isEmpty
                ? 'Armazém / filial'
                : 'Retirada da permuta: ${desk.known.pickupUnit}',
          ),
          const SizedBox(height: 14),

          _section('PADRÃO DO GRÃO', Icons.grass_outlined),
          Row(children: [
            Expanded(child: _textField(_cultivar, 'Cultivar')),
            const SizedBox(width: 12),
            Expanded(child: _numberField(_sackWeight, 'Peso da saca (kg)')),
          ]),
          Row(children: [
            Expanded(child: _numberField(_moisture, 'Umidade máx. (%)', percent: true)),
            const SizedBox(width: 12),
            Expanded(child: _numberField(_impurities, 'Impurezas máx. (%)', percent: true)),
            const SizedBox(width: 12),
            Expanded(child: _numberField(_oil, 'Teor de óleo (%)', percent: true)),
          ]),
          const SizedBox(height: 14),

          _section('ORIGEM DA DÍVIDA', Icons.receipt_long_outlined),
          Row(children: [
            Expanded(child: _textField(_invoiceNumber, 'Nº da nota fiscal')),
            const SizedBox(width: 12),
            Expanded(child: _textField(_duplicateNumber, 'Nº da duplicata')),
          ]),
          _textField(_insurancePolicy, 'Nº da apólice (se houver seguro)'),
          const SizedBox(height: 14),

          _section('LAVOURAS EM PENHOR', Icons.map_outlined),
          ..._areas.asMap().entries.map((entry) => _AreaCard(
                position: entry.key,
                area: entry.value,
                onChanged: (updated) => setState(() {
                  final next = [..._areas];
                  next[entry.key] = updated;
                  _areas = next;
                }),
                onRemove: () => setState(() {
                  final next = [..._areas]..removeAt(entry.key);
                  _areas = next;
                }),
              )),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _areas = [..._areas, const CprArea()]),
            icon: const Icon(Icons.add, size: 18),
            label: Text(_areas.isEmpty ? 'Adicionar lavoura' : 'Adicionar outra lavoura'),
          ),
          const SizedBox(height: 20),

          // O AVALISTA e as HIPOTECAS fecham o formulário porque não saem no
          // documento: eles são da PROPOSTA, e o modelo de cédula em uso não
          // tem cláusula para nenhum dos dois. Ficam por último para não
          // empurrar para baixo o que a cédula realmente precisa.
          _section('AVALISTAS', Icons.handshake_outlined),
          ..._guarantors.asMap().entries.map((entry) => _GuarantorCard(
                position: entry.key,
                guarantor: entry.value,
                onChanged: (updated) => setState(() {
                  final next = [..._guarantors];
                  next[entry.key] = updated;
                  _guarantors = next;
                }),
                onRemove: () => setState(() {
                  final next = [..._guarantors]..removeAt(entry.key);
                  _guarantors = next;
                }),
              )),
          OutlinedButton.icon(
            onPressed: () =>
                setState(() => _guarantors = [..._guarantors, const CprGuarantor()]),
            icon: const Icon(Icons.add, size: 18),
            label: Text(
                _guarantors.isEmpty ? 'Adicionar avalista' : 'Adicionar outro avalista'),
          ),
          const SizedBox(height: 20),

          _section('HIPOTECAS', Icons.account_balance_outlined),
          TextFormField(
            controller: _mortgages,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Hipotecas oferecidas em garantia',
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  /// Gera a cédula em **.docx** e entrega o arquivo.
  ///
  /// Word, e não PDF, porque a cédula ainda passa por gente: o jurídico revisa,
  /// o cartório pede um ajuste de redação. Um PDF obrigaria a redigitar o
  /// documento fora do sistema para mudar uma linha — e é aí que a versão que
  /// vai a registro deixa de ser a que o sistema conhece.
  ///
  /// Só existe com a cédula COMPLETA — e "completa" inclui o cadastro da
  /// credora, porque um título sem a qualificação de quem cobra não é título.
  /// Gerar com lacunas produziria um documento que parece pronto e não é.
  Future<void> _generate() async {
    final desk = _desk;
    if (desk == null || !desk.complete) return;
    setState(() => _generating = true);
    try {
      await FileSaver.instance.saveFile(
        name: 'cpr-${CprDocx.filename(desk)}',
        bytes: CprDocx.build(desk),
        ext: 'docx',
        mimeType: MimeType.microsoftWord,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('CPR gerada em Word.'),
        backgroundColor: AppColors.approved,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível gerar a CPR: \$e')),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// FATURAR — o ato do posto, e o fim da linha da permuta.
  ///
  /// Ele mora aqui, e não num diálogo à parte, porque faturar e montar a cédula
  /// são o mesmo trabalho: o faturista abre a permuta aprovada, preenche o que
  /// o documento exige e fatura. Enquanto foram duas telas, a cédula era um
  /// segundo passo que se descobria depois — e um faturamento sem cédula
  /// passava despercebido.
  ///
  /// A confirmação continua existindo porque o ato é IRREVERSÍVEL: não existe
  /// desfaturar, e o diálogo é onde entra a observação (opcional — o
  /// faturamento normal não tem o que explicar).
  Future<void> _invoice({required bool generate}) async {
    final desk = _desk;
    if (desk == null || !_barter.awaitsInvoice) return;

    final noteCtrl = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Faturar permuta'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_barter.id} • ${_barter.producerName}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            generate
                ? 'A CPR está completa e o arquivo será gerado em seguida.'
                : desk.complete
                    ? 'A CPR fica salva e completa. Você gera o arquivo quando quiser.'
                    : 'A CPR ainda tem ${desk.gaps.length} campo(s) em branco. Ela '
                        'continua salva e pode ser completada depois.',
            style: TextStyle(fontSize: 12, color: AppColors.textMedium),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            maxLength: 500,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Observação (opcional)',
              hintText: 'Número da nota, entrega parcial…',
            ),
          ),
        ]),
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
    if (confirmado != true || !mounted) return;

    setState(() => _invoicing = true);
    try {
      // A CÉDULA vai antes do faturamento: ela é rascunho e pode ser corrigida
      // depois, mas o que a pessoa acabou de digitar não pode se perder se o
      // faturamento falhar no meio.
      await AppData.saveBarterCpr(_barter.id, _collect());
      final faturada = await AppData.invoiceBarter(_barter.id, noteCtrl.text);
      if (!mounted) return;
      setState(() {
        _barter = faturada;
        _invoicing = false;
      });
      widget.onInvoiced?.call(faturada);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Permuta faturada.'),
        backgroundColor: AppColors.invoiced,
        behavior: SnackBarBehavior.floating,
      ));
      // O documento sai na sequência SÓ quando foi isso que se pediu. As duas
      // opções do rodapé são escolhas de verdade: quem tocou em "Faturar sem a
      // CPR" não quer um arquivo aparecendo no fim.
      if (generate && (_desk?.complete ?? false)) await _generate();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _invoicing = false);
      showErrorSnack(context, e);
    }
  }

  /// A BARRA DE AÇÃO. O que ela oferece muda com o estado da permuta, porque o
  /// trabalho muda.
  ///
  /// **Esperando faturamento** — os DOIS caminhos, lado a lado, e não um botão
  /// que troca de rótulo: eles são escolhas diferentes, e uma delas precisa
  /// estar visível mesmo quando não pode ser tomada, senão ninguém descobre que
  /// existe. *Faturar sem a CPR* existe porque a matrícula que não chegou não
  /// pode segurar o faturamento; *Faturar e gerar CPR* é o caminho normal, e
  /// acende quando a última pendência cai.
  ///
  /// **Já faturada** — sobra o documento, num botão só.
  ///
  /// O SALVAR não está aqui em nenhum dos dois: ele subiu para a barra de
  /// título. Três botões lado a lado não caberiam num celular, e ele é
  /// secundário de verdade — os dois caminhos de faturamento salvam a CPR antes
  /// de carimbar.
  Widget _saveBar() {
    final complete = _desk?.complete ?? false;
    final ocupado = _saving || _generating || _invoicing;

    // ENQUANTO A PERMUTA ESPERA FATURAMENTO, o rodapé oferece os DOIS caminhos
    // lado a lado, e não um botão que troca de rótulo: eles são escolhas
    // diferentes, e uma delas precisa estar visível mesmo quando não pode ser
    // tomada. "Faturar sem a CPR" existe porque a matrícula que não chegou não
    // pode segurar o faturamento; "Faturar e gerar CPR" é o caminho normal, e
    // ele acende quando a CPR fica completa.
    if (_barter.awaitsInvoice) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: ocupado ? null : () => _invoice(generate: false),
                  icon: const Icon(Icons.receipt_long_outlined, size: 19),
                  label: const Text(
                    'Faturar sem a CPR',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.invoiced,
                    side: BorderSide(color: AppColors.invoiced.withValues(alpha: 0.6)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 52,
                child: Tooltip(
                  message: complete
                      ? 'Fatura a permuta e gera o arquivo da CPR'
                      : 'Faltam ${_desk?.gaps.length ?? 0} campo(s) para gerar a CPR',
                  child: ElevatedButton.icon(
                    onPressed: complete && !ocupado ? () => _invoice(generate: true) : null,
                    icon: _invoicing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.onPrimary),
                          )
                        : const Icon(Icons.description_outlined, size: 20),
                    label: Text(
                      _invoicing ? 'Faturando…' : 'Faturar e gerar CPR',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.invoiced,
                      foregroundColor: AppColors.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
    }

    // JÁ FATURADA: o ato que resta é o documento — a CPR continua editável,
    // porque corrigir uma matrícula não desfatura nada. O Salvar está na barra
    // de título, então aqui sobra um botão só.
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: Tooltip(
            message: complete
                ? 'Gera o arquivo da CPR para assinatura'
                : 'Faltam ${_desk?.gaps.length ?? 0} campo(s) para gerar a CPR',
            child: ElevatedButton.icon(
              onPressed: complete && !ocupado ? _generate : null,
              icon: _generating
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child:
                          CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                    )
                  : const Icon(Icons.description_outlined, size: 21),
              label: Text(
                _generating ? 'Gerando…' : 'Gerar CPR',
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
  }

  Widget _section(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 10),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.primary,
            ),
          ),
        ]),
      );

  /// `caps` desligado onde a maiúscula automática atrapalha: e-mail e números
  /// de documento não são nomes próprios.
  Widget _textField(
    TextEditingController controller,
    String label, {
    String? hint,
    bool caps = true,
    ValueChanged<String>? onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          onChanged: onChanged,
          textCapitalization:
              caps ? TextCapitalization.words : TextCapitalization.none,
          decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
        ),
      );

  /// Campo numérico. A validação é de FORMATO — "isto é um número?" —, e não de
  /// preenchimento: quem cobra o que falta é o servidor, na lista de pendências
  /// do topo. Campo vazio passa, porque o rascunho é salvável pela metade.
  Widget _numberField(TextEditingController controller, String label, {bool percent = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(labelText: label, isDense: true),
          validator: (value) {
            final text = (value ?? '').trim();
            if (text.isEmpty) return null;
            final parsed = double.tryParse(text.replaceAll(',', '.'));
            if (parsed == null) return 'Número inválido';
            if (percent && (parsed < 0 || parsed > 100)) return 'Entre 0 e 100';
            return null;
          },
        ),
      );
}

/// O QUE CHEGOU DAS ETAPAS ANTERIORES — a decisão do comitê, que é o que
/// autoriza este faturamento.
///
/// O diálogo antigo de faturamento mostrava isto antes de confirmar, e a
/// informação não se perdeu ao virar tela: o faturista fatura o que foi
/// aprovado, e saber por quem é parte de saber que pode.
class _InvoicingHeader extends StatelessWidget {
  final BarterModel barter;

  const _InvoicingHeader({required this.barter});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.invoicedBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.invoiced.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.receipt_long_outlined, size: 19, color: AppColors.invoiced),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Esta permuta aguarda faturamento',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark),
            ),
            const SizedBox(height: 3),
            Text(
              barter.hasDecision
                  ? 'Aprovada por ${barter.reviewedBy}'
                      '${barter.reviewNote?.isNotEmpty == true ? ' — ${barter.reviewNote}' : ''}. '
                      'Preencha a CPR e fature.'
                  : 'Preencha a CPR e fature.',
              style: TextStyle(fontSize: 12, color: AppColors.textMedium, height: 1.35),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// O CARTÃO DO TOPO: o que a permuta já respondeu, e ninguém redigita.
class _KnownCard extends StatelessWidget {
  final CprKnown known;

  const _KnownCard({required this.known});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.lock_outline, size: 16, color: AppColors.textLight),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'DA PERMUTA ${known.barterCode} • não se digita aqui',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: AppColors.textLight,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          _line('Emitente', '${known.emitterName} • ${known.emitterDocument}'),
          _line('Produto', '${known.grainName} • safra ${known.versionCode}'),
          _line('Quantidade',
              '${formatSacks(known.sacks)} sacas • ${formatQty(known.quantityKg)} kg'),
          _line('Preço da saca', formatCurrency(known.sackPrice)),
          _line('Valor da cédula', formatCurrency(known.totalValue)),
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: AppColors.textLight)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.textDark, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );
}

/// O QUE FALTA — a lista que o servidor escreve, na ordem em que o documento
/// pede. É lista e não "incompleta" porque a resposta útil é "falta o RG e a
/// matrícula da segunda lavoura".
class _GapsCard extends StatelessWidget {
  final List<String> gaps;
  final bool complete;

  const _GapsCard({required this.gaps, required this.complete});

  @override
  Widget build(BuildContext context) {
    final ok = gaps.isEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ok ? AppColors.approvedBg : AppColors.pendingBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (ok ? AppColors.approved : AppColors.pending).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(ok ? Icons.check_circle_outline : Icons.pending_actions,
                size: 18, color: ok ? AppColors.approved : AppColors.pending),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ok
                    ? (complete
                        ? 'CPR completa, pronta para gerar.'
                        : 'Sua parte está completa. Falta o cadastro da empresa.')
                    : 'Faltam ${gaps.length} campo(s) para a CPR ficar pronta',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark),
              ),
            ),
          ]),
          if (!ok) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: gaps
                  .map((gap) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Text(gap,
                            style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// A pendência que NÃO é do faturista. Ela fica num cartão à parte de propósito:
/// somada à lista dele, mandaria a pessoa procurar um campo de CNPJ que não
/// existe neste formulário.
class _CreditorGapsCard extends StatelessWidget {
  final List<String> gaps;
  final VoidCallback onFix;

  const _CreditorGapsCard({required this.gaps, required this.onFix});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.settings_outlined, size: 17, color: AppColors.textMedium),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Falta completar o cadastro da empresa',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textDark),
            ),
            const SizedBox(height: 3),
            Text(
              '${gaps.join('; ')}. O seu preenchimento continua valendo: a '
              'cédula é que não fica pronta para virar documento.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textLight, height: 1.35),
            ),
            // A pendência vem com a SAÍDA junto. Uma lista do que falta sem o
            // caminho para resolvê-la é um aviso que a pessoa relê toda vez que
            // abre a tela e não pode fazer nada a respeito.
            if (AppData.can(Capability.creditorManage))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onFix,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Completar cadastro da empresa'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// A credora, para conferência. Ela aparece em quatro cláusulas do documento e é
/// sempre a mesma empresa — por isso é cadastro, e não campo desta tela.
class _CreditorCard extends StatelessWidget {
  final CprCreditor creditor;
  final VoidCallback onEdit;

  const _CreditorCard({required this.creditor, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    if (creditor.name.isEmpty) return const SizedBox.shrink();
    final canEdit = AppData.can(Capability.creditorManage);
    return InkWell(
      onTap: canEdit ? onEdit : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('CREDORA',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.textLight,
                  )),
              const SizedBox(height: 4),
              Text(creditor.name,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
              Text(
                'CNPJ ${creditor.cnpj} • ${creditor.address}, ${creditor.addressNumber}, '
                '${creditor.city} • Foro: ${creditor.effectiveForum}',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMedium, height: 1.35),
              ),
            ]),
          ),
          if (canEdit)
            Icon(Icons.chevron_right, size: 20, color: AppColors.textLight),
        ]),
      ),
    );
  }
}

/// O aviso da sugestão. Ela vem da última cédula do MESMO produtor, e o aviso
/// existe porque a pessoa precisa saber que aquele texto não foi ela quem
/// digitou agora: o estado civil de dois anos atrás pode ter mudado.
class _SuggestionNote extends StatelessWidget {
  const _SuggestionNote();

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.auto_awesome_outlined, size: 16, color: AppColors.textLight),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'Campos preenchidos a partir da última cédula deste produtor. '
          'Confira antes de salvar: o que mudou desde então é você quem sabe.',
          style: TextStyle(fontSize: 11.5, color: AppColors.textLight, height: 1.35),
        ),
      ),
    ]);
  }
}

/// UMA LAVOURA na lista do penhor.
///
/// Ela se redesenha a cada tecla a partir do estado da tela (sem controllers
/// próprios) porque a lista muda de tamanho: com um controller por campo,
/// remover a primeira área deixaria o texto dela colado na segunda.
class _AreaCard extends StatelessWidget {
  final int position;
  final CprArea area;
  final ValueChanged<CprArea> onChanged;
  final VoidCallback onRemove;

  const _AreaCard({
    required this.position,
    required this.area,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              '${position + 1}ª lavoura',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textDark),
            ),
          ),
          IconButton(
            tooltip: 'Remover lavoura',
            onPressed: onRemove,
            icon: Icon(Icons.delete_outline, size: 19, color: AppColors.textLight),
            visualDensity: VisualDensity.compact,
          ),
        ]),
        Row(children: [
          Expanded(
            flex: 3,
            child: _field(
              'Localidade',
              area.locality,
              (v) => onChanged(area.copyWith(locality: v)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _field(
              'Área (ha)',
              area.areaHa == 0 ? '' : _CprFormScreenState._decimal(area.areaHa),
              (v) => onChanged(area.copyWith(areaHa: _CprFormScreenState._parse(v))),
              numeric: true,
            ),
          ),
        ]),
        _field('Município/UF', area.city, (v) => onChanged(area.copyWith(city: v))),
        Row(children: [
          Expanded(
            child: _field('Matrícula', area.registryNumber,
                (v) => onChanged(area.copyWith(registryNumber: v))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _field(
                'Livro', area.registryBook, (v) => onChanged(area.copyWith(registryBook: v))),
          ),
        ]),
        _field('Comarca do registro', area.registryDistrict,
            (v) => onChanged(area.copyWith(registryDistrict: v))),
        // "Dentro de uma área maior" muda a frase do documento: é a diferença
        // entre penhorar a lavoura e parecer penhorar a fazenda inteira.
        CheckboxListTile(
          value: area.withinLargerArea,
          onChanged: (v) => onChanged(area.copyWith(withinLargerArea: v ?? false)),
          title: Text('O plantio ocupa parte de uma área maior',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMedium)),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          dense: true,
        ),
        const SizedBox(height: 4),
        Text(
          'PROPRIETÁRIOS DO IMÓVEL',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AppColors.textLight,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Nem sempre é o emitente: a lavoura penhorada costuma ser arrendada.',
          style: TextStyle(fontSize: 11, color: AppColors.textLight),
        ),
        const SizedBox(height: 8),
        ...area.owners.asMap().entries.map((entry) => Row(children: [
              Expanded(
                flex: 3,
                child: _field('Nome', entry.value.name, (v) {
                  final owners = [...area.owners];
                  owners[entry.key] = entry.value.copyWith(name: v);
                  onChanged(area.copyWith(owners: owners));
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _field('CPF/CNPJ', entry.value.document, (v) {
                  final owners = [...area.owners];
                  owners[entry.key] = entry.value.copyWith(document: v);
                  onChanged(area.copyWith(owners: owners));
                }),
              ),
              IconButton(
                tooltip: 'Remover proprietário',
                onPressed: () {
                  final owners = [...area.owners]..removeAt(entry.key);
                  onChanged(area.copyWith(owners: owners));
                },
                icon: Icon(Icons.close, size: 17, color: AppColors.textLight),
                visualDensity: VisualDensity.compact,
              ),
            ])),
        TextButton.icon(
          onPressed: () =>
              onChanged(area.copyWith(owners: [...area.owners, const CprOwner()])),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Adicionar proprietário'),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      ]),
    );
  }

  Widget _field(String label, String value, ValueChanged<String> onChanged,
          {bool numeric = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          // A chave amarra o campo à POSIÇÃO na lista: sem ela, remover a
          // primeira lavoura faria o Flutter reaproveitar o campo de texto e o
          // conteúdo apareceria na linha seguinte.
          key: ValueKey('$label-$position-${value.hashCode}'),
          initialValue: value,
          onChanged: onChanged,
          keyboardType:
              numeric ? const TextInputType.numberWithOptions(decimal: true) : null,
          inputFormatters:
              numeric ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))] : null,
          textCapitalization:
              numeric ? TextCapitalization.none : TextCapitalization.words,
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );
}

/// UM AVALISTA na lista.
///
/// A qualificação dele tem a MESMA forma da do emitente, campo por campo — para
/// o direito os dois são a mesma coisa, pessoas que se obrigam. O bloco do
/// cônjuge segue a mesma regra: só aparece para quem é casado.
///
/// Como as lavouras, ele se redesenha a partir do estado da tela em vez de ter
/// controllers próprios: a lista muda de tamanho, e um controller por campo
/// deixaria o texto colado no índice errado depois de uma remoção.
class _GuarantorCard extends StatelessWidget {
  final int position;
  final CprGuarantor guarantor;
  final ValueChanged<CprGuarantor> onChanged;
  final VoidCallback onRemove;

  const _GuarantorCard({
    required this.position,
    required this.guarantor,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${position + 1}º avalista',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          ),
          IconButton(
            tooltip: 'Remover avalista',
            onPressed: onRemove,
            icon: Icon(Icons.delete_outline, size: 19, color: AppColors.textLight),
            visualDensity: VisualDensity.compact,
          ),
        ]),
        _f('Nome', guarantor.name, (v) => onChanged(guarantor.copyWith(name: v))),
        Row(children: [
          Expanded(
              child: _f('CPF', guarantor.document,
                  (v) => onChanged(guarantor.copyWith(document: v)),
                  caps: false)),
          const SizedBox(width: 10),
          Expanded(
              child: _f('RG', guarantor.rg, (v) => onChanged(guarantor.copyWith(rg: v)),
                  caps: false)),
          const SizedBox(width: 10),
          Expanded(
              child: _f('CNH', guarantor.cnh, (v) => onChanged(guarantor.copyWith(cnh: v)),
                  caps: false)),
        ]),
        Row(children: [
          Expanded(
              child: _f('Nacionalidade', guarantor.nationality,
                  (v) => onChanged(guarantor.copyWith(nationality: v)))),
          const SizedBox(width: 10),
          Expanded(
              child: _f('Profissão', guarantor.profession,
                  (v) => onChanged(guarantor.copyWith(profession: v)))),
          const SizedBox(width: 10),
          Expanded(
              child: _f('Estado civil', guarantor.maritalStatus,
                  (v) => onChanged(guarantor.copyWith(maritalStatus: v)))),
        ]),
        Row(children: [
          Expanded(
              flex: 3,
              child: _f('Logradouro', guarantor.address,
                  (v) => onChanged(guarantor.copyWith(address: v)))),
          const SizedBox(width: 10),
          Expanded(
              child: _f('Nº', guarantor.addressNumber,
                  (v) => onChanged(guarantor.copyWith(addressNumber: v)),
                  caps: false)),
        ]),
        Row(children: [
          Expanded(
              child: _f('Município/UF', guarantor.city,
                  (v) => onChanged(guarantor.copyWith(city: v)))),
          const SizedBox(width: 10),
          Expanded(
              child: _f('E-mail', guarantor.email,
                  (v) => onChanged(guarantor.copyWith(email: v)),
                  caps: false)),
        ]),
        Row(children: [
          Expanded(
              child: _f('Filiação: pai', guarantor.fatherName,
                  (v) => onChanged(guarantor.copyWith(fatherName: v)))),
          const SizedBox(width: 10),
          Expanded(
              child: _f('Filiação: mãe', guarantor.motherName,
                  (v) => onChanged(guarantor.copyWith(motherName: v)))),
        ]),
        // O cônjuge do avalista, pela mesma regra do emitente: aval de quem é
        // casado costuma exigir anuência, porque há regime de bens no meio.
        if (guarantor.needsSpouse) ...[
          const SizedBox(height: 2),
          Text('CÔNJUGE DO AVALISTA',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppColors.textLight,
              )),
          const SizedBox(height: 8),
          _f('Nome', guarantor.spouseName,
              (v) => onChanged(guarantor.copyWith(spouseName: v))),
          Row(children: [
            Expanded(
                child: _f('CPF', guarantor.spouseDocument,
                    (v) => onChanged(guarantor.copyWith(spouseDocument: v)),
                    caps: false)),
            const SizedBox(width: 10),
            Expanded(
                child: _f('RG', guarantor.spouseRg,
                    (v) => onChanged(guarantor.copyWith(spouseRg: v)),
                    caps: false)),
          ]),
          Row(children: [
            Expanded(
                child: _f('Nacionalidade', guarantor.spouseNationality,
                    (v) => onChanged(guarantor.copyWith(spouseNationality: v)))),
            const SizedBox(width: 10),
            Expanded(
                child: _f('Profissão', guarantor.spouseProfession,
                    (v) => onChanged(guarantor.copyWith(spouseProfession: v)))),
          ]),
        ],
      ]),
    );
  }

  Widget _f(String label, String value, ValueChanged<String> onChanged,
          {bool caps = true}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          // A chave amarra o campo à POSIÇÃO na lista — sem ela, remover o
          // primeiro avalista faria o texto dele reaparecer no segundo.
          key: ValueKey('aval-$label-$position-${value.hashCode}'),
          initialValue: value,
          onChanged: onChanged,
          textCapitalization:
              caps ? TextCapitalization.words : TextCapitalization.none,
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );
}

class _Retry extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _Retry({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off, size: 40, color: AppColors.textLight),
          const SizedBox(height: 12),
          Text(
            error is ApiException ? (error as ApiException).message : 'Não foi possível carregar.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMedium),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Tentar novamente')),
        ]),
      ),
    );
  }
}

/// Campo de DATA. Ele não é digitável de propósito: emissão e vencimento saem
/// impressos por extenso no documento ("Aos [DIA] dias do mês de…"), e uma data
/// digitada à mão entra com 13 no mês em algum momento.
class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  const _DateField({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            suffixIcon: Icon(Icons.calendar_today_outlined, size: 17, color: AppColors.textLight),
          ),
          child: Text(
            value == null ? 'sem data' : formatDate(value!),
            style: TextStyle(
              fontSize: 14,
              color: value == null ? AppColors.textLight : AppColors.textDark,
            ),
          ),
        ),
      ),
    );
  }
}
