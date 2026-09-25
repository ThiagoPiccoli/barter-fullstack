import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../branding/active_brand.dart';
import '../data/app_data.dart';
import '../repositories/barter_program_repository.dart';
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
        grains: result.grains,
        endsAt: result.endsAt,
        targetSales: result.targetSales,
        targetBarters: result.targetBarters,
        closeOnGoal: result.closeOnGoal,
        insuranceRequired: result.insuranceRequired,
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

  /// ABRE A SAFRA — o CICLO, e não mais a cultura.
  ///
  /// Não há grão a escolher aqui: as culturas entram no LANÇAMENTO, e mudam de
  /// uma versão para a outra. O Barter pode abrir só com soja e ganhar o milho
  /// na versão seguinte sem que a safra tenha deixado de ser a mesma.
  Future<void> _openSeasonDialog() async {
    final result = await showDialog<_SeasonRequest>(
      context: context,
      builder: (_) => const _OpenSeasonDialog(),
    );
    if (result == null) return;

    try {
      await AppData.openSeason(
        year: result.year,
        name: result.name,
        letter: result.letter,
      );
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// ACERTA O VENCIMENTO DA CPR de UMA CULTURA do lançamento.
  ///
  /// Ele era da safra, quando a safra era a cultura. Hoje o mesmo Barter tem
  /// soja vencendo em junho e milho em setembro, e a data é de cada uma — mexer
  /// na do milho não pode alcançar as cédulas de soja.
  ///
  /// O diálogo AVISA o alcance antes de perguntar a data, e não depois: mexer
  /// aqui muda a entrega de toda cédula daquela cultura que ainda não foi
  /// emitida — as já emitidas congelaram a data delas. Sem o aviso, o admin
  /// corrigiria "a data desta cultura" achando que corrige um cadastro, e
  /// antecipando (ou adiando) a colheita de dezenas de produtores num campo que
  /// ninguém mais confere depois.
  Future<void> _cprDueDateDialog(
    BarterVersionModel version,
    VersionGrainModel grain,
  ) async {
    final cultura = grain.grainName.toLowerCase();
    final picked = await showDatePicker(
      context: context,
      initialDate: grain.cprDueDate ?? DateTime(_openSeason?.year ?? DateTime.now().year, 6, 30),
      firstDate: DateTime((_openSeason?.year ?? DateTime.now().year) - 1, 1, 1),
      lastDate: DateTime((_openSeason?.year ?? DateTime.now().year) + 2, 12, 31),
      helpText: 'Vencimento da CPR de $cultura',
    );
    if (picked == null || !mounted) return;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mudar o vencimento da CPR?'),
        content: Text(
          'As CPRs pagas em $cultura passam a vencer em ${_fullDate(picked)}.\n\n'
          'Vale para as cédulas desta cultura que ainda NÃO foram emitidas. '
          'As já emitidas mantêm a data com que saíram — elas estão assinadas. '
          'As outras culturas do Barter não são tocadas.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mudar')),
        ],
      ),
    );
    if (confirmado != true) return;

    try {
      await AppData.updateVersionGrain(version.code, grain.grainId, cprDueDate: picked);
      await _loadDetail();
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
      _toast('Vencimento da CPR de $cultura: ${_fullDate(picked)}.');
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// ACERTA A PRODUTIVIDADE ESTIMADA de uma cultura — a taxa que dimensiona a
  /// área do penhor das permutas dela.
  ///
  /// Existe pelo mesmo motivo do vencimento: republicar a tabela inteira por
  /// causa de um número de dois dígitos encerraria a versão vigente e
  /// reiniciaria a contagem do realizado.
  Future<void> _estimatedYieldDialog(
    BarterVersionModel version,
    VersionGrainModel grain,
  ) async {
    final controller = TextEditingController(
      text: grain.estimatedYield > 0 ? grain.estimatedYield.toStringAsFixed(0) : '',
    );
    final informado = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Produção estimada de ${grain.grainName.toLowerCase()}'),
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
              final value = double.tryParse(
                controller.text.trim().replaceAll('.', '').replaceAll(',', '.'),
              );
              if (value != null && value > 0) Navigator.pop(ctx, value);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (informado == null) return;

    try {
      await AppData.updateVersionGrain(version.code, grain.grainId, estimatedYield: informado);
      await _loadDetail();
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
      _toast('${grain.grainName}: ${informado.toStringAsFixed(0)} sc/ha.');
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

  /// LIGA ou DESLIGA o seguro agrícola do Barter vigente.
  ///
  /// O diálogo aparece ao LIGAR, e não é cerimônia: ligar acrescenta, a cada
  /// permuta nova, a área cultivável do produtor vezes a taxa da praça dele —
  /// custo que vira saca e que o produtor vai pagar na colheita. E ele conta
  /// quantos produtores estão em município SEM taxa cadastrada, porque a
  /// permuta deles passa a ser recusada no registro: melhor saber disso aqui do
  /// que pelo telefonema do consultor com o produtor na frente.
  ///
  /// Desligar não pede confirmação: ele não cria custo para ninguém, e as
  /// permutas que já nasceram com seguro continuam com ele (a taxa está
  /// congelada em cada uma).
  Future<void> _setInsurance(BarterVersionModel version, bool enabled) async {
    if (enabled) {
      final semTaxa = AppData.producers
          .where((p) => AppData.insuranceRateFor(p.city) == null)
          .length;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.shield_outlined, color: AppColors.atManager, size: 36),
          title: const Text('Incluir o seguro neste Barter'),
          content: Text(
            'Toda permuta registrada em ${version.code} a partir de agora vai incluir o '
            'seguro agrícola: a área cultivável do produtor vezes o valor por hectare do '
            'município dele. O custo entra na conta e é pago em sacas, como os insumos.'
            '${semTaxa > 0 ? '\n\nAtenção: $semTaxa produtor(es) estão em município sem taxa '
                'cadastrada, e a permuta deles será recusada no registro até a praça entrar '
                'na base de seguros.' : ''}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Incluir o seguro'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await AppData.setVersionInsurance(version.code, enabled);
      await _loadDetail();
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
      _toast(enabled
          ? 'As permutas novas passam a incluir o seguro agrícola.'
          : 'As permutas novas deixam de incluir o seguro. As já registradas não mudam.');
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
                onEditYield:
                    current.isOpen ? (grain) => _estimatedYieldDialog(current, grain) : null,
              ),
              const SizedBox(height: 16),
              // O VENCIMENTO DA CPR, uma linha por CULTURA.
              //
              // Ele vem logo abaixo do cartão do lançamento porque é dele que
              // depende: cada cultura tem a sua data, e é aqui que o admin a
              // acerta antes de a primeira cédula travar. Era um cartão da
              // SAFRA, quando a safra tinha um grão só.
              _sectionTitle('Vencimento das cédulas'),
              const SizedBox(height: 8),
              _CulturesDueDateCard(
                version: current,
                onEdit: (grain) => _cprDueDateDialog(current, grain),
              ),
              const SizedBox(height: 16),
              // O SEGURO vem antes das metas de propósito: ele muda o CUSTO de
              // cada permuta, e as metas medem o que já foi vendido. O que
              // decide dinheiro fica mais perto do cartão do lançamento.
              _sectionTitle('Seguro agrícola'),
              const SizedBox(height: 8),
              _InsuranceCard(
                version: current,
                onChanged: (enabled) => _setInsurance(current, enabled),
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

  /// ACERTAR A PRODUÇÃO ESTIMADA de uma cultura, sem republicar a tabela.
  /// Nulo quando a versão está encerrada: ali a taxa é registro do que valeu.
  final void Function(VersionGrainModel grain)? onEditYield;

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
          Text(
              '${season.name} • ${version.prices.length} insumo(s) na tabela • '
              '${version.grains.length} cultura(s)',
              style: TextStyle(color: AppColors.onPrimarySubtle, fontSize: 12)),
          const SizedBox(height: 14),
          // AS CULTURAS deste lançamento, uma linha cada. Elas coexistem: o
          // produtor escolhe em qual paga, e cada uma tem a própria cotação e a
          // própria produtividade — a segunda é o que dimensiona o penhor, e 60
          // sc/ha de soja não é 170 de milho.
          //
          // PRODUTIVIDADE ZERO É UM ALARME, e não um campo em branco: aquela
          // cultura está VIGENTE e recusando toda permuta nova, porque sem a
          // taxa não há como dimensionar a garantia. Sem este aviso, o admin
          // veria um Barter aberto e um time de vendas parado, sem ligar as duas
          // coisas — o erro apareceria como "a API está recusando permuta", na
          // voz do consultor.
          for (final grain in version.grains) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
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
                        child: Text('Saca de ${grain.grainName.toLowerCase()}',
                            style: TextStyle(color: AppColors.onPrimary, fontSize: 12)),
                      ),
                      Text(formatCurrency(grain.price),
                          style: TextStyle(
                              color: AppColors.onPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        grain.estimatedYield > 0
                            ? Icons.agriculture_outlined
                            : Icons.warning_amber_rounded,
                        color: AppColors.onPrimaryMuted,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          grain.estimatedYield > 0
                              ? 'Produção estimada (penhor)'
                              : 'Sem produção estimada — recusa permuta nesta cultura',
                          style: TextStyle(color: AppColors.onPrimarySubtle, fontSize: 11),
                        ),
                      ),
                      if (grain.estimatedYield > 0)
                        Text('${grain.estimatedYield.toStringAsFixed(0)} sc/ha',
                            style: TextStyle(
                                color: AppColors.onPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      if (onEditYield != null)
                        IconButton(
                          onPressed: () => onEditYield!(grain),
                          icon: Icon(Icons.edit_outlined,
                              size: 14, color: AppColors.onPrimarySubtle),
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
          ],
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

/// O VENCIMENTO DA CPR DE CADA CULTURA — o dia em que o produtor entrega
/// aquele grão.
///
/// Ele existe como cartão porque é uma decisão do LANÇAMENTO que ninguém mais
/// toma, e porque ele muda de cultura para cultura: soja vence na colheita da
/// soja, milho safrinha no dele. Já foi campo do formulário da cédula, digitado
/// uma vez por permuta por quem não tinha como saber a data certa daquela
/// cultura — e duas cédulas da mesma safra saíam com vencimentos diferentes, sem
/// ninguém ter como descobrir qual estava certa a não ser comparando os papéis.
///
/// Depois disso ele morou na SAFRA, e de lá saiu pelo mesmo motivo que o grão:
/// a safra passou a aceitar mais de uma cultura, e uma data só para as duas
/// seria uma delas errada.
///
/// VAZIO É ÂMBAR, e não neutro: nada quebra até a primeira emissão daquela
/// cultura, e então TODA cédula dela trava de uma vez. O aviso é o que separa
/// "acerto isto hoje" de "descubro isto com o produtor esperando na sala do
/// emissor".
class _CulturesDueDateCard extends StatelessWidget {
  final BarterVersionModel version;
  final void Function(VersionGrainModel grain) onEdit;

  const _CulturesDueDateCard({required this.version, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final grain in version.grains) ...[
          _row(grain),
          if (grain != version.grains.last) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _row(VersionGrainModel grain) {
    final due = grain.cprDueDate;
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
                  'Vencimento da CPR • ${grain.grainName}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  acertado
                      ? '${_fullDate(due)} • todas as cédulas pagas em '
                          '${grain.grainName.toLowerCase()} vencem neste dia'
                      : 'Ainda não acertado. Sem ele, nenhuma cédula paga em '
                          '${grain.grainName.toLowerCase()} pode ser emitida.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMedium, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          acertado
              ? TextButton(onPressed: () => onEdit(grain), child: const Text('Mudar'))
              : ElevatedButton(
                  onPressed: () => onEdit(grain),
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
/// O SEGURO AGRÍCOLA deste lançamento — o interruptor e o que ele significa.
///
/// Cartão próprio, e não uma linha dentro do cartão da versão, pelo mesmo
/// motivo do vencimento da CPR: ele não é um dado do lançamento, é uma DECISÃO
/// sobre ele — e uma que muda o custo de toda permuta que vier depois.
///
/// O que ele mostra além do interruptor é o estado da BASE: quantas praças
/// estão cadastradas e quantos produtores ficariam de fora. Ligado o seguro,
/// essa segunda contagem é a lista de recusas que o consultor vai encontrar.
class _InsuranceCard extends StatelessWidget {
  final BarterVersionModel version;
  final ValueChanged<bool> onChanged;

  const _InsuranceCard({required this.version, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cities = AppData.insuranceRates.length;
    final semTaxa =
        AppData.producers.where((p) => AppData.insuranceRateFor(p.city) == null).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: version.insuranceRequired,
              onChanged: onChanged,
              title: const Text('Este Barter leva seguro', style: TextStyle(fontSize: 13)),
              subtitle: Text(
                version.insuranceRequired
                    ? 'Cada permuta nova inclui a área do produtor × o valor por hectare da praça dele.'
                    : 'As permutas saem sem seguro. A base por município continua cadastrada.',
                style: TextStyle(fontSize: 11, color: AppColors.textLight),
              ),
            ),
            const Divider(height: 20),
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
            if (version.insuranceRequired && semTaxa > 0) ...[
              const SizedBox(height: 8),
              Text(
                'A permuta de um produtor sem taxa é RECUSADA no registro, com o nome do '
                'município na mensagem. Quem a lê é o consultor, e quem a resolve é você.',
                style: TextStyle(fontSize: 11, color: AppColors.textLight),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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
        subtitle: Text('${season.versions.length} versão(ões)',
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

  /// AS CULTURAS deste lançamento — pelo menos uma.
  ///
  /// Cada uma leva a cotação da saca, a produtividade estimada (as duas metades
  /// da mesma conversão: a primeira leva o custo a sacas, a segunda as sacas à
  /// área do penhor), o vencimento da entrega e a meta de sacas dela.
  final List<VersionGrainInput> grains;

  final DateTime? endsAt;
  final double? targetSales;
  final int? targetBarters;
  final bool closeOnGoal;

  /// ESTE LANÇAMENTO LEVA SEGURO? Ver `BarterVersionModel.insuranceRequired`.
  final bool insuranceRequired;

  final String? note;
  final bool carryOver;

  const _PublishRequest({
    required this.filename,
    required this.bytes,
    required this.grains,
    this.endsAt,
    this.targetSales,
    this.targetBarters,
    this.closeOnGoal = false,
    this.insuranceRequired = false,
    this.note,
    this.carryOver = false,
  });
}

/// O RASCUNHO DE UMA CULTURA no formulário de publicação.
///
/// Ele guarda os controladores dos quatro campos que mudam de grão para grão,
/// porque eles são editados juntos e descartados juntos — uma cultura removida
/// da lista leva os campos dela embora.
class _GrainDraft {
  String? grainId;
  final price = TextEditingController();
  final yield_ = TextEditingController();
  final targetSacks = TextEditingController();
  DateTime? cprDueDate;

  _GrainDraft({this.grainId});

  void dispose() {
    price.dispose();
    yield_.dispose();
    targetSacks.dispose();
  }
}

/// Formulário de publicação: a planilha dos insumos + AS CULTURAS + a vigência
/// e as metas.
///
/// A planilha traz os INSUMOS, e ela é UMA para todas as culturas: o litro de
/// glifosato custa os mesmos R$ 40 quer ele vá ser pago em soja ou em milho. O
/// que se digita aqui é o que muda de um grão para o outro — a cotação da saca,
/// a produtividade, o vencimento e a meta —, porque nada disso vem do
/// fornecedor: é a cooperativa que decide por quanto recebe.
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

  /// ESTE LANÇAMENTO LEVA SEGURO? Padrão desligado, como no servidor: o que
  /// acrescenta custo à permuta de todo mundo se escolhe, não se herda.
  bool _insuranceRequired = false;
  String? _error;

  /// AS CULTURAS sendo lançadas. A lista nasce com as da versão anterior —
  /// republicar uma tabela raramente muda quais grãos o Barter aceita, e
  /// redigitar a produtividade a cada vez é a chance de sair um 6 no lugar de
  /// 60, com o efeito de a permuta seguinte exigir dez vezes mais terra em
  /// garantia. Sem versão anterior, uma linha em branco.
  late final List<_GrainDraft> _grains = _initialGrains();

  List<_GrainDraft> _initialGrains() {
    final previous = widget.previous?.grains ?? const <VersionGrainModel>[];
    if (previous.isEmpty) return [_GrainDraft()];
    return previous.map((grain) {
      final draft = _GrainDraft(grainId: grain.grainId)
        ..cprDueDate = grain.cprDueDate;
      if (grain.price > 0) {
        draft.price.text = grain.price.toStringAsFixed(2).replaceAll('.', ',');
      }
      if (grain.estimatedYield > 0) {
        draft.yield_.text = grain.estimatedYield.toStringAsFixed(0);
      }
      if ((grain.targetSacks ?? 0) > 0) {
        draft.targetSacks.text = grain.targetSacks!.toStringAsFixed(0);
      }
      return draft;
    }).toList();
  }

  final _sales = TextEditingController();
  final _barters = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    for (final grain in _grains) {
      grain.dispose();
    }
    _sales.dispose();
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
    // AS CULTURAS, conferidas uma a uma antes de subir a planilha: o 422 do
    // servidor chegaria depois do upload inteiro, e a mensagem dele não diz em
    // qual linha do formulário está o problema.
    final grains = <VersionGrainInput>[];
    for (final (index, draft) in _grains.indexed) {
      final numero = _grains.length > 1 ? ' da ${index + 1}ª cultura' : '';
      final grainId = draft.grainId;
      if (grainId == null) {
        setState(() => _error = 'Escolha o grão$numero.');
        return;
      }
      if (grains.any((grain) => grain.grainId == grainId)) {
        setState(() => _error = 'A mesma cultura aparece duas vezes.');
        return;
      }
      final price = _number(draft.price);
      if (price == null || price <= 0) {
        setState(() => _error = 'Informe o valor da saca$numero.');
        return;
      }
      final estimatedYield = _number(draft.yield_);
      if (estimatedYield == null || estimatedYield <= 0) {
        setState(() => _error = 'Informe a produção estimada$numero (sacas por hectare).');
        return;
      }
      grains.add(VersionGrainInput(
        grainId: grainId,
        price: price,
        estimatedYield: estimatedYield,
        cprDueDate: draft.cprDueDate,
        targetSacks: _number(draft.targetSacks),
      ));
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
        grains: grains,
        endsAt: _endsAt,
        targetSales: _number(_sales),
        targetBarters: _number(_barters)?.round(),
        closeOnGoal: _closeOnGoal,
        insuranceRequired: _insuranceRequired,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        carryOver: _carryOver,
      ),
    );
  }

  /// Alguma meta foi digitada? É o que dá sentido ao encerramento automático.
  ///
  /// As METAS DE SACAS entram na conta mesmo sendo de cada cultura: "encerrar ao
  /// bater meta" com uma meta de sacas só no milho é uma combinação legítima —
  /// o Barter fecha quando o milho enche.
  bool get _hasTarget =>
      [_sales, _barters].any((c) => (_number(c) ?? 0) > 0) ||
      _grains.any((grain) => (_number(grain.targetSacks) ?? 0) > 0);

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

            // AS CULTURAS. Elas coexistem: o Barter pode abrir só com soja e
            // acrescentar o milho aqui, e a partir daí o consultor escolhe em
            // qual delas cada cliente paga. A tabela de insumos é a mesma para
            // todas — o que muda é a cotação que converte o custo em sacas.
            Row(
              children: [
                Icon(Icons.grass, color: AppColors.primary, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Culturas do lançamento',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark)),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _grains.add(_GrainDraft())),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Acrescentar'),
                ),
              ],
            ),
            Text(
              'O produtor escolhe em qual delas paga. Cada uma tem a própria '
              'cotação, produção estimada e data de entrega.',
              style: TextStyle(fontSize: 11, color: AppColors.textLight),
            ),
            const SizedBox(height: 10),
            for (final (index, draft) in _grains.indexed) ...[
              _grainCard(index, draft),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 2),

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
                Expanded(child: _target(_barters, 'Permutas')),
              ],
            ),
            const SizedBox(height: 4),
            // A META DE SACAS não está aqui: ela é de cada CULTURA, e fica no
            // cartão dela. Sacas de soja e de milho não somam — um número único
            // juntando as duas seria uma barra de progresso sem significado.
            Text('A meta de sacas é de cada cultura, no cartão dela.',
                style: TextStyle(fontSize: 11, color: AppColors.textLight)),

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

            const Divider(height: 24),
            // O SEGURO fica com as metas, e não com o preço da saca: as duas
            // taxas de cima (cotação e produtividade) são obrigatórias e a
            // conta não sai sem elas; isto aqui é uma OPÇÃO do lançamento, como
            // o encerramento automático.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _insuranceRequired,
              onChanged: (v) => setState(() => _insuranceRequired = v),
              title: const Text('Incluir seguro agrícola', style: TextStyle(fontSize: 13)),
              subtitle: Text(
                _insuranceRequired
                    ? 'Cada permuta inclui a área do produtor × o valor por hectare do município dele.'
                    : 'As permutas saem sem seguro. Pode ser ligado depois, sem republicar.',
                style: TextStyle(fontSize: 11, color: AppColors.textLight),
              ),
            ),
            if (_insuranceRequired && AppData.insuranceRates.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'A base de seguros está vazia: sem praça cadastrada, toda permuta será '
                  'recusada no registro. Cadastre-as em Cadastros › Seguros.',
                  style: TextStyle(fontSize: 11, color: AppColors.pending),
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

  /// UMA CULTURA no formulário: o grão, a cotação, a produção estimada, o
  /// vencimento da entrega e a meta de sacas dela.
  ///
  /// O VENCIMENTO é opcional aqui de propósito: o Barter é lançado antes de a
  /// colheita ter data fechada, e travar a publicação por causa dele pararia a
  /// venda por um campo que a cédula sabe cobrar sozinha, de quem o resolve.
  Widget _grainCard(int index, _GrainDraft draft) {
    final grains = AppData.grains;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: draft.grainId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Grão', isDense: true),
                  items: [
                    for (final grain in grains)
                      DropdownMenuItem(value: grain.id, child: Text(grain.name)),
                  ],
                  onChanged: (value) => setState(() => draft.grainId = value),
                ),
              ),
              // A PRIMEIRA cultura não se remove: um Barter sem cultura nenhuma
              // é uma tabela de insumos que ninguém tem como pagar.
              if (_grains.length > 1)
                IconButton(
                  tooltip: 'Remover esta cultura',
                  onPressed: () => setState(() {
                    _grains.removeAt(index).dispose();
                  }),
                  icon: Icon(Icons.close, size: 18, color: AppColors.textLight),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Saca (R\$)',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: draft.yield_,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Produção (sc/ha)',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'A cotação converte o custo em sacas; a produção divide as sacas '
            'para achar a área do penhor.',
            style: TextStyle(fontSize: 10, color: AppColors.textLight),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final chosen = await showDatePicker(
                      context: context,
                      initialDate: draft.cprDueDate ?? DateTime(now.year + 1, 6, 30),
                      firstDate: now,
                      lastDate: DateTime(now.year + 3),
                      helpText: 'Vencimento da CPR desta cultura',
                    );
                    if (chosen != null) setState(() => draft.cprDueDate = chosen);
                  },
                  icon: const Icon(Icons.event_outlined, size: 16),
                  label: Text(
                    draft.cprDueDate == null
                        ? 'Vencimento da CPR'
                        : 'Vence ${_fullDate(draft.cprDueDate!)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                ),
              ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: draft.targetSacks,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Meta (sacas)', isDense: true),
                ),
              ),
            ],
          ),
        ],
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
  final int year;
  final String? name;
  final String? letter;

  const _SeasonRequest({required this.year, this.name, this.letter});
}

/// A ABERTURA DA SAFRA — o CICLO em que o Barter vai acontecer.
///
/// NÃO HÁ GRÃO AQUI, e é a mudança que esta tela carrega: as culturas são do
/// LANÇAMENTO (ver o formulário de publicação), porque elas coexistem e mudam de
/// uma versão para a outra. O Barter pode abrir só com soja e ganhar o milho na
/// versão seguinte sem que a safra tenha deixado de ser a mesma — e, enquanto o
/// grão morou aqui, oferecer duas culturas exigia abrir duas safras.
///
/// O VENCIMENTO DA CPR saiu junto, pelo mesmo motivo: ele é a data de entrega
/// DAQUELE grão, e uma safra com soja e milho tem duas.
class _OpenSeasonDialog extends StatefulWidget {
  const _OpenSeasonDialog();

  @override
  State<_OpenSeasonDialog> createState() => _OpenSeasonDialogState();
}

class _OpenSeasonDialogState extends State<_OpenSeasonDialog> {
  late final _year = TextEditingController(text: '${DateTime.now().year}');
  final _name = TextEditingController();
  final _letter = TextEditingController();

  @override
  void dispose() {
    _year.dispose();
    _name.dispose();
    _letter.dispose();
    super.dispose();
  }

  /// A sugestão de código, para o admin ver o que vai nascer: B2026.
  ///
  /// A letra era a inicial do grão ("S de soja") e hoje é a do CICLO — o `B` de
  /// Barter, que é o padrão do servidor. Ela continua editável porque quem roda
  /// dois ciclos no mesmo ano (verão e inverno) os separa por ela.
  String get _preview {
    final letter = _letter.text.trim().isEmpty ? 'B' : _letter.text.trim().toUpperCase();
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
          Text(
            'A safra é o CICLO. As culturas em que o produtor pode pagar — e a '
            'cotação, a produção estimada e o vencimento de cada uma — são '
            'escolhidas ao publicar o Barter.',
            style: TextStyle(fontSize: 12, color: AppColors.textMedium),
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Nome (opcional)',
              hintText: 'Barter 2026/27',
            ),
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
                year: year,
                name: _name.text.trim().isEmpty ? null : _name.text.trim(),
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
