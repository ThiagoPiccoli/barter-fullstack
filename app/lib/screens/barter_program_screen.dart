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
/// O ENCERRAMENTO POR META é uma OPÇÃO do lançamento, e as duas metades dela
/// aparecem aqui: o interruptor no formulário de publicação e o mesmo
/// interruptor no cartão de metas, para quem mudou de ideia no meio do Barter.
///
/// Nenhuma das duas fecha nada nesta tela. Quem encerra, no automático, é a
/// aprovação do comitê que cruza a meta — no servidor, com autor e hora (ver
/// `closeIfGoalReached` na API). O que esta tela faz é dizer em que modo o
/// Barter está e avisar antes de ligar o automático com a meta já batida, porque
/// aí o Barter fecha no mesmo toque.
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
        estimatedYield: result.estimatedYield,
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

  /// Liga ou desliga o encerramento automático por meta na versão vigente.
  ///
  /// O diálogo aparece só num caso, e é o caso que importa: ligar com a meta JÁ
  /// batida encerra o Barter na hora. Sem ele, o admin marcaria um interruptor
  /// para valer "daqui para a frente" e descobriria a operação parada.
  Future<void> _setCloseOnGoal(BarterVersionModel version, bool enabled) async {
    if (enabled && version.anyGoalMet) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.flag, color: AppColors.pending, size: 36),
          title: const Text('A meta já foi atingida'),
          content: Text(
            'Ligar o encerramento automático agora encerra ${version.code} '
            'imediatamente: os consultores param de registrar permutas. As '
            'permutas já enviadas continuam valendo.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.denied),
              child: const Text('Ligar e encerrar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      final updated = await AppData.setVersionCloseOnGoal(version.code, enabled);
      await _loadDetail();
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
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
        cprDueDate: result.cprDueDate,
      );
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// ACERTA o vencimento da CPR de uma safra JÁ ABERTA.
  ///
  /// O diálogo AVISA o alcance antes de perguntar a data, e não depois: mexer
  /// aqui muda a entrega de toda cédula da safra que ainda não foi emitida — as
  /// já emitidas congelaram a data delas, e é por isso que elas não são
  /// alcançadas. Sem o aviso, o admin corrigiria "a data desta safra" achando
  /// que corrige um cadastro, e antecipando (ou adiando) a colheita de dezenas
  /// de produtores num campo que ninguém mais confere depois.
  Future<void> _cprDueDateDialog(SeasonModel season) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: season.cprDueDate ?? DateTime(season.year, 6, 30),
      firstDate: DateTime(season.year, 1, 1),
      lastDate: DateTime(season.year + 1, 12, 31),
      helpText: 'Vencimento da CPR de ${season.name}',
    );
    if (picked == null || !mounted) return;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mudar o vencimento da CPR?'),
        content: Text(
          'As CPRs de ${season.name} passam a vencer em ${_fullDate(picked)}.\n\n'
          'Vale para todas as cédulas da safra que ainda NÃO foram emitidas. '
          'As já emitidas mantêm a data com que saíram — elas estão assinadas.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mudar')),
        ],
      ),
    );
    if (confirmado != true) return;

    try {
      await AppData.setSeasonCprDueDate(season.code, picked);
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
      _toast('Vencimento da CPR de ${season.name}: ${_fullDate(picked)}.');
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
                _GoalsCard(
                  version: current,
                  onModeChanged: (enabled) => _setCloseOnGoal(current, enabled),
                ),
                const SizedBox(height: 16),
              ],
            ],
            // O VENCIMENTO DA CPR, fora do bloco da versão vigente.
            //
            // Cartão PRÓPRIO, e não uma linha dentro do cartão do lançamento:
            // ele é da SAFRA e vale para TODAS as versões dela. Dentro daquele
            // cartão pareceria que cada lançamento tem o seu — e a primeira
            // versão nova sairia com alguém procurando onde mudá-lo de novo.
            //
            // E fica FORA do `if (current == null)` porque não depende de haver
            // tabela publicada: o calendário da colheita se sabe quando a safra
            // abre, e acertá-lo antes é melhor do que lembrar dele depois, com
            // a primeira cédula travada.
            _CprDueDateCard(season: season, onEdit: () => _cprDueDateDialog(season)),
            const SizedBox(height: 16),
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
              'lançamento, e sem lançamento os consultores não registram permuta.',
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
          const SizedBox(height: 8),

          // A PRODUTIVIDADE ESTIMADA, ao lado da cotação — as duas taxas do
          // lançamento, no mesmo cartão, porque são as duas metades da mesma
          // conversão: a cotação leva o custo a sacas, esta leva as sacas à área
          // do penhor.
          //
          // ZERO É UM ALARME, e não um campo em branco: esta versão está VIGENTE
          // e recusando toda permuta nova, porque sem a taxa não há como
          // dimensionar a garantia. Sem este aviso, o admin veria um Barter
          // aberto e um time de vendas parado, sem ligar as duas coisas — o erro
          // apareceria como "a API está recusando permuta", na voz do consultor.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.onPrimaryOverlay,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  version.estimatedYield > 0
                      ? Icons.agriculture_outlined
                      : Icons.warning_amber_rounded,
                  color: AppColors.onPrimaryMuted,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    version.estimatedYield > 0
                        ? 'Produção estimada (penhor)'
                        : 'Sem produção estimada — o Barter recusa permuta nova',
                    style: TextStyle(color: AppColors.onPrimary, fontSize: 12),
                  ),
                ),
                if (version.estimatedYield > 0)
                  Text('${version.estimatedYield.toStringAsFixed(0)} sc/ha',
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

}

