import '../models/models.dart';
import '../services/api/api_client.dart';
import '../services/token_storage.dart';

/// Login/logout contra a API. O token fica no [ApiClient] para as chamadas da
/// sessão e no [TokenStorage] para sobreviver ao fechamento do app; o usuário
/// logado fica em AppData.currentUser.
class AuthRepository {
  /// O último `/me` cru, guardado para o cache offline gravar o usuário no
  /// mesmo formato em que ele voltaria do servidor — ver
  /// [CatalogRepository.listProductsRaw].
  Map<String, dynamic>? _lastMe;

  Map<String, dynamic>? get lastMeRaw => _lastMe;

  Future<UserModel> login(String email, String password) async {
    final data = await api.post('/auth/login', body: {
      'email': email,
      'password': password,
    }) as Map<String, dynamic>;
    final token = data['token'] as String;
    api.token = token;
    await TokenStorage.write(token);
    _lastMe = data['user'] as Map<String, dynamic>;
    return UserModel.fromJson(_lastMe!);
  }

  /// Retoma a sessão guardada no aparelho. Devolve o usuário quando o token
  /// ainda vale no servidor e null quando não há sessão a retomar. Falhas de
  /// rede sobem para quem chamou — aí o token continua guardado, porque o
  /// servidor fora do ar não significa sessão inválida.
  Future<UserModel?> restore() async {
    final token = await TokenStorage.read();
    if (token != null) {
      api.token = token;
    } else if (!api.hasToken) {
      return null;
    }
    // Sem cofre disponível (desktop sem entitlement, Linux sem libsecret) o
    // token só existe em memória; retomar a sessão da abertura ainda funciona
    // enquanto o app não fecha, então o que está em mãos vale.
    try {
      // Sem o gatilho de sessão expirada: aqui ainda não há tela para onde
      // voltar, quem decide o destino é a tela de abertura.
      final data = await api.get('/me', signalSessionLoss: false);
      _lastMe = data as Map<String, dynamic>;
      return UserModel.fromJson(_lastMe!);
    } on ApiException catch (e) {
      if (e.isAuthError) {
        await forget();
        return null;
      }
      rethrow;
    }
  }

  /// Revoga o token no servidor. Localmente a sessão é encerrada mesmo que a
  /// chamada falhe (ex.: sem rede) — sair do app nunca pode ficar bloqueado.
  Future<void> logout() async {
    try {
      // Um 401 aqui é o token já morto: é exatamente o que queremos, e não
      // deve disparar o fluxo de "sessão expirada" por cima da saída.
      await api.post('/auth/logout', signalSessionLoss: false);
    } on ApiException {
      // Sessão local encerra de qualquer forma.
    } finally {
      await forget();
    }
  }

  /// Troca a própria senha. O servidor exige a atual, derruba as outras
  /// sessões e mantém esta — então o usuário segue usando o app sem relogar.
  Future<UserModel> changePassword(String current, String next) async {
    final data = await api.post('/auth/password', body: {
      'currentPassword': current,
      'newPassword': next,
    });
    return UserModel.fromJson(data as Map<String, dynamic>);
  }

  /// Esquece a sessão local sem falar com o servidor — para quando o próprio
  /// servidor já rejeitou o token.
  Future<void> forget() async {
    api.clearToken();
    await TokenStorage.clear();
  }
}
