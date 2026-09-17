import 'package:file_picker/file_picker.dart';
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

/// A CÉDULA DE PRODUTO RURAL (CPR) — a tela de quem a preenche e de quem a
/// emite.
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
///    e o SCR do produtor.
///
/// QUEM ESCREVE É O CONSULTOR, e essa é a mudança de dono desta tela. Ela era do
/// faturista, e nada do que a cédula pede está na mesa de quem fatura: a
/// matrícula do imóvel, o nome do cônjuge, o dono da área arrendada e o SCR são
/// o que se traz da visita à fazenda. O faturista os obtinha por telefone e
/// digitava — e cada intermediação dessas é um RG com um dígito trocado dentro
/// de um título executável.
///
/// QUEM EMITE É O EMISSOR, no rodapé: ele lê o que os outros postos produziram
/// contra o que o documento exige, gera a cédula, lança as assinaturas colhidas
/// e o registro. São três atos porque acontecem em dias diferentes.
///
/// O RASCUNHO É SALVÁVEL PELA METADE, e isso é a decisão de desenho da tela: a
/// qualificação o consultor tem da visita, a matrícula costuma vir por e-mail do
/// produtor no dia seguinte, o SCR sai depois da consulta. Um formulário que só
/// aceitasse tudo de uma vez recusaria exatamente o estado em que o trabalho
/// passa a maior parte do tempo — e o rascunho voltaria para o papel ao lado do
/// computador.
///
/// DEPOIS DE EMITIDA ela é SÓ LEITURA: o documento existe no mundo, alguém
/// conferiu e assinou embaixo, e reescrevê-lo por baixo faria a segunda via sair
/// diferente da primeira — que é a que está com o produtor.
///
/// QUEM DIZ O QUE FALTA é o servidor ([CprDesk.gaps]), e não uma validação
/// local: a regra do que o documento exige mora em um lugar só, e uma exigência
/// nova aparece nas telas já instaladas sem versão nova do app. As validações
/// daqui são de FORMATO (número onde se espera número), não de completude.

/// Abre a MESA DA CÉDULA de uma permuta.
///
/// Existe como função porque a tela é chamada de vários lugares (o detalhe, a
/// fila do painel e a lista de permutas), e todos precisam saber da permuta
/// atualizada quando um ato do emissor a move.
///
/// DEVOLVE O FECHAMENTO DA TELA porque há quem precise reagir a ele: o aviso de
/// cédula incompleta do detalhe recarrega as pendências quando esta volta —
/// senão a pessoa preenche o que faltava e encontra o mesmo aviso vermelho
/// dizendo que falta.
Future<void> openCprDesk(
  BuildContext context,
  BarterModel barter, {
  ValueChanged<BarterModel>? onChanged,
}) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => CprFormScreen(barter: barter, onChanged: onChanged),
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
  /// A permuta cuja cédula está sendo preenchida, conferida ou emitida.
  final BarterModel barter;

  /// Avisa quem abriu a tela que a permuta ANDOU — os três atos do emissor a
  /// movem de estado, e a lista que ficou atrás precisa saber.
  final ValueChanged<BarterModel>? onChanged;

  const CprFormScreen({super.key, required this.barter, this.onChanged});

  @override
  State<CprFormScreen> createState() => _CprFormScreenState();
}

class _CprFormScreenState extends State<CprFormScreen> {
  final _formKey = GlobalKey<FormState>();

  CprDesk? _desk;
  Object? _loadError;
  bool _saving = false;
  bool _generating = false;

  /// Um ato do EMISSOR em andamento (emitir, assinar ou registrar). Um só para
  /// os três: eles nunca acontecem ao mesmo tempo, e o que a tela precisa é
  /// travar os botões enquanto qualquer um deles está no ar.
  bool _issuing = false;

  /// UM ANEXO subindo — o SCR, ou a via carimbada que chegou depois. Separado
  /// de [_saving] porque são rotas e erros diferentes: o upload pode falhar com
  /// o formulário salvo, e vice-versa. Um só para os dois porque eles nunca
  /// acontecem ao mesmo tempo, e o que a tela precisa é travar o botão do anexo
  /// enquanto qualquer um está no ar.
  bool _uploadingAttachment = false;

  /// A permuta como ela está AGORA. Ela muda de estado dentro desta tela — é
  /// aqui que a emissão acontece —, e o rodapé lê isto para saber qual dos três
  /// atos do emissor é o da vez.
  late BarterModel _barter = widget.barter;

  /// ESTA TELA ACEITA ESCRITA?
  ///
  /// Duas condições, e as duas do servidor: a pessoa preenche cédula
  /// (`barters.cprFill`, o consultor) e o documento ainda não saiu. Depois da
  /// emissão ninguém escreve — nem quem escreveu antes.
  bool get _canEdit => AppData.can(Capability.bartersCprFill) && !_barter.isCprIssued;

  /// Esta pessoa EMITE a cédula? (`barters.cprIssue`, o emissor).
  bool get _canIssue => AppData.can(Capability.bartersCprIssue);

  /// E PODE ANEXAR O SCR? — a única escrita da cédula com DOIS donos.
  ///
  /// O consultor porque é ele quem consulta o SCR; o EMISSOR porque é ele quem
  /// fica travado por ele na hora de emitir, e mandá-lo pedir ao consultor e
  /// esperar seria a resposta errada com o produtor na sala. Anexar não é
  /// escrever a cédula: o que o emissor não pode é mexer no que ele confere, e o
  /// SCR não é afirmação dele sobre o produtor — é o relatório do Banco Central,
  /// do jeito que veio. Ver `RequireAnyCapability` na rota.
  bool get _canAttachScr => (_canEdit || _canIssue) && !_barter.isCprIssued;

