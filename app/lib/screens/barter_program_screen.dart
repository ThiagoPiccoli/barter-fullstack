import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../services/api/api_client.dart';
import '../services/num_input.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// O LANÇAMENTO do Barter, do lado do admin — uma SAFRA POR CULTURA.
///
/// Cada cultura é um Barter à parte: a Soja 26/27 e a Canola 2027 abrem,
/// publicam as suas versões (cada uma com a planilha, a cotação, a meta e o
/// seguro dela), batem meta e encerram sem que a outra perceba. A tela responde
/// "por quanto se permuta ESTA cultura agora": o admin escolhe a safra no topo e
/// vê a versão vigente dela, o vencimento, o seguro, as metas e o histórico.
///
/// DOIS ENCERRAMENTOS, e eles são diferentes de propósito:
///
/// - encerrar a VERSÃO pausa a cultura (a meta bateu, a tabela venceu) — e pode
///   sair outra versão depois, com outra meta;
/// - encerrar a SAFRA é o fim do ciclo daquela cultura. Ela pode ser reaberta,
///   e isso fica na trilha.
///
/// O ENCERRAMENTO POR META é uma OPÇÃO da versão. Nenhum interruptor desta tela
/// fecha nada por conta própria: quem encerra, no automático, é a aprovação do
/// comitê que cruza a meta — no servidor, com autor e hora.
class BarterProgramTab extends StatefulWidget {
  final VoidCallback onChanged;
  const BarterProgramTab({super.key, required this.onChanged});

  @override
  State<BarterProgramTab> createState() => _BarterProgramTabState();
}

class _BarterProgramTabState extends State<BarterProgramTab> {
  bool _loading = false;

  /// A safra que o admin está olhando. Começa na primeira aberta.
  String? _seasonId;

  /// A versão vigente DA SAFRA ESCOLHIDA com METAS. O cache guarda a versão
  /// "crua" (a mesma que o consultor recebe, sem números de retaguarda); o
  /// realizado vem do detalhe.
  BarterVersionModel? _detailed;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  List<SeasonModel> get _openSeasons => AppData.seasons.where((s) => s.isOpen).toList();
  List<SeasonModel> get _closedSeasons => AppData.seasons.where((s) => !s.isOpen).toList();

  /// A safra em foco: a escolhida, se ela ainda está aberta; senão a primeira.
  SeasonModel? get _season {
    final open = _openSeasons;
    for (final season in open) {
      if (season.id == _seasonId) return season;
    }
    return open.isEmpty ? null : open.first;
  }

  Future<void> _loadDetail() async {
    final current = _season?.activeVersion;
    if (current == null) {
      if (mounted) setState(() => _detailed = null);
      return;
    }
    try {
      final detail = await AppData.versionDetail(current.slug);
      if (mounted) setState(() => _detailed = detail);
    } on ApiException {
      // Sem o detalhe a tela ainda funciona: mostra a versão sem as metas.
    }
  }

  /// Recarrega depois de um ato do admin: safras, versões vigentes e o detalhe.
  Future<void> _afterChange() async {
    await _loadDetail();
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  Future<void> _refresh() async {
    try {
      await AppData.refreshBarterVersion();
      await AppData.refreshSeasons();
      await _loadDetail();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
    if (mounted) setState(() {});
    widget.onChanged();
  }

  void _select(SeasonModel season) {
    setState(() {
      _seasonId = season.id;
      _detailed = null;
    });
    _loadDetail();
  }

  Future<void> _publish(SeasonModel season) async {
    final result = await showModalBottomSheet<_PublishRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PublishSheet(season: season),
    );
    if (result == null || !mounted) return;

    setState(() => _loading = true);
    try {
      final version = await AppData.publishVersion(
        seasonSlug: season.slug,
        filename: result.filename,
        bytes: result.bytes,
        grainPrice: result.grainPrice,
        estimatedYield: result.estimatedYield,
        cprDueDate: result.cprDueDate,
        insurancePolicy: result.insurancePolicy,
        endsAt: result.endsAt,
        targetSales: result.targetSales,
        targetSacks: result.targetSacks,
        targetBarters: result.targetBarters,
        closeOnGoal: result.closeOnGoal,
        note: result.note,
        carryOver: result.carryOver,
      );
      await _loadDetail();
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onChanged();
      // Quantos itens entraram sem unidade legível. É o número que manda o
      // admin à aba Histórico antes de o consultor pedir "3 unidades" de um
      // produto que se vende em bombona.
      final pendentes = AppData.inputs.where((p) => p.unitPending).length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${brand.copy.programTitle} ${version.code} publicado com '
            '${version.prices.length} insumo(s).'
            '${pendentes > 0 ? ' $pendentes sem unidade — revise no Histórico.' : ''}'),
        backgroundColor: pendentes > 0 ? AppColors.pending : AppColors.approved,
        duration: Duration(seconds: pendentes > 0 ? 6 : 4),
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showErrorSnack(context, e);
    }
  }

