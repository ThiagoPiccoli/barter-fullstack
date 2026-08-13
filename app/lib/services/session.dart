import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../screens/login_screen.dart';
import '../widgets/common_widgets.dart';
import 'api/api_client.dart';

/// Chaves globais do MaterialApp. Permitem navegar e avisar o usuário de fora
/// da árvore de widgets, que é o que a expiração de sessão exige: quem
/// descobre o 401 é a camada de dados, em qualquer tela do app.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Liga o [ApiClient] à navegação: quando o servidor rejeita o token, a sessão
/// local é descartada e o app volta ao login de onde estiver.
///
/// Sem isso o usuário fica preso — o app segue nas telas internas mostrando
/// "Sessão expirada" a cada toque, sem caminho de volta. Acontece de verdade
/// quando o admin exclui um consultor logado: a exclusão apaga os tokens dele
/// em cascata e o aparelho ainda está na tela de permutas.
void installSessionExpiryHandler() {
  api.onSessionExpired = () {
    // Navega primeiro para tirar as telas autenticadas do ar; só depois
    // esvazia o cache, que elas leem durante o build.
    appNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
    showErrorOn(
      appMessengerKey.currentState,
      'Sua sessão foi encerrada. Faça login novamente.',
    );
    AppData.discardSession();
  };
}
