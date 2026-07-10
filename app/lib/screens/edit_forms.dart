import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/api/api_client.dart';
import '../widgets/common_widgets.dart';

/// Iniciais (até 2 letras) a partir do nome, para o avatar do rascunho local;
/// o valor definitivo vem do servidor junto com o registro salvo.
String initialsFrom(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (words.first[0] + words.last[0]).toUpperCase();
}

/// Cadastro/edição de um PRODUTOR (cliente). Quando [producer] é null, cria um
/// novo registro; caso contrário, edita o existente. Salva em [AppData.producers] e
/// devolve o produtor resultante via Navigator.pop.
class EditProducerScreen extends StatefulWidget {
  final ProducerModel? producer;
  const EditProducerScreen({super.key, this.producer});

  @override
  State<EditProducerScreen> createState() => _EditProducerScreenState();
}

class _EditProducerScreenState extends State<EditProducerScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _document;
  late final TextEditingController _phone;
  late final TextEditingController _farm;
  late final TextEditingController _city;
  late final TextEditingController _area;

  /// Vendedor dono da carteira a que o produtor pertence. Obrigatório: todo
  /// produtor nasce dentro da carteira de alguém.
  String? _sellerId;

  bool get _isNew => widget.producer == null;

  @override
  void initState() {
    super.initState();
    final p = widget.producer;
    // Se o vendedor da carteira foi excluído, força o admin a escolher outro.
    _sellerId = p != null && AppData.sellerById(p.sellerId) != null ? p.sellerId : null;
    _name = TextEditingController(text: p?.name ?? '');
    _document = TextEditingController(text: p?.document ?? '');
    _phone = TextEditingController(text: p?.phone ?? '');
    _farm = TextEditingController(text: p?.farmName ?? '');
    _city = TextEditingController(text: p?.city ?? '');
    _area = TextEditingController(
      text: p == null
          ? ''
          : (p.areaHa == p.areaHa.roundToDouble()
              ? p.areaHa.toStringAsFixed(0)
              : p.areaHa.toStringAsFixed(1).replaceAll('.', ',')),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _document.dispose();
    _phone.dispose();
    _farm.dispose();
    _city.dispose();
    _area.dispose();
    super.dispose();
  }

  /// Envia o cadastro à API e devolve o registro salvo (com id do servidor).
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final old = widget.producer;
    final name = _name.text.trim();
    final draft = ProducerModel(
      id: old?.id ?? '',
      name: name,
      sellerId: _sellerId!,
      document: _document.text.trim(),
      phone: _phone.text.trim(),
      farmName: _farm.text.trim(),
      city: _city.text.trim(),
      areaHa: double.parse(_area.text.trim().replaceAll(',', '.')),
      avatarInitials: initialsFrom(name),
      createdAt: old?.createdAt ?? DateTime.now(),
    );
    try {
      final saved = await AppData.saveProducer(draft, isNew: _isNew);
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Novo Produtor' : 'Editar Produtor')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: DropdownButtonFormField<String>(
                initialValue: _sellerId,
                decoration: const InputDecoration(
                  labelText: 'Carteira do vendedor',
                  prefixIcon: Icon(Icons.badge_outlined, size: 20),
                ),
                items: AppData.sellers
                    .map((s) => DropdownMenuItem(
                          value: s.id,
                          child: Text('${s.name} • ${s.branch}',
                              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _sellerId = v),
                validator: (v) => v == null ? 'Escolha o vendedor responsável' : null,
              ),
            ),
            _EditField(controller: _name, label: 'Nome', icon: Icons.person_outline, required: true),
            _EditField(controller: _document, label: 'Documento (CPF/CNPJ)', icon: Icons.badge_outlined, required: true),
            _EditField(
              controller: _phone,
              label: 'Telefone',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            _EditField(controller: _farm, label: 'Propriedade', icon: Icons.agriculture_outlined, required: true),
            _EditField(controller: _city, label: 'Município/UF', icon: Icons.location_on_outlined, required: true),
            _EditField(
              controller: _area,
              label: 'Área cultivável (ha)',
              icon: Icons.straighten,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              required: true,
              validator: (v) {
                final n = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                if (n == null || n <= 0) return 'Informe uma área válida (maior que 0)';
                return null;
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'A área define os insumos obrigatórios e a quantidade mínima de cada '
              'um nas novas permutas deste produtor. O produtor só aparece para o '
              'vendedor dono da carteira escolhida acima.',
              style: TextStyle(fontSize: 11, color: AppColors.textLight),
            ),
            const SizedBox(height: 20),
            _SaveButton(onPressed: _save, isNew: _isNew),
          ],
        ),
      ),
    );
  }
}