  /// E A VIA CARIMBADA do registro — pode ser anexada agora?
  ///
  /// Só depois do ato, e só por quem emite: ela é a prova de um fato que já foi
  /// lançado. O caminho normal é ela subir JUNTO com o registro; esta porta
  /// existe para o caso real de o cartório devolver o papel semanas depois de
  /// dar o número, quando o ato não se refaz mais.
  bool get _canAttachRegistryFile => _canIssue && _barter.isCprRegistered;

  /// A CÉDULA PODE SER EMITIDA AGORA? — completa, ou faltando só o número.
  ///
  /// O número é a exceção porque ele é o que o próprio diálogo de emissão pede:
  /// ele vem de fora do sistema (cartório, B3, controle da credora) e só o
  /// emissor o tem. Travar o botão por ele mandaria o emissor pedir ao consultor
  /// um dado que o consultor não conhece — e a tela nunca destravaria.
  bool get _readyToIssue {
    final desk = _desk;
    if (desk == null) return false;
    if (desk.complete) return true;
    if (desk.creditorGaps.isNotEmpty) return false;
    return desk.gaps.every((gap) => gap.contains('número da CPR'));
  }

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

  /// A DATA DA CONSULTA do SCR. O anexo em si não é campo — ele sobe por rota
  /// própria, e o que a tela guarda dele é o que o servidor devolveu.
  DateTime? _scrConsultedAt;

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
    _scrConsultedAt = draft.scrConsultedAt;
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
        scrConsultedAt: _scrConsultedAt,
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
        // O TÍTULO diz o ATO da vez, e não a tela: quem chega aqui pelo botão do
        // emissor veio emitir; quem chega pelo do consultor veio preencher; e
        // depois de emitida sobra o documento.
        title: Text(
          _barter.isCprIssued
              ? 'Cédula de ${_barter.id}'
              : _canIssue
                  ? 'Emitir CPR de ${_barter.id}'
                  : 'Cédula de Produto Rural',
        ),
        actions: [
          if (_desk != null) ...[
            // SALVAR mora aqui, e não no rodapé, porque o rodapé é das DUAS
            // opções de faturamento — e três botões lado a lado não caberiam
            // num celular. Ele também é secundário de verdade: os dois caminhos
            // de faturamento salvam a CPR antes de carimbar, então este botão é
            // o "guardo e volto depois".
            if (_canEdit)
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
                    onPressed: _issuing || _generating ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                  ),
            IconButton(
              tooltip: 'Recarregar',
              onPressed: _saving || _issuing ? null : _load,
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
          _StageHeader(barter: _barter, canIssue: _canIssue, canEdit: _canEdit),
          const SizedBox(height: 14),
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
                onTap: _canEdit
                    ? () => _pickDate(
                          current: _issuedAt,
                          onPicked: (d) => setState(() => _issuedAt = d),
                        )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            // O VENCIMENTO é LEITURA, e essa é a correção desta versão: ele
            // muda conforme a CULTURA e vale para a safra inteira. Quem o
            // acerta é o admin, no cadastro da safra — um campo aqui devolveria
            // o problema que ele resolve: duas cédulas da mesma safra vencendo
            // em dias diferentes, sem como saber qual está certa.
            Expanded(
              child: _ReadOnlyDate(
                label: 'Vencimento',
                value: desk.known.dueDate,
                hint: desk.known.seasonName.isEmpty
                    ? 'Definido na safra'
                    : 'Da safra ${desk.known.seasonName}',
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

          // ── O SCR: o anexo obrigatório ────────────────────────────────
          //
          // Ele é a única exigência da cédula que não vem do modelo do
          // documento: vem da decisão de não assinar título sem olhar o
          // endividamento de quem o emite.
          _section('SCR DO PRODUTOR', Icons.account_balance_outlined),
          _ScrCard(
            file: _desk?.cpr?.scrFile,
            consultedAt: _scrConsultedAt,
            uploading: _uploadingAttachment,
            // O EMISSOR anexa também — ver [_canAttachScr]. A DATA da consulta
            // continua sendo campo do formulário, e por isso continua só de quem
            // preenche: ela é informação sobre o documento, e não o documento.
            onPick: _canAttachScr ? _pickScr : null,
            onOpen: _desk?.cpr?.scrFile == null ? null : _downloadScr,
            onPickDate: _canEdit
                ? () => _pickDate(
                      current: _scrConsultedAt,
                      onPicked: (d) => setState(() => _scrConsultedAt = d),
                    )
                : null,
          ),
          const SizedBox(height: 14),

          // ── O QUE VOLTOU DE FORA: a cédula assinada e a via do cartório ─
          //
          // Só aparece quando há o que mostrar (ou quando há o que anexar): numa
          // cédula que ainda nem foi emitida, esta seção seria um bloco de dois
          // traços anunciando trabalho que não é da vez.
          if (_desk?.cpr?.signedFile != null ||
              _desk?.cpr?.registryFile != null ||
              _canAttachRegistryFile) ...[
            _section('DOCUMENTOS ASSINADOS E REGISTRADOS', Icons.verified_outlined),
            _ReturnedDocsCard(
              signed: _desk?.cpr?.signedFile,
              registry: _desk?.cpr?.registryFile,
              signedAt: _barter.cprSignedAt,
              registeredAt: _barter.cprRegisteredAt,
              registryNumber: _barter.cprRegistryNumber ?? '',
              busy: _uploadingAttachment,
              onOpenSigned: _desk?.cpr?.signedFile == null ? null : _downloadSignedCpr,
              onOpenRegistry: _desk?.cpr?.registryFile == null ? null : _downloadRegistryFile,
              onPickRegistry: _canAttachRegistryFile ? _pickRegistryFile : null,
            ),
            const SizedBox(height: 14),
          ],

          // ── A origem da dívida: as NOTAS do faturamento ───────────────
          //
          // LEITURA. Elas eram dois campos de texto aqui, digitados por quem
          // não emitia a nota, e cabia uma só. Agora chegam do faturamento, com
          // o arquivo junto e em lista.
          _section('ORIGEM DA DÍVIDA (CLÁUSULA VII)', Icons.receipt_long_outlined),
          _InvoicesCard(
            invoices: desk.known.invoices,
            onOpen: _barter.invoices.isEmpty ? null : _downloadInvoice,
            barterInvoices: _barter.invoices,
          ),
          const SizedBox(height: 12),
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

  /* ── O SCR: anexar e abrir ─────────────────────────────────────────── */

  /// ESCOLHE E ANEXA o SCR do produtor — o relatório do Banco Central.
  ///
  /// Rota própria, e não um campo do formulário: um anexo de megabytes dentro do
  /// JSON faria cada salvamento de rascunho reenviá-lo. O SCR novo SUBSTITUI o
  /// anterior no servidor — ele é uma fotografia, e duas com datas diferentes
  /// penduradas na mesma cédula fariam alguém conferir a errada.
  Future<void> _pickScr() async {
    final arquivo = await FilePicker.pickFile(
      dialogTitle: 'SCR do produtor',
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
    );
    if (arquivo == null) return;
    // Os BYTES são lidos aqui, e não o caminho: no Android/iOS o arquivo
    // escolhido fica num diretório temporário que pode sumir antes do envio. É
    // a mesma razão da carga da planilha do Barter.
    final bytes = await arquivo.readAsBytes();
    if (!mounted) return;

    setState(() => _uploadingAttachment = true);
    try {
      final desk = await AppData.saveBarterScr(
        _barter.id,
        filename: arquivo.name,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() {
        _desk = desk;
        _uploadingAttachment = false;
        // O RESTO DO FORMULÁRIO não é reescrito: quem sobe o SCR pode estar no
        // meio de uma digitação, e um `_fill` aqui jogaria fora o que ainda não
        // foi salvo. O que a tela precisa do servidor é o anexo e as pendências.
        if (desk.cpr != null) _scrConsultedAt = desk.cpr!.scrConsultedAt;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('SCR anexado à cédula.'),
        backgroundColor: AppColors.approved,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingAttachment = false);
      showErrorSnack(context, error);
    }
  }

  Future<void> _downloadScr() => _saveAttachment(
        () => AppData.downloadBarterScr(_barter.id),
      );

  Future<void> _downloadInvoice(String invoiceId) => _saveAttachment(
        () => AppData.downloadBarterInvoiceFile(_barter.id, invoiceId),
      );

  Future<void> _downloadSignedCpr() => _saveAttachment(
        () => AppData.downloadSignedCpr(_barter.id),
      );

  Future<void> _downloadRegistryFile() => _saveAttachment(
        () => AppData.downloadCprRegistryFile(_barter.id),
      );

  /// A VIA CARIMBADA que chegou DEPOIS do ato do registro.
  ///
  /// Sobe por rota própria porque o ato já aconteceu e não se refaz: o cartório
  /// devolve o papel quando devolve, às vezes semanas depois de dar o número.
  Future<void> _pickRegistryFile() async {
    final arquivo = await FilePicker.pickFile(
      dialogTitle: 'Via registrada da cédula',
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
    );
    if (arquivo == null) return;
    final bytes = await arquivo.readAsBytes();
    if (!mounted) return;

    setState(() => _uploadingAttachment = true);
    try {
      final desk = await AppData.saveCprRegistryFile(
        _barter.id,
        filename: arquivo.name,
        bytes: bytes,
      );
      if (!mounted) return;
      // Só o `_desk` é trocado, e não o formulário: ver `_pickScr`.
      setState(() {
        _desk = desk;
        _uploadingAttachment = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Via registrada anexada à cédula.'),
        backgroundColor: AppColors.approved,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingAttachment = false);
      showErrorSnack(context, error);
    }
  }

  /// BAIXA um anexo e o entrega à pessoa.
  ///
  /// `FileSaver` e não `printing`: o anexo pode ser PDF, XML ou imagem, e só o
  /// primeiro teria visualizador. O que a pessoa quer aqui é o ARQUIVO — abrir
  /// é decisão do aparelho dela.
  Future<void> _saveAttachment(
    Future<({List<int> bytes, String filename, String contentType})> Function() fetch,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final arquivo = await fetch();
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

  /* ── A emissão: os três atos do emissor ────────────────────────────── */

  /// EMITE a cédula — o ato que CONFERE.
  ///
  /// O diálogo existe porque a emissão é IRREVERSÍVEL para o formulário: do
  /// ato em diante a cédula não se reescreve, nem por quem a escreveu. Quem
  /// confirma precisa saber disso antes.
  ///
  /// A recusa do servidor (422) chega com a lista do que falta e com quem cada
  /// coisa se resolve — e é ela que a tela mostra, em vez de uma validação local
  /// que divergiria dela no primeiro campo novo.
  Future<void> _issue() async {
    final desk = _desk;
    if (desk == null) return;

    final noteCtrl = TextEditingController();
    // O NÚMERO DA CÉDULA é informado AQUI quando ela ainda não o tem — é a única
    // coisa da cédula que o emissor escreve, e escreve porque é a única que ele
    // tem: a numeração vem de fora do sistema (cartório, B3, controle da
    // credora). O consultor não a conhece quando visita a fazenda.
    final numberCtrl = TextEditingController(text: desk.cpr?.number ?? '');
    final precisaNumero = (desk.cpr?.number ?? '').trim().isEmpty;
    final formKey = GlobalKey<FormState>();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Emitir a cédula'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_barter.id} • ${_barter.producerName}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              Text(
                'Emitir é CONFERIR: você afirma que a qualificação, as matrículas e '
                'a origem da dívida estão corretas. Depois disso a cédula não se '
                'reescreve — a correção passa a ser de papel.',
                style: TextStyle(fontSize: 12, color: AppColors.textMedium, height: 1.35),
              ),
              const SizedBox(height: 12),
              if (precisaNumero)
                TextFormField(
                  controller: numberCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Nº da CPR',
                    hintText: 'Como a credora a numera',
                    isDense: true,
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Informe o número da cédula' : null,
                ),
              if (precisaNumero) const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                maxLength: 500,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                  hintText: 'Duas vias impressas, papel timbrado…',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? true) Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.invoiced),
            child: const Text('Emitir'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    await _runIssuanceStep(
      () => AppData.issueBarterCpr(
        _barter.id,
        number: numberCtrl.text,
        note: noteCtrl.text,
      ),
      'Cédula emitida. Agora é a coleta de assinaturas.',
    );
    // O DOCUMENTO sai na sequência: é para isso que a emissão existe, e pedir um
    // segundo toque logo depois de confirmar seria um passo que ninguém entende.
    if (mounted && (_desk?.complete ?? false)) await _generate();
  }

  /// A COLETA DE ASSINATURAS concluída — o lançamento de um fato de fora, com o
  /// PAPEL ASSINADO junto.
  ///
  /// O anexo é obrigatório, e é a correção do ato: a cédula sai daqui em branco
  /// e volta assinada, e enquanto não havia onde guardar a que voltou, o sistema
  /// dizia "assinada" sem ter como mostrar. A segunda via saía diferente da que
  /// está na mão do produtor, e o documento com as assinaturas morava no e-mail
  /// de alguém.
  Future<void> _sign() async {
    final resposta = await _askIssuance(
      title: 'Registrar as assinaturas',
      explanation: 'Lance aqui quando o papel assinado voltar, com ele anexado. '
          'A data é a da assinatura, e não a de hoje: o produtor assina na '
          'fazenda, e o documento chega ao escritório depois.',
      noteLabel: 'Quem assinou (opcional)',
      noteHint: 'Emitente e cônjuge, presencial…',
      askDate: true,
      fileLabel: 'Cédula assinada',
      fileRequired: true,
      confirmLabel: 'Registrar',
    );
    if (resposta == null) return;

    await _runIssuanceStep(
      () => AppData.signBarterCpr(
        _barter.id,
        filename: resposta.fileName!,
        bytes: resposta.fileBytes!,
        signedAt: resposta.date,
        note: resposta.note,
      ),
      'Assinaturas registradas e cédula assinada anexada. '
      'Falta levar a cédula a registro.',
    );
  }

  /// O REGISTRO do título — o fim da linha. O número é OBRIGATÓRIO.
  Future<void> _register() async {
    final resposta = await _askIssuance(
      title: 'Registrar a cédula',
      explanation: 'O NÚMERO do registro é o que transforma "levamos ao cartório" '
          'em "está registrada" — é por ele que se pede a certidão depois.',
      noteLabel: 'Observação (opcional)',
      noteHint: 'Custas, exigência cumprida…',
      askDate: true,
      askRegistry: true,
      // OPCIONAL, ao contrário da assinatura: o que prova o registro é o número,
      // e o cartório devolve a via carimbada quando devolve. Exigi-la aqui
      // travaria o fim da linha por um papel que ainda está no protocolo.
      fileLabel: 'Via registrada (opcional)',
      confirmLabel: 'Registrar',
    );
    if (resposta == null) return;

    await _runIssuanceStep(
      () => AppData.registerBarterCpr(
        _barter.id,
        registryNumber: resposta.registryNumber,
        registryPlace: resposta.registryPlace,
        registeredAt: resposta.date,
        note: resposta.note,
        filename: resposta.fileName,
        bytes: resposta.fileBytes,
      ),
      'Cédula registrada. A permuta está concluída.',
    );
  }

  /// O CORPO COMUM dos três atos: roda, atualiza a tela e avisa quem abriu.
  ///
  /// Em um lugar só porque o que eles têm de diferente é a chamada e a frase; o
  /// resto — travar os botões, trocar a permuta, recarregar a mesa e devolver o
  /// estado novo para a lista que ficou atrás — é idêntico, e três cópias disso
  /// divergiriam na primeira correção.
  Future<void> _runIssuanceStep(
    Future<BarterModel> Function() run,
    String success,
  ) async {
    setState(() => _issuing = true);
    try {
      final atualizada = await run();
      if (!mounted) return;
      setState(() {
        _barter = atualizada;
        _issuing = false;
      });
      widget.onChanged?.call(atualizada);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success),
        backgroundColor: AppColors.approved,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (error) {
      if (!mounted) return;
      setState(() => _issuing = false);
      showErrorSnack(context, error);
    }
  }

  /// O DIÁLOGO dos atos do emissor que pedem dados — a assinatura e o registro.
  ///
  /// Um só para os dois porque a forma é a mesma (uma data, um texto, o anexo e,
  /// no registro, o número e o lugar), e duas telas quase iguais é uma a mais
  /// para manter em dia.
  ///
  /// [fileLabel] liga o ANEXO. Ele é o documento que VOLTA de fora — a cédula
  /// assinada, a via carimbada pelo cartório — e sobe no MESMO ato: um botão
  /// separado depois faria o lançamento acontecer sem o papel, que é o estado
  /// que a tela existe para não produzir. [fileRequired] separa os dois casos:
  /// não há "assinada" sem o papel assinado, e há "registrada" sem a via —
  /// o número do registro já é a prova, e o cartório devolve quando devolve.
  Future<_IssuanceAnswer?> _askIssuance({
    required String title,
    required String explanation,
    required String noteLabel,
    required String noteHint,
    required String confirmLabel,
    bool askDate = false,
    bool askRegistry = false,
    String? fileLabel,
    bool fileRequired = false,
  }) async {
    final noteCtrl = TextEditingController();
    final numberCtrl = TextEditingController();
    final placeCtrl = TextEditingController();
    DateTime? quando = DateTime.now();
    String? nomeArquivo;
    List<int>? bytesArquivo;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_barter.id} • ${_barter.producerName}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                Text(
                  explanation,
                  style: TextStyle(fontSize: 12, color: AppColors.textMedium, height: 1.35),
                ),
                const SizedBox(height: 12),
                if (askRegistry) ...[
                  TextField(
                    controller: numberCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Nº do registro',
                      hintText: 'R-4 / 18.442',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: placeCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Onde (opcional)',
                      hintText: 'CRI Maringá/PR, B3…',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (askDate)
                  _DateField(
                    label: 'Data',
                    value: quando,
                    onTap: () async {
                      final escolhida = await showDatePicker(
                        context: ctx,
                        initialDate: quando ?? DateTime.now(),
                        firstDate: DateTime(DateTime.now().year - 3),
                        lastDate: DateTime.now(),
                      );
                      if (escolhida != null) setDialogState(() => quando = escolhida);
                    },
                  ),
                TextField(
                  controller: noteCtrl,
                  maxLength: 500,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: noteLabel, hintText: noteHint),
                ),
                if (fileLabel != null) ...[
                  const SizedBox(height: 4),
                  _AttachmentPicker(
                    label: fileLabel,
                    required: fileRequired,
                    fileName: nomeArquivo,
                    onPick: () async {
                      final arquivo = await FilePicker.pickFile(
                        dialogTitle: fileLabel,
                        type: FileType.custom,
                        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
                      );
                      if (arquivo == null) return;
                      // Os BYTES são lidos aqui, e não o caminho: no Android/iOS
                      // o arquivo escolhido fica num diretório temporário que
                      // pode sumir antes do envio. Ver `_pickScr`.
                      final bytes = await arquivo.readAsBytes();
                      setDialogState(() {
                        nomeArquivo = arquivo.name;
                        bytesArquivo = bytes;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              // O botão SÓ LIGA com o anexo obrigatório em mãos. A recusa existe
              // no servidor de qualquer jeito, mas descobri-la depois de
              // preencher a data e a observação seria refazer o formulário
              // inteiro por uma exigência que a tela já conhecia.
              onPressed: fileRequired && bytesArquivo == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.invoiced),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return null;

    return _IssuanceAnswer(
      date: quando,
      note: noteCtrl.text,
      registryNumber: numberCtrl.text,
      registryPlace: placeCtrl.text,
      fileName: nomeArquivo,
      fileBytes: bytesArquivo,
    );
  }

  /// A BARRA DE AÇÃO. O que ela oferece muda com o ESTADO da permuta e com o
  /// papel de quem abriu, porque o trabalho muda.
  ///
  /// - **quem preenche** (consultor) vê o documento quando ele fica pronto: o
  ///   ato dele é salvar, e o Salvar mora na barra de título;
  /// - **quem emite** (emissor) vê o ato da vez — emitir, registrar as
  ///   assinaturas ou registrar a cédula. UM botão, e não três: eles acontecem
  ///   em dias diferentes, e oferecer os três juntos convidaria a lançar um
  ///   registro que ainda não houve;
  /// - **quem só lê** (admin) vê o documento, e nada mais.
  Widget _saveBar() {
    final complete = _desk?.complete ?? false;
    final ocupado = _saving || _generating || _issuing || _uploadingAttachment;

    final ato = _issuanceAction();
    if (ato != null) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            // GERAR fica ao lado, e menor: depois de emitida, a segunda via é o
            // que se pede de novo — e antes da emissão ele é o ensaio do
            // documento que o emissor está conferindo.
            if (complete)
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: ocupado ? null : _generate,
                    icon: const Icon(Icons.description_outlined, size: 19),
                    label: const Text('Gerar .docx',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.invoiced,
                      side: BorderSide(color: AppColors.invoiced.withValues(alpha: 0.6)),
                    ),
                  ),
                ),
              ),
            if (complete) const SizedBox(width: 10),
            Expanded(
              flex: complete ? 1 : 2,
              child: SizedBox(
                height: 52,
                child: Tooltip(
                  message: ato.enabled
                      ? ato.tooltip
                      : 'Faltam ${_desk?.gaps.length ?? 0} campo(s) e/ou o cadastro da credora',
                  child: ElevatedButton.icon(
                    onPressed: ato.enabled && !ocupado ? ato.run : null,
                    icon: _issuing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.onPrimary),
                          )
                        : Icon(ato.icon, size: 20),
                    label: Text(
                      ato.label,
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

    // SEM ATO DE EMISSÃO: sobra o documento. É o rodapé do consultor (que já
    // preencheu e quer ver como ficou) e o de quem só lê.
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: Tooltip(
            message: complete
                ? 'Gera o arquivo da CPR em Word'
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

  /// O ATO DO EMISSOR da vez — ou null, quando não há (não é o emissor, ou a
  /// cédula já foi registrada).
  ///
  /// UM de cada vez, lido do ESTADO da permuta: é a mesma ordem que o servidor
  /// impõe (`barter-workflow.ts`), e oferecer os três juntos convidaria a lançar
  /// um registro de uma cédula que ninguém assinou.
  _IssuanceAction? _issuanceAction() {
    if (!_canIssue) return null;
    if (_barter.awaitsCprIssue) {
      return _IssuanceAction(
        label: 'Emitir CPR',
        icon: Icons.description_outlined,
        // A EMISSÃO depende de a cédula estar completa — MENOS pelo número, que
        // é o que o próprio diálogo pede. Travar o botão por ele mandaria o
        // emissor pedir ao consultor um dado que só ele tem, e a tela nunca
        // destravaria.
        enabled: _readyToIssue,
        tooltip: 'Confere a cédula e emite o título',
        run: _issue,
      );
    }
    if (_barter.awaitsSignatures) {
      return _IssuanceAction(
        label: 'Registrar assinaturas',
        icon: Icons.draw_outlined,
        enabled: true,
        tooltip: 'Lança a coleta de assinaturas concluída',
        run: _sign,
      );
    }
    if (_barter.awaitsRegistration) {
      return _IssuanceAction(
        label: 'Registrar cédula',
        icon: Icons.verified_outlined,
        enabled: true,
        tooltip: 'Lança o registro do título, com o número',
        run: _register,
      );
    }
    return null;
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

/// EM QUE PÉ ESTÁ ESTA CÉDULA — o cabeçalho que diz o que se espera de quem
/// abriu a tela.
///
/// Ele substituiu o cabeçalho de faturamento, e a troca é a mudança inteira
/// resumida: a tela não é mais o passo de faturar, é a mesa de um DOCUMENTO por
/// onde passam três pessoas. A frase muda com o estado e com o papel porque a
/// pergunta de cada um é outra — "o que falta eu preencher?", "dá para emitir?",
/// "como ficou?".
class _StageHeader extends StatelessWidget {
  final BarterModel barter;
  final bool canIssue;
  final bool canEdit;

  const _StageHeader({required this.barter, required this.canIssue, required this.canEdit});

  @override
  Widget build(BuildContext context) {
    final (titulo, texto, cor, fundo, icone) = _conteudo();
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icone, size: 19, color: cor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              titulo,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark),
            ),
            const SizedBox(height: 3),
            Text(
              texto,
              style: TextStyle(fontSize: 12, color: AppColors.textMedium, height: 1.35),
            ),
          ]),
        ),
      ]),
    );
  }

  (String, String, Color, Color, IconData) _conteudo() {
    if (barter.isCprRegistered) {
      return (
        'Cédula registrada',
        'Registro ${barter.cprRegistryNumber ?? ''}'
            '${barter.cprRegistryPlace?.isNotEmpty == true ? ' — ${barter.cprRegistryPlace}' : ''}. '
            'A permuta está concluída; o que resta aqui é a segunda via.',
        AppColors.approved,
        AppColors.approvedBg,
        Icons.verified_rounded,
      );
    }
    if (barter.awaitsRegistration) {
      return (
        'Assinada, aguardando o registro',
        'A garantia só vale contra terceiros depois de registrada. Lance o número '
            'quando o cartório responder.',
        AppColors.invoiced,
        AppColors.invoicedBg,
        Icons.draw_outlined,
      );
    }
    if (barter.awaitsSignatures) {
      return (
        'Emitida, aguardando as assinaturas',
        'Emitida por ${barter.cprEmittedBy ?? 'o emissor'}. O documento não se '
            'reescreve mais — a correção agora é de papel.',
        AppColors.invoiced,
        AppColors.invoicedBg,
        Icons.description_outlined,
      );
    }
    if (barter.awaitsCprIssue) {
      return (
        canIssue ? 'Pronta para conferir e emitir' : 'Faturada, aguardando a emissão',
        canIssue
            ? 'Leia o que o consultor preencheu contra o que o documento exige. '
                'A cédula com lacuna não sai — as pendências estão logo abaixo.'
            : 'A cédula está com o emissor. O que estiver em branco abaixo ainda '
                'pode ser preenchido até ele emitir.',
        AppColors.invoiced,
        AppColors.invoicedBg,
        Icons.fact_check_outlined,
      );
    }
    // ANTES DO FATURAMENTO: a cédula é coleta, e ela não espera a nota sair.
    return (
      canEdit ? 'Coleta da cédula' : 'Cédula em preenchimento',
      canEdit
          ? 'Preencha o que você traz da visita: a qualificação do produtor, as '
              'matrículas das lavouras e o SCR. A emissão vem depois do '
              'faturamento, e o que faltar aqui trava ela.'
          : 'O consultor preenche esta cédula. Ela é emitida depois do '
              'faturamento.',
      AppColors.pending,
      AppColors.pendingBg,
      Icons.edit_note_rounded,
    );
  }
}

/// UMA DATA QUE NÃO SE DIGITA — o vencimento, que é da safra.
///
/// Ele tem a forma de campo, e não de linha de texto, de propósito: ele ESTÁ no
/// bloco de identificação da cédula, ao lado da emissão, e quem lê o formulário
/// precisa vê-lo onde ele sai no documento. O que a tela diz é DE ONDE ele vem,
/// para ninguém procurar onde digitá-lo.
class _ReadOnlyDate extends StatelessWidget {
  final String label;
  final DateTime? value;
  final String hint;

  const _ReadOnlyDate({required this.label, required this.value, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          helperText: hint,
          helperMaxLines: 2,
          suffixIcon: Icon(Icons.lock_outline, size: 16, color: AppColors.textLight),
        ),
        child: Text(
          value == null ? 'não definido na safra' : formatDate(value!),
          style: TextStyle(
            fontSize: 14,
            color: value == null ? AppColors.denied : AppColors.textDark,
            fontWeight: value == null ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// O SCR DO PRODUTOR — o anexo obrigatório da cédula.
///
/// Ele ganha um cartão próprio, e não uma linha no meio do formulário, porque é
/// a única pendência da cédula que não se resolve digitando: é um documento que
/// alguém precisa ir buscar. Um campo discreto no meio de trinta o esconderia
/// justamente de quem tem de providenciá-lo.
/// OS DOIS DOCUMENTOS QUE VOLTARAM DE FORA — a cédula assinada e a via
/// carimbada pelo registro.
///
/// Eles ficam juntos porque respondem à mesma pergunta, que é a última que se
/// faz sobre uma permuta: *cadê o papel?* Enquanto não tinham onde ficar, a
/// permuta dizia "assinada" e "registrada" e a prova das duas coisas morava no
/// e-mail de alguém — e a segunda via saía do sistema em branco, diferente da
/// que está na mão do produtor.
///
/// A DATA de cada ato vem da PERMUTA e o arquivo vem da CÉDULA, e os dois
/// aparecem na mesma linha de propósito: "assinada em 14/03" sem o papel é
/// exatamente o estado que este cartão existe para denunciar.
class _ReturnedDocsCard extends StatelessWidget {
  final BarterFileModel? signed;
  final BarterFileModel? registry;
  final DateTime? signedAt;
  final DateTime? registeredAt;
  final String registryNumber;
  final bool busy;
  final VoidCallback? onOpenSigned;
  final VoidCallback? onOpenRegistry;
  final VoidCallback? onPickRegistry;

  const _ReturnedDocsCard({
    required this.signed,
    required this.registry,
    required this.signedAt,
    required this.registeredAt,
    required this.registryNumber,
    required this.busy,
    required this.onOpenSigned,
    required this.onOpenRegistry,
    required this.onPickRegistry,
  });

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (signed != null || signedAt != null)
        _ReturnedDocRow(
          icon: Icons.draw_outlined,
          title: 'Cédula assinada',
          file: signed,
          // Sem assinatura lançada a linha nem aparece; com ela e sem papel, o
          // texto diz o que falta — é o único estado que ainda pode existir em
          // cédula assinada antes desta mudança.
          empty: signedAt == null
              ? 'Ainda não assinada'
              : 'Assinada em ${_date(signedAt!)} — sem o papel anexado',
          subtitle: signedAt == null ? '' : 'Assinada em ${_date(signedAt!)}',
          onOpen: onOpenSigned,
          onPick: null,
          busy: false,
        ),
      if (signed != null || signedAt != null) const SizedBox(height: 8),
      if (registry != null || registeredAt != null)
        _ReturnedDocRow(
          icon: Icons.gavel_outlined,
          title: 'Via registrada',
          file: registry,
          empty: registeredAt == null
              ? 'Ainda não registrada'
              : 'Registrada${registryNumber.isEmpty ? '' : ' sob $registryNumber'}'
                  ' — via ainda no cartório',
          subtitle: registeredAt == null
              ? ''
              : 'Registrada em ${_date(registeredAt!)}'
                  '${registryNumber.isEmpty ? '' : ' sob $registryNumber'}',
          onOpen: onOpenRegistry,
          onPick: onPickRegistry,
          busy: busy,
        ),
    ]);
  }
}

/// Uma linha do cartão acima: o documento, o que se sabe dele, e o que dá para
/// fazer com ele.
class _ReturnedDocRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final BarterFileModel? file;
  final String empty;
  final String subtitle;
  final bool busy;
  final VoidCallback? onOpen;
  final VoidCallback? onPick;

  const _ReturnedDocRow({
    required this.icon,
    required this.title,
    required this.file,
    required this.empty,
    required this.subtitle,
    required this.busy,
    required this.onOpen,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final anexado = file != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: anexado ? AppColors.approvedBg : AppColors.pendingBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (anexado ? AppColors.approved : AppColors.pending).withValues(alpha: 0.35),
        ),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: anexado ? AppColors.approved : AppColors.pending),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              title,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark),
            ),
            const SizedBox(height: 2),
            Text(
              anexado
                  ? '${file!.fileName} • ${file!.sizeLabel}'
                      '${subtitle.isEmpty ? '' : ' • $subtitle'}'
                  : empty,
              style: TextStyle(fontSize: 11.5, color: AppColors.textMedium),
            ),
          ]),
        ),
        if (anexado && onOpen != null)
          IconButton(
            tooltip: 'Baixar',
            onPressed: onOpen,
            icon: const Icon(Icons.download_outlined, size: 20),
          ),
        if (onPick != null)
          busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: onPick,
                  child: Text(anexado ? 'Trocar' : 'Anexar'),
                ),
      ]),
    );
  }
}

