import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../services/api/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// O LANÇAMENTO do Barter, do lado do admin.
///
/// É aqui que se responde "por quanto se permuta agora": a safra corrente, a
/// versão vigente com o valor da saca, o quanto falta para cada meta e o botão
/// que publica a próxima versão a partir da planilha do fornecedor.
///
/// O que esta tela deliberadamente NÃO faz é fechar o Barter sozinha. As metas
/// medem e avisam; encerrar continua sendo um ato do admin, com um toque — o
/// realizado é leitura de negócio, e desligar a operação de madrugada por causa
/// de uma soma seria pior do que avisar.
class BarterProgramTab extends StatefulWidget {
  final VoidCallback onChanged;
  const BarterProgramTab({super.key, required this.onChanged});

  @override
  State<BarterProgramTab> createState() => _BarterProgramTabState();
}

class _BarterProgramTabState extends State<BarterProgramTab> {
  bool _loading = false;

  /// A versão vigente com METAS. O cache guarda a versão "crua" (é a mesma que
  /// o consultor recebe, sem números de retaguarda); o realizado vem do detalhe.
  BarterVersionModel? _detailed;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    final current = AppData.currentVersion;
    if (current == null) {
      if (mounted) setState(() => _detailed = null);
      return;
    }
    try {
      final detail = await AppData.versionDetail(current.code);
      if (mounted) setState(() => _detailed = detail);
    } on ApiException {
      // Sem o detalhe a tela ainda funciona: mostra a versão sem as metas.
    }
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

  SeasonModel? get _openSeason {
    for (final season in AppData.seasons) {
      if (season.isOpen) return season;
    }
    return null;
  }

  Future<void> _publish() async {
    final season = _openSeason;
    if (season == null) {
      _toast('Abra uma safra antes de lançar um Barter.');
      return;
    }

    final result = await showModalBottomSheet<_PublishRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PublishSheet(season: season, previous: AppData.currentVersion),
    );
    if (result == null || !mounted) return;

