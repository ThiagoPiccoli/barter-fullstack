/// No navegador não há como separar os casos, e responder `false` é honesto.
///
/// O `fetch` do browser devolve o mesmo erro opaco ("Failed to fetch") para
/// rede caída, servidor fora do ar e bloqueio de CORS — é proposital, para que
/// uma página não consiga sondar a rede de quem a abriu. O `package:http`
/// repassa tudo isso como uma `ClientException` só.
///
/// Então a versão web cai sempre na mensagem genérica ("Falha de comunicação
/// com o servidor"), que cobre os três casos sem afirmar nenhum.
bool isConnectionFailure(Object error) => false;