class _ScrCard extends StatelessWidget {
  final BarterFileModel? file;
  final DateTime? consultedAt;
  final bool uploading;
  final VoidCallback? onPick;
  final VoidCallback? onOpen;
  final VoidCallback? onPickDate;

  const _ScrCard({
    required this.file,
    required this.consultedAt,
    required this.uploading,
    required this.onPick,
    required this.onOpen,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    final anexado = file != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: anexado ? AppColors.approvedBg : AppColors.pendingBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (anexado ? AppColors.approved : AppColors.pending).withValues(alpha: 0.35),
          ),
        ),
        child: Row(children: [
          Icon(
            anexado ? Icons.picture_as_pdf_outlined : Icons.upload_file_outlined,
            size: 20,
            color: anexado ? AppColors.approved : AppColors.pending,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                anexado ? file!.fileName : 'SCR ainda não anexado',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark),
              ),
              const SizedBox(height: 2),
              Text(
                anexado
                    ? '${file!.sizeLabel} • enviado por ${file!.uploadedBy}'
                    : 'Obrigatório: a CPR é crédito, e sem o SCR ela não é emitida.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMedium),
              ),
            ]),
          ),
          if (anexado && onOpen != null)
            IconButton(
              tooltip: 'Baixar o SCR',
              onPressed: onOpen,
              icon: const Icon(Icons.download_outlined, size: 20),
            ),
          if (onPick != null)
            uploading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: anexado ? 'Substituir o SCR' : 'Anexar o SCR',
                    onPressed: onPick,
                    icon: Icon(anexado ? Icons.autorenew : Icons.attach_file, size: 20),
                  ),
        ]),
      ),
      const SizedBox(height: 10),
      _DateField(label: 'Data da consulta ao SCR', value: consultedAt, onTap: onPickDate),
    ]);
  }
}

