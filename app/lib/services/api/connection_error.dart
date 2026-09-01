/// Distingue "a rede não chegou no servidor" de "o servidor respondeu errado",
/// sem arrastar o `dart:io` para dentro do [ApiClient].
///
/// O motivo de existir é a versão **web**: `dart:io` não compila para o
/// navegador, e bastava aquele `import` no `api_client.dart` para o
/// `flutter build web` falhar inteiro. Como a distinção só é possível no
/// nativo, ela fica atrás de um import condicional — cada plataforma recebe a
/// implementação que consegue responder.
///
/// Ver [connection_error_io.dart] (nativo) e [connection_error_web.dart].
library;

export 'connection_error_web.dart' if (dart.library.io) 'connection_error_io.dart';
