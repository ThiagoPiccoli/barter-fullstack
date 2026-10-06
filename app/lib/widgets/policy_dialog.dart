import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../models/models.dart';
import '../services/api/api_client.dart';
import '../theme/app_theme.dart';
import 'common_widgets.dart';

/// A APÓLICE — o ato da SEGURADORA: anexar o documento e informar o número.
///
/// O ARQUIVO é escolhido PRIMEIRO, pelo mesmo motivo da nota fiscal: ele é o
/// ato. Pedir o número antes deixaria a pessoa preencher o formulário para
/// descobrir no fim que o PDF está em outra pasta — e o número digitado some
/// junto.
///
/// Os dois vão juntos numa requisição só: a apólice sem número é um PDF que a
/// cédula não tem como citar, e o número sem a apólice é afirmação sem prova —
/// que é o que ele foi enquanto o consultor o digitava na cédula.
Future<void> informBarterPolicy(
  BuildContext context,
  BarterModel barter, {
  required ValueChanged<BarterModel> onInsured,
}) async {
  final arquivo = await FilePicker.pickFile(
    dialogTitle: 'Apólice do seguro',
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'xml', 'png', 'jpg', 'jpeg'],
  );
  if (arquivo == null) return;
  // Os BYTES são lidos aqui: no Android/iOS o caminho do arquivo escolhido é
  // temporário e pode sumir antes do envio.
  final bytes = await arquivo.readAsBytes();
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final numberCtrl = TextEditingController();
      final noteCtrl = TextEditingController();
      var submitting = false;
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final filled = numberCtrl.text.trim().isNotEmpty;
          return AlertDialog(
            title: const Text('Informar apólice'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BarterIdentity(barter: barter),
                  if (barter.insuranceCity.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Seguro cotado em ${barter.insuranceCity} • '
                      '${areaLabelOf(barter.plantedAreaHa)}',
                      style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    Icon(Icons.attach_file, size: 16, color: AppColors.textMedium),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        arquivo.name,
                        style: TextStyle(fontSize: 12, color: AppColors.textMedium),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: numberCtrl,
                    autofocus: true,
                    maxLength: 60,
                    onChanged: (_) => setLocal(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Nº da apólice',
                      helperText: 'É o número que a cédula (CPR) vai citar.',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Observação (opcional)',
                      hintText: 'Coberturas, vigência, seguradora contratada…',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: submitting || !filled
                    ? null
                    : () async {
                        setLocal(() => submitting = true);
                        try {
                          final updated = await AppData.insureBarter(
                            barter.id,
                            policyNumber: numberCtrl.text,
                            filename: arquivo.name,
                            bytes: bytes,
                            note: noteCtrl.text,
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          onInsured(updated);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: const Text(
                                'Apólice informada. A permuta seguiu para o faturista.'),
                            backgroundColor: AppColors.atInsurer,
                          ));
                        } on ApiException catch (e) {
                          if (!ctx.mounted) return;
                          setLocal(() => submitting = false);
                          showErrorSnack(ctx, e);
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.atInsurer),
                child: submitting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.onPrimary))
                    : const Text('Informar apólice'),
              ),
            ],
          );
        },
      );
    },
  );
}
