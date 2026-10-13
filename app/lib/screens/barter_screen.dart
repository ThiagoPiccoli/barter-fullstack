import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../services/num_input.dart';
import '../theme/app_theme.dart';
import '../models/barter_simulation.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/api/api_client.dart';
import '../services/barter_draft.dart';
import '../services/barter_math.dart';
import '../services/tax_regime.dart';
import '../widgets/class_avatar.dart';
import '../widgets/filter_bar.dart';
import '../widgets/common_widgets.dart';
import 'edit_forms.dart';
import 'send_simulation.dart';

/// Construtor de permuta.
///
/// O consultor escolhe a CULTURA primeiro — cada cultura aberta (Soja 26/27,
/// Milho 2027) é um Barter à parte, com a sua tabela —, depois o PRODUTOR, a
/// UNIDADE e os INSUMOS, com a ÁREA PLANTADA daquela cultura. Os valores vêm da
/// versão vigente da cultura escolhida, e é ela que converte o custo dos
/// insumos em sacas. Sem Barter aberto não existe permuta nova, e a tela diz
/// isso em vez de montar um pedido que o servidor recusaria.
///
/// O ADMIN usa a mesma tela para GERAR permuta (quando o cliente liga para a
/// central): ele escolhe entre todos os produtores, e a permuta nasce do
/// consultor da carteira do produtor escolhido — é ele quem segue com ela. Ver
/// [_byAdmin].
class NewBarterScreen extends StatefulWidget {
  /// Quem está montando: o consultor dono da carteira, ou o admin que gera a
  /// permuta em nome dele.
  final UserModel consultant;

  /// Uma SIMULAÇÃO sendo retomada, quando a tela foi aberta pela aba de
  /// simulações.
  ///
  /// Null é o caso normal — a aba "Nova Permuta", com a tela em branco. Com uma
  /// simulação, as três etapas já vêm respondidas e salvar REESCREVE esta mesma
  /// simulação, em vez de deixar uma segunda cópia na lista.
  final BarterSimulation? simulation;

  /// Um RASCUNHO JÁ REGISTRADO sendo remontado — a permuta que voltou para a
  /// mão do consultor depois de o admin liberar a alteração dela (ou que ainda
  /// não foi encaminhada).
  ///
  /// É a mesma tela, e de propósito: remontar uma permuta é escolher insumos
  /// contra as mesmas regras de mínimo, com a mesma lista e a mesma conta em
  /// sacas. O que muda é o desfecho — aqui o botão do rodapé grava no SERVIDOR
  /// (`PUT /barters/:code/inputs`) em vez de guardar uma simulação no aparelho,
  /// e as etapas de produtor e unidade não existem: as duas estão congeladas no
  /// registro, e trocá-las seria outra permuta.
  final BarterModel? draft;

  const NewBarterScreen({
    super.key,
    required this.consultant,
    this.simulation,
    this.draft,
  });
  @override
  State<NewBarterScreen> createState() => _NewBarterScreenState();
}

/// Como ordenar a lista de insumos. Sem preço: o consultor não vê R$, então
/// "mais caro primeiro" não existe do lado dele.
enum _InputSort { name, chosenFirst }

class _NewBarterScreenState extends State<NewBarterScreen> {
  final Map<String, double> _inputQty = {};
  String? _producerId;

  /// A UNIDADE onde o produtor vai retirar os insumos (etapa 2).
  ///
  /// É logística e nada mais: qualquer unidade serve, e ela não muda quem
  /// analisa a permuta — isso é sempre o gerente do consultor. A etapa existe
  /// aqui, e não no cadastro do produtor, porque a retirada é combinada caso a
  /// caso: o mesmo produtor pode buscar em praças diferentes ao longo da safra.
  String? _unitId;

  String _searchQuery = '';

  /// Recortes da lista de insumos. Com o catálogo real (centenas de itens), a
  /// busca por texto sozinha obriga a saber o nome antes de procurar — e quem
  /// monta a permuta pensa por classe ("agora os herbicidas") e pelo que já
  /// escolheu, não por nome exato.
  String? _classId;
  bool _onlyChosen = false;
  _InputSort _sort = _InputSort.name;

  /// A CULTURA em que esta permuta será paga — a SAFRA dela ("Soja 26/27"), e a
  /// primeira decisão. É do consultor, junto com o produtor: é ele quem sabe o
  /// que o cliente vai plantar naquele talhão. Fixa numa remontagem: a permuta
  /// é de uma cultura só.
  String? _seasonId;

  /// A ÁREA PLANTADA (ha) da cultura que a permuta cobre — a régua dos mínimos
  /// por hectare, do seguro e do teto da garantia.
  final _area = TextEditingController();

  /// O SEGURO, quando a versão o oferece como opcional: o que o produtor quis.
  bool _wantsInsurance = false;

  /// O MUNICÍPIO DO SEGURO escolhido na opção do seguro. `null` é "o do
  /// cadastro do produtor", que é por onde a escolha começa — a lavoura quase
  /// sempre fica onde o produtor mora, e quando não fica o consultor troca.
  String? _insuranceCity;

  /// A simulação que esta tela está escrevendo, quando já existe uma.
  ///
  /// Vem preenchida ao retomar uma simulação, e passa a existir no primeiro
  /// "Salvar" de uma permuta nova. É ela que faz o segundo toque em "Salvar"
  /// REESCREVER a simulação — sem isso, cada toque deixaria mais uma cópia da
  /// mesma permuta na lista.
  String? _simulationId;


  /// A permuta registrada que esta tela está remontando, quando é o caso.
  BarterModel? get _draft => widget.draft;

