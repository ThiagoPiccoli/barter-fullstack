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

/// Uma página de uma coleção paginada: os itens devolvidos e o total real que
/// existe por trás deles. É o `meta` que a API manda ao lado de `data`.
class ApiPage {
  final List<dynamic> items;
  final int total;

  const ApiPage(this.items, this.total);
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
  /// sessão morreu do lado de lá — o admin excluiu o consultor, ou a sessão foi
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

  /// Busca uma coleção paginada INTEIRA, página por página.
  ///
  /// A API limita quanto uma resposta pode carregar de uma vez (o servidor não
  /// pode ser obrigado a montar a base inteira num JSON só). O app, por outro
  /// lado, foi feito em cima de um cache completo em memória — o painel do
  /// admin soma sacas, valores e rankings sobre TODAS as permutas —, então
  /// aqui as páginas são remontadas em uma lista só.
  ///
  /// É por isso que a paginação existe no servidor mas não aparece nas telas:
  /// ela protege a API hoje e deixa pronto o dia em que as listas passarem a
  /// carregar sob demanda.
  Future<List<Map<String, dynamic>>> getAll(
    String path, {
    Map<String, String>? query,
    int pageSize = 200,
  }) async {
    // Trava de segurança: se o servidor devolvesse um `total` que a paginação
    // nunca alcança, o laço não pode girar para sempre.
    const maxPages = 200;
    final all = <Map<String, dynamic>>[];

    for (var page = 0; page < maxPages; page++) {
      final result = await _page(path, {
        ...?query,
        'limit': '$pageSize',
        'offset': '${all.length}',
      });
      all.addAll(result.items.cast<Map<String, dynamic>>());
      if (result.items.isEmpty || all.length >= result.total) break;
    }
    return all;
  }

  /// Uma página com o `meta` preservado (o `get` comum descarta o envelope).
  Future<ApiPage> _page(String path, Map<String, String> query) async {
    final body = await _send('GET', path, query: query, unwrap: false);
    if (body is! Map<String, dynamic>) return const ApiPage([], 0);
    final items = (body['data'] as List?) ?? const [];
    final meta = body['meta'];
    final total = meta is Map<String, dynamic> ? (meta['total'] as num?)?.toInt() : null;
    // Rota sem paginação (ou resposta antiga): o que veio é tudo o que existe.
    return ApiPage(items, total ?? items.length);
  }

  Future<dynamic> post(String path, {Object? body, bool signalSessionLoss = true}) =>
      _send('POST', path, body: body, signalSessionLoss: signalSessionLoss);

  Future<dynamic> put(String path, {Object? body}) => _send('PUT', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Envia um ARQUIVO com campos de formulário (multipart) — hoje, a planilha
  /// que lança uma versão do Barter.
  ///
  /// Não passa pelo `_send` porque o corpo é outro (multipart, não JSON) e o
  /// arquivo pode ser grande: o timeout aqui é maior, já que quem espera é o
  /// admin olhando a barra de progresso, não uma tela que precisa responder ao
  /// toque. O resto do contrato é o mesmo — token, envelope e mensagem de erro
  /// em pt-BR passam pelo mesmo tratamento.
  Future<dynamic> upload(
    String path, {
    required String filename,
    required List<int> bytes,
    Map<String, String> fields = const {},
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1$path');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Accept'] = 'application/json'
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';

    http.Response response;
    try {
      final streamed = await request.send().timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException(0, 'O envio do arquivo demorou demais. Tente novamente.');
    } on SocketException {
      throw const ApiException(0, 'Sem conexão com o servidor. Verifique sua rede.');
    } on http.ClientException {
      throw const ApiException(0, 'Falha ao enviar o arquivo.');
    }

    final decoded = response.body.isEmpty ? null : _tryDecode(response.body);
    if (response.statusCode >= 400) {
      if (response.statusCode == 401 && _token != null) {
        _token = null;
        onSessionExpired?.call();
      }
      throw ApiException(response.statusCode, _errorMessage(response.statusCode, decoded));
    }
    if (decoded is Map<String, dynamic> && decoded.containsKey('data')) return decoded['data'];
    return decoded;
  }

  /// [unwrap] falso devolve o envelope cru (`{data, meta}`) — quem pagina
  /// precisa do `meta`, que o desembrulho normal joga fora.
  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool signalSessionLoss = true,
    bool unwrap = true,
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

    // Envelope padrão da API: { data: ... } — e { data, meta } nas listas
    // paginadas, que quem pediu o envelope cru quer inteiro.
    if (unwrap && decoded is Map<String, dynamic> && decoded.containsKey('data')) {
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
