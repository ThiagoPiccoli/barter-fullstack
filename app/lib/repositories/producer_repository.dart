import '../models/models.dart';
import '../services/api/api_client.dart';

/// CRUD de produtores. A API já devolve a lista escopada: consultor recebe só
/// a própria carteira; admin recebe todas.
class ProducerRepository {
  /// Carteira completa (paginada no servidor — ver ApiClient.getAll).
  Future<List<ProducerModel>> list() async => parse(await listRaw());

  /// A mesma carteira, ainda como veio da API — ver
  /// [CatalogRepository.listProductsRaw] para o porquê do JSON cru.
  Future<List<Map<String, dynamic>>> listRaw() => api.getAll('/producers');

  List<ProducerModel> parse(List<Map<String, dynamic>> rows) =>
      rows.map(ProducerModel.fromJson).toList();

  Future<ProducerModel> create(ProducerModel producer) async {
    final data = await api.post('/producers', body: _payload(producer));
    return ProducerModel.fromJson(data as Map<String, dynamic>);
  }

  Future<ProducerModel> update(ProducerModel producer) async {
    final data = await api.put('/producers/${producer.id}', body: _payload(producer));
    return ProducerModel.fromJson(data as Map<String, dynamic>);
  }

  Future<void> delete(String id) => api.delete('/producers/$id');

  Map<String, dynamic> _payload(ProducerModel p) => {
        'name': p.name,
        // A carteira inteira, sempre: o servidor SUBSTITUI a lista que estava
        // lá pela que chega aqui, então mandar só o que mudou apagaria o resto.
        'consultantIds': p.consultantIds.map(int.parse).toList(),
        'document': p.document,
        if (p.phone.isNotEmpty) 'phone': p.phone,
        'farmName': p.farmName,
        'city': p.city,
        'areaHa': p.areaHa,
      };
}
