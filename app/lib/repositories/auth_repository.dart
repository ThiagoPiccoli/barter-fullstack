import '../models/models.dart';
import '../services/api/api_client.dart';

/// Login/logout contra a API. O token fica no [ApiClient]; o usuário logado
/// fica em AppData.currentUser.
class AuthRepository {
  Future<UserModel> login(String email, String password) async {
    final data = await api.post('/auth/login', body: {
      'email': email,
      'password': password,
    }) as Map<String, dynamic>;
    api.token = data['token'] as String;
    return UserModel.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// Revoga o token no servidor; localmente a sessão é encerrada mesmo que a
  /// chamada falhe (ex.: sem rede) — sair do app nunca pode ficar bloqueado.
  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } on ApiException {
      // Sessão local encerra de qualquer forma.
    } finally {
      api.clearToken();
    }
  }
}
