import '../models/models.dart';
import '../services/api/api_client.dart';

/// Permutas. O payload de criação leva apenas produtos e quantidades — quem
/// precifica, valida mínimos e calcula as sacas do grão é o servidor.
class BarterRepository {
  Future<List<BarterModel>> list() async {
    final data = await api.get('/barters') as List;
    return data.cast<Map<String, dynamic>>().map(BarterModel.fromJson).toList();
  }

  Future<BarterModel> create({
    required String producerId,
    required String grainId,
    required Map<String, double> inputQuantities,
  }) async {
    final data = await api.post('/barters', body: {
      'producerId': int.parse(producerId),
      'grainId': int.parse(grainId),
      'inputs': [
        for (final entry in inputQuantities.entries)
          if (entry.value > 0)
            {'productId': int.parse(entry.key), 'quantity': entry.value},
      ],
    });
    return BarterModel.fromJson(data as Map<String, dynamic>);
  }

  /// Revisão do admin (aprovar/negar). [code] é o id público (PRM-2026-001).
  Future<BarterModel> review(String code, BarterStatus status, String note) async {
    final data = await api.post('/barters/$code/review', body: {
      'status': status.name,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    return BarterModel.fromJson(data as Map<String, dynamic>);
  }
}
