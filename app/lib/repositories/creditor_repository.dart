import '../models/models.dart';
import '../services/api/api_client.dart';

/// A CREDORA — cadastro ÚNICO, na rota no singular.
///
/// Sem `:id` e sem exclusão, pelo mesmo desenho do comitê: uma instalação serve
/// uma empresa. Duas credoras cadastradas fariam a cédula ter de escolher, e
/// nada no documento diz qual.
///
/// A leitura NUNCA dá 404: instalação nova devolve o cadastro vazio com as
/// pendências listadas, porque a ausência é o estado inicial e não um erro.
class CreditorRepository {
  Future<CprCreditor> get() async {
    final data = await api.get('/creditor');
    return CprCreditor.fromJson(data as Map<String, dynamic>);
  }

  /// Grava o cadastro inteiro. Campo vazio APAGA — é formulário curto, lido de
  /// cima a baixo, e não rascunho: sem isso não haveria como remover um foro
  /// eleito que deixou de valer.
  Future<CprCreditor> save(CprCreditor creditor) async {
    final data = await api.put('/creditor', body: creditor.toJson());
    return CprCreditor.fromJson(data as Map<String, dynamic>);
  }
}
