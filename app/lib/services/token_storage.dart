import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda o token de acesso entre execuções do app (Keychain no iOS/macOS,
/// armazenamento criptografado no Android). É o que permite o consultor abrir o
/// app e continuar logado — sem isso, cada abertura exigiria login de novo.
///
/// O token é opaco e revogável no servidor: guardá-lo aqui não decide nada
/// sozinho, quem diz se a sessão ainda vale é o `GET /me` no start.
class TokenStorage {
  TokenStorage._();

  static const _key = 'barter.access_token';
  static const _storage = FlutterSecureStorage();

  /// Token guardado, ou null se não há sessão anterior. Nunca lança: se o
  /// cofre do sistema não estiver disponível (desktop sem entitlement, Linux
  /// sem libsecret, plugin ausente nos testes), o app apenas cai no login.
  static Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String token) async {
    try {
      await _storage.write(key: _key, value: token);
    } catch (_) {
      // Sem cofre disponível a sessão vale só enquanto o app estiver aberto.
    }
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nada a apagar (ou cofre indisponível): a sessão local já foi limpa.
    }
  }
}