/// A data por extenso curto (30/06/2026). Fora de qualquer cartão porque três
/// deles a usam — a vigência da versão, o vencimento da CPR e a correção dele.
String _fullDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

/// O VENCIMENTO DA CPR da safra aberta — o dia em que o produtor entrega o grão.
///
/// Ele existe como cartão porque é uma decisão da SAFRA que ninguém mais toma:
/// ele muda conforme a CULTURA (soja vence na colheita da soja, milho safrinha
/// no dele) e vale para todas as cédulas da temporada. Já foi campo do
/// formulário da cédula, digitado uma vez por permuta por quem não tinha como
/// saber a data certa daquela cultura — e duas cédulas da mesma safra saíam com
/// vencimentos diferentes, sem ninguém ter como descobrir qual estava certa a
/// não ser comparando os papéis.
///
/// VAZIO É ÂMBAR, e não neutro: nada quebra até a primeira emissão, e então
/// TODA cédula da safra trava de uma vez. O aviso é o que separa "acerto isto
/// hoje" de "descubro isto com o produtor esperando na sala do emissor".
class _CprDueDateCard extends StatelessWidget {
  final SeasonModel season;
  final VoidCallback onEdit;

  const _CprDueDateCard({required this.season, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final due = season.cprDueDate;
    final acertado = due != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: acertado ? AppColors.surface : AppColors.pendingBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: acertado
              ? AppColors.borderSubtle
              : AppColors.pending.withValues(alpha: 0.4),
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
                  'Vencimento da CPR',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  acertado
                      ? '${_fullDate(due)} • todas as cédulas de ${season.name} '
                          'vencem neste dia'
                      : 'Ainda não acertado. Sem ele, nenhuma cédula de '
                          '${season.name} pode ser emitida.',
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

/// As metas com o realizado, e o que acontece quando uma delas bate.
///
/// O interruptor mora aqui, junto das barras, porque é aqui que o admin olha
/// quando a meta está para bater — e é nesse momento que ele decide se o Barter
/// para sozinho ou espera um toque dele.
class _GoalsCard extends StatelessWidget {
  final BarterVersionModel version;

  /// Ligar/desligar o encerramento automático. Pode ENCERRAR o Barter (a tela
  /// avisa antes) — ver `_setCloseOnGoal`.
  final ValueChanged<bool> onModeChanged;

  const _GoalsCard({required this.version, required this.onModeChanged});

  String _value(BarterGoal goal, double number) =>
      goal.isMoney ? formatCurrency(number) : formatQty(number);

  /// A frase da faixa verde: o que a meta batida SIGNIFICA neste modo.
  String get _metMessage => version.closeOnGoal
      ? 'Meta atingida. O Barter foi encerrado: a próxima aprovação já não entra nesta versão.'
      : 'Meta atingida. O Barter continua aberto até você encerrá-lo.';

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
            const Divider(height: 26),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: version.closeOnGoal,
              onChanged: onModeChanged,
              title: const Text('Encerrar ao bater meta', style: TextStyle(fontSize: 13)),
              subtitle: Text(
                version.closeOnGoal
                    ? 'A aprovação que cruzar a meta encerra o Barter na hora.'
                    : 'A meta só avisa: o Barter fica aberto até você encerrá-lo.',
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
                  // POR QUE ela fechou — uma pessoa, ou a meta que a encerrou
                  // sozinha. É a única resposta disponível meses depois, e o
                  // servidor escreve as duas no mesmo campo.
                  if (!isCurrent && version.closedBy != null)
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

  /// A PRODUTIVIDADE ESTIMADA da cultura (sc/ha) — a taxa que dimensiona a área
  /// do penhor das permutas desta gestão. Obrigatória, como o valor da saca: as
  /// duas são as metades da mesma conversão.
  final double estimatedYield;
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
    this.endsAt,
    this.targetSales,
    this.targetSacks,
    this.targetBarters,
    this.closeOnGoal = false,
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
  bool _closeOnGoal = false;
  String? _error;

  late final TextEditingController _grainPrice = TextEditingController(
    text: widget.previous?.grainPrice.toStringAsFixed(2).replaceAll('.', ',') ?? '',
  );

  /// A PRODUTIVIDADE vem preenchida com a da versão anterior, e é o campo em que
  /// isso mais importa: ela muda pouco de uma gestão para a outra (é estimativa
  /// agronômica da cultura, não cotação de mercado), e redigitá-la a cada
  /// republicação é a chance de sair um 6 no lugar de 60 — com o efeito de a
  /// permuta seguinte exigir dez vezes mais terra em garantia.
  late final TextEditingController _estimatedYield = TextEditingController(
    text: (widget.previous?.estimatedYield ?? 0) > 0
        ? widget.previous!.estimatedYield.toStringAsFixed(0)
        : '',
  );
  final _sales = TextEditingController();
  final _sacks = TextEditingController();
  final _barters = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _grainPrice.dispose();
    _estimatedYield.dispose();
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
    final estimatedYield = _number(_estimatedYield);
    if (estimatedYield == null || estimatedYield <= 0) {
      setState(() => _error =
          'Informe a produção estimada de ${widget.season.grainName.toLowerCase()} (sacas por hectare).');
      return;
    }

    // A mesma regra do servidor, respondida antes de subir a planilha: sem meta,
    // "encerrar ao bater meta" é uma opção ligada que nunca aconteceria. O 422
    // chegaria depois do upload inteiro.
    if (_closeOnGoal && !_hasTarget) {
      setState(() => _error = 'Defina ao menos uma meta para o Barter encerrar ao atingi-la.');
      return;
    }

    Navigator.pop(
      context,
      _PublishRequest(
        filename: filename,
        bytes: bytes,
        grainPrice: grainPrice,
        estimatedYield: estimatedYield,
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

  /// Alguma meta foi digitada? É o que dá sentido ao encerramento automático.
  bool get _hasTarget => [_sales, _sacks, _barters].any((c) => (_number(c) ?? 0) > 0);

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

            TextField(
              controller: _estimatedYield,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText:
                    'Produção estimada de ${widget.season.grainName.toLowerCase()} (sc/ha)',
                helperText: 'Divide as sacas da permuta para achar a área do penhor',
                helperMaxLines: 2,
                prefixIcon: const Icon(Icons.agriculture_outlined),
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
            // de propósito: é a segunda metade da mesma decisão, e o admin que
            // digita um número precisa dizer se ele avisa ou desliga a operação.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _closeOnGoal,
              onChanged: (v) => setState(() => _closeOnGoal = v),
              title: const Text('Encerrar ao bater meta', style: TextStyle(fontSize: 13)),
              subtitle: Text(
                _closeOnGoal
                    ? 'A aprovação que cruzar a meta encerra este Barter na hora.'
                    : 'A meta só avisa no painel: quem encerra é você.',
                style: TextStyle(fontSize: 11, color: AppColors.textLight),
              ),
            ),
            const SizedBox(height: 4),

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

  /// O VENCIMENTO DA CPR da safra — ver [SeasonModel.cprDueDate]. Opcional: a
  /// safra abre antes de o calendário da colheita estar fechado.
  final DateTime? cprDueDate;

  const _SeasonRequest({
    required this.grainId,
    required this.year,
    this.letter,
    this.cprDueDate,
  });
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
  DateTime? _cprDueDate;

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
          const SizedBox(height: 14),
          // O VENCIMENTO DA CPR nasce AQUI porque ele é da CULTURA, e a cultura
          // é o que esta tela acabou de escolher no primeiro campo. Perguntá-lo
          // no mesmo lugar em que se escolhe o grão é perguntá-lo a quem tem a
          // resposta na cabeça — o calendário da colheita daquele grão.
          _CprDueDateField(
            value: _cprDueDate,
            year: int.tryParse(_year.text.trim()) ?? DateTime.now().year,
            onPicked: (d) => setState(() => _cprDueDate = d),
          ),
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
                cprDueDate: _cprDueDate,
              ),
            );
          },
          child: const Text('Abrir'),
        ),
      ],
    );
  }
}

