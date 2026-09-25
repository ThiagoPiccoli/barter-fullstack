import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../data/app_data.dart';
import '../services/api/api_client.dart';
import '../widgets/common_widgets.dart';
import '../branding/active_brand.dart';
import '../branding/brand_wordmark.dart';
import 'destination.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  /// O foco da SENHA, para o Enter do e-mail cair nela. Sem ele, o teclado do
  /// celular não teria para onde mandar o "próximo" e o dedo voltaria à tela.
  final _passFocus = FocusNode();

  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  /// Autentica na API e carrega todos os dados da sessão (catálogo, carteira,
  /// permutas). Erros chegam com mensagem legível via [ApiException].
  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      showErrorSnack(context, 'Informe e-mail e senha para entrar.');
      return;
    }

    setState(() => _loading = true);
    try {
      final user = await AppData.login(email, password);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => destinationFor(user)),
      );
    } on ApiException catch (e) {
      if (mounted) {
        showErrorSnack(
            context, e.statusCode == 400 ? 'E-mail ou senha inválidos.' : e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Não há recuperação por e-mail: quem provisiona e redefine senhas é o
  /// administrador. Melhor dizer isso do que deixar um botão que não faz nada.
  void _showPasswordHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.support_agent, color: AppColors.primary, size: 40),
        title: const Text('Esqueceu a senha?'),
        content: Text(
          'Peça ao administrador da cooperativa para cadastrar uma senha provisória '
          'para você. Ao entrar com ela, o app pede que você defina uma senha só sua.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textMedium),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 60),
              const BrandWordmark(size: 60, showTagline: false),
              const SizedBox(height: 10),
              Text(
                brand.identity.tagline,
                style: TextStyle(color: AppColors.onPrimarySubtle, fontSize: 14, letterSpacing: 0.8),
              ),
              const SizedBox(height: 50),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cardShadow,
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Bem-vindo',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textDark),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Acesse sua conta para continuar',
                      style: TextStyle(fontSize: 13, color: AppColors.textMedium),
                    ),
                    const SizedBox(height: 24),
                    // O ENTER ATRAVESSA O FORMULÁRIO: do e-mail para a senha, da
                    // senha para dentro. Digitar login e senha e ter de largar o
                    // teclado para caçar o botão é atrito em cima da ação que
                    // todo mundo faz todo dia, e várias vezes por dia.
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofocus: true,
                      onSubmitted: (_) => _passFocus.requestFocus(),
                      decoration: InputDecoration(
                        labelText: 'E-mail',
                        prefixIcon: const Icon(Icons.email_outlined),
                        hintText: 'admin@${brand.identity.emailDomain}',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passCtrl,
                      focusNode: _passFocus,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      // A trava do `_loading` é a MESMA do botão: o Enter é outro
                      // caminho para o mesmo ato, e não um atalho que escapa das
                      // regras dele. Sem ela, dois Enters em sequência mandariam
                      // dois logins.
                      onSubmitted: (_) {
                        if (!_loading) _login();
                      },
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _showPasswordHelp,
                        child: Text('Esqueci minha senha',
                            style: TextStyle(color: AppColors.primaryMedium, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        child: _loading
                            ? SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                            : const Text('Entrar'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Text(
                'v1.0.0 • ${brand.identity.legalName} © 2026',
                style: TextStyle(color: AppColors.onPrimarySubtle, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