/// AS NOTAS FISCAIS do faturamento, como a cédula as cita (cláusula VII).
///
/// LEITURA, e é o ponto: elas eram dois campos de texto aqui, digitados por quem
/// não emitia a nota, e cabia uma só. Agora chegam de quem as emitiu, com o
/// arquivo junto — e o botão ao lado de cada uma é o que permite ao emissor
/// conferir o documento que o título afirma, sem pedir o PDF a ninguém.
class _InvoicesCard extends StatelessWidget {
  final List<CprInvoiceRef> invoices;
  final List<BarterInvoiceModel> barterInvoices;
  final ValueChanged<String>? onOpen;

  const _InvoicesCard({
    required this.invoices,
    required this.barterInvoices,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (invoices.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.pendingBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.pending.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(Icons.receipt_long_outlined, size: 19, color: AppColors.pending),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Nenhuma nota fiscal anexada ainda. Ela é do faturista, e é ela que '
              'a cédula cita como origem da dívida.',
              style: TextStyle(fontSize: 12, color: AppColors.textMedium, height: 1.35),
            ),
          ),
        ]),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < invoices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(children: [
                Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.invoiced),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      'NF ${invoices[i].label}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark),
                    ),
                    if (invoices[i].duplicateNumber.isNotEmpty)
                      Text(
                        'DUP ${invoices[i].duplicateNumber}',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textMedium),
                      ),
                  ]),
                ),
                // O botão só aparece quando há ARQUIVO: as notas herdadas do
                // campo de texto antigo existem sem documento, e oferecer um
                // download que levaria 404 seria pior do que não oferecer.
                if (onOpen != null && i < barterInvoices.length && barterInvoices[i].file != null)
                  IconButton(
                    tooltip: 'Baixar a nota',
                    onPressed: () => onOpen!(barterInvoices[i].id),
                    icon: const Icon(Icons.download_outlined, size: 19),
                  ),
              ]),
            ),
          ),
      ],
    );
  }
}