/// O CAMPO DO VENCIMENTO DA CPR — usado na abertura da safra e na correção
/// depois dela.
///
/// Ele é um DIA escolhido no calendário, e não um texto digitado: "30/06/26",
/// "30-06-2026" e "06/30/2026" são a mesma intenção escrita de três jeitos, e
/// uma delas vira a data errada dentro de um título executável.
///
/// A JANELA vai do ano da safra ao seguinte porque a colheita atravessa o ano:
/// a soja 2026 vence em junho de 2026, e o milho safrinha da mesma temporada, em
/// setembro — mas uma safra aberta em novembro colhe no ano seguinte.
class _CprDueDateField extends StatelessWidget {
  final DateTime? value;
  final int year;
  final ValueChanged<DateTime> onPicked;

  const _CprDueDateField({
    required this.value,
    required this.year,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    final escolhido = value != null;
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime(year, 6, 30),
          firstDate: DateTime(year, 1, 1),
          lastDate: DateTime(year + 1, 12, 31),
          helpText: 'Vencimento da CPR',
        );
        if (picked != null) onPicked(picked);
      },
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Vencimento da CPR',
          isDense: true,
          prefixIcon: const Icon(Icons.event_available_outlined, size: 20),
          // O QUE ACONTECE SE FICAR EM BRANCO, e não "opcional": quem lê precisa
          // saber o que está adiando, e o preço é uma cédula que não é emitida.
          helperText: escolhido
              ? 'Todas as CPRs desta safra vencem neste dia'
              : 'Sem ele, a cédula da safra não pode ser emitida',
          helperMaxLines: 2,
        ),
        child: Text(
          escolhido ? _fullDate(value!) : 'Escolher a data da entrega',
          style: TextStyle(
            fontSize: 14,
            color: escolhido ? AppColors.textDark : AppColors.textLight,
          ),
        ),
      ),
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
            'As permutas já registradas não mudam: elas guardam o valor do momento em que foram fechadas.',
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