  Future<void> _closeVersion(BarterVersionModel version) async {
    final confirmed = await _confirm(
      icon: Icons.lock_outline,
      title: 'Encerrar ${version.code}?',
      text: 'Os consultores param de registrar permutas de '
          '${version.grainName.toLowerCase()} imediatamente. As outras culturas '
          'seguem abertas, e uma nova versão desta pode ser publicada depois. As '
          'permutas já enviadas continuam valendo pelos valores desta versão.',
      action: 'Encerrar versão',
    );
    if (!confirmed) return;

    try {
      await AppData.closeVersion(version.slug);
      await _afterChange();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// Liga ou desliga o encerramento automático por meta na versão vigente.
  ///
  /// O diálogo aparece só num caso, e é o caso que importa: ligar com a meta JÁ
  /// batida encerra a versão na hora.
  Future<void> _setCloseOnGoal(BarterVersionModel version, bool enabled) async {
    if (enabled && version.anyGoalMet) {
      final confirmed = await _confirm(
        icon: Icons.flag,
        title: 'A meta já foi atingida',
        text: 'Ligar o encerramento automático agora encerra ${version.code} '
            'imediatamente: os consultores param de registrar permutas desta cultura. '
            'As permutas já enviadas continuam valendo.',
        action: 'Ligar e encerrar',
      );
      if (!confirmed) return;
    }

    try {
      final updated = await AppData.setVersionCloseOnGoal(version.slug, enabled);
      await _afterChange();
      // O servidor pode ter ENCERRADO a versão nesta mesma chamada. Quem conta é
      // a resposta dele, e não o que o app pediu.
      _toast(updated.isOpen
          ? (enabled
              ? '${updated.code} passa a encerrar ao bater meta.'
              : '${updated.code} só encerra por decisão sua.')
          : '${updated.code} encerrado: meta atingida.');
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// ABRE A SAFRA DE UMA CULTURA.
  Future<void> _openSeasonDialog() async {
    if (AppData.grains.isEmpty) {
      _toast(
        'Cadastre um grão antes de abrir a safra: aba Valores › + › '
        'Novo ${brand.copy.grain.toLowerCase()}.',
      );
      return;
    }
    final result = await showDialog<_SeasonRequest>(
      context: context,
      builder: (_) => const _OpenSeasonDialog(),
    );
    if (result == null) return;

    try {
      await AppData.openSeason(
        grainId: result.grainId,
        startYear: result.startYear,
        endYear: result.endYear,
        insurancePolicy: result.insurancePolicy,
      );
      // A safra recém-aberta vira a safra em foco: é dela o próximo passo.
      final opened = AppData.seasons.where((s) => s.isOpen && s.grainId == result.grainId);
      if (opened.isNotEmpty) _seasonId = opened.first.id;
      await _afterChange();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// ACERTA O VENCIMENTO DA CPR da versão vigente.
  ///
  /// O diálogo AVISA o alcance antes de perguntar a data: mexer aqui muda a
  /// entrega de toda cédula desta versão que ainda não foi emitida — as já
  /// emitidas congelaram a data delas.
  Future<void> _cprDueDateDialog(BarterVersionModel version) async {
    final season = _season;
    final baseYear = season?.endYear ?? DateTime.now().year;
    final picked = await showDatePicker(
      context: context,
      initialDate: version.cprDueDate ?? DateTime(baseYear, 6, 30),
      firstDate: DateTime(baseYear - 2, 1, 1),
      lastDate: DateTime(baseYear + 2, 12, 31),
      helpText: 'Vencimento da CPR de ${version.code}',
    );
    if (picked == null || !mounted) return;

    final confirmado = await _confirm(
      icon: Icons.event_outlined,
      title: 'Mudar o vencimento da CPR?',
      text: 'As CPRs desta versão passam a vencer em ${_fullDate(picked)}.\n\n'
          'Vale para as cédulas que ainda NÃO foram emitidas. As já emitidas mantêm a '
          'data com que saíram — elas estão assinadas. As outras versões e culturas não '
          'são tocadas.',
      action: 'Mudar',
      danger: false,
    );
    if (!confirmado) return;

    try {
      await AppData.updateVersionTerms(version.slug, cprDueDate: picked);
      await _afterChange();
      _toast('Vencimento da CPR de ${version.code}: ${_fullDate(picked)}.');
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// ACERTA A PRODUTIVIDADE ESTIMADA da versão vigente — a taxa que dimensiona
  /// a área do penhor das permutas dela.
  Future<void> _estimatedYieldDialog(BarterVersionModel version) async {
    final controller = TextEditingController(
      text: version.estimatedYield > 0 ? version.estimatedYield.toStringAsFixed(0) : '',
    );
    final informado = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Produção estimada de ${version.grainName.toLowerCase()}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ela divide as sacas da permuta para achar a área do penhor. '
              'Vale para as permutas que ainda vão nascer — as registradas '
              'congelaram a taxa delas.',
              style: TextStyle(fontSize: 12, color: AppColors.textMedium),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Sacas por hectare'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final value = parseNumber(controller.text);
              if (value != null && value > 0) Navigator.pop(ctx, value);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (informado == null) return;

    try {
      await AppData.updateVersionTerms(version.slug, estimatedYield: informado);
      await _afterChange();
      _toast('${version.grainName}: ${informado.toStringAsFixed(0)} sc/ha.');
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _closeSeasonDialog(SeasonModel season) async {
    final confirmed = await _confirm(
      icon: Icons.event_busy_outlined,
      title: 'Encerrar a safra ${season.name}?',
      text: 'É o fim do ciclo de ${season.grainName.toLowerCase()}: a versão vigente '
          'fecha junto e nenhuma versão nova sai nesta safra. As outras culturas '
          'seguem. Se precisar, a safra pode ser reaberta depois.',
      action: 'Encerrar safra',
    );
    if (!confirmed) return;

    try {
      await AppData.closeSeason(season.slug);
      await _afterChange();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _reopenSeason(SeasonModel season) async {
    final confirmed = await _confirm(
      icon: Icons.lock_open_outlined,
      title: 'Reabrir a safra ${season.name}?',
      text: 'Versões novas voltam a poder ser publicadas nela. A última versão '
          'continua encerrada: a venda recomeça com uma tabela publicada agora. '
          'A reabertura fica registrada na auditoria.',
      action: 'Reabrir',
      danger: false,
    );
    if (!confirmed) return;

    try {
      await AppData.reopenSeason(season.slug);
      _seasonId = season.id;
      await _afterChange();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// A POLÍTICA DE SEGURO da versão vigente.
  ///
  /// O diálogo aparece ao tornar o seguro OBRIGATÓRIO, e não é cerimônia: cada
  /// permuta nova passa a carregar área plantada × taxa da praça — custo que vira
  /// saca. E ele conta quantos produtores estão em município SEM taxa, porque a
  /// permuta deles passa a ser recusada no registro.
  Future<void> _setInsurance(BarterVersionModel version, InsurancePolicy policy) async {
    if (policy == version.insurancePolicy) return;
    if (policy == InsurancePolicy.required) {
      final semTaxa = AppData.producers.where((p) => AppData.insuranceRateFor(p.city) == null).length;
      final confirmed = await _confirm(
        icon: Icons.shield_outlined,
        title: 'Seguro obrigatório em ${version.code}',
        text: 'Toda permuta registrada nesta versão a partir de agora vai incluir o '
            'seguro agrícola: a área plantada informada vezes o valor por hectare do '
            'município do produtor. O custo entra na conta e é pago em sacas.'
            '${semTaxa > 0 ? '\n\nAtenção: $semTaxa produtor(es) estão em município sem taxa '
                'cadastrada, e a permuta deles será recusada no registro até a praça entrar '
                'na base de seguros.' : ''}',
        action: 'Tornar obrigatório',
        danger: false,
      );
      if (!confirmed) return;
    }

    try {
      await AppData.setVersionInsurance(version.slug, policy);
      await _afterChange();
      _toast('${version.code}: ${policy.label.toLowerCase()} nas permutas novas. '
          'As já registradas não mudam.');
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// O SEGURO PADRÃO da safra — o que vem preenchido na próxima versão.
  Future<void> _setSeasonInsurance(SeasonModel season, InsurancePolicy policy) async {
    if (policy == season.insurancePolicy) return;
    try {
      await AppData.setSeasonInsurance(season.slug, policy);
      await _afterChange();
      _toast('${season.name}: as próximas versões nascem com ${policy.label.toLowerCase()}.');
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<bool> _confirm({
    required IconData icon,
    required String title,
    required String text,
    required String action,
    bool danger = true,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(icon, color: danger ? AppColors.denied : AppColors.primary, size: 36),
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: danger ? ElevatedButton.styleFrom(backgroundColor: AppColors.denied) : null,
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final season = _season;
    final cached = season?.activeVersion;
    // O detalhe só vale se for da versão vigente DESTA safra: trocar de safra no
    // seletor não pode mostrar as metas da outra por um instante.
    final current = _detailed != null && _detailed!.id == cached?.id ? _detailed : cached;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle('Safras abertas')),
              TextButton.icon(
                onPressed: _openSeasonDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Abrir safra'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (season == null)
            _NoSeasonCard(onOpen: _openSeasonDialog)
          else ...[
            // AS CULTURAS ABERTAS, uma ficha cada: é aqui que o admin troca de
            // Barter. Cada uma mostra se está vendendo agora.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final open in _openSeasons)
                  ChoiceChip(
                    label: Text(open.name),
                    avatar: Icon(
                      open.activeVersion?.isOpen == true ? Icons.circle : Icons.pause_circle_outline,
                      size: 12,
                      color: open.activeVersion?.isOpen == true ? AppColors.approved : AppColors.textLight,
                    ),
                    selected: open.id == season.id,
                    onSelected: (_) => _select(open),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (current == null)
              _EmptyVersionCard(
                season: season,
                loading: _loading,
                onPublish: () => _publish(season),
              )
            else ...[
              _CurrentVersionCard(
                season: season,
                version: current,
                loading: _loading,
                onPublish: () => _publish(season),
                onClose: () => _closeVersion(current),
                onEditYield: current.isOpen ? () => _estimatedYieldDialog(current) : null,
              ),
              const SizedBox(height: 16),
              _sectionTitle('Vencimento das cédulas'),
              const SizedBox(height: 8),
              _DueDateCard(version: current, onEdit: () => _cprDueDateDialog(current)),
              const SizedBox(height: 16),
              // O SEGURO vem antes das metas de propósito: ele muda o CUSTO de
              // cada permuta, e as metas medem o que já foi vendido.
              _sectionTitle('Seguro agrícola'),
              const SizedBox(height: 8),
              _InsuranceCard(
                season: season,
                version: current,
                onVersionPolicy: (policy) => _setInsurance(current, policy),
                onSeasonPolicy: (policy) => _setSeasonInsurance(season, policy),
              ),
              const SizedBox(height: 16),
              if (current.goals.isNotEmpty) ...[
                _sectionTitle('Metas de ${current.code}'),
                const SizedBox(height: 8),
                _GoalsCard(
                  version: current,
                  onModeChanged: (enabled) => _setCloseOnGoal(current, enabled),
                ),
                const SizedBox(height: 16),
              ],
            ],
            _sectionTitle('Versões de ${season.name}'),
            const SizedBox(height: 8),
            ...season.versions.map((version) => _VersionHistoryTile(
                  version: version,
                  isCurrent: version.id == current?.id,
                )),
            if (season.versions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Nenhuma versão publicada ainda.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.textLight)),
              ),
            const SizedBox(height: 4),
            Center(
              child: TextButton.icon(
                onPressed: () => _closeSeasonDialog(season),
                icon: const Icon(Icons.event_busy_outlined, size: 16),
                label: Text('Encerrar ${brand.copy.season} ${season.name}'),
                style: TextButton.styleFrom(foregroundColor: AppColors.denied),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _sectionTitle('Safras encerradas'),
          const SizedBox(height: 8),
          if (_closedSeasons.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Nenhuma safra encerrada.',
                  style: TextStyle(fontSize: 12, color: AppColors.textLight)),
            ),
          ..._closedSeasons.map(
            (s) => _ClosedSeasonTile(season: s, onReopen: () => _reopenSeason(s)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(text,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark));
}

/* ── Cartões ──────────────────────────────────────────────────────────── */

class _NoSeasonCard extends StatelessWidget {
  final VoidCallback onOpen;
  const _NoSeasonCard({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.agriculture_outlined, size: 44, color: AppColors.textLight),
            const SizedBox(height: 12),
            Text('Nenhuma safra aberta',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 6),
            Text(
              'Cada cultura tem a sua safra (Soja 26/27, Canola 2027). Sem safra aberta '
              'não há lançamento, e sem lançamento os consultores não registram permuta.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textMedium),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Abrir safra'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyVersionCard extends StatelessWidget {
  final SeasonModel season;
  final bool loading;
  final VoidCallback onPublish;
  const _EmptyVersionCard({
    required this.season,
    required this.loading,
    required this.onPublish,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(Icons.upload_file_outlined, size: 40, color: AppColors.primary),
            const SizedBox(height: 10),
            Text(
                season.versions.isEmpty
                    ? '${season.name}: nenhum ${brand.copy.program} lançado'
                    : '${season.name}: sem versão vigente',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 6),
            Text(
                'Suba a planilha de insumos desta cultura e informe o valor da saca para '
                'publicar a próxima versão.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: loading ? null : onPublish,
                icon: const Icon(Icons.upload_file, size: 18),
                label: Text(loading ? 'Publicando...' : 'Publicar versão'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// O cartão-estrela: a versão vigente da cultura, o valor da saca, a produção
/// estimada e a vigência.
class _CurrentVersionCard extends StatelessWidget {
  final SeasonModel season;
  final BarterVersionModel version;
  final bool loading;
  final VoidCallback onPublish;
  final VoidCallback onClose;

  /// ACERTAR A PRODUÇÃO ESTIMADA, sem republicar a tabela. Nulo quando a versão
  /// está encerrada: ali a taxa é registro do que valeu.
  final VoidCallback? onEditYield;

  const _CurrentVersionCard({
    required this.season,
    required this.version,
    required this.loading,
    required this.onPublish,
    required this.onClose,
    this.onEditYield,
  });

  @override
  Widget build(BuildContext context) {
    final open = version.isOpen;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(version.code,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.onPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.onPrimaryOverlay,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(open ? 'vigente' : 'encerrada',
                    style: TextStyle(
                        color: AppColors.onPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${season.name} • ${version.prices.length} insumo(s) na tabela',
              style: TextStyle(color: AppColors.onPrimarySubtle, fontSize: 12)),
          const SizedBox(height: 14),
          // A COTAÇÃO e a PRODUÇÃO ESTIMADA desta cultura. PRODUÇÃO ZERO É UM
          // ALARME, e não um campo em branco: a versão está VIGENTE e recusando
          // toda permuta nova, porque sem a taxa não há como dimensionar a
          // garantia.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.onPrimaryOverlay,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.grass, color: AppColors.onPrimaryMuted, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Saca de ${version.grainName.toLowerCase()}',
                          style: TextStyle(color: AppColors.onPrimary, fontSize: 12)),
                    ),
                    Text(formatCurrency(version.grainPrice),
                        style: TextStyle(
                            color: AppColors.onPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      version.estimatedYield > 0
                          ? Icons.agriculture_outlined
                          : Icons.warning_amber_rounded,
                      color: AppColors.onPrimaryMuted,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        version.estimatedYield > 0
                            ? 'Produção estimada (penhor)'
                            : 'Sem produção estimada — recusa permuta nesta cultura',
                        style: TextStyle(color: AppColors.onPrimarySubtle, fontSize: 11),
                      ),
                    ),
                    if (version.estimatedYield > 0)
                      Text('${version.estimatedYield.toStringAsFixed(0)} sc/ha',
                          style: TextStyle(
                              color: AppColors.onPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                    if (onEditYield != null)
                      IconButton(
                        onPressed: onEditYield,
                        icon: Icon(Icons.edit_outlined, size: 14, color: AppColors.onPrimarySubtle),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Acertar a produção estimada',
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.event_outlined, color: AppColors.onPrimarySubtle, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  version.endsAt == null
                      ? 'Sem data de encerramento: vale até você encerrar'
                      : 'Vigente até ${_fullDate(version.endsAt!)}',
                  style: TextStyle(color: AppColors.onPrimarySubtle, fontSize: 12),
                ),
              ),
            ],
          ),
          if (version.sourceFile != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.description_outlined, color: AppColors.onPrimarySubtle, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(version.sourceFile!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.onPrimarySubtle, fontSize: 12)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: loading ? null : onPublish,
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: Text(loading ? 'Publicando...' : 'Nova versão'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (open) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onClose,
                    icon: const Icon(Icons.lock_outline, size: 16),
                    label: const Text('Encerrar versão'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.onPrimary,
                      side: BorderSide(color: AppColors.onPrimaryMuted),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A data por extenso curto (30/06/2026).
String _fullDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

/// O VENCIMENTO DA CPR da versão — o dia em que o produtor entrega.
///
/// VAZIO É ÂMBAR, e não neutro: nada quebra até a primeira emissão, e então TODA
/// cédula da versão trava de uma vez. O aviso é o que separa "acerto isto hoje"
/// de "descubro isto com o produtor esperando na sala do emissor".
class _DueDateCard extends StatelessWidget {
  final BarterVersionModel version;
  final VoidCallback onEdit;

  const _DueDateCard({required this.version, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final due = version.cprDueDate;
    final acertado = due != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: acertado ? AppColors.surface : AppColors.pendingBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: acertado ? AppColors.borderSubtle : AppColors.pending.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            acertado ? Icons.event_available_outlined : Icons.event_busy_outlined,
            size: 22,
            color: acertado ? AppColors.primary : AppColors.pending,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vencimento da CPR • ${version.code}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark),
                ),
                const SizedBox(height: 2),
                Text(
                  acertado
                      ? '${_fullDate(due)} • todas as cédulas desta versão vencem neste dia'
                      : 'Ainda não acertado. Sem ele, nenhuma cédula desta versão pode ser emitida.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMedium, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          acertado
              ? TextButton(onPressed: onEdit, child: const Text('Mudar'))
              : ElevatedButton(
                  onPressed: onEdit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.pending,
                    foregroundColor: AppColors.onPrimary,
                  ),
                  child: const Text('Acertar'),
                ),
        ],
      ),
    );
  }
}

/// O seletor de política de seguro — obrigatório, opcional ou sem seguro.
class _PolicySelector extends StatelessWidget {
  final InsurancePolicy value;
  final ValueChanged<InsurancePolicy>? onChanged;
  const _PolicySelector({required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<InsurancePolicy>(
      showSelectedIcon: false,
      segments: [
        for (final policy in InsurancePolicy.values)
          ButtonSegment(value: policy, label: Text(policy.label, style: const TextStyle(fontSize: 12))),
      ],
      selected: {value},
      onSelectionChanged: onChanged == null ? null : (selected) => onChanged!(selected.first),
    );
  }
}

/// O SEGURO AGRÍCOLA da cultura: a política DESTA versão e o padrão da safra.
///
/// Os dois moram juntos porque o admin os decide juntos: a versão é o que vale
/// para as permutas de hoje; o padrão é o que vem preenchido na próxima versão.
/// O cartão mostra também o estado da BASE: quantos produtores ficariam de fora.
class _InsuranceCard extends StatelessWidget {
  final SeasonModel season;
  final BarterVersionModel version;
  final ValueChanged<InsurancePolicy> onVersionPolicy;
  final ValueChanged<InsurancePolicy> onSeasonPolicy;

  const _InsuranceCard({
    required this.season,
    required this.version,
    required this.onVersionPolicy,
    required this.onSeasonPolicy,
  });

  String get _explain => switch (version.insurancePolicy) {
        InsurancePolicy.required =>
          'Cada permuta nova inclui a área plantada × o valor por hectare da praça do produtor.',
        InsurancePolicy.optional =>
          'O consultor oferece o seguro, e o produtor decide. A recusa fica registrada na permuta.',
        InsurancePolicy.none => 'As permutas desta versão saem sem seguro.',
      };

  @override
  Widget build(BuildContext context) {
    final cities = AppData.insuranceRates.length;
    final semTaxa = AppData.producers.where((p) => AppData.insuranceRateFor(p.city) == null).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nesta versão (${version.code})',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 8),
            _PolicySelector(
              value: version.insurancePolicy,
              onChanged: version.isOpen ? onVersionPolicy : null,
            ),
            const SizedBox(height: 6),
            Text(_explain, style: TextStyle(fontSize: 11, color: AppColors.textLight)),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text('Padrão da safra ${season.name}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                ),
                PopupMenuButton<InsurancePolicy>(
                  tooltip: 'Mudar o padrão',
                  initialValue: season.insurancePolicy,
                  onSelected: onSeasonPolicy,
                  itemBuilder: (_) => [
                    for (final policy in InsurancePolicy.values)
                      PopupMenuItem(value: policy, child: Text(policy.label)),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(season.insurancePolicy.label,
                          style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w700)),
                      Icon(Icons.arrow_drop_down, color: AppColors.primary),
                    ],
                  ),
                ),
              ],
            ),
            Text('É o que vem preenchido ao publicar a próxima versão desta cultura.',
                style: TextStyle(fontSize: 11, color: AppColors.textLight)),
            const Divider(height: 24),
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 16, color: AppColors.atManager),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cities == 0
                        ? 'Nenhuma praça na base de seguros — cadastre-as em Cadastros › Seguros.'
                        : '$cities praça(s) na base'
                            '${semTaxa > 0 ? ' • $semTaxa produtor(es) em município sem taxa' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      color: semTaxa > 0 || cities == 0 ? AppColors.pending : AppColors.textMedium,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (version.insurancePolicy != InsurancePolicy.none && semTaxa > 0) ...[
              const SizedBox(height: 8),
              Text(
                version.insuranceRequired
                    ? 'A permuta de um produtor sem taxa é RECUSADA no registro, com o nome do '
                        'município na mensagem. Quem a lê é o consultor, e quem a resolve é você.'
                    : 'Para um produtor sem taxa, o seguro aparece bloqueado na tela do consultor, '
                        'e a permuta segue sem ele.',
                style: TextStyle(fontSize: 11, color: AppColors.textLight),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// As metas com o realizado, e o que acontece quando uma delas bate.
///
/// O interruptor mora aqui, junto das barras, porque é aqui que o admin olha
/// quando a meta está para bater — e é nesse momento que ele decide se a versão
/// para sozinha ou espera um toque dele. Fechada, uma nova versão pode sair com
/// outra meta.
class _GoalsCard extends StatelessWidget {
  final BarterVersionModel version;

  /// Ligar/desligar o encerramento automático. Pode ENCERRAR a versão (a tela
  /// avisa antes) — ver `_setCloseOnGoal`.
  final ValueChanged<bool> onModeChanged;

  const _GoalsCard({required this.version, required this.onModeChanged});

  String _value(BarterGoal goal, double number) =>
      goal.isMoney ? formatCurrency(number) : formatQty(number);

  /// A frase da faixa verde: o que a meta batida SIGNIFICA neste modo.
  String get _metMessage => version.closeOnGoal
      ? 'Meta atingida. A versão foi encerrada: publique a próxima para voltar a vender esta cultura.'
      : 'Meta atingida. A versão continua aberta até você encerrá-la.';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (version.anyGoalMet) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.approved.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.flag, size: 16, color: AppColors.approved),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _metMessage,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDark),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            for (var i = 0; i < version.goals.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _goalRow(version.goals[i]),
            ],
            const Divider(height: 26),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: version.closeOnGoal,
              onChanged: version.isOpen ? onModeChanged : null,
              title: const Text('Encerrar ao bater meta', style: TextStyle(fontSize: 13)),
              subtitle: Text(
                version.closeOnGoal
                    ? 'A aprovação que cruzar a meta encerra esta versão na hora.'
                    : 'A meta só avisa: a versão fica aberta até você encerrá-la.',
                style: TextStyle(fontSize: 11, color: AppColors.textLight),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _goalRow(BarterGoal goal) {
    final color = goal.met ? AppColors.approved : AppColors.primaryMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(goal.label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            ),
            Text('${_value(goal, goal.realized)} de ${_value(goal, goal.target)}',
                style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
            const SizedBox(width: 8),
            Text('${(goal.ratio * 100).round()}%',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: goal.ratio,
            minHeight: 7,
            backgroundColor: AppColors.primarySurface,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _VersionHistoryTile extends StatelessWidget {
  final BarterVersionModel version;
  final bool isCurrent;
  const _VersionHistoryTile({required this.version, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final color = isCurrent ? AppColors.approved : AppColors.textLight;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
                width: 4,
                height: 38,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(version.code,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                      ),
                      const SizedBox(width: 8),
                      if (isCurrent && version.isOpen)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.approved.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('vigente',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.approved)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    version.note ?? version.sourceFile ?? 'Publicada em ${_fullDate(version.startsAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                  ),
                  // POR QUE ela fechou — uma pessoa, ou a meta que a encerrou
                  // sozinha. É a única resposta disponível meses depois.
                  if (version.status != 'active' && version.closedBy != null)
                    Text(
                      'Encerrada: ${version.closedBy}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AppColors.textLight),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatCurrency(version.grainPrice),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                Text('a saca', style: TextStyle(fontSize: 10, color: AppColors.textLight)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ClosedSeasonTile extends StatelessWidget {
  final SeasonModel season;
  final VoidCallback onReopen;
  const _ClosedSeasonTile({required this.season, required this.onReopen});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.inventory_2_outlined, color: AppColors.textLight),
        title: Text(season.name,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
        subtitle: Text(
            '${season.code} • ${season.versions.length} versão(ões)'
            '${season.closedAt != null ? ' • encerrada em ${_fullDate(season.closedAt!)}' : ''}',
            style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
        trailing: TextButton(onPressed: onReopen, child: const Text('Reabrir')),
      ),
    );
  }
}

/* ── Publicação ───────────────────────────────────────────────────────── */

/// O que o admin escolheu para publicar a próxima versão da cultura.
class _PublishRequest {
  final String filename;
  final List<int> bytes;

  /// A cotação da saca e a produtividade — as duas metades da mesma conversão:
  /// a primeira leva o custo a sacas, a segunda as sacas à área do penhor.
  final double grainPrice;
  final double estimatedYield;
  final DateTime? cprDueDate;
  final InsurancePolicy insurancePolicy;

  final DateTime? endsAt;
  final double? targetSales;
  final double? targetSacks;
  final int? targetBarters;
  final bool closeOnGoal;

  final String? note;
  final bool carryOver;

  const _PublishRequest({
    required this.filename,
    required this.bytes,
    required this.grainPrice,
    required this.estimatedYield,
    required this.insurancePolicy,
    this.cprDueDate,
    this.endsAt,
    this.targetSales,
    this.targetSacks,
    this.targetBarters,
    this.closeOnGoal = false,
    this.note,
    this.carryOver = false,
  });
}

/// Formulário de publicação: a PLANILHA DESTA CULTURA + a cotação da saca, a
/// produtividade, o vencimento, o seguro, a vigência e as metas.
///
/// Cada cultura sobe a sua planilha. O que se digita aqui é o que não vem do
/// fornecedor: é a cooperativa que decide por quanto recebe a saca, quanto
/// espera colher, quando vence a entrega e se a versão leva seguro.
class _PublishSheet extends StatefulWidget {
  final SeasonModel season;
  const _PublishSheet({required this.season});

  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  String? _filename;
  List<int>? _bytes;
  DateTime? _endsAt;
  DateTime? _cprDueDate;
  bool _carryOver = false;
  bool _closeOnGoal = false;

  /// O SEGURO desta versão. Nasce com o PADRÃO DA SAFRA — "a soja leva seguro" —
  /// e o admin muda quando esta versão é diferente.
  late InsurancePolicy _insurancePolicy = widget.season.insurancePolicy;
  String? _error;

  final _price = TextEditingController();
  final _yield = TextEditingController();
  final _sales = TextEditingController();
  final _sacks = TextEditingController();
  final _barters = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    // OS TERMOS da versão anterior desta safra vêm preenchidos: republicar uma
    // tabela raramente muda a produtividade, e redigitá-la a cada vez é a chance
    // de sair um 6 no lugar de 60 — e a permuta seguinte exigir dez vezes mais
    // terra em garantia. As metas NÃO vêm: cada versão tem a sua.
    final previous = widget.season.versions.isEmpty ? null : widget.season.versions.first;
    if (previous != null) {
      if (previous.grainPrice > 0) {
        _price.text = previous.grainPrice.toStringAsFixed(2).replaceAll('.', ',');
      }
      if (previous.estimatedYield > 0) {
        _yield.text = previous.estimatedYield.toStringAsFixed(0);
      }
      _cprDueDate = previous.cprDueDate;
    }
  }

  @override
  void dispose() {
    _price.dispose();
    _yield.dispose();
    _sales.dispose();
    _sacks.dispose();
    _barters.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Planilha de insumos de ${widget.season.name}',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (file == null) return;
    // Lê os bytes aqui: no Android/iOS o caminho do arquivo é temporário e
    // pode sumir antes do envio; o que vai para a API é o conteúdo.
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _filename = file.name;
      _bytes = bytes;
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: _endsAt ?? now.add(const Duration(days: 30)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: DateTime(now.year + 3),
      helpText: 'Vigência até',
    );
    if (chosen != null) setState(() => _endsAt = chosen);
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: _cprDueDate ?? DateTime(widget.season.endYear, 6, 30),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: 'Vencimento da CPR desta versão',
    );
    if (chosen != null) setState(() => _cprDueDate = chosen);
  }

  double? _number(TextEditingController controller) => parseNumber(controller.text);

  /// Alguma meta foi digitada? É o que dá sentido ao encerramento automático.
  bool get _hasTarget => [_sales, _sacks, _barters].any((c) => (_number(c) ?? 0) > 0);

  void _submit() {
    final bytes = _bytes;
    final filename = _filename;
    if (bytes == null || filename == null) {
      setState(() => _error = 'Escolha a planilha .xlsx com os insumos desta cultura.');
      return;
    }
    final price = _number(_price);
    if (price == null || price <= 0) {
      setState(() => _error = 'Informe o valor da saca.');
      return;
    }
    final estimatedYield = _number(_yield);
    if (estimatedYield == null || estimatedYield <= 0) {
      setState(() => _error = 'Informe a produção estimada (sacas por hectare).');
      return;
    }
    // A mesma regra do servidor, respondida antes de subir a planilha: sem meta,
    // "encerrar ao bater meta" é uma opção ligada que nunca aconteceria.
    if (_closeOnGoal && !_hasTarget) {
      setState(() => _error = 'Defina ao menos uma meta para a versão encerrar ao atingi-la.');
      return;
    }

    Navigator.pop(
      context,
      _PublishRequest(
        filename: filename,
        bytes: bytes,
        grainPrice: price,
        estimatedYield: estimatedYield,
        cprDueDate: _cprDueDate,
        insurancePolicy: _insurancePolicy,
        endsAt: _endsAt,
        targetSales: _number(_sales),
        targetSacks: _number(_sacks),
        targetBarters: _number(_barters)?.round(),
        closeOnGoal: _closeOnGoal,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        carryOver: _carryOver,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final season = widget.season;
    final nextNumber = (season.versions.isEmpty ? 0 : season.versions.first.number) + 1;
    final nextCode = '${season.code}.${nextNumber.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.upload_file, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Publicar $nextCode',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
            Text(
              'A planilha traz os insumos de ${season.grainName.toLowerCase()} (nome, unidade, '
              'classe, preço). A versão anterior desta safra é encerrada na hora, e as '
              'permutas já registradas continuam com os valores delas. As outras culturas '
              'não são tocadas.',
              style: TextStyle(fontSize: 12, color: AppColors.textMedium),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.attach_file, size: 18),
              label: Text(_filename ?? 'Escolher planilha (.xlsx)'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.centerLeft,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Saca de ${season.grainName.toLowerCase()} (R\$)',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _yield,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Produção (sc/ha)', isDense: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'A cotação converte o custo em sacas; a produção divide as sacas para achar a '
              'área do penhor.',
              style: TextStyle(fontSize: 10, color: AppColors.textLight),
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.event_available_outlined, color: AppColors.primary),
              title: Text(
                _cprDueDate == null ? 'Vencimento da CPR' : 'CPR vence ${_fullDate(_cprDueDate!)}',
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text('Opcional agora: sem ele as cédulas não são emitidas',
                  style: TextStyle(fontSize: 11, color: AppColors.textLight)),
              trailing: TextButton(
                onPressed: _pickDueDate,
                child: Text(_cprDueDate == null ? 'Definir' : 'Mudar'),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.event_outlined, color: AppColors.primary),
              title: Text(
                _endsAt == null ? 'Sem data de encerramento' : 'Vigente até ${_fullDate(_endsAt!)}',
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text('Depois desta data a API recusa permuta nova',
                  style: TextStyle(fontSize: 11, color: AppColors.textLight)),
              trailing: _endsAt == null
                  ? TextButton(onPressed: _pickDate, child: const Text('Definir'))
                  : IconButton(
                      onPressed: () => setState(() => _endsAt = null),
                      icon: const Icon(Icons.close, size: 18),
                    ),
            ),

            const Divider(height: 24),
            Text('Seguro agrícola',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            Text('Vem com o padrão da safra (${season.insurancePolicy.label.toLowerCase()}).',
                style: TextStyle(fontSize: 11, color: AppColors.textLight)),
            const SizedBox(height: 8),
            _PolicySelector(
              value: _insurancePolicy,
              onChanged: (policy) => setState(() => _insurancePolicy = policy),
            ),
            if (_insurancePolicy != InsurancePolicy.none && AppData.insuranceRates.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'A base de seguros está vazia: cadastre as praças em Cadastros › Seguros.',
                  style: TextStyle(fontSize: 11, color: AppColors.pending),
                ),
              ),

            const Divider(height: 24),
            Text('Metas (opcionais)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            Text('Medem o realizado das permutas aprovadas nesta versão.',
                style: TextStyle(fontSize: 11, color: AppColors.textLight)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _target(_sales, 'Vendas (R\$)')),
                const SizedBox(width: 10),
                Expanded(child: _target(_sacks, 'Sacas')),
                const SizedBox(width: 10),
                Expanded(child: _target(_barters, 'Permutas')),
              ],
            ),
            // O QUE FAZER quando a meta bater. Fica encostado nos campos de meta
            // de propósito: é a segunda metade da mesma decisão.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _closeOnGoal,
              onChanged: (v) => setState(() => _closeOnGoal = v),
              title: const Text('Encerrar ao bater meta', style: TextStyle(fontSize: 13)),
              subtitle: Text(
                _closeOnGoal
                    ? 'A aprovação que cruzar a meta encerra esta versão na hora.'
                    : 'A meta só avisa no painel: quem encerra é você.',
                style: TextStyle(fontSize: 11, color: AppColors.textLight),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _note,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Observação do lançamento', counterText: ''),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _carryOver,
              onChanged: (v) => setState(() => _carryOver = v),
              title: const Text('Manter os insumos que não vierem na planilha',
                  style: TextStyle(fontSize: 13)),
              subtitle: Text(
                _carryOver
                    ? 'Os ausentes seguem com o valor da versão anterior desta safra.'
                    : 'A planilha é a tabela: o que não estiver nela sai do Barter.',
                style: TextStyle(fontSize: 11, color: AppColors.textLight),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(fontSize: 12, color: AppColors.denied)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.publish, size: 18),
                label: Text('Publicar $nextCode'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _target(TextEditingController controller, String label) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, isDense: true),
      );
}

/* ── Abertura de safra ────────────────────────────────────────────────── */

class _SeasonRequest {
  final String grainId;
  final int startYear;
  final int endYear;
  final InsurancePolicy insurancePolicy;

  const _SeasonRequest({
    required this.grainId,
    required this.startYear,
    required this.endYear,
    required this.insurancePolicy,
  });
}

/// A ABERTURA DA SAFRA DE UMA CULTURA — "Soja 26/27", "Canola 2027".
///
/// O ANO é o que o admin escolhe: a cultura que cruza o ano (planta num, colhe
/// no outro) sai como 26/27; a que cabe num ano só sai como 2027. O SEGURO é o
/// padrão da cultura, que vem preenchido em cada versão publicada nela.
class _OpenSeasonDialog extends StatefulWidget {
  const _OpenSeasonDialog();

  @override
  State<_OpenSeasonDialog> createState() => _OpenSeasonDialogState();
}

class _OpenSeasonDialogState extends State<_OpenSeasonDialog> {
  late String? _grainId = AppData.grains.isEmpty ? null : AppData.grains.first.id;
  late final _year = TextEditingController(text: '${DateTime.now().year}');
  bool _crossesYear = true;
  InsurancePolicy _insurancePolicy = InsurancePolicy.none;

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  int? get _startYear => int.tryParse(_year.text.trim());

  /// O nome que vai nascer, para o admin ver antes de abrir: "Soja 26/27".
  String get _preview {
    final start = _startYear;
    final grain = AppData.grains.where((g) => g.id == _grainId).firstOrNull;
    if (start == null || grain == null) return '';
    final years = _crossesYear
        ? '${(start % 100).toString().padLeft(2, '0')}/${((start + 1) % 100).toString().padLeft(2, '0')}'
        : '$start';
    return '${grain.name} $years';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Abrir safra'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cada cultura tem a sua safra: ela abre, publica versões, bate meta e encerra '
              'sem mexer nas outras. Só uma safra aberta por grão.',
              style: TextStyle(fontSize: 12, color: AppColors.textMedium),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _grainId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Cultura (grão do catálogo)', isDense: true),
              items: [
                for (final grain in AppData.grains)
                  DropdownMenuItem(value: grain.id, child: Text(grain.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (value) => setState(() => _grainId = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _year,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Ano do plantio', isDense: true),
              onChanged: (_) => setState(() {}),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _crossesYear,
              onChanged: (v) => setState(() => _crossesYear = v),
              title: const Text('A safra cruza o ano', style: TextStyle(fontSize: 13)),
              subtitle: Text(
                _crossesYear
                    ? 'Planta num ano e colhe no seguinte (ex.: soja 26/27).'
                    : 'Planta e colhe no mesmo ano (ex.: canola 2027).',
                style: TextStyle(fontSize: 11, color: AppColors.textLight),
              ),
            ),
            const SizedBox(height: 4),
            Text('Seguro padrão da cultura',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDark)),
            const SizedBox(height: 6),
            _PolicySelector(
              value: _insurancePolicy,
              onChanged: (policy) => setState(() => _insurancePolicy = policy),
            ),
            const SizedBox(height: 10),
            if (_preview.isNotEmpty)
              Text('Safra: $_preview',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () {
            final start = _startYear;
            final grainId = _grainId;
            if (start == null || grainId == null) return;
            Navigator.pop(
              context,
              _SeasonRequest(
                grainId: grainId,
                startYear: start,
                endYear: _crossesYear ? start + 1 : start,
                insurancePolicy: _insurancePolicy,
              ),
            );
          },
          child: const Text('Abrir'),
        ),
      ],
    );
  }
}

/// Corrige um valor DENTRO de uma versão vigente — um insumo ou a saca.
Future<void> showVersionPriceDialog(
  BuildContext context, {
  required BarterVersionModel version,
  required String productId,
  required String productName,
  required double price,
  required VoidCallback onUpdated,
}) {
  final priceCtrl = TextEditingController(text: price.toStringAsFixed(2).replaceAll('.', ','));

  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Corrigir valor'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Text('Vale a partir de agora no Barter ${version.code}',
              style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
          const SizedBox(height: 16),
          TextField(
            controller: priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Preço (R\$)', prefixIcon: Icon(Icons.sell_outlined)),
            autofocus: true,
          ),
          const SizedBox(height: 8),
          Text(
            'As permutas já registradas não mudam: elas guardam o valor do momento em que foram fechadas.',
            style: TextStyle(fontSize: 11, color: AppColors.textLight),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () async {
            final novo = parseNumber(priceCtrl.text);
            if (novo == null || novo <= 0) return;
            try {
              await AppData.updateVersionPrice(version.slug, productId, novo);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              onUpdated();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('Valor corrigido nesta versão.'),
                backgroundColor: AppColors.approved,
              ));
            } on ApiException catch (e) {
              if (ctx.mounted) showErrorSnack(ctx, e);
            }
          },
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
}
