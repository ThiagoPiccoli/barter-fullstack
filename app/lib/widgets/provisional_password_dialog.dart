import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// Mostra a senha de primeira entrada de um consultor.
///
/// Esta tela é a ÚNICA chance de ler esse valor: o servidor sorteia a senha,
/// devolve uma vez e guarda só o hash. Por isso o diálogo não fecha ao tocar
/// fora — fechar sem querer significaria ter de redefinir a senha de novo — e
/// oferece o botão de copiar, porque o caminho normal é o admin repassar isso
/// ao consultor por telefone ou mensagem.
///
/// A senha é aleatória de propósito. Enquanto foi um valor fixo igual para
/// todos ('123456'), quem soubesse o e-mail de um consultor novo entrava antes
/// dele e ficava com a conta.
Future<void> showProvisionalPassword(
  BuildContext context,
  ProvisionedConsultant provisioned, {
  required bool isReset,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProvisionalPasswordDialog(provisioned: provisioned, isReset: isReset),
  );
}

class _ProvisionalPasswordDialog extends StatelessWidget {
  final ProvisionedConsultant provisioned;
  final bool isReset;

  const _ProvisionalPasswordDialog({required this.provisioned, required this.isReset});

  @override
  Widget build(BuildContext context) {
    final name = provisioned.consultant.name.split(' ').first;

    return AlertDialog(
      icon: Icon(Icons.key_outlined, color: AppColors.primary, size: 40),
      title: Text(isReset ? 'Senha redefinida' : 'Consultor cadastrado'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isReset
                ? 'Passe esta senha para $name. As sessões abertas na conta dele foram encerradas.'
                : 'Passe esta senha para $name entrar pela primeira vez.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textMedium),
          ),
          const SizedBox(height: 16),
          _PasswordBox(password: provisioned.provisionalPassword),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.pendingBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.pending.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.pending),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Anote agora: esta senha não pode ser consultada depois. Se ela se '
                    'perder, basta redefinir e uma nova será gerada.\n\n'
                    'Ao entrar, o consultor é obrigado a criar uma senha só dele.',
                    style: TextStyle(fontSize: 12, color: AppColors.textDark, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Anotei'),
        ),
      ],
    );
  }
}

/// A senha em destaque, em fonte monoespaçada (para não confundir caracteres
/// parecidos ao ditar) e com um toque para copiar.
class _PasswordBox extends StatefulWidget {
  final String password;
  const _PasswordBox({required this.password});

  @override
  State<_PasswordBox> createState() => _PasswordBoxState();
}

class _PasswordBoxState extends State<_PasswordBox> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.password));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _copy,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.primarySurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            SelectableText(
              widget.password,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                letterSpacing: 2,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_copied ? Icons.check : Icons.copy, size: 14, color: AppColors.primaryMedium),
                const SizedBox(width: 4),
                Text(
                  _copied ? 'Copiada' : 'Toque para copiar',
                  style: TextStyle(fontSize: 12, color: AppColors.primaryMedium),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
