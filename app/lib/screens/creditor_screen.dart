import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../models/models.dart';
import '../services/api/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// A CREDORA — a empresa nos documentos que ela emite.
///
/// A CPR nomeia duas partes: o EMITENTE (o produtor, que muda a cada cédula) e
/// a CREDORA, que é sempre a mesma e aparece em quatro cláusulas — a
/// qualificação (II), a promessa de entrega, o local de entrega (V-d) e o foro
/// (XX) —, com a qualificação por inteiro repetida nas três primeiras.
///
/// Por isso ela é CADASTRO e não campo de formulário: pedir a razão social a
/// cada cédula é pedir que alguém digite o CNPJ do próprio empregador trezentas
/// vezes, e a trezentésima primeira sai com um dígito trocado num título de
/// crédito.
///
/// Ela tem DOIS DONOS — o admin e o faturista (`creditor.manage`). É a única
/// coisa deste sistema que os dois dividem, e a razão é que ela não decide
/// permuta nem concede acesso: é o timbre do papel, e quem percebe o CNPJ
/// errado é quem monta a cédula.
///
/// CADASTRO ÚNICO: uma instalação serve uma empresa. Não há lista, nem
/// exclusão — duas credoras fariam a cédula ter de escolher, e nada no
/// documento diz qual.
class CreditorScreen extends StatefulWidget {
  /// Dentro de outra tela (a aba Empresa dos Cadastros) ela dispensa o Scaffold
  /// e a barra de título — quem já os tem é a tela de fora. Aberta sozinha (o
  /// caminho do faturista, a partir da cédula), ela os traz.
  final bool embedded;

  const CreditorScreen({super.key, this.embedded = false});

  @override
  State<CreditorScreen> createState() => _CreditorScreenState();
}

class _CreditorScreenState extends State<CreditorScreen> {
  final _formKey = GlobalKey<FormState>();

  CprCreditor? _creditor;
  Object? _loadError;
  bool _saving = false;

  final _name = TextEditingController();
  final _cnpj = TextEditingController();
  final _address = TextEditingController();
  final _addressNumber = TextEditingController();
  final _city = TextEditingController();
  final _forum = TextEditingController();

  List<TextEditingController> get _all => [
        _name,
        _cnpj,
        _address,
        _addressNumber,
        _city,
        _forum,
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
      _creditor = null;
      _loadError = null;
    });
    try {
      final creditor = await AppData.creditor();
      if (!mounted) return;
      setState(() {
        _creditor = creditor;
        _fill(creditor);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  void _fill(CprCreditor creditor) {
    _name.text = creditor.name;
    _cnpj.text = creditor.cnpj;
    _address.text = creditor.address;
    _addressNumber.text = creditor.addressNumber;
    _city.text = creditor.city;
    _forum.text = creditor.forum;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final saved = await AppData.saveCreditor(CprCreditor(
        name: _name.text,
        cnpj: _cnpj.text,
        address: _address.text,
        addressNumber: _addressNumber.text,
        city: _city.text,
        forum: _forum.text,
      ));
      if (!mounted) return;
      setState(() {
        _creditor = saved;
        _saving = false;
        _fill(saved);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(saved.isComplete
            ? 'Credora salva. As cédulas já saem com estes dados.'
            : 'Salvo. Faltam ${saved.gaps.length} campo(s) para emitir cédula.'),
        backgroundColor: saved.isComplete ? AppColors.approved : AppColors.pending,
        behavior: SnackBarBehavior.floating,
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(children: [
        Expanded(child: _body()),
        if (_creditor != null) _saveBar(),
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Empresa (credora)')),
      body: _body(),
      bottomNavigationBar: _creditor == null ? null : SafeArea(child: _saveBar()),
    );
  }

  Widget _saveBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child:
                        CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                  )
                : const Icon(Icons.save_outlined, size: 20),
            label: Text(_saving ? 'Salvando…' : 'Salvar'),
          ),
        ),
      );

  Widget _body() {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 40, color: AppColors.textLight),
            const SizedBox(height: 12),
            Text(
              _loadError is ApiException
                  ? (_loadError as ApiException).message
                  : 'Não foi possível carregar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textMedium),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: const Text('Tentar novamente')),
          ]),
        ),
      );
    }

    final creditor = _creditor;
    if (creditor == null) return const Center(child: CircularProgressIndicator());

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _StatusCard(creditor: creditor),
          const SizedBox(height: 18),
          _field(_name, 'Razão social', hint: 'Como consta no CNPJ'),
          _field(_cnpj, 'CNPJ', hint: '00.000.000/0001-00', caps: false),
          Row(children: [
            Expanded(flex: 3, child: _field(_address, 'Logradouro da sede')),
            const SizedBox(width: 12),
            Expanded(child: _field(_addressNumber, 'Nº', caps: false)),
          ]),
          _field(_city, 'Cidade/UF', hint: 'Maringá/PR'),
          _field(_forum, 'Foro eleito (opcional)', hint: 'Em branco = a comarca da sede'),
          // O vazio do foro é o CASO NORMAL, e a tela precisa dizer isso: um
          // campo opcional em branco, sem explicação, parece pendência.
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 16),
            child: Text(
              creditor.effectiveForum.isEmpty
                  ? 'Cláusula XX da CPR. Preencha a cidade acima e o foro sai dela.'
                  : 'Cláusula XX da CPR. Sairá impresso: ${creditor.effectiveForum}.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textLight, height: 1.35),
            ),
          ),
          if (creditor.updatedBy.isNotEmpty)
            Text(
              'Última alteração por ${creditor.updatedBy}'
              '${creditor.updatedAt == null ? '' : ' em ${formatDate(creditor.updatedAt!)}'}.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textLight),
            ),
          const SizedBox(height: 12),
          Text(
            'Estes dados aparecem em quatro cláusulas de cada Cédula de Produto '
            'Rural: na qualificação da credora, na promessa de entrega, no local '
            'de entrega e no foro.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textLight, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool caps = true,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          textCapitalization: caps ? TextCapitalization.words : TextCapitalization.none,
          decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
        ),
      );
}

/// O estado do cadastro: pronto para emitir, ou o que ainda falta.
///
/// A lista de pendências é a MESMA que aparece na tela da cédula, e vem do
/// mesmo lugar (o servidor) — é o que faz as duas telas dizerem exatamente a
/// mesma coisa sobre o que está faltando.
class _StatusCard extends StatelessWidget {
  final CprCreditor creditor;

  const _StatusCard({required this.creditor});

  @override
  Widget build(BuildContext context) {
    final ok = creditor.isComplete;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ok ? AppColors.approvedBg : AppColors.pendingBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (ok ? AppColors.approved : AppColors.pending).withValues(alpha: 0.4),
        ),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ok ? Icons.verified_outlined : Icons.pending_actions,
            size: 19, color: ok ? AppColors.approved : AppColors.pending),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              ok
                  ? 'Cadastro completo — as cédulas saem com estes dados.'
                  : 'Falta preencher: ${creditor.gaps.join(', ')}.',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark),
            ),
            if (!ok) ...[
              const SizedBox(height: 3),
              Text(
                'Sem isto o faturista consegue preencher a cédula, mas ela não '
                'fica pronta para virar documento.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMedium, height: 1.35),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
