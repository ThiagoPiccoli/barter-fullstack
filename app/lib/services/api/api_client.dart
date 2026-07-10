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
/// de erros do Adonis em [ApiException].
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

  bool get hasToken => _token != null;

  set token(String? value) => _token = value;

  void clearToken() => _token = null;

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body}) => _send('POST', path, body: body);

  Future<dynamic> put(String path, {Object? body}) => _send('PUT', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
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

  /// Extrai a mensagem nos formatos de erro do Adonis:
  /// `{message}` (exceções) ou `{errors: [{message}]}` (validação).
  String _errorMessage(int status, dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final errors = decoded['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        if (first is Map && first['message'] is String) return first['message'] as String;
      }
      if (decoded['message'] is String) return decoded['message'] as String;
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
