import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../data/app_data.dart';
import '../services/api/api_client.dart';
import '../widgets/common_widgets.dart';
import 'destination.dart';
import 'login_screen.dart';

/// Tela de abertura: decide entre retomar a sessão guardada no aparelho — indo
/// direto ao painel — ou pedir login. O token guardado é opaco, só o servidor
/// sabe se ainda vale, então a decisão custa uma ida à API; é essa espera que
/// esta tela cobre com a marca do app.
class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  /// Mensagem da falha de comunicação, quando houve uma. Enquanto é null, a
  /// tela está consultando o servidor.
  String? _error;

  @override
  void initState() {
    super.initState();
    _resume();
  }

  Future<void> _resume() async {
    setState(() => _error = null);
    final UserModel? user;
    try {
      user = await AppData.restoreSession();
    } on ApiException catch (e) {
      // Servidor fora do ar não invalida a sessão: o token continua guardado
      // e a tela oferece nova tentativa em vez de derrubar o usuário.
      if (mounted) setState(() => _error = e.message);
      return;
    }
    if (!mounted) return;
    _go(user == null ? const LoginScreen() : destinationFor(user));
  }

  void _go(Widget screen) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BarterLogo(size: 60),
                const SizedBox(height: 8),
                const Text(
                  'Permuta de Grãos por Insumos',
                  style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 14, letterSpacing: 1),
                ),
                const SizedBox(height: 44),
                if (_error == null)
                  const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                else
                  _RetryBlock(message: _error!, onRetry: _resume),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Falha ao retomar a sessão: explica o problema e dá as duas saídas — tentar
/// de novo (o servidor pode voltar) ou entrar com outra conta.
class _RetryBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _RetryBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.cloud_off_outlined, color: Color(0xAAFFFFFF), size: 40),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 46,
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Tentar novamente'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.white,
              foregroundColor: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          ),
          child: const Text(
            'Entrar com outra conta',
            style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 13),
          ),
        ),
      ],
    );
  }
}
