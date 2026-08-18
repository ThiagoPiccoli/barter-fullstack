import '../models/models.dart';
import '../services/api/api_client.dart';

/// UNIDADES de retirada — os locais onde o produtor busca os insumos.
///
/// A LISTAGEM é de todo mundo: o consultor precisa dela para escolher onde o
/// produtor retira, e a retaguarda para ler o local nas permutas. O cadastro é
/// do admin, e o servidor recusa quem não tem `units.manage`.
///
/// Não é paginada de propósito: a lista tem teto natural (uma cooperativa tem
/// dezenas de unidades) e o app precisa dela inteira para montar o seletor da
/// permuta. Mesmo critério do catálogo de classes.
class UnitRepository {
  Future<List<UnitModel>> list() async => parse(await listRaw());

  Future<List<Map<String, dynamic>>> listRaw() async =>
      (await api.get('/units') as List).cast<Map<String, dynamic>>();

  List<UnitModel> parse(List<Map<String, dynamic>> rows) =>
      rows.map(UnitModel.fromJson).toList();

  Future<UnitModel> create(UnitModel unit) async {
    final data = await api.post('/units', body: _payload(unit));
    return UnitModel.fromJson(data as Map<String, dynamic>);
  }

  Future<UnitModel> update(UnitModel unit) async {
    final data = await api.put('/units/${unit.id}', body: _payload(unit));
    return UnitModel.fromJson(data as Map<String, dynamic>);
  }

  Future<void> delete(String id) => api.delete('/units/$id');

  /// Curto porque a unidade é curta: um nome e uma cidade. Não há responsável —
  /// quem analisa a permuta é o gerente do consultor que a registrou.
  Map<String, dynamic> _payload(UnitModel u) => {'name': u.name, 'city': u.city};
}