  @override
  void initState() {
    super.initState();

    // A REMONTAGEM de um rascunho já registrado: produtor, unidade e imposto
    // vêm congelados do registro, e só os insumos estão em jogo. Ela sai daqui
    // com as três etapas respondidas, direto na lista de insumos.
    final draft = widget.draft;
    if (draft != null) {
      _producerId = draft.producerId;
      _unitId = draft.unitId;
      // A CULTURA da permuta é a safra dela, fixa desde o registro; a área e a
      // escolha do seguro vêm como foram gravadas, e podem ser corrigidas.
      _seasonId = draft.seasonId;
      if (draft.plantedAreaHa > 0) _area.text = formatQty(draft.plantedAreaHa);
      _wantsInsurance = draft.insuranceChoice == InsuranceChoice.accepted;
      if (draft.insuranceCity.isNotEmpty) _insuranceCity = draft.insuranceCity;
      for (final item in draft.inputs) {
        if (item.quantity > 0) _inputQty[item.productId] = item.quantity;
      }
      _loadDraftVersion(draft);
      return;
    }

    final simulation = widget.simulation;
    if (simulation == null) {
      // UMA CULTURA SÓ aberta não vira escolha: ela já é a resposta.
      if (AppData.currentVersions.length == 1) _seasonId = AppData.currentVersions.single.seasonId;
      return;
    }
    _simulationId = simulation.id;
    _producerId = simulation.producerId;
    _unitId = simulation.unitId;
    // A CULTURA guardada com a simulação. As guardadas antes das safras por
    // cultura só têm o grão — e a versão vigente dele é a resposta.
    _seasonId = AppData.versionOfSimulation(simulation)?.seasonId ??
        (simulation.seasonId.isEmpty ? null : simulation.seasonId);
    if (simulation.plantedAreaHa > 0) _area.text = formatQty(simulation.plantedAreaHa);
    _wantsInsurance = simulation.insurance ?? false;
    if (simulation.insuranceCity.isNotEmpty) _insuranceCity = simulation.insuranceCity;
    _inputQty.addAll(simulation.inputQuantities);

    // A simulação é mais velha do que o cadastro: entre guardar e retomar, o
    // produtor pode ter saído da carteira e a unidade pode ter sido desativada.
    // A tela sozinha só voltaria para a etapa 1, sem dizer por quê — e o
    // consultor concluiria que o app perdeu a simulação dele.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_producer == null) {
        _toast(
          '${simulation.producerName} não está mais na sua carteira. Escolha outro produtor.',
        );
      } else if (_unit == null) {
        _toast('A unidade ${simulation.unitName} não está mais disponível. Escolha outra.');
      }
    });
  }

  /// A TABELA DA PERMUTA que está sendo remontada, quando a tela está em modo
  /// de alteração.
  ///
  /// Ela é buscada no servidor (`GET /barters/:code/version`) porque pode ser de
  /// uma gestão ANTERIOR: a alteração atravessa versões da mesma cultura, e os
  /// preços continuam sendo os da gestão em que a permuta foi fechada. Montar
  /// com a tabela vigente mostraria ao consultor um total em sacas diferente do
  /// que o servidor gravaria.
  BarterVersionModel? _draftVersion;

  /// E se ela não veio (sem rede, gestão apagada), o que houve.
  String? _versionError;

  /// Busca a tabela da permuta em remontagem.
  ///
  /// Falha em VOZ ALTA, ao contrário da linha do tempo do detalhe: sem a tabela
  /// não há preço, e uma tela de alteração que abrisse "vazia" deixaria o
  /// consultor zerar os insumos sem perceber.
  Future<void> _loadDraftVersion(BarterModel draft) async {
    try {
      final version = await AppData.barterVersion(draft.id);
      if (!mounted) return;
      setState(() => _draftVersion = version);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _versionError = error.message);
    }
  }

  @override
  void dispose() {
    _area.dispose();
    super.dispose();
  }

  /// A VERSÃO que precifica esta tela.
  ///
  /// Na permuta nova é a vigente DA CULTURA escolhida — é ela que diz por quanto
  /// se permuta hoje. Na REMONTAGEM é a da permuta, pelo motivo em
  /// [_draftVersion].
  BarterVersionModel? get _version {
    if (widget.draft != null) return _draftVersion;
    final seasonId = _seasonId;
    return seasonId == null ? null : AppData.versionForSeason(seasonId);
  }

  /// A área plantada informada, ou zero enquanto ela não foi.
  double get _plantedAreaHa => parseNumber(_area.text) ?? 0;

  /// ESCOLHE A CULTURA da permuta nova.
  ///
  /// Os insumos escolhidos antes caem: cada cultura tem a sua tabela, e o que
  /// estava na tabela da soja pode nem existir na do milho. O produtor e a
  /// unidade ficam — eles não dependem da cultura.
  void _chooseCulture(String seasonId) {
    setState(() {
      _seasonId = seasonId;
      _inputQty.clear();
      _inputQty.addAll(_composition.requiredMinimums);
    });
  }

  /// Volta à escolha da cultura (só na permuta nova, com mais de uma aberta).
  void _changeCulture() => setState(() {
        _seasonId = null;
        _inputQty.clear();
      });

  /// A ÁREA mudou: os mínimos por hectare mudam com ela, e os insumos exigidos
  /// sobem até o mínimo novo (nunca descem sozinhos — o que o consultor pôs a
  /// mais é escolha dele).
  void _onAreaChanged(String _) {
    setState(() {
      for (final entry in _composition.requiredMinimums.entries) {
        final current = _inputQty[entry.key] ?? 0;
        if (current < entry.value) _inputQty[entry.key] = entry.value;
      }
    });
  }

  /// A PERMUTA SENDO MONTADA, do ponto de vista do DOMÍNIO.
  ///
  /// Tudo o que se pergunta sobre ela — o que é permutável nesta gestão, quanto
  /// custa, quantas sacas dá, o que as réguas ainda cobram — mora em
  /// `services/barter_draft.dart`. Esta tela guarda o que o consultor TOCOU (a
  /// versão, o produtor, a unidade, a cultura e as quantidades) e pergunta o
  /// resto; assim, refazer a tela não é reescrever a regra.
  ///
  /// Montada a cada leitura, de propósito: ela não tem estado próprio, e o
  /// estado que ela lê muda a cada toque.
  BarterDraft get _composition {
    final producer = _producer;
    final version = _version;
    return BarterDraft(
      version: version,
      producer: producer,
      quantities: _inputQty,
      allInputs: AppData.inputs,
      classes: AppData.classes,
      plantedAreaHa: _plantedAreaHa,
      wantsInsurance: _wantsInsurance,
      // A TAXA do município escolhido entra pronta, na moeda da versão: a busca
      // é do cache, e a regra — se ela se aplica, quanto custa, o que fazer
      // quando falta — é de lá.
      insuranceRate: producer == null ? null : _insuranceRate,
      hasInsuranceRates: _insuranceRates.isNotEmpty,
      offBarterCost: _offBarterCost,
    );
  }

  /// A BASE DE SEGUROS na moeda da versão desta tela — os municípios que a
  /// opção do seguro oferece.
  List<InsuranceRateModel> get _insuranceRates =>
      AppData.insuranceRatesByVersion[_version?.slug] ?? AppData.insuranceRates;

  /// O município que precifica o seguro: o escolhido, ou o do cadastro do
  /// produtor enquanto ninguém escolheu.
  String get _insuranceCityWanted => _insuranceCity ?? _producer?.city ?? '';

  /// A taxa desse município, na moeda da versão — `null` fora da base.
  InsuranceRateModel? get _insuranceRate => _insuranceCityWanted.isEmpty
      ? null
      : AppData.insuranceRateFor(_insuranceCityWanted, versionSlug: _version?.slug);

  /// O município que vai no registro: a grafia da BASE, e só quando a permuta
  /// leva seguro.
  String get _insuranceCityToSend =>
      _composition.insuranceApplies ? (_insuranceRate?.city ?? '') : '';

  /// O ADMIN gerando permuta em nome do consultor do produtor.
  ///
  /// Muda três coisas, e só três: a lista de produtores (todos os que têm
  /// consultor, e não uma carteira), o consultor da permuta (o do produtor) e o
  /// desfecho (registra no servidor na hora — a central tem rede, e a permuta
  /// precisa aparecer na mesa do consultor, não num aparelho que não é dele).
  bool get _byAdmin => widget.consultant.role == UserRole.admin && _draft == null;

  /// Os produtores que esta tela oferece.
  List<ProducerModel> get _wallet => _byAdmin
      ? AppData.producers.where((p) => (p.consultantId ?? '').isNotEmpty).toList()
      : AppData.producersForConsultant(widget.consultant.id);

  /// O NOME do consultor da permuta: quem monta, ou — gerada pelo admin — o
  /// consultor do produtor escolhido.
  String _consultantNameFor(ProducerModel? producer) {
    if (_draft != null) return _draft!.consultantName;
    if (!_byAdmin) return widget.consultant.name;
    final id = producer?.consultantId;
    if (id == null) return 'Consultor do produtor';
    return AppData.consultantById(id)?.name ?? 'Consultor do produtor';
  }

  /// Os insumos que a versão desta tela colocou na mesa.
  List<ProductModel> get _catalog => _composition.catalog;

  /// Os insumos escolhidos, precificados PELA VERSÃO — a entrada da matemática
  /// da permuta (services/barter_math.dart, espelho do cálculo do servidor).
  ///
  /// O valor unitário vem na moeda da LENTE: R$ para a retaguarda, sacas do grão
  /// para o consultor, que é quem monta permuta. As duas atravessam a mesma
  /// conta — ver [BarterVersionModel.costPerSack].
  ProductModel? _productById(String id) => _composition.productById(id);

  /// Produtor (cliente) designado para esta permuta (ou null).
  ProducerModel? get _producer => _producerId == null ? null : AppData.producerById(_producerId!);

  /// A unidade de retirada escolhida (ou null).
  UnitModel? get _unit => AppData.unitById(_unitId);

  /// O que veio de FORA DO BARTER nesta permuta — os pedidos que o admin
  /// atendeu. A conta é da própria permuta (ver
  /// `BarterModel.addedProductRequestsCost`); zero numa permuta nova, que ainda
  /// não tem pedido nenhum.
  double get _offBarterCost => _draft?.addedProductRequestsCost ?? 0;

  /// Sacas da cultura escolhida necessárias para cobrir o custo. Mesmo
  /// arredondamento do servidor: o número da tela é o que será gravado.
  double get _sacksNeeded => _composition.sacksNeeded;

  /// Quantidade mínima obrigatória de um insumo para o produtor atual.
  double _minFor(String inputId) => _composition.minimumFor(inputId);

  /// Há algum insumo com exigência mínima por área para o produtor atual?
  bool get _hasRequiredInputs => _composition.hasRequiredInputs;

  /// Classes que carregam uma regra de mínimo capaz de travar o envio.
  List<ProductClassModel> get _ruledClasses => _composition.ruledClasses;

  /// Progresso (0–1) rumo ao mínimo da classe — proporção, nunca R$.
  double _classProgress(ProductClassModel c) => _composition.progressOn(c);

  /// A classe aparece como cumprida na tela? Só depois de haver permuta.
  bool _classMetOnScreen(ProductClassModel c) => _composition.isMetOnScreen(c);

  /// Classes ainda abaixo do mínimo (para avisar o consultor).
  List<ProductClassModel> get _unmetClasses => _composition.unmetClasses;

  void _setInput(String id, double qty) {
    setState(() {
      // Insumos exigidos por área não podem ficar abaixo do mínimo obrigatório
      // — a regra é do domínio (ver `BarterDraft.clampToMinimum`).
      final v = _composition.clampToMinimum(id, qty);
      if (v <= 0) {
        _inputQty.remove(id);
      } else {
        _inputQty[id] = roundQuantity(v);
      }
    });
  }

  /// Escolhe o produtor. Pré-preenche os insumos exigidos por área com seus
  /// mínimos obrigatórios, calculados a partir da área plantada informada.
  void _selectProducer(String id) {
    final p = AppData.producerById(id);
    // Só aceita produtores da carteira do consultor logado — ou, para o admin,
    // os que TÊM consultor: é ele quem fica com a permuta.
    if (p == null) return;
    if (_byAdmin ? (p.consultantId ?? '').isEmpty : !p.isAttendedBy(widget.consultant.id)) return;
    setState(() {
      _producerId = id;
      _insuranceCity = null;
      _searchQuery = '';
      // OS INSUMOS EXIGIDOS POR ÁREA já entram no mínimo de cada um: eles são
      // obrigatórios, e começar em zero faria o consultor descobrir isso um a
      // um, na recusa do envio. Ver `BarterDraft.requiredMinimums`.
      _inputQty.addAll(_composition.requiredMinimums);
    });
  }

  /// CADASTRA O CLIENTE NOVO de onde ele falta: na escolha do produtor.
  ///
  /// O produtor que o consultor cadastra nasce na carteira dele, e é por isso
  /// que ele pode ser escolhido na volta. A escolha usa o produtor que a tela
  /// DEVOLVE, e não o primeiro da carteira: cancelar escolheria um cliente que
  /// ninguém acabou de cadastrar.
  Future<void> _registerProducer() async {
    final created = await Navigator.push<ProducerModel>(
      context,
      MaterialPageRoute(builder: (_) => const EditProducerScreen()),
    );
    if (created == null || !mounted) return;
    _selectProducer(created.id);
  }

  /// Troca o produtor: limpa a permuta em construção e volta à escolha.
  ///
  /// A unidade cai junto porque a etapa dela vem DEPOIS: voltar para a primeira
  /// etapa com a segunda ainda respondida deixaria a tela mostrando uma
  /// retirada escolhida para um produtor que ainda não existe.
  void _changeProducer() {
    setState(() {
      _producerId = null;
      _unitId = null;
      _insuranceCity = null;
      _searchQuery = '';
      _inputQty.clear();
    });
  }

  /// Escolhe a unidade de retirada (segunda etapa).
  void _selectUnit(String id) {
    if (AppData.unitById(id) == null) return;
    setState(() {
      _unitId = id;
      _searchQuery = '';
    });
  }

  /// Volta para a escolha da unidade, preservando os insumos já montados.
  void _changeUnit() => setState(() {
    _unitId = null;
    _searchQuery = '';
  });

  bool _saving = false;

  /// Dá para GUARDAR o que está montado?
  ///
  /// Repare no que NÃO está aqui: [_classesOk]. Guardar uma permuta incompleta é
  /// o ponto da simulação — o consultor para no meio porque acabou o expediente,
  /// porque falta combinar um item com o produtor, ou porque ainda vai conferir
  /// o estoque. Exigir a permuta pronta para salvar deixaria o botão desligado
  /// exatamente nas horas em que ele serve. Quem cobra o mínimo das classes é o
  /// ENVIO, lá na aba de simulações, e antes dele o próprio servidor.
  bool get _canSave =>
      !_saving &&
      _producerId != null &&
      _unitId != null &&
      _inputQty.values.any((qty) => qty > 0) &&
      // Na REMONTAGEM a área é obrigatória: ela vai ao servidor junto — e na
      // permuta GERADA PELO ADMIN também, pelo mesmo motivo. Na simulação,
      // guardar sem ela é permitido — quem cobra é o envio.
      ((_draft == null && !_byAdmin) || _plantedAreaHa > 0);

  /// Guarda a simulação NO APARELHO. Montar e guardar não falam com o servidor
  /// em momento algum — a permuta é montada na fazenda, onde pode não haver
  /// sinal, e enviar dependia de rede no exato momento em que o consultor estava
  /// mais longe dela.
  ///
  /// GUARDAR é o desfecho; ENVIAR é oferecido logo depois, em `_offerToSend`, e
  /// a ordem é o ponto. O trabalho já está no aparelho quando a pergunta chega,
  /// então dizer "agora não" — ou ficar sem sinal no meio do envio — não custa
  /// nada. Era um botão de enviar NO RODAPÉ, concorrendo com o de guardar, que
  /// fazia a permuta depender de rede para não se perder.
  /// A SIMULAÇÃO como ela está na tela, pronta para ser guardada ou registrada.
  ///
  /// Ela foi extraída de [_save] quando o PEDIDO DE FORA DO BARTER ganhou um
  /// botão nesta tela: os dois caminhos precisam do mesmo objeto — um para
  /// guardá-lo no aparelho, o outro para registrá-lo no servidor —, e duas
  /// cópias desta montagem seriam duas chances de a permuta registrada não ser
  /// a que está na tela.
  BarterSimulation _simulationOf(
    ProducerModel producer,
    UnitModel unit,
    List<MapEntry<String, double>> chosen,
  ) {
    final now = DateTime.now();
    final version = _version;
    return BarterSimulation(
      id: _simulationId ?? BarterSimulation.newId(),
      consultantId: widget.consultant.id,
      producerId: producer.id,
      producerName: producer.name,
      unitId: unit.id,
      unitName: unit.name,
      versionCode: version?.code ?? '',
      // Nome e unidade de cada insumo vão CONGELADOS: sem rede o catálogo do
      // AppData está vazio, e a lista de simulações mostraria uma coluna de ids
      // justamente na situação em que ela é a única coisa que o consultor tem.
      items: [
        for (final entry in chosen)
          SimulationItem(
            productId: entry.key,
            productName: _productById(entry.key)?.name ?? '',
            unit: _productById(entry.key)?.unit ?? '',
            quantity: entry.value,
          ),
      ],
      simulatedSacks: _sacksNeeded,
      // A CULTURA escolhida, guardada com a simulação: ela fica no aparelho até
      // o envio, e enviá-la sem a cultura faria a permuta nascer numa que
      // ninguém escolheu.
      seasonId: version?.seasonId ?? _seasonId ?? '',
      seasonName: version?.seasonName ?? '',
      grainId: version?.grainId ?? '',
      grainName: version?.grainName ?? '',
      plantedAreaHa: _plantedAreaHa,
      insurance: _composition.insuranceChoice,
      insuranceCity: _insuranceCityToSend,
      // O REGIME é o do CADASTRO do produtor, lido agora: a permuta não escolhe
      // imposto, ela herda o que ele declarou ao fisco. Guardá-lo na simulação é
      // só o registro do que valia quando ela foi montada — quem aplica a
      // alíquota é o servidor, no envio, lendo o cadastro de novo.
      taxRegime: producer.taxRegime,
      createdAt: widget.simulation?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _save() async {
    final producer = _producer;
    final unit = _unit;
    final chosen = _inputQty.entries.where((entry) => entry.value > 0).toList();
    if (producer == null || unit == null || chosen.isEmpty) {
      _toast('Escolha o produtor, a unidade de retirada e ao menos um insumo.');
      return;
    }

    // A REMONTAGEM não passa por aqui: ela grava no servidor, não no aparelho.
    if (_draft != null) return _saveDraft();
    // Nem a permuta GERADA PELO ADMIN: ela vai direto à mesa do consultor.
    if (_byAdmin) return _generate(producer, unit, chosen);

    setState(() => _saving = true);
    final simulation = _simulationOf(producer, unit, chosen);

    final persisted = await AppData.saveSimulation(simulation);
    if (!mounted) return;

    // GUARDADA. Só a partir daqui o envio é oferecido — nesta ordem, e não como
    // um segundo botão no rodapé: o trabalho já está no aparelho, então o
    // consultor pode dizer "não" (ou ficar sem sinal no meio do envio) sem
    // perder nada. Era esse o motivo de o envio não morar nesta tela.
    final enviada = await _offerToSend(simulation);
    if (!mounted) return;

    // Retomada a partir da lista: volta para ela, que é de onde o consultor
    // veio. Se a permuta foi encaminhada agora, a simulação já não está lá.
    if (widget.simulation != null) {
      Navigator.pop(context, true);
      return;
    }

    // Vindo da aba "Nova Permuta", a simulação foi ARQUIVADA e a tela volta a
    // ficar em branco. Deixá-la preenchida sugeriria que ainda há algo pendente
    // ali, e o consultor acabaria montando a próxima por cima da que guardou.
    setState(() {
      _saving = false;
      _simulationId = null;
      _inputQty.clear();
      _producerId = null;
      _unitId = null;
      _searchQuery = '';
      _area.clear();
      _wantsInsurance = false;
      _insuranceCity = null;
    });
    // Quem acabou de encaminhar já viu o diálogo do registro: repetir "envie em
    // Simulações" mandaria procurar uma simulação que não existe mais.
    if (enviada) return;
    _toast(
      persisted
          ? 'Simulação de ${producer.name} guardada. Envie ao gerente em Minhas '
                '${brand.copy.barterPluralTitle} › Simulações.'
          : 'Simulação guardada só nesta sessão: o aparelho não permitiu gravá-la. '
                'Envie-a antes de fechar o app.',
    );
  }

  /// A REMONTAGEM gravada no SERVIDOR — o desfecho quando esta tela está
  /// refazendo um rascunho já registrado.
  ///
  /// Ela é o contrário da simulação em quase tudo, e o motivo é o mesmo dos dois
  /// lados: a permuta já EXISTE no servidor. Guardá-la no aparelho criaria uma
  /// segunda versão dela fora dali — e a próxima sincronização não saberia qual
  /// das duas é a permuta. Por isso aqui não há "guardar para depois": ou os
  /// insumos novos entram no registro, ou nada mudou.
  ///
  /// Quem reprecifica é o servidor, pela tabela da versão em que a permuta foi
  /// fechada, e é ele quem confere de novo os mínimos por hectare e por classe —
  /// as mesmas travas do registro. A tela devolve a permuta atualizada a quem a
  /// abriu.
  Future<void> _saveDraft() async {
    final draft = _draft;
    if (draft == null) return;

    setState(() => _saving = true);
    try {
      final updated = await AppData.replaceBarterInputs(
        draft.id,
        _inputQty,
        plantedAreaHa: _plantedAreaHa > 0 ? _plantedAreaHa : null,
        insurance: _composition.insuranceChoice,
        insuranceCity: _insuranceCityToSend.isEmpty ? null : _insuranceCityToSend,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.pop(context, updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnack(context, e);
    }
  }

  /// O PEDIDO DE FORA DO BARTER, feito de onde a falta aparece.
  ///
  /// É aqui que o consultor descobre que falta um item: ele procura o adjuvante
  /// na lista e ele não está lá. Só que o pedido é amarrado a uma PERMUTA, e o
  /// que existe nesta tela é uma SIMULAÇÃO — ela mora no aparelho, e o servidor
  /// não a conhece.
  ///
  /// Então o botão faz as duas coisas num ato só: REGISTRA a permuta como
  /// rascunho e manda o pedido. Não é atalho escondido — o diálogo diz isso
  /// antes de qualquer campo, e o rótulo do botão repete. A alternativa era
  /// mandar o consultor guardar, registrar, achar a permuta em Minhas Permutas e
  /// só então pedir: quatro telas para uma frase.
  ///
  /// Registrar em DUAS etapas (registrar aqui, pedir depois) foi descartado pelo
  /// motivo oposto ao de sempre: o pedido cancelado deixaria uma permuta
  /// registrada que ninguém pediu para registrar.
  ///
  /// Depois do pedido a tela SAI, e tem de sair: a simulação deixou de existir
  /// (virou permuta), e continuar aqui com o botão "Guardar simulação" ligado
  /// registraria a mesma permuta uma segunda vez.
  Future<void> _requestProduct() async {
    final producer = _producer;
    final unit = _unit;
    final chosen = _inputQty.entries.where((entry) => entry.value > 0).toList();
    if (producer == null || unit == null || chosen.isEmpty) {
      _toast('Escolha o produtor, a unidade de retirada e ao menos um insumo antes de pedir.');
      return;
    }

    final simulation = _simulationOf(producer, unit, chosen);
    // GUARDADA ANTES de falar com o servidor, como no envio e pelo mesmo
    // motivo: se a rede cair no meio, o trabalho já está no aparelho — e é a
    // simulação guardada que a reconciliação procura quando a resposta se perde.
    await AppData.saveSimulation(simulation);
    if (!mounted) return;
    // O id fica: quem desiste do pedido e tenta de novo REESCREVE a simulação
    // que acabou de ser guardada. Sem isto, cada abertura do diálogo deixaria
    // mais uma cópia da mesma permuta na lista de simulações.
    setState(() => _simulationId = simulation.id);

    showProductRequestDialog(
      context,
      headline: 'Simulação • ${producer.name}',
      subline: 'Retirada em ${unit.name}',
      notice:
          'Para o que o Barter não tem na tabela. Ao enviar, esta permuta é '
          'REGISTRADA como rascunho seu — ela não vai ao gerente agora — e o '
          'administrador acerta o valor do item pedido.',
      submitLabel: 'Registrar e Pedir',
      onSubmit: (draft) async {
        final barter = await registerToRequestProduct(simulation);
        return AppData.requestBarterProduct(
          barter.id,
          productName: draft.productName,
          unit: draft.unit,
          quantity: draft.quantity,
          note: draft.note,
        );
      },
      successMessage: (barter) =>
          'Pedido enviado. A permuta ${barter.id} ficou como rascunho seu até o '
          'administrador responder.',
      onDone: (barter) {
        if (!mounted) return;
        // DE ONDE ela veio decide para onde ela vai, e são dois lugares
        // diferentes: retomada da lista de simulações, esta tela é uma rota
        // empilhada e volta para a lista (que recarrega sem a simulação que
        // acabou de virar permuta); na aba "Nova Permuta" ela não é rota
        // nenhuma, e um `pop` aqui derrubaria o painel inteiro do consultor.
        if (widget.simulation != null) {
          Navigator.pop(context, true);
          return;
        }
        // A aba volta a ficar em branco, como depois de guardar: a simulação
        // deixou de existir, e um formulário preenchido sugeriria que ainda há
        // algo pendente ali — o consultor montaria a próxima por cima dela.
        setState(() {
          _simulationId = null;
          _inputQty.clear();
          _producerId = null;
          _unitId = null;
          _searchQuery = '';
          _area.clear();
          _wantsInsurance = false;
          _insuranceCity = null;
        });
      },
    );
  }

  /// A PERMUTA GERADA PELO ADMIN — registrada no servidor, como rascunho do
  /// consultor do produtor.
  ///
  /// Sem simulação no aparelho: a simulação é do consultor (ela mora no
  /// aparelho DELE, à espera do parecer), e uma guardada aqui ficaria num lugar
  /// onde ele não a vê. O registro direto põe a permuta na mesa de quem segue
  /// com ela; quem a gerou fica na linha do tempo (o servidor grava o admin no
  /// evento do registro).
  ///
  /// SEM ENCAMINHAR: encaminhar pede o parecer e a cédula, e os dois são do
  /// consultor, que conhece o produtor.
  Future<void> _generate(
    ProducerModel producer,
    UnitModel unit,
    List<MapEntry<String, double>> chosen,
  ) async {
    final version = _version;
    if (version == null) return;
    setState(() => _saving = true);
    try {
      final barter = await AppData.createBarter(
        producerId: producer.id,
        unitId: unit.id,
        seasonId: version.seasonId,
        plantedAreaHa: _plantedAreaHa,
        inputQuantities: Map.fromEntries(chosen),
        insurance: _composition.insuranceChoice,
        insuranceCity: _insuranceCityToSend,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          '${barter.id} gerada para a carteira de ${barter.consultantName}. Ela fica '
          'como rascunho dele até ele escrever o parecer e encaminhá-la.',
        ),
      ));
      Navigator.pop(context, barter);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnack(context, e);
    }
  }

  /// "Encaminhar agora?" — a pergunta que vem logo depois de guardar.
  ///
  /// Ela é BARATA de propósito: não fala com o servidor. Só quem responde que
  /// sim é que entra no fluxo de envio (que aí sim busca a tabela vigente e
  /// confere o que mudou). Perguntar depois de já ter tentado a rede faria a
  /// tela pedir sinal para quem só queria guardar e ir embora.
  ///
  /// Devolve `true` quando a permuta foi mesmo registrada.
  Future<bool> _offerToSend(BarterSimulation simulation) async {
    final agora = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.bookmark_added_outlined, color: AppColors.primary, size: 40),
        title: const Text('Simulação guardada'),
        content: Text(
          'A permuta de ${simulation.producerName} está guardada neste aparelho. '
          'Quer registrá-la agora? No passo seguinte você escreve o seu parecer e '
          'escolhe entre deixá-la como rascunho ou encaminhá-la ao gerente. Se '
          'preferir, ela espera em Minhas ${brand.copy.barterPluralTitle} › Simulações.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Agora não')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
    if (agora != true || !mounted) return false;

    // O resumo do envio vem em seguida, e não é repetição do que ele acabou de
    // ver: é lá que ele escreve o PARECER e escolhe entre guardar o rascunho e
    // encaminhar ao gerente.
    return sendSimulationToManager(
      context,
      simulation: simulation,
      consultant: widget.consultant,
    );
  }

  /// Rebaixa o PACOTE do Barter — tabela, catálogo, classes, carteira e
  /// unidades —, que é tudo o que esta tela lê, e o grava no aparelho.
  ///
  /// É o pacote inteiro e não só a versão: a tabela de valores referencia o
  /// catálogo, e atualizar uma sem a outra deixaria a tela calculando sacas com
  /// as duas metades de momentos diferentes.
  Future<void> _refreshVersion() async {
    try {
      await AppData.syncOfflinePackage();
    } on ApiException catch (e) {
      // Sem rede a tela continua com o que tinha — que agora pode vir do
      // aparelho. Só avisa quem não tem nada: para quem já baixou uma vez, o
      // silêncio é a resposta certa, porque a tela continua utilizável.
      if (mounted && AppData.lastSyncAt == null) _toast(e.message);
    }
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  /// Formata um percentual de regra (ex.: 2,5%).
  String _fmtPct(double v) {
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '${s.replaceAll('.', ',')}%';
  }

  @override
  Widget build(BuildContext context) {
    final version = _version;
    final producer = _producer;
    final unit = _unit;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _draft != null
              ? 'Alterar insumos • ${_draft!.id}'
              : _byAdmin
              ? 'Gerar ${brand.copy.barterTitle}'
              : widget.simulation == null
              ? 'Nova ${brand.copy.barterTitle}'
              : 'Simulação • ${widget.simulation!.producerName}',
        ),
        actions: const [LogoutButton()],
      ),
      // As etapas, na ordem em que uma habilita a seguinte: a CULTURA define a
      // tabela; o produtor e a unidade dizem de quem é e onde se retira; só
      // então os insumos, com a área plantada.
      // A REMONTAGEM depende da tabela DA PERMUTA, que vem do servidor: ela pode
      // ser de uma gestão anterior, e é ela que precifica esta tela.
      body: _draft != null && _draftVersion == null
          ? _buildLoadingDraftVersion()
          // A ALTERAÇÃO atravessa VERSÕES da mesma cultura, enquanto ela tiver
          // Barter aberto. É a mesma regra que o servidor aplica (ver
          // `change-request.ts`), dita aqui para a tela não abrir um caminho que
          // termina em 422.
          : _draft != null && !_draftCultureOpen
          ? _buildDraftCultureClosed()
          : _draft == null && _seasonId == null && AppData.currentVersions.isNotEmpty
          ? _buildCultureStep()
          : version == null || (_draft == null && !version.isOpen)
          ? _buildClosedBarter()
          : producer == null
          ? _buildProducerStep(version)
          : unit == null
          ? _buildUnitStep(version, producer)
          : _buildInputStep(version, producer, unit),
    );
  }

  /// A cultura da permuta em remontagem ainda tem Barter aberto?
  ///
  /// A alteração atravessa versões (a permuta da primeira soja continua
  /// alterável com a terceira no ar) e não atravessa o fim da venda daquela
  /// cultura. Mesma regra do servidor, em `cultureRefusal`.
  bool get _draftCultureOpen {
    final seasonId = _draft?.seasonId ?? '';
    if (seasonId.isEmpty) return false;
    return AppData.versionForSeason(seasonId)?.isOpen == true;
  }

  /// A tabela da permuta está a caminho, ou não veio.
  ///
  /// Falha em VOZ ALTA, ao contrário da linha do tempo do detalhe: sem a tabela
  /// não há preço nesta tela, e uma alteração aberta "vazia" deixaria o
  /// consultor mexer em quantidades cujo total ele não pode ver.
  Widget _buildLoadingDraftVersion() {
    final error = _versionError;
    if (error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 40),
        Icon(Icons.cloud_off_outlined, size: 56, color: AppColors.textLight),
        const SizedBox(height: 14),
        Text(
          'Não deu para abrir a tabela desta permuta',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark),
        ),
        const SizedBox(height: 8),
        Text(
          '$error\n\nOs valores da ${_draft!.id} são os do '
          '${brand.copy.programTitle} ${_draft!.versionCode}, e sem eles não dá para '
          'remontar os insumos. Tente de novo quando tiver sinal.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textMedium),
        ),
        const SizedBox(height: 18),
        Center(
          child: FilledButton.icon(
            onPressed: () {
              setState(() => _versionError = null);
              _loadDraftVersion(_draft!);
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Tentar de novo'),
          ),
        ),
      ],
    );
  }

  /// A cultura da permuta a remontar não tem Barter aberto, e por isso ela não
  /// se remonta: remontá-la seria reabrir a venda de uma cultura que a operação
  /// parou de vender.
  Widget _buildDraftCultureClosed() {
    final cultura = _draft!.seasonName.isNotEmpty ? _draft!.seasonName : 'desta cultura';
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 40),
        Icon(Icons.grass_outlined, size: 56, color: AppColors.textLight),
        const SizedBox(height: 14),
        Text(
          'O ${brand.copy.programTitle} de $cultura está fechado',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark),
        ),
        const SizedBox(height: 8),
        Text(
          'A ${_draft!.id} é de $cultura (${brand.copy.programTitle} ${_draft!.versionCode}). '
          'A alteração vale enquanto a cultura da permuta tiver um ${brand.copy.programTitle} '
          'aberto. Fale com o administrador.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textMedium),
        ),
      ],
    );
  }

  /// A ESCOLHA DA CULTURA — a primeira etapa da permuta nova.
  ///
  /// Cada cultura aberta é um Barter à parte, com a sua tabela de insumos, a
  /// sua cotação e o seu seguro: a escolha vem antes de tudo porque ela decide
  /// quais insumos existem na lista.
  Widget _buildCultureStep() {
    final versions = AppData.currentVersions;
    return RefreshIndicator(
      onRefresh: _refreshVersion,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const OfflineBanner(),
          _hint(
            icon: Icons.grass,
            color: AppColors.grain,
            text: 'Etapa 1: escolha a cultura em que o produtor vai pagar.',
          ),
          const SizedBox(height: 10),
          for (final version in versions)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                enabled: version.isOpen,
                onTap: version.isOpen ? () => _chooseCulture(version.seasonId) : null,
                leading: CircleAvatar(
                  backgroundColor: AppColors.grainBg,
                  child: Icon(Icons.grass, color: AppColors.grain),
                ),
                title: Text(
                  version.seasonName.isNotEmpty ? version.seasonName : version.grainName,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark),
                ),
                subtitle: Text(
                  '${brand.copy.programTitle} ${version.code}'
                  '${version.endsAt != null ? ' • até ${_shortDate(version.endsAt!)}' : ''}'
                  '${version.insurancePolicy != InsurancePolicy.none ? ' • ${version.insurancePolicy.label.toLowerCase()}' : ''}'
                  '${version.isOpen ? '' : ' • fechado'}',
                  style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                ),
                trailing: Icon(Icons.chevron_right, color: AppColors.textLight),
              ),
            ),
        ],
      ),
    );
  }

  /// Sem Barter aberto não há o que montar: nem grão, nem valores, nem regra.
  /// A tela diz isso — e não deixa o consultor descobrir no envio.
  ///
  /// São TRÊS situações diferentes atrás da mesma tela vazia, e confundi-las é
  /// caro. "Barter fechado" respondido a quem nunca baixou a tabela manda o
  /// consultor embora achando que não há o que fazer — quando bastava conectar
  /// uma vez. O que separa as duas é [AppData.lastSyncAt]: com ele, o servidor
  /// já respondeu alguma vez, e a ausência de versão é um fato do negócio; sem
  /// ele, ninguém nunca perguntou.
  Widget _buildClosedBarter() {
    final version = _version;
    final neverSynced = AppData.lastSyncAt == null;
    final closed = version != null && !version.isOpen;
    // Outra cultura ainda vende? Então a saída é escolher outra, e não esperar.
    final others = AppData.currentVersions.where((v) => v.isOpen && v.seasonId != _seasonId);

    final String title;
    final String body;
    if (neverSynced) {
      title = 'Baixe o ${brand.copy.programTitle} uma vez';
      body =
          'Este aparelho ainda não tem a tabela de valores. Conecte-se à '
          'internet e atualize: depois disso você monta simulações offline, '
          'inclusive abrindo o app sem sinal.';
    } else if (closed) {
      title = '${brand.copy.programTitle} de ${version.seasonName} fechado';
      body =
          'A versão ${version.code} não aceita permuta agora. Assim que o administrador '
          'publicar a próxima, ela aparece aqui.';
    } else {
      title = '${brand.copy.programTitle} fechado no momento';
      body =
          'Não há lançamento aberto para registrar permutas. Assim que o '
          'administrador publicar a próxima versão, ela aparece aqui.';
    }

    return RefreshIndicator(
      onRefresh: _refreshVersion,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 40),
          Icon(
            neverSynced ? Icons.cloud_download_outlined : Icons.event_busy_outlined,
            size: 64,
            color: AppColors.textLight,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMedium),
          ),
          // Quem chegou aqui abrindo uma simulação precisa ouvir a outra metade:
          // ela não se perdeu. Sem esta frase, a tela em branco no lugar da
          // permuta que ele montou diz exatamente o contrário — e o consultor
          // remonta tudo do zero quando o Barter reabrir.
          if (widget.simulation != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Sua simulação continua guardada neste aparelho. Assim que houver '
                '${brand.copy.programTitle} aberto, ela é refeita com os mesmos '
                'insumos e volta a poder ser encaminhada.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.primary),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Center(
            child: FilledButton.icon(
              onPressed: _refreshVersion,
              icon: Icon(neverSynced ? Icons.cloud_download_outlined : Icons.refresh, size: 18),
              label: Text(neverSynced ? 'Baixar agora' : 'Verificar novamente'),
            ),
          ),
          if (_draft == null && others.isNotEmpty) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _changeCulture,
                icon: const Icon(Icons.grass, size: 18),
                label: const Text('Escolher outra cultura'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Etapa 1: escolher o produtor da permuta. Vem antes de tudo porque a área
  /// dele define quais insumos são obrigatórios e em que quantidade mínima.
  /// A lista é a CARTEIRA do consultor logado: ele nunca vê produtores dos
  /// colegas — só o admin enxerga todas as carteiras.
  Widget _buildProducerStep(BarterVersionModel version) {
    final wallet = _wallet;
    final query = _searchQuery.trim().toLowerCase();
    final producers = query.isEmpty
        ? wallet
        : wallet
              .where(
                (p) =>
                    p.name.toLowerCase().contains(query) ||
                    p.city.toLowerCase().contains(query) ||
                    p.farmName.toLowerCase().contains(query),
              )
              .toList();

    return Column(
      children: [
        const OfflineBanner(),
        _buildHeader(version),
        if (wallet.isEmpty)
          Expanded(child: _emptyWalletHint())
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: _hint(
              icon: Icons.person_pin_circle_outlined,
              color: AppColors.primary,
              // Só o que fazer agora. Que a área manda nos obrigatórios é
              // verdade, mas é assunto da etapa dos insumos — e lá ela é dita no
              // lugar onde a pessoa vê o efeito, em vez de duas telas antes.
              text: _byAdmin
                  ? 'Escolha o produtor. A permuta fica com o consultor da carteira dele.'
                  : 'Escolha um produtor da sua carteira.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(
              children: [
                Expanded(child: _searchBox('Buscar produtor, fazenda ou cidade...')),
                // O CLIENTE NOVO se cadastra aqui, sem sair da permuta: é aqui
                // que o consultor descobre que ele não está na carteira.
                if (AppData.can(Capability.producersRegister)) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Cadastrar produtor',
                    onPressed: _registerProducer,
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: producers.isEmpty
                ? _emptySearchHint()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    itemCount: producers.length,
                    itemBuilder: (_, i) => _ProducerChoiceTile(
                      producer: producers[i],
                      onSelect: () => _selectProducer(producers[i].id),
                    ),
                  ),
          ),
        ],
      ],
    );
  }

  /// Etapa 2: escolher a UNIDADE de retirada.
  ///
  /// É uma etapa própria, e não um campo no rodapé da lista de insumos, porque
  /// é um combinado com o produtor ("onde você quer buscar?") e não um detalhe
  /// de preenchimento. Qualquer unidade serve — inclusive de outra praça —, e
  /// ela não muda quem analisa a permuta: isso é sempre o gerente do consultor.
  Widget _buildUnitStep(BarterVersionModel version, ProducerModel producer) {
    final all = AppData.units;
    final query = _searchQuery.trim().toLowerCase();
    final units = query.isEmpty
        ? all
        : all
              .where(
                (u) => u.name.toLowerCase().contains(query) || u.city.toLowerCase().contains(query),
              )
              .toList();

    return Column(
      children: [
        const OfflineBanner(),
        _buildHeader(version, producer: producer),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: _hint(
            icon: Icons.store_outlined,
            color: AppColors.primary,
            text:
                'Onde ${producer.name.split(' ').first} vai retirar os insumos. '
                'Pode ser qualquer unidade, combine com ele.',
          ),
        ),
        if (all.isEmpty)
          Expanded(child: _emptyUnitsHint())
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: _searchBox('Buscar unidade ou cidade...'),
          ),
          Expanded(
            child: units.isEmpty
                ? _emptySearchHint()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    itemCount: units.length,
                    itemBuilder: (_, i) =>
                        _UnitChoiceTile(unit: units[i], onSelect: () => _selectUnit(units[i].id)),
                  ),
          ),
        ],
      ],
    );
  }

  /// Não há nenhuma unidade cadastrada — e sem local não há retirada.
  Widget _emptyUnitsHint() {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 40),
        Icon(Icons.store_mall_directory_outlined, size: 56, color: AppColors.textLight),
        const SizedBox(height: 14),
        Text(
          'Nenhuma unidade cadastrada',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark),
        ),
        const SizedBox(height: 8),
        Text(
          'A permuta é retirada em uma unidade, e ainda não há nenhuma no cadastro. '
          'Fale com o administrador.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textMedium),
        ),
        const SizedBox(height: 18),
        Center(
          child: TextButton.icon(
            onPressed: _refreshVersion,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Verificar novamente'),
          ),
        ),
      ],
    );
  }

  /// Etapa 3: montar os insumos (já com os mínimos pré-preenchidos), com o
  /// produtor, a unidade, o Barter vigente, o seguro e o total fixados no
  /// CABEÇALHO.
  Widget _buildInputStep(BarterVersionModel version, ProducerModel producer, UnitModel unit) {
    return Column(
      children: [
        const OfflineBanner(),
        _buildHeader(version, producer: producer, unit: unit),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: _searchBox('Buscar insumo ou código...'),
        ),
        _buildInputFilters(),
        Expanded(child: _buildInputList()),
        _buildFooter(version, producer),
      ],
    );
  }

  /// A ÁREA PLANTADA da cultura que esta permuta cobre.
  ///
  /// Ela era a área do cadastro do produtor, e saiu de lá porque a fazenda
  /// planta mais de uma coisa: dos 120 ha, 60 de soja e 60 de trigo. Aqui ela é
  /// a área DAQUELA cultura, e é a régua de tudo o que é "por hectare": os
  /// mínimos dos insumos, o seguro e o teto da garantia.
  Widget _buildAreaField(BarterVersionModel version) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _area,
        onChanged: _onAreaChanged,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.straighten, size: 18),
          labelText: 'Área plantada de ${version.grainName.toLowerCase()} (ha)',
          helperText: 'Define os mínimos por hectare, o seguro e o teto da garantia.',
          errorText: _plantedAreaHa > 0 || _area.text.isEmpty ? null : 'Informe uma área maior que zero',
        ),
      ),
    );
  }

  /// A barra de filtros da lista de insumos.
  ///
  /// Os chips recortam por CLASSE — que é como quem monta a permuta pensa
  /// ("agora os herbicidas") — e por "escolhidos", que é a revisão do que já
  /// está na permuta sem precisar caçar item por item numa lista de centenas.
  Widget _buildInputFilters() {
    final chosen = _inputQty.values.where((qty) => qty > 0).length;
    return FilterBar<_InputSort>(
      chips: [
        FilterChipData(
          label: 'Todos',
          selected: _classId == null && !_onlyChosen,
          onTap: () => setState(() {
            _classId = null;
            _onlyChosen = false;
          }),
        ),
        // Só aparece quando há o que revisar: chip que devolveria lista vazia
        // é ruído na barra.
        if (chosen > 0)
          FilterChipData(
            label: 'Escolhidos ($chosen)',
            selected: _onlyChosen,
            onTap: () => setState(() => _onlyChosen = !_onlyChosen),
          ),
        for (final productClass in _classesInVersion)
          FilterChipData(
            label: productClass.name,
            selected: _classId == productClass.id,
            onTap: () => setState(() {
              _classId = _classId == productClass.id ? null : productClass.id;
            }),
          ),
      ],
      sortLabel: _sort == _InputSort.name ? 'Nome' : 'Escolhidos',
      sortOptions: const {
        _InputSort.name: 'Nome (A a Z)',
        _InputSort.chosenFirst: 'Escolhidos primeiro',
      },
      current: _sort,
      onSort: (value) => setState(() => _sort = value),
    );
  }

  Widget _searchBox(String hint) => SizedBox(
    height: 40,
    child: TextField(
      onChanged: (v) => setState(() => _searchQuery = v),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => setState(() => _searchQuery = ''),
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      ),
    ),
  );

  /// ABRE O CADASTRO do produtor para correção, sem sair da permuta.
  ///
  /// A permuta EM MONTAGEM lê o cadastro a cada quadro, então a correção
  /// aparece na hora. A permuta JÁ REGISTRADA não: a área dela está congelada no
  /// registro (é o denominador dos mínimos e do investimento), e é isso que o
  /// aviso diz — corrigir o cadastro hoje vale para as PRÓXIMAS.
  Future<void> _editProducer(ProducerModel producer) async {
    final updated = await Navigator.push<ProducerModel>(
      context,
      MaterialPageRoute(builder: (_) => EditProducerScreen(producer: producer)),
    );
    if (updated == null || !mounted) return;
    setState(() {});
    if (_draft != null) {
      _toast('Cadastro atualizado. A área plantada é desta permuta, e se corrige aqui.');
    }
  }

  /// O CABEÇALHO DA PERMUTA — tudo o que a identifica e o que ela custa, num
  /// bloco só, no alto das três etapas.
  ///
  /// Eram quatro faixas empilhadas (o Barter, o produtor, a retirada e o painel
  /// das sacas), e num telefone elas comiam metade da altura antes do primeiro
  /// insumo. Agora são, no máximo, duas linhas:
  ///
  /// 1. a IDENTIFICAÇÃO, numa linha só — o mesmo componente que identifica a
  ///    permuta no resto do app ([BarterIdentity]), com a cultura e a retirada
  ///    junto; as trocas ficam no menu da ponta;
  /// 2. o SEGURO (a opção e o município) e o TOTAL A ENTREGAR — um valor só, o
  ///    da permuta inteira, seguro incluso.
  ///
  /// A segunda linha só existe na etapa dos insumos: antes dela não há conta.
  Widget _buildHeader(BarterVersionModel version, {ProducerModel? producer, UnitModel? unit}) {
    final grain = version.grainName.toLowerCase();
    final menu = _headerMenu(producer, unit);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            child: BarterIdentity.parts(
              singleLine: true,
              code: _draft?.id ?? (widget.simulation != null ? 'Simulação' : 'Nova ${brand.copy.barterTitle.toLowerCase()}'),
              producerName: producer?.name ?? 'Produtor a escolher',
              consultantName: _consultantNameFor(producer),
              areaHa: _plantedAreaHa,
              extra: [
                BarterIdentityFact(
                  icon: Icons.grass,
                  tooltip: 'Cultura e ${brand.copy.programTitle} — pagamento em $grain',
                  value: version.seasonName.isNotEmpty
                      ? '${version.seasonName} • ${version.code}'
                      : '${brand.copy.programTitle} ${version.code}',
                ),
                if (unit != null)
                  BarterIdentityFact(
                    icon: Icons.store_outlined,
                    tooltip: 'Unidade de retirada',
                    value: unit.label,
                  ),
              ],
              trailing: menu,
            ),
          ),
          if (producer != null && unit != null) ...[
            const Divider(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _buildInsuranceOption(version, producer)),
                  const SizedBox(width: 10),
                  // O VALOR DO GRÃO: um número só, o que o produtor entrega
                  // pela permuta inteira — seguro e itens de fora do Barter
                  // inclusos. Eram dois (o painel sem o seguro e o rodapé com
                  // ele), e o consultor tinha de explicar a diferença na fazenda.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('A entregar', style: TextStyle(fontSize: 10, color: AppColors.textMedium)),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: formatSacks(_sacksNeeded),
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary),
                          ),
                          TextSpan(
                            text: ' $grain',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// As TROCAS do cabeçalho: a cultura, o produtor (e o cadastro dele) e a
  /// unidade. Num menu, e não em botões, porque a linha da identificação é uma
  /// só — e trocar é o caso raro, que pode custar um toque a mais.
  ///
  /// Numa REMONTAGEM o produtor, a unidade e a cultura estão congelados no
  /// registro (trocá-los seria outra permuta); sobra editar o cadastro.
  Widget? _headerMenu(ProducerModel? producer, UnitModel? unit) {
    final canChangeCulture = _draft == null && AppData.currentVersions.length > 1;
    final canEditProducer = producer != null && AppData.can(Capability.producersEdit);
    final canChangeProducer = producer != null && _draft == null;
    final canChangeUnit = unit != null && _draft == null;
    if (!canChangeCulture && !canEditProducer && !canChangeProducer && !canChangeUnit) return null;

    return PopupMenuButton<VoidCallback>(
      tooltip: 'Trocar',
      icon: Icon(Icons.more_vert, size: 20, color: AppColors.primary),
      padding: EdgeInsets.zero,
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        if (canChangeCulture)
          PopupMenuItem(value: _changeCulture, child: const Text('Trocar cultura')),
        // EDITAR OS DADOS do cliente, de dentro da permuta: é aqui que o
        // consultor descobre que o cadastro está velho. Ver `EditProducerScreen`.
        if (canEditProducer)
          PopupMenuItem(
            value: () => _editProducer(producer),
            child: Text('Editar dados de ${producer.name.split(' ').first}'),
          ),
        if (canChangeProducer) PopupMenuItem(value: _changeProducer, child: const Text('Trocar produtor')),
        if (canChangeUnit) PopupMenuItem(value: _changeUnit, child: const Text('Trocar unidade')),
      ],
    );
  }

  /// A OPÇÃO DO SEGURO, dentro do cabeçalho: se a permuta leva, por qual
  /// MUNICÍPIO, e quanto custa — em sacas, porque é com grão que ele é pago.
  ///
  /// O município é ESCOLHA do consultor, entre os da base de seguros: começa no
  /// do cadastro do produtor, e se troca quando a lavoura é em outro lugar (quem
  /// arrenda do outro lado do rio). Sem taxa no escolhido, o aviso diz o que
  /// fazer — escolher outro, ou pedir ao administrador —, que é a recusa que o
  /// servidor daria no registro, antecipada.
  Widget _buildInsuranceOption(BarterVersionModel version, ProducerModel producer) {
    final draft = _composition;
    if (version.insurancePolicy == InsurancePolicy.none) {
      return Text('Sem seguro neste ${brand.copy.programTitle}',
          style: TextStyle(fontSize: 11, color: AppColors.textLight));
    }

    final rates = _insuranceRates;
    final chosen = _insuranceRate;
    final applies = draft.insuranceApplies;
    final grain = version.grainName.toLowerCase();

    final String? warning = draft.insuranceBlocked
        ? 'A base de seguros está vazia. Peça ao administrador.'
        : draft.insuranceMissing
        ? (_insuranceCityWanted.isEmpty
              ? 'Escolha o município do seguro.'
              : '$_insuranceCityWanted não tem valor por hectare. Escolha outro município.')
        : null;

    // A segunda linha é do QUANTO: o custo em sacas — ou, faltando a taxa, o
    // que fazer. Fica embaixo, e não ao lado do município, porque num telefone
    // de 360 a linha de cima já divide a largura com o total.
    final String? detail = warning ??
        (applies && draft.insuranceSacks > 0
            ? '+ ${formatSacks(draft.insuranceSacks)} $grain de seguro'
            : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Tooltip(
              message: draft.insuranceOffered ? 'Seguro agrícola (opcional)' : 'Seguro agrícola obrigatório',
              child: Icon(Icons.shield_outlined, size: 16, color: AppColors.atManager),
            ),
            if (draft.insuranceOffered)
              SizedBox(
                height: 28,
                child: FittedBox(
                  child: Switch(
                    value: _wantsInsurance && !draft.insuranceBlocked,
                    onChanged: draft.insuranceBlocked
                        ? null
                        : (value) => setState(() => _wantsInsurance = value),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            // O MUNICÍPIO ocupa o que sobra da linha, e corta com reticências:
            // "Campo Mourão/PR" não cabe inteiro ao lado do total num telefone.
            Expanded(
              child: applies && rates.isNotEmpty
                  ? DropdownButton<String>(
                      value: chosen?.city,
                      isExpanded: true,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      hint: Text('Município do seguro',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: AppColors.textLight)),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                      items: [
                        for (final rate in rates)
                          DropdownMenuItem(
                            value: rate.city,
                            child: Text(rate.city, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (city) => setState(() => _insuranceCity = city),
                    )
                  : Text(
                      draft.insuranceOffered ? 'Seguro (opcional)' : 'Seguro obrigatório',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDark),
                    ),
            ),
          ],
        ),
        if (detail != null)
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: warning != null ? AppColors.pending : AppColors.textMedium,
            ),
          ),
      ],
    );
  }

  /// A lista de insumos do Barter vigente.
  ///
  /// `ListView.builder` não é otimização prematura aqui: cada `_InputTile` é um
  /// widget COM ESTADO, que cria o próprio `TextEditingController`. Com a lista
  /// real (656 insumos), a forma `children:` montava 656 tiles e 656
  /// controllers na abertura da tela — para o consultor ver oito.
  /// Os insumos que a lista mostra: busca + classe + "só os escolhidos", na
  /// ordem pedida.
  List<ProductModel> get _visibleInputs {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _catalog.where((input) {
      if (!input.matches(query)) return false;
      if (_classId != null && input.classId != _classId) return false;
      if (_onlyChosen && (_inputQty[input.id] ?? 0) <= 0) return false;
      return true;
    }).toList();

    filtered.sort((a, b) {
      if (_sort == _InputSort.chosenFirst) {
        final chosenA = (_inputQty[a.id] ?? 0) > 0;
        final chosenB = (_inputQty[b.id] ?? 0) > 0;
        if (chosenA != chosenB) return chosenA ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    return filtered;
  }

  /// Só as classes que TÊM insumo no Barter vigente viram chip — oferecer um
  /// recorte que devolveria lista vazia é um filtro que mente.
  List<ProductClassModel> get _classesInVersion {
    final ids = _catalog.map((input) => input.classId).whereType<String>().toSet();
    return AppData.classes.where((c) => ids.contains(c.id)).toList();
  }

  Widget _buildInputList() {
    final query = _searchQuery.trim().toLowerCase();
    final inputs = _visibleInputs;

    // O cabeçalho (dica + barras de mínimo por classe) só aparece sem busca:
    // quem está procurando um item quer a lista, não a explicação.
    final filtrando = query.isNotEmpty || _classId != null || _onlyChosen;
    final version = _version;
    final header = <Widget>[
      // A ÁREA PLANTADA abre a lista — sempre, com ou sem busca: é ela que
      // define os mínimos que a lista abaixo aplica. Dentro da lista, e não
      // fixa no alto, porque a tela de um telefone estreito não tem altura
      // para mais uma faixa fixa.
      if (version != null) _buildAreaField(version),
      // Com filtro ativo, quantos itens sobraram de quantos — é o que diz se
      // vale continuar rolando ou refinar a busca.
      if (filtrando && inputs.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            '${inputs.length} de ${_catalog.length} insumo(s)',
            style: TextStyle(fontSize: 11, color: AppColors.textLight),
          ),
        ),
      if (query.isEmpty) ...[
        _hint(
          icon: _hasRequiredInputs ? Icons.rule : Icons.info_outline,
          color: AppColors.input,
          // A REGRA que ele pode esbarrar, sem a narração de como o app chegou
          // nela: o que trava a mão dele é o mínimo, e é isso que precisa estar
          // escrito.
          text: _hasRequiredInputs
              ? 'Os obrigatórios já vêm no mínimo da área. Você pode aumentar, não reduzir.'
              : 'Escolha os insumos que o produtor precisa.',
        ),
        const SizedBox(height: 8),
        ..._ruledClasses.map(
          (c) => _ClassRuleTile(
            name: c.name,
            detail: c.ruleType == ClassRuleType.percentOfTotal
                ? 'mín. ${_fmtPct(c.ruleValue)} do total da permuta'
                : 'mínimo por área da propriedade',
            progress: _classProgress(c),
            met: _classMetOnScreen(c),
          ),
        ),
        if (_ruledClasses.isNotEmpty) const SizedBox(height: 8),
      ],
    ];

    // O PEDIDO DE FORA DO BARTER fecha a lista, e só na SIMULAÇÃO: quem está
    // remontando um rascunho chegou aqui pelo detalhe da permuta, que já tem o
    // botão — e lá ele não precisa registrar nada antes.
    // Nem na permuta GERADA PELO ADMIN: quem atende o pedido é ele mesmo.
    final canRequest = _draft == null && !_byAdmin;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      itemCount:
          header.length + (inputs.isEmpty ? 1 : inputs.length) + (canRequest ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < header.length) return header[index];
        if (inputs.isEmpty) return index == header.length ? _emptySearchHint() : _requestTile();
        if (index == header.length + inputs.length) return _requestTile();
        final input = inputs[index - header.length];
        return _InputTile(
          // A chave amarra o estado do tile ao PRODUTO, não à posição: sem
          // ela, filtrar a lista faria o campo de quantidade de um insumo
          // aparecer noutro.
          key: ValueKey(input.id),
          product: input,
          qty: _inputQty[input.id] ?? 0,
          minQty: _minFor(input.id),
          onChanged: (q) => _setInput(input.id, q),
        );
      },
    );
  }

  /// A PORTA DO PEDIDO, no fim da lista de insumos.
  ///
  /// Fim da lista, e não no rodapé: o rodapé é do ato principal desta tela
  /// (guardar), e o pedido é o que se faz quando a lista ACABOU e o item não
  /// estava nela. Quem rolou até aqui é exatamente quem procurou e não achou.
  ///
  /// Discreto de propósito — contorno e uma linha de explicação. Pedir um item
  /// de fora não é o caminho normal da permuta: o normal é montá-la com a
  /// tabela, e o pedido custa uma resposta do administrador.
  Widget _requestTile() => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _saving ? null : _requestProduct,
          icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
          label: const Text('Falta um insumo na lista?'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.input,
            side: BorderSide(color: AppColors.input),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Peça ao administrador o que este Barter não tem. A permuta é '
          'registrada como rascunho seu para o pedido poder ser respondido.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppColors.textLight),
        ),
      ],
    ),
  );

  /// Nada encontrado — dizendo POR QUE, que é o que permite desfazer. Com três
  /// recortes possíveis (busca, classe, escolhidos), "nenhum item encontrado"
  /// sozinho deixa o consultor procurando o que ele mesmo ligou.
  Widget _emptySearchHint() {
    final motivos = [
      if (_searchQuery.trim().isNotEmpty) '"${_searchQuery.trim()}"',
      if (_classId != null) AppData.classById(_classId)?.name ?? 'classe',
      if (_onlyChosen) 'só os escolhidos',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 40, color: AppColors.textLight),
          const SizedBox(height: 8),
          Text(
            motivos.isEmpty
                ? 'Nenhum insumo neste Barter'
                : 'Nenhum insumo em ${motivos.join(' + ')}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textLight),
          ),
          if (motivos.isNotEmpty) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => setState(() {
                _searchQuery = '';
                _classId = null;
                _onlyChosen = false;
              }),
              child: const Text('Limpar filtros', style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  /// Aviso para o consultor sem produtores na carteira: sem carteira não há
  /// permuta — e o caminho é cadastrar o primeiro, ali mesmo.
  Widget _emptyWalletHint() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group_off_outlined, size: 56, color: AppColors.textLight),
          const SizedBox(height: 12),
          Text(
            'Sua carteira de produtores está vazia',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark),
          ),
          const SizedBox(height: 6),
          Text(
            AppData.can(Capability.producersRegister)
                ? 'Cadastre o primeiro produtor para registrar uma permuta. '
                    'Ele entra na sua carteira.'
                : 'Peça ao administrador para cadastrar produtores na sua carteira '
                    'antes de registrar uma permuta.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMedium),
          ),
          if (AppData.can(Capability.producersRegister)) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _registerProducer,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Cadastrar produtor'),
            ),
          ],
        ],
      ),
    ),
  );

  /// O rodapé da etapa 3: o que ainda trava a permuta, o Funrural e o botão de
  /// guardar. O total em sacas mora no cabeçalho — ver [_buildHeader].
  ///
  /// Recebe o [producer] em vez de reler `_producerId`: o documento dele é o que
  /// escolhe entre as alíquotas de CPF e as de CNPJ, e o rodapé só existe dentro
  /// da etapa que já o tem resolvido. Buscá-lo de novo abriria um caminho em que
  /// a busca falha e a conta cai calada nas alíquotas de CPF — imposto errado,
  /// sem aviso nenhum. Pela assinatura isso não é representável.
  Widget _buildFooter(BarterVersionModel version, ProducerModel producer) {
    final sacks = _sacksNeeded;
    final inputCount = _inputQty.values.where((q) => q > 0).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(color: AppColors.cardShadow, blurRadius: 10, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A ÁREA ainda não informada: sem ela não há mínimo por hectare nem
            // seguro, e o registro é recusado.
            if (_plantedAreaHa <= 0) ...[
              Row(
                children: [
                  Icon(Icons.straighten, size: 14, color: AppColors.pending),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Informe a área plantada para fechar a conta e poder registrar.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.pending),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            if (_unmetClasses.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 14, color: AppColors.pending),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Mínimo não atingido: ${_unmetClasses.map((c) => c.name).join(', ')}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.pending,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            // O TOTAL não se repete aqui: ele é o valor único do cabeçalho.
            // Fica só o que explica o número — o item de FORA DO BARTER está no
            // total e não está na lista desta tela (ele não é do catálogo), e
            // sem a frase o número parece errado para quem confere item a item.
            if (_offBarterCost > 0) ...[
              Text(
                'O total inclui ${_draft!.addedProductRequests.length} item(ns) de fora do Barter.',
                style: TextStyle(fontSize: 11, color: AppColors.textMedium),
              ),
              const SizedBox(height: 4),
            ],
            // O IMPOSTO DA ENTREGA, junto do total, porque é onde a conversa
            // acontece: o produtor pergunta "quanto eu entrego?" na fazenda, e a
            // resposta honesta inclui o Funrural. Descobrir depois, na nota, era
            // a diferença virar assunto no pior momento.
            //
            // AVISO, e não escolha. O regime é do produtor e mora no cadastro
            // dele (a opção é feita perante o fisco, uma vez, valendo para todas
            // as entregas): um seletor aqui convidava a marcar a alíquota menor
            // numa permuta específica, que é uma declaração que quem fecha a
            // permuta não tem como fazer. Corrigir o regime é ato do admin, no
            // cadastro.
            if (inputCount > 0) ...[
              _TaxRegimeNotice(
                regime: producer.taxRegime,
                document: producer.document,
                sacks: sacks,
                grainName: version.grainName,
              ),
            ],
            const SizedBox(height: 8),
            // UM botão, e não dois. Enviar ao gerente existe nesta tela, mas
            // DEPOIS de guardar (ver `_offerToSend`), nunca como uma segunda
            // saída aqui: duas saídas deixariam o consultor escolher a que
            // depende de rede no pior lugar para depender dela, e perder o
            // trabalho junto com o envio que não completou.
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _canSave ? _save : null,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(_byAdmin ? Icons.add_task : Icons.bookmark_added_outlined, size: 18),
                label: Text(
                  _saving
                      ? (_draft == null && !_byAdmin ? 'Guardando...' : 'Salvando...')
                      : _draft != null
                      ? 'Salvar insumos da ${_draft!.id}'
                      : _byAdmin
                      ? 'Gerar ${brand.copy.barterTitle.toLowerCase()}'
                      : widget.simulation == null
                      ? 'Guardar simulação'
                      : 'Salvar alterações',
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Dito em voz alta porque é a pergunta que o botão sozinho deixa no
            // ar — "então já foi para o gerente?". Vale com e sem sinal: ter
            // rede não faz a permuta escapar; quem decide o momento é ele.
            //
            // Na REMONTAGEM a frase é outra porque o desfecho é outro: a permuta
            // já existe, o que se está fazendo é reescrever os insumos dela no
            // servidor, e ela continua rascunho até ser encaminhada de novo.
            Text(
              _draft != null
                  ? 'Os insumos são gravados na permuta. Ela continua rascunho até você '
                        'encaminhá-la de novo ao gerente.'
                  : _byAdmin
                  ? 'Ela é registrada como rascunho de ${_consultantNameFor(producer)}, que escreve '
                        'o parecer e a encaminha ao gerente.'
                  : 'Nada é enviado agora: ela fica em Minhas ${brand.copy.barterPluralTitle} › '
                        'Simulações até você encaminhar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textLight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hint({required IconData icon, required Color color, required String text}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// O IMPOSTO DA ENTREGA, no fechamento da permuta: um AVISO, e não uma escolha.
///
/// A entrega de grão é comercialização de produção rural, e sobre ela incidem o
/// Funrural e o Senar. A base da parte previdenciária (a receita da venda ou a
/// folha de pagamento) é a opção FORMAL que o produtor fez perante o fisco: ela
/// vale para o ano e para todas as entregas dele, e por isso mora no CADASTRO.
/// Aqui ela é lida, e é isso que este bloco diz em voz alta.
///
/// Ele já foi um seletor de duas opções, e o seletor era o erro: dois
/// percentuais lado a lado, um deles oito vezes menor, convidam a marcar o
/// barato numa permuta específica. Isso não é preferência de quem fecha a
/// permuta; é uma declaração ao fisco que ele não tem como fazer. Quem corrige
/// o regime é o admin, no cadastro do produtor, e vale da próxima permuta em
/// diante.
///
/// Escolher a FOLHA não isenta a entrega: o Senar continua saindo da
/// comercialização, e por isso a alíquota cai (0,20% de CPF, 0,25% de CNPJ) em
/// vez de zerar. PF ou PJ não é perguntado: sai do documento do produtor.
///
/// O QUANTO sai em SACAS porque é a unidade em que o consultor enxerga a
/// permuta (ele não vê R$), e é a resposta à pergunta que o produtor faz na
/// fazenda: "quanto eu entrego?".
class _TaxRegimeNotice extends StatelessWidget {
  /// O regime do CADASTRO do produtor desta permuta.
  final TaxRegime regime;

  /// O documento dele: é a contagem de dígitos que decide se a alíquota é a de
  /// CPF ou a de CNPJ.
  final String document;

  /// As sacas a entregar, para o aviso dizer quanto o percentual dá em grão.
  final double sacks;
  final String grainName;

  const _TaxRegimeNotice({
    required this.regime,
    required this.document,
    required this.sacks,
    required this.grainName,
  });

  @override
  Widget build(BuildContext context) {
    final rate = taxRateOf(regime, document);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.receipt_long_outlined, size: 16, color: AppColors.info),
          const SizedBox(width: 8),
          // Expanded pela razão de sempre nesta tela: `Text` solto numa `Row`
          // não tem largura máxima, e a linha estoura no telefone estreito.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No cadastro, este produtor recolhe o Funrural '
                  '${regime.shortLabel.toLowerCase()} '
                  '(${rate.toStringAsFixed(2).replaceAll('.', ',')}%).',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.info,
                    height: 1.25,
                  ),
                ),
                Text(
                  'Estimativa de + ${formatSacks(taxAmountOf(sacks, rate))} '
                  '${grainName.toLowerCase()} de Funrural e Senar sobre a entrega.',
                  style: TextStyle(fontSize: 11, color: AppColors.info, height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dia e mês ("31/03") — o encerramento do Barter na escolha da cultura.
String _shortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

class _ClassRuleTile extends StatelessWidget {
  final String name;
  final String detail;
  final double progress;
  final bool met;

  const _ClassRuleTile({
    required this.name,
    required this.detail,
    required this.progress,
    required this.met,
  });

  @override
  Widget build(BuildContext context) {
    final color = met ? AppColors.approved : AppColors.pending;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(met ? Icons.check_circle : Icons.rule, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            met ? 'Exigência atingida • $detail' : 'Exigência: $detail',
            style: TextStyle(fontSize: 11, color: AppColors.textMedium),
          ),
        ],
      ),
    );
  }
}

/// Linha de um insumo na etapa de montagem. Quando [minQty] > 0, o insumo é
/// obrigatório para a área do produtor: vem pré-preenchido e não pode descer
/// abaixo do mínimo.
class _InputTile extends StatefulWidget {
  final ProductModel product;
  final double qty;
  final double minQty;
  final ValueChanged<double> onChanged;

  const _InputTile({
    super.key,
    required this.product,
    required this.qty,
    required this.minQty,
    required this.onChanged,
  });

  @override
  State<_InputTile> createState() => _InputTileState();
}

class _InputTileState extends State<_InputTile> {
  /// Controller próprio (com dispose) para o campo não perder foco/teclado a
  /// cada rebuild — antes era recriado em todo build, com vazamento.
  late final TextEditingController _qtyCtrl = TextEditingController(
    text: widget.qty > 0 ? formatQty(widget.qty) : '',
  );

  ProductModel get product => widget.product;
  double get qty => widget.qty;
  double get minQty => widget.minQty;
  ValueChanged<double> get onChanged => widget.onChanged;

  bool get _required => minQty > 0;

  @override
  void didUpdateWidget(_InputTile old) {
    super.didUpdateWidget(old);
    // Sincroniza o texto apenas quando a mudança veio de fora (botões +/-,
    // pré-preenchimento do mínimo), sem brigar com a digitação do usuário.
    final typed = parseNumberOr(_qtyCtrl.text);
    if ((widget.qty - typed).abs() > 0.004) {
      _qtyCtrl.text = widget.qty > 0 ? formatQty(widget.qty) : '';
      _qtyCtrl.selection = TextSelection.collapsed(offset: _qtyCtrl.text.length);
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // A figura é da CLASSE: com centenas de insumos na lista, é ela
                // que deixa o consultor varrer por bloco (herbicida, adubo) em
                // vez de ler item por item.
                ClassAvatar(productClass: AppData.classById(product.classId)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              product.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                          if (_required) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.input.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'mín. ${formatQty(minQty)} ${product.unit}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.input,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      // O CÓDIGO ao lado da unidade, na linha de apoio: a busca
                      // já aceita procurar por ele, e sem vê-lo escrito o
                      // consultor não tinha como conferir se o insumo que ele
                      // achou é mesmo o que o produtor pediu — dois nomes
                      // parecidos ("Glifosato 480 SL" e "Glifosato 480 WG") só
                      // se distinguem por aí. Some quando o produto não tem
                      // código, em vez de imprimir um traço.
                      Text(
                        [
                          if ((product.sku ?? '').isNotEmpty) product.sku!,
                          _required
                              ? 'Obrigatório • medido em ${product.unit}'
                              : 'Medido em ${product.unit}',
                        ].join(' • '),
                        style: TextStyle(fontSize: 12, color: AppColors.textLight),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StepBtn(
                  icon: Icons.remove,
                  color: AppColors.input,
                  onTap: qty > minQty
                      ? () => onChanged((qty - 1).clamp(minQty, double.infinity))
                      : null,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                      hintText: '0',
                      contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      isDense: true,
                    ),
                    onSubmitted: (v) => onChanged(parseNumberOr(v)),
                    onChanged: (v) => onChanged(parseNumberOr(v)),
                  ),
                ),
                const SizedBox(width: 8),
                _StepBtn(icon: Icons.add, color: AppColors.input, onTap: () => onChanged(qty + 1)),
                const SizedBox(width: 8),
                // Expanded, e não `Spacer` + texto solto: a unidade longa ("saco
                // 50kg") não cabia ao lado dos botões num telefone de 320, e o
                // texto sem largura máxima estourava a linha em vez de cortar.
                Expanded(
                  child: qty > 0
                      ? Text(
                          '${formatQty(qty)} ${product.unit}',
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.input,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Card de escolha do produtor (etapa 1). Destaca a área da propriedade, que é
/// a base das exigências mínimas de insumo da permuta.
class _ProducerChoiceTile extends StatelessWidget {
  final ProducerModel producer;
  final VoidCallback onSelect;

  const _ProducerChoiceTile({required this.producer, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primarySurface,
                child: Text(
                  producer.avatarInitials,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      producer.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      producer.location,
                      style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textLight),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card de escolha da unidade de retirada (etapa 2). Nome e cidade, porque é
/// só isso que a unidade é: um local. Qualquer uma da lista serve.
class _UnitChoiceTile extends StatelessWidget {
  final UnitModel unit;
  final VoidCallback onSelect;

  const _UnitChoiceTile({required this.unit, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primarySurface,
                child: Icon(Icons.store_outlined, size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unit.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      unit.city,
                      style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textLight),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled ? color.withValues(alpha: 0.12) : AppColors.disabledBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: enabled ? color : AppColors.divider),
        ),
        child: Icon(icon, size: 16, color: enabled ? color : AppColors.disabledFg),
      ),
    );
  }
}
