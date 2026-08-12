import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Erro de API legível para o usuário. [message] vem do backend quando
/// disponível (regras de negócio chegam em pt-BR prontas para exibir).
class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  bool get isAuthError => statusCode == 401;

  @override
  String toString() => message;
}

/// Cliente HTTP do app. Toda chamada à API passa por aqui: base URL, token
/// de acesso (Bearer), decodificação do envelope `{data: ...}` e conversão
/// de erros da API em [ApiException].
///
/// A base URL é definida em tempo de build:
///   flutter run --dart-define=API_URL=http://192.168.0.10:3333
/// Sem definição, usa localhost (simulador iOS/desktop). No emulador Android,
/// use http://10.0.2.2:3333.
class ApiClient {
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:3333',
  );

  static const Duration _timeout = Duration(seconds: 15);

  String? _token;

  /// Avisa que o servidor rejeitou o token (401) numa chamada autenticada: a
  /// sessão morreu do lado de lá — o admin excluiu o vendedor, ou a sessão foi
  /// encerrada em outro aparelho — e o app precisa voltar ao login em vez de
  /// repetir "Sessão expirada" a cada toque. Registrado uma vez no start,
  /// em services/session.dart.
  void Function()? onSessionExpired;

  bool get hasToken => _token != null;

  set token(String? value) => _token = value;

  void clearToken() => _token = null;

  Future<dynamic> get(
    String path, {
    Map<String, String>? query,
    bool signalSessionLoss = true,
  }) =>
      _send('GET', path, query: query, signalSessionLoss: signalSessionLoss);

  Future<dynamic> post(String path, {Object? body, bool signalSessionLoss = true}) =>
      _send('POST', path, body: body, signalSessionLoss: signalSessionLoss);

  Future<dynamic> put(String path, {Object? body}) => _send('PUT', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool signalSessionLoss = true,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1$path').replace(queryParameters: query);
    final request = http.Request(method, uri);
    request.headers['Accept'] = 'application/json';
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    http.Response response;
    try {
      final streamed = await request.send().timeout(_timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException(0, 'O servidor demorou para responder. Tente novamente.');
    } on SocketException {
      throw const ApiException(0, 'Sem conexão com o servidor. Verifique sua rede.');
    } on http.ClientException {
      throw const ApiException(0, 'Falha de comunicação com o servidor.');
    }

    final decoded = response.body.isEmpty ? null : _tryDecode(response.body);
    if (response.statusCode >= 400) {
      // Descarta o token ANTES de avisar: chamadas simultâneas que também
      // tomarem 401 (o refresh dispara várias de uma vez) já encontram a
      // sessão sem token e não repetem o fluxo de volta ao login.
      if (response.statusCode == 401 && _token != null && signalSessionLoss) {
        _token = null;
        onSessionExpired?.call();
      }
      throw ApiException(response.statusCode, _errorMessage(response.statusCode, decoded));
    }

    // Envelope padrão da API: { data: ... }
    if (decoded is Map<String, dynamic> && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  dynamic _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// Extrai a mensagem dos formatos de erro do NestJS: `message` como string
  /// (exceções e o ValidationPipe da API, que devolve uma frase pronta em
  /// pt-BR) ou como lista (validação padrão do Nest — usamos a primeira).
  String _errorMessage(int status, dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final message = decoded['message'];
      if (message is String && message.isNotEmpty) return message;
      if (message is List && message.isNotEmpty) return message.first.toString();
    }
    switch (status) {
      case 401:
        return 'Sessão expirada. Faça login novamente.';
      case 403:
        return 'Você não tem permissão para esta ação.';
      case 404:
        return 'Registro não encontrado.';
      default:
        return 'Erro inesperado no servidor ($status).';
    }
  }
}

/// Instância única usada por todos os repositórios.
final ApiClient api = ApiClient();
