import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/api/api_client.dart';
import '../widgets/common_widgets.dart';
import 'bootstrap_screen.dart';

/// Definição da própria senha. Aparece de dois jeitos:
///
/// - OBRIGATÓRIA ([forced]): o consultor entrou com a senha provisória que o
///   admin cadastrou. Não dá para voltar nem pular — é o passo que garante que
///   a senha do provisionamento não vira a senha definitiva de ninguém. Ao
///   final, entra direto no painel.
/// - VOLUNTÁRIA: aberta pelo próprio usuário a partir do perfil; ao final,
///   apenas volta para onde estava.
class ChangePasswordScreen extends StatefulWidget {
  final UserModel user;
  final bool forced;

  const ChangePasswordScreen({super.key, required this.user, this.forced = false});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final UserModel updated;
    try {
      updated = await AppData.changePassword(_current.text, _next.text);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorSnack(context, e);
      }
      return;
    }
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Senha alterada com sucesso!'),
      backgroundColor: AppColors.approved,
      behavior: SnackBarBehavior.floating,
    ));

    if (widget.forced) {
      // Primeira entrada concluída. Volta pela tela de abertura em vez de ir
      // direto ao painel: enquanto a senha era provisória o servidor recusava
      // as rotas de negócio, então o cache está vazio e precisa ser carregado
      // agora — com a mesma espera e o mesmo "tentar novamente" de sempre, em
      // vez de um painel em branco se a rede falhar bem nesta hora.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const BootstrapScreen()),
        (route) => false,
      );
    } else {
      Navigator.of(context).pop(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Na versão obrigatória o botão de voltar some e o gesto de voltar é
    // bloqueado: não há para onde ir antes de definir a senha.
    return PopScope(
      canPop: !widget.forced,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.forced ? 'Defina sua senha' : 'Alterar senha'),
          automaticallyImplyLeading: !widget.forced,
          actions: [if (widget.forced) const LogoutButton()],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.forced)
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.pendingBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.pending.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_reset, color: AppColors.pending, size: 22),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Você entrou com a senha provisória cadastrada pelo administrador. '
                          'Defina uma senha só sua para continuar.',
                          style: TextStyle(fontSize: 13, color: AppColors.textDark, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              _PasswordField(
                controller: _current,
                label: widget.forced ? 'Senha provisória' : 'Senha atual',
                icon: Icons.lock_outline,
                obscure: _obscure,
                onToggle: () => setState(() => _obscure = !_obscure),
                validator: (v) => (v == null || v.isEmpty) ? 'Informe a senha atual' : null,
              ),
              _PasswordField(
                controller: _next,
                label: 'Nova senha',
                icon: Icons.lock_reset,
                obscure: _obscure,
                onToggle: () => setState(() => _obscure = !_obscure),
                validator: (v) {
                  if (v == null || v.length < 6) return 'Use ao menos 6 caracteres';
                  if (v == _current.text) return 'A nova senha precisa ser diferente da atual';
                  return null;
                },
              ),
              _PasswordField(
                controller: _confirm,
                label: 'Repita a nova senha',
                icon: Icons.check_circle_outline,
                obscure: _obscure,
                onToggle: () => setState(() => _obscure = !_obscure),
                validator: (v) => v != _next.text ? 'As senhas não conferem' : null,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Salvar senha'),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'As outras sessões abertas nesta conta serão encerradas.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textLight),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final VoidCallback onToggle;
  final String? Function(String?) validator;

  const _PasswordField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.obscure,
    required this.onToggle,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed: onToggle,
          ),
        ),
        validator: validator,
      ),
    );
  }
}
