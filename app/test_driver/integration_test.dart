import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Driver do teste de integração: salva os screenshots tirados pelo teste em
/// build/verify_screenshots/ (fora do controle de versão).
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('build/verify_screenshots/$name.png')
        ..createSync(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