    setState(() => _loading = true);
    try {
      final version = await AppData.publishVersion(
        seasonCode: season.code,
        filename: result.filename,
        bytes: result.bytes,
        grainPrice: result.grainPrice,
        endsAt: result.endsAt,
        targetSales: result.targetSales,
        targetSacks: result.targetSacks,
        targetBarters: result.targetBarters,
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.lock_outline, color: AppColors.pending, size: 36),
        title: Text('Encerrar ${version.code}?'),
        content: const Text(
          'Os consultores param de registrar permutas imediatamente. As permutas '
          'já enviadas continuam valendo pelos valores desta versão.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.denied),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await AppData.closeVersion(version.code);
      await _loadDetail();
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _openSeasonDialog() async {
    final grains = AppData.grains;
    if (grains.isEmpty) {
      _toast('Cadastre um grão no catálogo antes de abrir a safra.');
      return;
    }
    final result = await showDialog<_SeasonRequest>(
      context: context,
      builder: (_) => _OpenSeasonDialog(grains: grains),
    );
    if (result == null) return;

    try {
      await AppData.openSeason(
        grainId: result.grainId,
        year: result.year,
        letter: result.letter,
      );
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _closeSeasonDialog(SeasonModel season) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.event_busy_outlined, color: AppColors.denied, size: 36),
        title: Text('Encerrar a safra ${season.name}?'),
        content: const Text(
          'A safra e o Barter vigente são encerrados. Depois disso é preciso '
          'abrir uma safra nova para voltar a permutar.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.denied),
            child: const Text('Encerrar safra'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await AppData.closeSeason(season.code);
      await _loadDetail();
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final season = _openSeason;
    final current = _detailed ?? AppData.currentVersion;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (season == null)
            _NoSeasonCard(onOpen: _openSeasonDialog)
          else ...[
            // O cartão da safra saiu daqui: ele repetia o que o cartão da
            // versão e a lista abaixo já dizem (o grão, a contagem de versões).
            // A safra aparece como subtítulo do lançamento vigente, e encerrá-la
            // é uma ação do fim da lista de versões — onde ela pertence.
            if (current == null)
              _EmptyVersionCard(season: season, loading: _loading, onPublish: _publish)
            else ...[
              _CurrentVersionCard(
                season: season,
                version: current,
                loading: _loading,
                onPublish: _publish,
                onClose: () => _closeVersion(current),
              ),
              const SizedBox(height: 16),
              if (current.goals.isNotEmpty) ...[
                _sectionTitle('Metas do lançamento'),
                const SizedBox(height: 8),
                _GoalsCard(version: current),
                const SizedBox(height: 16),
              ],
            ],
            _sectionTitle('Versões de ${season.name}'),
            const SizedBox(height: 8),
            ...season.versions.map((version) => _VersionHistoryTile(
                  version: version,
                  isCurrent: version.code == current?.code,
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
          ...AppData.seasons
              .where((s) => !s.isOpen)
              .map((s) => _ClosedSeasonTile(season: s)),
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
              'A safra é a temporada do Barter sobre um grão. Sem ela não há '
              'lançamento — e sem lançamento os consultores não registram permuta.',
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
            Text('${season.name}: nenhum ${brand.copy.program} lançado',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 6),
            Text('Suba a planilha de insumos e informe o valor da saca para publicar a primeira versão.',
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

/// O cartão-estrela: a versão vigente, o valor da saca e a vigência.
class _CurrentVersionCard extends StatelessWidget {
  final SeasonModel season;
  final BarterVersionModel version;
  final bool loading;
  final VoidCallback onPublish;
  final VoidCallback onClose;

  const _CurrentVersionCard({
    required this.season,
    required this.version,
    required this.loading,
    required this.onPublish,
    required this.onClose,
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
              Text(version.code,
                  style: TextStyle(
                      color: AppColors.onPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.onPrimaryOverlay,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
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
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.event_outlined, color: AppColors.onPrimarySubtle, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  version.endsAt == null
                      ? 'Sem data de encerramento — vale até você encerrar'
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
                    label: const Text('Encerrar'),
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

  static String _fullDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

/// As metas com o realizado. Meta atingida vira aviso — não fecha nada.
class _GoalsCard extends StatelessWidget {
  final BarterVersionModel version;
  const _GoalsCard({required this.version});

  String _value(BarterGoal goal, double number) =>
      goal.isMoney ? formatCurrency(number) : formatQty(number);

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
                        'Meta atingida. O Barter continua aberto até você encerrá-lo.',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDark),
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
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
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
            Container(width: 4, height: 38,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(version.code,
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                      const SizedBox(width: 8),
                      if (isCurrent)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.approved.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('vigente',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.approved)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    version.note ?? version.sourceFile ?? 'Publicada em ${_date(version.startsAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: AppColors.textMedium),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatCurrency(version.grainPrice),
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                Text('a saca', style: TextStyle(fontSize: 10, color: AppColors.textLight)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _ClosedSeasonTile extends StatelessWidget {
  final SeasonModel season;
  const _ClosedSeasonTile({required this.season});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.inventory_2_outlined, color: AppColors.textLight),
        title: Text('${season.code} • ${season.name}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
        subtitle: Text('${season.versions.length} versão(ões) • pagamento em ${season.grainName.toLowerCase()}',
            style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
      ),
    );
  }
}

/* ── Publicação ───────────────────────────────────────────────────────── */

/// O que o admin escolheu para publicar a próxima versão.
class _PublishRequest {
  final String filename;
  final List<int> bytes;
  final double grainPrice;
  final DateTime? endsAt;
  final double? targetSales;
  final double? targetSacks;
  final int? targetBarters;
  final String? note;
  final bool carryOver;

  const _PublishRequest({
    required this.filename,
    required this.bytes,
    required this.grainPrice,
    this.endsAt,
    this.targetSales,
    this.targetSacks,
    this.targetBarters,
    this.note,
    this.carryOver = false,
  });
}

/// Formulário de publicação: a planilha dos insumos + o valor da saca + a
/// vigência e as metas.
///
/// A planilha traz os INSUMOS; o valor da saca é digitado aqui porque ele não
/// vem do fornecedor — é a cotação com que a cooperativa decide receber.
class _PublishSheet extends StatefulWidget {
  final SeasonModel season;
  final BarterVersionModel? previous;
  const _PublishSheet({required this.season, this.previous});

  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  String? _filename;
  List<int>? _bytes;
  DateTime? _endsAt;
  bool _carryOver = false;
  String? _error;

  late final TextEditingController _grainPrice = TextEditingController(
    text: widget.previous?.grainPrice.toStringAsFixed(2).replaceAll('.', ',') ?? '',
  );
  final _sales = TextEditingController();
  final _sacks = TextEditingController();
  final _barters = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _grainPrice.dispose();
    _sales.dispose();
    _sacks.dispose();
    _barters.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Planilha de insumos',
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

  double? _number(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text.replaceAll('.', '').replaceAll(',', '.'));
  }

  void _submit() {
    final bytes = _bytes;
    final filename = _filename;
    if (bytes == null || filename == null) {
      setState(() => _error = 'Escolha a planilha .xlsx com os insumos.');
      return;
    }
    final grainPrice = _number(_grainPrice);
    if (grainPrice == null || grainPrice <= 0) {
      setState(() => _error = 'Informe o valor da saca de ${widget.season.grainName.toLowerCase()}.');
      return;
    }

    Navigator.pop(
      context,
      _PublishRequest(
        filename: filename,
        bytes: bytes,
        grainPrice: grainPrice,
        endsAt: _endsAt,
        targetSales: _number(_sales),
        targetSacks: _number(_sacks),
        targetBarters: _number(_barters)?.round(),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        carryOver: _carryOver,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nextNumber = (widget.season.versions.isEmpty ? 0 : widget.season.versions.first.number) + 1;
    final nextCode = '${widget.season.code}.${nextNumber.toString().padLeft(2, '0')}';

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
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              'A planilha traz os insumos (nome, unidade, classe, preço e custo). '
              'A versão anterior é encerrada na hora, e as permutas já registradas '
              'continuam com os valores delas.',
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

            TextField(
              controller: _grainPrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Valor da saca de ${widget.season.grainName.toLowerCase()} (R\$)',
                prefixIcon: const Icon(Icons.grass),
              ),
            ),
            const SizedBox(height: 12),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.event_outlined, color: AppColors.primary),
              title: Text(
                _endsAt == null
                    ? 'Sem data de encerramento'
                    : 'Vigente até ${_endsAt!.day.toString().padLeft(2, '0')}/${_endsAt!.month.toString().padLeft(2, '0')}/${_endsAt!.year}',
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
            Text('Metas (opcionais)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            Text('Ao atingir, o painel avisa — quem encerra o Barter é você.',
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
            const SizedBox(height: 12),

            TextField(
              controller: _note,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Observação do lançamento',
                counterText: '',
              ),
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
                    ? 'Os ausentes seguem com o valor da versão anterior.'
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
  final int year;
  final String? letter;
  const _SeasonRequest({required this.grainId, required this.year, this.letter});
}

class _OpenSeasonDialog extends StatefulWidget {
  final List<ProductModel> grains;
  const _OpenSeasonDialog({required this.grains});

  @override
  State<_OpenSeasonDialog> createState() => _OpenSeasonDialogState();
}

class _OpenSeasonDialogState extends State<_OpenSeasonDialog> {
  late String _grainId = widget.grains.first.id;
  late final _year = TextEditingController(text: '${DateTime.now().year}');
  final _letter = TextEditingController();

  @override
  void dispose() {
    _year.dispose();
    _letter.dispose();
    super.dispose();
  }

  ProductModel get _grain => widget.grains.firstWhere((g) => g.id == _grainId);

  /// A sugestão de código, para o admin ver o que vai nascer: S2026.
  String get _preview {
    final letter = _letter.text.trim().isEmpty
        ? _grain.name.characters.first.toUpperCase()
        : _letter.text.trim().toUpperCase();
    return '$letter${_year.text.trim()}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Abrir safra'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _grainId,
            decoration: const InputDecoration(labelText: 'Grão da safra'),
            items: widget.grains
                .map((g) => DropdownMenuItem(value: g.id, child: Text(g.name)))
                .toList(),
            onChanged: (v) => setState(() => _grainId = v ?? _grainId),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Ano'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _letter,
                  maxLength: 2,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Letra', counterText: ''),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Código da safra: $_preview • versões $_preview.01, $_preview.02…',
              style: TextStyle(fontSize: 11, color: AppColors.textMedium)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () {
            final year = int.tryParse(_year.text.trim());
            if (year == null) return;
            Navigator.pop(
              context,
              _SeasonRequest(
                grainId: _grainId,
                year: year,
                letter: _letter.text.trim().isEmpty ? null : _letter.text.trim(),
              ),
            );
          },
          child: const Text('Abrir'),
        ),
      ],
    );
  }
}

/* ── Correção pontual de valor ────────────────────────────────────────── */

/// Corrige preço (e custo) de um item da versão vigente — inclusive a saca do
/// grão, que entra pelo mesmo caminho.
///
/// Substitui o antigo "atualizar valor" do catálogo: valor não é mais atributo
/// do produto, é do lançamento. Só a versão vigente aceita correção; as
/// encerradas são o registro do que valeu.
Future<void> showVersionPriceDialog(
  BuildContext context, {
  required String productId,
  required String productName,
  required double price,
  required VoidCallback onUpdated,
}) {
  final priceCtrl = TextEditingController(text: price.toStringAsFixed(2).replaceAll('.', ','));
  final version = AppData.currentVersion;

  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Corrigir valor'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          if (version != null)
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
            'As permutas já registradas não mudam — elas guardam o valor do momento em que foram fechadas.',
            style: TextStyle(fontSize: 11, color: AppColors.textLight),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () async {
            final novo = double.tryParse(priceCtrl.text.replaceAll('.', '').replaceAll(',', '.'));
            if (novo == null || novo <= 0) return;
            try {
              await AppData.updateVersionPrice(productId, novo);
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
