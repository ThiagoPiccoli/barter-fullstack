import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/api/api_client.dart';
import '../widgets/common_widgets.dart';
import '../widgets/provisional_password_dialog.dart';

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

  /// Os consultores que atendem este produtor. PELO MENOS UM: um produtor que
  /// ninguém atende não aparece para ninguém. Pode ser mais de um — consultores
  /// dividem região e atendem o mesmo cliente.
  final Set<String> _consultantIds = {};

  bool get _isNew => widget.producer == null;

  @override
  void initState() {
    super.initState();
    final p = widget.producer;
    // Consultor excluído sai da lista: o vínculo dele já não existe no
    // servidor, e mostrá-lo marcado prometeria salvar algo que seria recusado.
    if (p != null) {
      _consultantIds.addAll(
        p.consultantIds.where((id) => AppData.consultantById(id) != null),
      );
    }
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
      consultantIds: _consultantIds.toList(),
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
            _ConsultantWalletField(
              selected: _consultantIds,
              onChanged: () => setState(() {}),
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
            Text(
              'A área define os insumos obrigatórios e a quantidade mínima de cada '
              'um nas novas permutas deste produtor. O produtor só aparece para os '
              'consultores marcados acima.',
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

/// A CARTEIRA do produtor: quais consultores o atendem.
///
/// Era um dropdown de escolha única, e a mudança para marcação múltipla é a
/// própria funcionalidade — consultores dividem região e atendem o mesmo
/// produtor. O dropdown obrigava a escolher um; a única forma de representar
/// dois era cadastrar o produtor duas vezes, e aí a área cultivável passava a
/// existir em dobro e as permutas do mesmo cliente se partiam entre dois
/// registros.
///
/// É um [FormField] e não uma lista solta para a exigência de "pelo menos um"
/// entrar no mesmo `validate()` dos outros campos — em vez de virar um `if`
/// antes do salvamento, que é o tipo de conferência que se esquece de fazer
/// quando aparece um segundo botão de salvar.
class _ConsultantWalletField extends StatelessWidget {
  /// O conjunto vivo de ids marcados — a tela é dona dele; este campo escreve
  /// dentro e avisa por [onChanged].
  final Set<String> selected;
  final VoidCallback onChanged;

  const _ConsultantWalletField({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final consultants = AppData.consultants;

    return FormField<Set<String>>(
      initialValue: selected,
      validator: (_) =>
          selected.isEmpty ? 'Marque pelo menos um consultor para atender este produtor' : null,
      builder: (state) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: AppShape.field,
                border: Border.all(
                  color: state.hasError ? AppColors.denied : AppColors.borderSubtle,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                    child: Row(
                      children: [
                        Icon(Icons.badge_outlined, size: 20, color: AppColors.textLight),
                        const SizedBox(width: 8),
                        Text(
                          'Consultores que atendem',
                          style: TextStyle(fontSize: 12, color: AppColors.textLight),
                        ),
                        const Spacer(),
                        if (selected.isNotEmpty)
                          Text(
                            '${selected.length} marcado(s)',
                            style: TextStyle(fontSize: 11, color: AppColors.textLight),
                          ),
                      ],
                    ),
                  ),
                  if (consultants.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Text(
                        'Nenhum consultor cadastrado ainda.',
                        style: TextStyle(fontSize: 13, color: AppColors.textMedium),
                      ),
                    )
                  else
                    // Teto de altura, e não a lista inteira: a carteira cresce
                    // com a operação, e sem isto o formulário viraria uma rolagem
                    // em que o botão de salvar some conforme a empresa contrata.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 4),
                        itemCount: consultants.length,
                        itemBuilder: (_, i) {
                          final c = consultants[i];
                          return CheckboxListTile(
                            value: selected.contains(c.id),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            title: Text(c.name,
                                style: const TextStyle(fontSize: 14),
                                overflow: TextOverflow.ellipsis),
                            subtitle: Text(c.branch,
                                style: TextStyle(fontSize: 11, color: AppColors.textLight),
                                overflow: TextOverflow.ellipsis),
                            onChanged: (marked) {
                              if (marked == true) {
                                selected.add(c.id);
                              } else {
                                selected.remove(c.id);
                              }
                              // O campo revalida na hora: desmarcar o último
                              // precisa acusar na hora, e não só ao salvar.
                              state.didChange(selected);
                              state.validate();
                              onChanged();
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 6),
                child: Text(
                  state.errorText!,
                  style: TextStyle(fontSize: 12, color: AppColors.denied),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Cadastro/edição de um CONSULTOR ou de um GERENTE.
///
/// Uma tela para os dois porque o cadastro é o mesmo — nome, e-mail, telefone e
/// unidade — e no servidor as duas rotas compartilham o mesmo motor de
/// provisionamento. O que separa é UM campo: o consultor aponta o gerente a
/// quem as permutas dele serão enviadas; o gerente não tem gerente.
///
/// Duas telas iguais menos um dropdown seria a receita para corrigir a validação
/// do e-mail em uma e esquecer a outra.
class EditStaffScreen extends StatefulWidget {
  /// O registro a editar, ou null para criar um novo.
  final UserModel? user;

  /// O papel que este formulário cadastra: consultor, gerente, faturista ou
  /// comitê. Decide a rota, o título, se o formulário pergunta o gerente e se o
  /// cadastro é de uma PESSOA ou de um ÓRGÃO (ver [_isCommittee]).
  final UserRole role;

  const EditStaffScreen({super.key, this.user, required this.role});

  @override
  State<EditStaffScreen> createState() => _EditStaffScreenState();
}

class _EditStaffScreenState extends State<EditStaffScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;

  /// A UNIDADE em que ele trabalha. Era um campo de texto ("Filial"); virou
  /// escolha de cadastro quando a filial deixou de ser rótulo e virou lugar.
  String? _unitId;

  /// O GERENTE dele — a quem as permutas que ele registrar serão enviadas, e
  /// quem dará o parecer técnico delas. Obrigatório para o consultor: sem
  /// gerente as permutas nasceriam endereçadas a ninguém, e o servidor recusa
  /// o cadastro. Null e não perguntado quando o cadastro é de um gerente.
  String? _managerId;

  bool get _isNew => widget.user == null;
  bool get _isConsultant => widget.role == UserRole.consultant;

  /// O COMITÊ não é uma pessoa: é uma reunião, e o cadastro é um só.
  ///
  /// Três coisas mudam por causa disso, e todas aparecem na tela: o campo de
  /// nome pede o nome do ÓRGÃO (não "nome completo"), não há exclusão — sem o
  /// cadastro nenhuma permuta é decidida — e o texto explica que o acesso é
  /// compartilhado por quem participa. O servidor impõe o resto: um segundo
  /// cadastro leva 422 (ver committee.controller.ts).
  bool get _isCommittee => widget.role == UserRole.committee;

  bool get _isBiller => widget.role == UserRole.biller;

  String get _roleLabel => widget.role.label;

  @override
  void initState() {
    super.initState();
    final v = widget.user;
    _name = TextEditingController(text: v?.name ?? '');
    _email = TextEditingController(text: v?.email ?? '');
    _phone = TextEditingController(text: v?.phone ?? '');
    // Só pré-seleciona o que ainda existe: uma unidade ou um gerente excluído
    // deixaria o dropdown com um valor fora da lista, e o Flutter derruba a
    // tela com "no item with matching value".
    _unitId = AppData.units.any((u) => u.id == v?.unitId) ? v?.unitId : null;
    _managerId = AppData.managers.any((m) => m.id == v?.managerId) ? v?.managerId : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// Envia o cadastro à API.
  ///
  /// No cadastro NOVO, o servidor sorteia a senha de primeira entrada e a
  /// devolve uma única vez — por isso a tela precisa mostrá-la antes de sair.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final old = widget.user;
    final name = _name.text.trim();
    final draft = UserModel(
      id: old?.id ?? '',
      name: name,
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      unitId: _unitId!,
      // O rótulo da unidade quem escreve é o servidor, a partir do id — aqui
      // ele vai só para o objeto ficar coerente enquanto a resposta não volta.
      branch: AppData.unitById(_unitId)?.name ?? '',
      managerId: _isConsultant ? _managerId! : '',
      role: widget.role,
      avatarInitials: initialsFrom(name),
      createdAt: old?.createdAt ?? DateTime.now(),
    );
    try {
      if (_isNew) {
        final provisioned = await _create(draft);
        if (!mounted) return;
        await showProvisionalPassword(context, provisioned, isReset: false);
        if (mounted) Navigator.pop(context, provisioned.consultant);
      } else {
        final saved = await _update(draft);
        if (mounted) Navigator.pop(context, saved);
      }
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// A rota vem do PAPEL — o mesmo desenho do servidor, onde cada papel tem a
  /// sua e o motor de provisionamento é um só. O admin não aparece: ele não se
  /// cadastra por aqui (ver `ManagedRole` em common/roles.ts), e o consultor não
  /// chega neste método sem gerente porque o formulário o exige antes.
  Future<ProvisionedConsultant> _create(UserModel draft) => switch (widget.role) {
        UserRole.consultant => AppData.createConsultant(draft),
        UserRole.manager => AppData.createManager(draft),
        UserRole.biller => AppData.createBiller(draft),
        UserRole.committee => AppData.createCommittee(draft),
        UserRole.admin => throw UnsupportedError('Não existe cadastro de administrador'),
      };

  Future<UserModel> _update(UserModel draft) => switch (widget.role) {
        UserRole.consultant => AppData.updateConsultant(draft),
        UserRole.manager => AppData.updateManager(draft),
        UserRole.biller => AppData.updateBiller(draft),
        UserRole.committee => AppData.updateCommittee(draft),
        UserRole.admin => throw UnsupportedError('Não existe cadastro de administrador'),
      };

  /// Nova senha de primeira entrada. Derruba as sessões abertas do titular no
  /// servidor — a confirmação avisa isso antes.
  Future<void> _resetPassword() async {
    final user = widget.user;
    if (user == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.lock_reset, color: AppColors.pending, size: 40),
        title: const Text('Redefinir senha?'),
        content: Text(
          _isCommittee
              // Na conta compartilhada a frase é outra porque o efeito é outro:
              // a senha circula entre quem participa da reunião, e trocá-la tira
              // o acesso de TODO MUNDO que estava com a anterior — que é
              // exatamente o que se quer quando a composição muda.
              ? 'Uma nova senha provisória será gerada para o ${user.name}, e a atual '
                  'deixa de valer para todos que a tinham.\n\n'
                  'Qualquer sessão aberta nesta conta será encerrada.'
              : 'Uma nova senha provisória será gerada para ${user.name.split(' ').first}, '
                  'e a senha atual deixa de valer.\n\n'
                  'Qualquer sessão aberta nesta conta será encerrada.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textMedium),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.lock_reset, size: 18),
            label: const Text('Redefinir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      // O comitê não tem id na rota: o cadastro é um só (ver CommitteeRepository).
      final provisioned = _isCommittee
          ? await AppData.resetCommitteePassword()
          : _isBiller
              ? await AppData.resetBillerPassword(user.id)
              : await AppData.resetManagerPassword(user.id);
      if (mounted) await showProvisionalPassword(context, provisioned, isReset: true);
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// Exclusão de GERENTE e FATURISTA — as duas pessoas que este formulário
  /// cadastra e que podem sair.
  ///
  /// No gerente o servidor RECUSA enquanto ele tiver consultores no time ou
  /// permutas esperando o parecer dele, e a mensagem diz qual dos dois falta — a
  /// tela só a exibe, em vez de repetir a regra aqui e arriscar divergir dela.
  /// O faturista sai sem trava: o que ele faturou guarda o nome dele no próprio
  /// registro, e a fila dele é o estado da permuta, não uma caixa de entrada.
  ///
  /// O COMITÊ não tem este botão, e nem rota: o cadastro é a ETAPA, e sem ele
  /// nenhuma permuta é decidida. Para tirar o acesso, redefine-se a senha.
  Future<void> _delete() async {
    final user = widget.user;
    if (user == null) return;
    await confirmDeleteRegistration(
      context,
      title: 'Excluir $_roleLabel',
      name: user.name,
      barterCount: _isBiller
          ? AppData.barters.where((b) => b.invoicedBy == user.name).length
          : AppData.barters.where((b) => b.managerId == user.id).length,
      onConfirm: () async {
        await (_isBiller ? AppData.deleteBiller(user.id) : AppData.deleteManager(user.id));
        if (mounted) Navigator.pop(context);
      },
    );
  }

  /// O que este cadastro faz no fluxo, em uma frase — a linha que explica ao
  /// admin o que ele está criando, e por que a próxima etapa depende dela.
  String _footerFor(UserRole role) => switch (role) {
        UserRole.consultant =>
          'As permutas registradas por este consultor são enviadas ao gerente escolhido '
              'acima, que dá o parecer técnico antes de elas seguirem para o comitê. A '
              'unidade é onde ele trabalha — ela não decide o parecer, e a retirada de cada '
              'permuta é combinada caso a caso.',
        UserRole.manager =>
          'O gerente recebe as permutas dos consultores do time dele e escreve o parecer '
              'técnico de cada uma. Ele passa a aparecer na lista de gerentes do cadastro de '
              'consultor — é lá que o time é montado.',
        UserRole.committee =>
          'O comitê é uma REUNIÃO, e este é o cadastro dela: um acesso só, compartilhado '
              'por quem participa. É por ele que se aprova ou nega a permuta depois do '
              'parecer do gerente, e a decisão sai assinada pelo comitê — a ata (quem '
              'estava, o que foi acordado) vai na observação da decisão.',
        UserRole.biller =>
          'O faturista fatura o que o comitê aprovou — a última etapa da permuta. A fila '
              'dele não é pessoal: é o estado da permuta, e todos os faturistas veem a '
              'mesma. Quem emitiu cada uma fica registrado na linha do tempo dela.',
        UserRole.admin => '',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isCommittee
            ? (_isNew ? 'Cadastrar Comitê' : 'Editar Comitê')
            : '${_isNew ? 'Novo' : 'Editar'} $_roleLabel'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Os cadastros de que este formulário depende. Sem eles os
            // dropdowns abrem vazios e o "campo obrigatório" viraria um beco
            // sem saída — dizer o que falta é o mínimo. O gerente só depende da
            // unidade; o consultor, das duas coisas.
            if (AppData.units.isEmpty || (_isConsultant && AppData.managers.isEmpty)) ...[
              _MissingPrerequisiteHint(
                missing: [
                  if (AppData.units.isEmpty) 'nenhuma unidade cadastrada',
                  if (_isConsultant && AppData.managers.isEmpty) 'nenhum gerente cadastrado',
                ],
              ),
              const SizedBox(height: 14),
            ],
            // O comitê não tem NOME DE PESSOA: o que se escreve aqui é o nome do
            // órgão, e é ele que vai assinar cada decisão. O rótulo dizer isso
            // evita o cadastro nascer com o nome de quem preencheu o formulário.
            _EditField(
              controller: _name,
              label: _isCommittee ? 'Nome do comitê' : 'Nome',
              icon: _isCommittee ? Icons.groups_2_outlined : Icons.person_outline,
              required: true,
            ),
            _EditField(
              controller: _email,
              label: _isCommittee ? 'E-mail de acesso do comitê' : 'E-mail',
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
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: DropdownButtonFormField<String>(
                initialValue: _unitId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Unidade',
                  prefixIcon: Icon(Icons.store_outlined, size: 20),
                ),
                items: AppData.units
                    .map((u) => DropdownMenuItem(
                          value: u.id,
                          child: Text(u.label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _unitId = v),
                validator: (v) =>
                    v == null ? 'Escolha a unidade ${_isCommittee ? 'em que o comitê se reúne' : 'de trabalho'}' : null,
              ),
            ),
            // Só o consultor tem gerente. Perguntar isso a um gerente criaria
            // uma hierarquia que o modelo não tem.
            if (_isConsultant)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonFormField<String>(
                  initialValue: _managerId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Gerente responsável',
                    prefixIcon: Icon(Icons.assignment_ind_outlined, size: 20),
                  ),
                  items: AppData.managers
                      .map((m) => DropdownMenuItem(
                            value: m.id,
                            child: Text(m.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _managerId = v),
                  validator: (v) => v == null ? 'Escolha o gerente deste consultor' : null,
                ),
              ),
            Text(_footerFor(widget.role), style: TextStyle(fontSize: 11, color: AppColors.textLight)),
            const SizedBox(height: 20),
            _SaveButton(onPressed: _save, isNew: _isNew),
            // Senha e exclusão de quem NÃO tem tela própria: o consultor tem as
            // dele no perfil, que existe porque ele tem carteira e histórico
            // para mostrar. Gerente, faturista e comitê não têm — e criar uma
            // tela só para pendurar dois botões seria pior do que tê-los aqui.
            if (!_isNew && !_isConsultant) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _resetPassword,
                icon: Icon(Icons.lock_reset, color: AppColors.pending),
                label: Text('Redefinir senha', style: TextStyle(color: AppColors.pending)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.pending),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              // O COMITÊ não se exclui: o cadastro é a ETAPA, e sem ele nenhuma
              // permuta é decidida. Não há rota para isso no servidor, e a tela
              // não oferece um botão que levaria a um 422.
              if (!_isCommittee) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _delete,
                  icon: Icon(Icons.delete_outline, color: AppColors.denied),
                  label: Text('Excluir ${_roleLabel.toLowerCase()}',
                      style: TextStyle(color: AppColors.denied)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.denied),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// O que falta cadastrar antes de este formulário poder ser concluído.
class _MissingPrerequisiteHint extends StatelessWidget {
  final List<String> missing;
  const _MissingPrerequisiteHint({required this.missing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.pendingBg,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.pending.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: AppColors.pending),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Há ${missing.join(' e ')}. O consultor precisa dos dois: a unidade onde '
              'trabalha e o gerente que dará o parecer das permutas dele.',
              style: TextStyle(fontSize: 12, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cadastro/edição de uma UNIDADE de retirada.
///
/// Curto porque a unidade é curta: um nome e uma cidade. Ela é o LOCAL onde o
/// produtor busca os insumos — não tem responsável e não decide quem analisa a
/// permuta. Se um dia este formulário ganhar um campo de gerente, é sinal de
/// que o modelo mudou, não de que faltava um campo.
class EditUnitScreen extends StatefulWidget {
  final UnitModel? unit;
  const EditUnitScreen({super.key, this.unit});

  @override
  State<EditUnitScreen> createState() => _EditUnitScreenState();
}

class _EditUnitScreenState extends State<EditUnitScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _city;

  bool get _isNew => widget.unit == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.unit?.name ?? '');
    _city = TextEditingController(text: widget.unit?.city ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final old = widget.unit;
    final draft = UnitModel(
      id: old?.id ?? '',
      name: _name.text.trim(),
      city: _city.text.trim(),
      createdAt: old?.createdAt ?? DateTime.now(),
    );
    try {
      final saved = await AppData.saveUnit(draft, isNew: _isNew);
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Nova Unidade' : 'Editar Unidade')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _EditField(
              controller: _name,
              label: 'Nome da unidade',
              icon: Icons.store_outlined,
              required: true,
            ),
            _EditField(
              controller: _city,
              label: 'Município/UF',
              icon: Icons.location_on_outlined,
              required: true,
            ),
            const SizedBox(height: 8),
            Text(
              'A unidade é o local de retirada dos insumos. O consultor escolhe uma ao '
              'registrar cada permuta — pode ser qualquer uma, combinada com o produtor. '
              'Ela não decide quem analisa a permuta: isso é o gerente do consultor.',
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

/// Cadastro de um PRODUTO — grão de pagamento ou insumo do catálogo.
///
/// Só criação. Depois de criado, o item se edita na tela dele (código, classe,
/// exigência por hectare) e o valor se corrige na versão vigente do Barter —
/// preço não é atributo do cadastro. Aqui é o passo que faltava para o catálogo
/// deixar de ser o que o seed criou e passar a ser administrável pelo app.
class NewProductScreen extends StatefulWidget {
  final ProductType type;
  const NewProductScreen({super.key, required this.type});

  @override
  State<NewProductScreen> createState() => _NewProductScreenState();
}

class _NewProductScreenState extends State<NewProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _unit = TextEditingController();
  final _price = TextEditingController();
  final _requiredPerHa = TextEditingController();
  String? _classId;
  bool _saving = false;

  bool get _isInput => widget.type == ProductType.input;
  String get _label => _isInput ? 'Insumo' : 'Grão';

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _unit.dispose();
    _price.dispose();
    _requiredPerHa.dispose();
    super.dispose();
  }

  double _number(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final saved = await AppData.createProduct(
        name: _name.text.trim(),
        sku: _sku.text.trim(),
        unit: _unit.text.trim(),
        type: widget.type,
        currentPrice: _number(_price),
        requiredPerHa: _isInput ? _number(_requiredPerHa) : 0,
        classId: _isInput ? _classId : null,
      );
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorSnack(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Novo $_label')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _EditField(
              controller: _name,
              label: 'Nome',
              icon: _isInput ? Icons.science_outlined : Icons.grass,
              required: true,
              validator: (v) => (v ?? '').trim().length < 2 ? 'Use ao menos 2 caracteres' : null,
            ),
            _EditField(
              controller: _sku,
              label: 'Código (opcional)',
              icon: Icons.qr_code_2,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                'É por ele que se procura o item na busca e que a planilha do '
                'fornecedor reconhece o cadastro. Em branco, o servidor gera '
                '(${_isInput ? 'INS' : 'GRA'}-0001).',
                style: TextStyle(fontSize: 11, color: AppColors.textLight),
              ),
            ),
            _EditField(
              controller: _unit,
              label: _isInput ? 'Unidade (litro, saco 50kg...)' : 'Unidade (saca 60kg...)',
              icon: Icons.straighten,
              required: true,
            ),
            _EditField(
              controller: _price,
              label: 'Valor de referência (R\$)',
              icon: Icons.attach_money,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              required: true,
              validator: (v) {
                final n = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                if (n == null || n <= 0) return 'Informe um valor maior que 0';
                return null;
              },
            ),
            if (_isInput) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonFormField<String?>(
                  initialValue: _classId,
                  decoration: const InputDecoration(
                    labelText: 'Classe (opcional)',
                    prefixIcon: Icon(Icons.category_outlined, size: 20),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Sem classe')),
                    ...AppData.classes.map(
                      (c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                    ),
                  ],
                  onChanged: (v) => setState(() => _classId = v),
                ),
              ),
              _EditField(
                controller: _requiredPerHa,
                label: 'Exigência por hectare (opcional)',
                icon: Icons.tune,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final text = (v ?? '').trim();
                  if (text.isEmpty) return null;
                  final n = double.tryParse(text.replaceAll(',', '.'));
                  if (n == null || n < 0) return 'Informe um número válido (ou deixe vazio)';
                  return null;
                },
              ),
              Text(
                'Com exigência por hectare, este insumo passa a ser obrigatório em toda '
                'permuta nova, no mínimo taxa × área do produtor.',
                style: TextStyle(fontSize: 11, color: AppColors.textLight),
              ),
            ] else
              Text(
                'O valor de referência é a taxa de câmbio da permuta: é ele que converte '
                'o custo dos insumos em sacas deste grão.',
                style: TextStyle(fontSize: 11, color: AppColors.textLight),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                      )
                    : const Icon(Icons.add, size: 18),
                label: Text('Cadastrar $_label'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editor da REGRA de mínimo de uma classe.
///
/// Só a regra: nome e lista de classes não se alteram por aqui, nem por rota
/// nenhuma. Classe é vocabulário do negócio (fungicidas, herbicidas, seguro
/// agrícola…) e vive na migration do servidor; o que muda de safra para safra é
/// o quanto do custo da permuta precisa passar por ela.
class EditClassRuleScreen extends StatefulWidget {
  final ProductClassModel productClass;
  const EditClassRuleScreen({super.key, required this.productClass});

  @override
  State<EditClassRuleScreen> createState() => _EditClassRuleScreenState();
}

class _EditClassRuleScreenState extends State<EditClassRuleScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _value;
  late ClassRuleType _ruleType;

  bool get _needsValue => _ruleType != ClassRuleType.none;

  @override
  void initState() {
    super.initState();
    final c = widget.productClass;
    _ruleType = c.ruleType;
    _value = TextEditingController(
      text: c.ruleValue > 0
          ? (c.ruleValue == c.ruleValue.roundToDouble()
                  ? c.ruleValue.toStringAsFixed(0)
                  : c.ruleValue.toStringAsFixed(2))
              .replaceAll('.', ',')
          : '',
    );
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  String get _valueLabel => _ruleType == ClassRuleType.valuePerHa
      ? 'Valor mínimo por hectare (R\$)'
      : 'Percentual mínimo do total (%)';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final value = _needsValue
        ? (double.tryParse(_value.text.trim().replaceAll(',', '.')) ?? 0)
        : 0.0;
    try {
      final saved = await AppData.updateClassRule(ProductClassModel(
        id: widget.productClass.id,
        slug: widget.productClass.slug,
        name: widget.productClass.name,
        ruleType: _ruleType,
        ruleValue: value,
      ));
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.productClass.name)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: AppColors.input),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'O nome da classe vem da lista de preços. O que se define '
                      'aqui é o mínimo que ela precisa representar na permuta.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Regra de mínimo',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 8),
            RadioGroup<ClassRuleType>(
              groupValue: _ruleType,
              onChanged: (v) => setState(() => _ruleType = v ?? ClassRuleType.none),
              child: const Column(
                children: [
                  _RuleOption(
                    value: ClassRuleType.none,
                    title: 'Sem exigência',
                    subtitle: 'A classe não trava o envio da permuta',
                  ),
                  _RuleOption(
                    value: ClassRuleType.percentOfTotal,
                    title: 'Percentual do total',
                    subtitle: 'A classe precisa representar X% do custo da permuta',
                  ),
                  _RuleOption(
                    value: ClassRuleType.valuePerHa,
                    title: 'Valor por hectare',
                    subtitle: 'A classe precisa somar R\$ X por hectare da propriedade',
                  ),
                ],
              ),
            ),
            if (_needsValue) ...[
              const SizedBox(height: 12),
              _EditField(
                controller: _value,
                label: _valueLabel,
                icon: Icons.percent,
                required: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
            const SizedBox(height: 24),
            _SaveButton(onPressed: _save, isNew: false),
          ],
        ),
      ),
    );
  }
}

class _RuleOption extends StatelessWidget {
  final ClassRuleType value;
  final String title;
  final String subtitle;
  const _RuleOption({required this.value, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return RadioListTile<ClassRuleType>(
      value: value,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: AppColors.textLight)),
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
      icon: Icon(Icons.delete_outline, color: AppColors.denied, size: 40),
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Excluir "$name"? Esta ação não pode ser desfeita.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textMedium)),
          if (barterCount > 0) ...[
            const SizedBox(height: 8),
            Text('As $barterCount permuta(s) já registradas serão mantidas no histórico.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textLight)),
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
