import '../models/models.dart';
import '../services/api/api_client.dart';

/// OS AVISOS de quem está logado — o que aconteceu numa permuta que a pessoa
/// acompanha e não pede ação dela. Ver `Notice` na API.
///
/// Só se LÊ e se DISPENSA: quem cria o aviso é o servidor, no mesmo ato que o
/// motiva (o comitê devolvendo a permuta ao consultor, o consultor a devolvendo
/// ao comitê).
class NoticeRepository {
  /// Os ainda não vistos, do mais novo para o mais antigo.
  Future<List<NoticeModel>> unread() async {
    final data = await api.get('/notices');
    return ((data as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(NoticeModel.fromJson)
        .toList();
  }

  /// Dispensa o aviso — ele some do painel.
  Future<void> markRead(int id) async {
    await api.post('/notices/$id/read');
  }
}
