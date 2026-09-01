import 'dart:io';

/// No nativo a falha de rede é reconhecível: o `package:http` embrulha a
/// `SocketException` do `dart:io` numa `ClientException` que **também**
/// implementa `SocketException` (ver `_ClientSocketException`, em
/// `http/src/io_client.dart`). O `is` abaixo enxerga o embrulho.
///
/// É o que sustenta o "Verifique sua rede" — recado que só faz sentido quando
/// se sabe que a requisição não chegou a sair.
bool isConnectionFailure(Object error) => error is SocketException;