/// A resposta de um diálogo de ato do emissor — a assinatura ou o registro.
class _IssuanceAnswer {
  final DateTime? date;
  final String note;
  final String registryNumber;
  final String registryPlace;

  /// O DOCUMENTO QUE VOLTOU, quando o ato o pede. Nome e bytes, e não um
  /// caminho: no celular o arquivo escolhido mora num diretório temporário que
  /// pode sumir antes do envio.
  final String? fileName;
  final List<int>? fileBytes;

  const _IssuanceAnswer({
    required this.date,
    required this.note,
    required this.registryNumber,
    required this.registryPlace,
    this.fileName,
    this.fileBytes,
  });
}

/// O ESCOLHEDOR DE ARQUIVO dentro do diálogo de um ato.
///
/// Ele mostra o NOME do que foi escolhido em vez de um "arquivo selecionado":
/// quem lança a cédula assinada de uma permuta acabou de mexer em vários PDFs
/// parecidos, e o nome é a única coisa que responde "é este mesmo?".
class _AttachmentPicker extends StatelessWidget {
  final String label;
  final bool required;
  final String? fileName;
  final Future<void> Function() onPick;

  const _AttachmentPicker({
    required this.label,
    required this.required,
    required this.fileName,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final escolhido = fileName != null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: escolhido ? AppColors.approvedBg : AppColors.pendingBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (escolhido ? AppColors.approved : AppColors.pending).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            escolhido ? Icons.check_circle_outline : Icons.attach_file,
            size: 18,
            color: escolhido ? AppColors.approved : AppColors.pending,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  fileName ?? (required ? 'Obrigatório • PDF ou imagem' : 'PDF ou imagem'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onPick,
            child: Text(escolhido ? 'Trocar' : 'Escolher'),
          ),
        ],
      ),
    );
  }
}

/// O ATO DO EMISSOR da vez, como o rodapé precisa dele: o rótulo, o ícone, se
/// ele pode ser tomado agora e o que acontece ao tocá-lo.
class _IssuanceAction {
  final String label;
  final IconData icon;
  final bool enabled;
  final String tooltip;
  final Future<void> Function() run;

  const _IssuanceAction({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.tooltip,
    required this.run,
  });
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

  /// Null DESLIGA o campo — é como a cédula já emitida (ou aberta por quem não
  /// preenche) mostra as datas: legíveis, e sem convidar ao toque.
  final VoidCallback? onTap;

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