/// Cadastro/edição de um VENDEDOR. Quando [vendor] é null, cria um novo; caso
/// contrário, edita o existente. Salva em [AppData.sellers] e devolve o resultado.
class EditVendorScreen extends StatefulWidget {
  final UserModel? vendor;
  const EditVendorScreen({super.key, this.vendor});

  @override
  State<EditVendorScreen> createState() => _EditVendorScreenState();
}

class _EditVendorScreenState extends State<EditVendorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _branch;

  bool get _isNew => widget.vendor == null;

  @override
  void initState() {
    super.initState();
    final v = widget.vendor;
    _name = TextEditingController(text: v?.name ?? '');
    _email = TextEditingController(text: v?.email ?? '');
    _phone = TextEditingController(text: v?.phone ?? '');
    _branch = TextEditingController(text: v?.branch ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _branch.dispose();
    super.dispose();
  }

  /// Envia o cadastro à API. Vendedor novo nasce com a senha padrão (123456)
  /// definida no servidor.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final old = widget.vendor;
    final name = _name.text.trim();
    final draft = UserModel(
      id: old?.id ?? '',
      name: name,
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      branch: _branch.text.trim(),
      role: old?.role ?? UserRole.seller,
      avatarInitials: initialsFrom(name),
      createdAt: old?.createdAt ?? DateTime.now(),
    );
    try {
      final saved = await AppData.saveSeller(draft, isNew: _isNew);
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Novo Vendedor' : 'Editar Vendedor')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _EditField(controller: _name, label: 'Nome', icon: Icons.person_outline, required: true),
            _EditField(
              controller: _email,
              label: 'E-mail',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              required: true,
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Campo obrigatório';
                if (!t.contains('@') || !t.contains('.')) return 'E-mail inválido';
                return null;
              },
            ),
            _EditField(
              controller: _phone,
              label: 'Telefone',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            _EditField(controller: _branch, label: 'Filial', icon: Icons.store_outlined, required: true),
            const SizedBox(height: 20),
            _SaveButton(onPressed: _save, isNew: _isNew),
          ],
        ),
      ),
    );
  }
}

/// Cadastro/edição de uma CATEGORIA ("pasta") de insumos e sua regra de mínimo.
/// Quando [category] é null, cria uma nova; caso contrário, edita a existente.
/// Salva em [AppData.categories] e devolve o resultado via Navigator.pop.
class EditCategoryScreen extends StatefulWidget {
  final InputCategoryModel? category;
  const EditCategoryScreen({super.key, this.category});

  @override
  State<EditCategoryScreen> createState() => _EditCategoryScreenState();
}

