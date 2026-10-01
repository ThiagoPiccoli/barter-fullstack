import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Se a coluna lateral está RECOLHIDA — só os ícones, sem os nomes —, guardado
/// no aparelho.
///
/// É uma preferência do APARELHO, e não da conta: quem recolhe a coluna o faz
/// pelo tamanho da janela que tem, e o mesmo login num notebook e num monitor
/// grande quer coisas diferentes. Pelo mesmo motivo vale para os três papéis —
/// a coluna é a mesma moldura em todos os painéis.
///
/// Vive num [ValueNotifier] e não no estado de um widget porque cada painel
/// monta a sua própria casca: trocar de conta ou voltar do login criaria outra,
/// e a escolha precisa sobreviver a isso sem uma nova leitura do cofre.
///
/// Grava no cofre do sistema pelo mesmo motivo de `SimulationStorage`: é o
/// armazenamento que o app já tem montado, e um booleano não justifica uma
/// segunda dependência.
class NavRailPreference {
  NavRailPreference._();

  static const _key = 'barter.nav_rail_collapsed';
  static const _storage = FlutterSecureStorage();

  /// Começa ABERTA: é o que o app sempre mostrou, e quem nunca tocou no botão
  /// não deve ver a coluna mudar sozinha.
  static final ValueNotifier<bool> collapsed = ValueNotifier(false);

  static Future<void>? _loading;

  /// Lê a preferência do aparelho, uma vez só. Nunca lança — sem cofre, a coluna
  /// abre como sempre abriu e a escolha vale enquanto o app estiver aberto.
  static Future<void> load() => _loading ??= _load();

  static bool _touched = false;

  static Future<void> _load() async {
    String? raw;
    try {
      raw = await _storage.read(key: _key);
    } catch (_) {
      return;
    }
    // Quem tocou no botão enquanto o cofre respondia já decidiu: o valor antigo
    // do disco não pode desfazer o clique.
    if (_touched) return;
    collapsed.value = raw == 'true';
  }

  /// Muda a coluna na hora e grava em seguida. Uma gravação recusada não volta
  /// atrás na tela: perder a preferência ao fechar o app é menos grave do que
  /// o botão parecer não funcionar.
  static Future<void> setCollapsed(bool value) async {
    _touched = true;
    collapsed.value = value;
    try {
      await _storage.write(key: _key, value: '$value');
    } catch (_) {}
  }

  /// Volta ao estado de app recém-aberto, para um teste não herdar o clique
  /// do anterior.
  @visibleForTesting
  static void reset() {
    _loading = null;
    _touched = false;
    collapsed.value = false;
  }
}
