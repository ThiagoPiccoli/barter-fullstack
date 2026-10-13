import 'package:flutter/material.dart';
import 'branding/active_brand.dart';
import 'theme/app_theme.dart';
import 'services/nav_rail_preference.dart';
import 'services/session.dart';
import 'screens/bootstrap_screen.dart';

void main() {
  // Liga o cliente HTTP à navegação antes de qualquer requisição: um token
  // rejeitado precisa achar o caminho de volta ao login desde a abertura.
  installSessionExpiryHandler();
  runApp(const BarterApp());
  // Depois do runApp, que é quem liga os canais nativos. A leitura corre junto
  // com a retomada da sessão na abertura, e a coluna lateral já nasce do jeito
  // que foi deixada, em vez de abrir e recolher na frente de quem entra.
  NavRailPreference.load();
}

class BarterApp extends StatelessWidget {
  const BarterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: brand.identity.appTitle,
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      // Chaves globais: a expiração de sessão é detectada na camada de dados,
      // que navega e avisa sem ter um BuildContext em mãos.
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appMessengerKey,
      home: const BootstrapScreen(),
    );
  }
}