class _EditCategoryScreenState extends State<EditCategoryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _value;
  late CategoryRuleType _ruleType;

  bool get _isNew => widget.category == null;
  bool get _needsValue => _ruleType != CategoryRuleType.none;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    _name = TextEditingController(text: c?.name ?? '');
    _ruleType = c?.ruleType ?? CategoryRuleType.none;
    _value = TextEditingController(
      text: (c != null && c.ruleValue > 0)
          ? (c.ruleValue == c.ruleValue.roundToDouble()
                  ? c.ruleValue.toStringAsFixed(0)
                  : c.ruleValue.toStringAsFixed(2))
              .replaceAll('.', ',')
          : '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  String get _valueLabel => _ruleType == CategoryRuleType.valuePerHa
      ? 'Valor mínimo por hectare (R\$)'
      : 'Percentual mínimo do total (%)';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final old = widget.category;
    final value = _needsValue
        ? (double.tryParse(_value.text.trim().replaceAll(',', '.')) ?? 0)
        : 0.0;
    final draft = InputCategoryModel(
      id: old?.id ?? '',
      name: _name.text.trim(),
      ruleType: _ruleType,
      ruleValue: value,
    );
    try {
      final saved = await AppData.saveCategory(draft, isNew: _isNew);
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Nova Categoria' : 'Editar Categoria')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _EditField(controller: _name, label: 'Nome da pasta', icon: Icons.folder_outlined, required: true),
            const SizedBox(height: 6),
            const Text('Regra de mínimo',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 8),
            RadioGroup<CategoryRuleType>(
              groupValue: _ruleType,
              onChanged: (v) => setState(() => _ruleType = v ?? CategoryRuleType.none),
              child: Column(
                children: const [
                  _RuleOption(
                    value: CategoryRuleType.none,
                    title: 'Sem exigência',
                    subtitle: 'A pasta só agrupa insumos.',
                  ),
                  _RuleOption(
                    value: CategoryRuleType.percentOfTotal,
                    title: '% do valor total',
                    subtitle: 'A pasta deve ser ao menos X% do custo total dos insumos.',
                  ),
                  _RuleOption(
                    value: CategoryRuleType.valuePerHa,
                    title: 'Valor por hectare',
                    subtitle: 'Mínimo de R\$ por hectare × área do produtor.',
                  ),
                ],
              ),
            ),
            if (_needsValue) ...[
              const SizedBox(height: 8),
              _EditField(
                controller: _value,
                label: _valueLabel,
                icon: _ruleType == CategoryRuleType.valuePerHa ? Icons.attach_money : Icons.percent,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                required: true,
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                  if (n == null || n <= 0) return 'Informe um valor maior que 0';
                  if (_ruleType == CategoryRuleType.percentOfTotal && n > 100) {
                    return 'O percentual não pode passar de 100';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 4),
            const Text(
              'Enquanto o mínimo da pasta não for atingido, o vendedor não consegue '
              'enviar a permuta. Edite o valor sempre que o período mudar.',
              style: TextStyle(fontSize: 11, color: AppColors.textLight),
            ),
            const SizedBox(height: 20),
            _SaveButton(onPressed: _save, isNew: _isNew),
          ],
        ),
      ),
    );
  }
}

/// Opção de regra de categoria (rádio + título + descrição).
class _RuleOption extends StatelessWidget {
  final CategoryRuleType value;
  final String title;
  final String subtitle;
  const _RuleOption({required this.value, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return RadioListTile<CategoryRuleType>(
      value: value,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
    );
  }
}

/// Confirma e executa a exclusão de um cadastro via API. As permutas antigas
/// não são afetadas: elas guardam o nome no próprio registro (snapshot no
/// servidor). Erros da API viram SnackBar de erro.
Future<void> confirmDeleteRegistration(
  BuildContext context, {
  required String title,
  required String name,
  required int barterCount,
  required Future<void> Function() onConfirm,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.delete_outline, color: AppColors.denied, size: 40),
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Excluir "$name"? Esta ação não pode ser desfeita.',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.textMedium)),
          if (barterCount > 0) ...[
            const SizedBox(height: 8),
            Text('As $barterCount permuta(s) já registradas serão mantidas no histórico.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Excluir'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.denied),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await onConfirm();
  } on ApiException catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
}

/// Campo de texto padrão das telas de edição (ícone + validação opcional).
class _EditField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool required;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _EditField({
    required this.controller,
    required this.label,
    required this.icon,
    this.required = false,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
        ),
        validator: validator ??
            (required
                ? (v) => (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null
                : null),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isNew;
  const _SaveButton({required this.onPressed, required this.isNew});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(isNew ? Icons.add : Icons.check, size: 18),
        label: Text(isNew ? 'Cadastrar' : 'Salvar alterações'),
      ),
    );
  }
}
