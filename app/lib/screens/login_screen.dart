import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../data/app_data.dart';
import '../data/demo_seed.dart';
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

/// Uma conta do dataset de demonstração no atalho de acesso rápido. Guarda só
/// a caixa postal — o domínio vem da marca ativa, como no resto do app.
class _DemoAccount {
  final String label;
  final String mailbox;
  final IconData icon;
  const _DemoAccount(this.label, this.mailbox, this.icon);
}

/// Um login por PAPEL, na mesma ordem de alcance do RBAC do servidor
/// (api/src/common/roles.ts). Só aparece em build de debug — ver abaixo.
const _demoAccounts = [
  _DemoAccount('Admin', 'admin', Icons.admin_panel_settings_outlined),
  _DemoAccount('Gerente', 'gerente', Icons.insights_outlined),
  _DemoAccount('Comitê', 'comite', Icons.groups_2_outlined),
  _DemoAccount('Faturista', 'faturista', Icons.receipt_long_outlined),
  _DemoAccount('Consultor', 'joao.silva', Icons.person_outlined),
];

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

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

  /// Preenche o formulário com uma conta do seed, sem entrar: quem confere qual
  /// papel está prestes a abrir é quem toca em "Entrar".
  void _fill(String mailbox) {
    _emailCtrl.text = '$mailbox@${brand.identity.emailDomain}';
    _passCtrl.text = demoSeedPassword;
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
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'E-mail',
                        prefixIcon: const Icon(Icons.email_outlined),
                        hintText: 'admin@${brand.identity.emailDomain}',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscure,
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
                    // Atalhos da demonstração só existem em build de debug: em
                    // release este bloco é removido na compilação (kDebugMode
                    // é constante). Sem isso, o app de produção sairia com as
                    // credenciais do seed impressas na tela de login.
                    if (kDebugMode) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),
                      Text(
                        'Acesso rápido (demonstração):',
                        style: TextStyle(fontSize: 11, color: AppColors.textLight),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final account in _demoAccounts)
                            OutlinedButton.icon(
                              onPressed: () => _fill(account.mailbox),
                              icon: Icon(account.icon, size: 15),
                              label: Text(account.label, style: const TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primaryMedium,
                                side: BorderSide(color: AppColors.primaryMedium),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Text(
                'v1.0.0 – ${brand.identity.legalName} © 2026',
                style: TextStyle(color: AppColors.onPrimarySubtle, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
