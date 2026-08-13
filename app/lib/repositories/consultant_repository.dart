import '../models/models.dart';
import '../services/api/api_client.dart';

/// Gestão de consultores (rotas exclusivas do admin).
///
/// A senha de primeira entrada é sorteada pelo SERVIDOR, uma por consultor, e
/// volta na resposta da criação — é a única vez que ela existe em texto puro.
/// O app não inventa senha nenhuma: se inventasse, ela precisaria trafegar em
/// algum lugar previsível, que é exatamente o que a aleatoriedade evita.
class ConsultantRepository {
  Future<List<UserModel>> list() async {
    final data = await api.get('/consultants') as List;
    return data.cast<Map<String, dynamic>>().map(UserModel.fromJson).toList();
  }

  Future<ProvisionedConsultant> create(UserModel consultant) async {
    final data = await api.post('/consultants', body: _payload(consultant));
    return ProvisionedConsultant.fromJson(data as Map<String, dynamic>);
  }

  Future<UserModel> update(UserModel consultant) async {
    final data = await api.put('/consultants/${consultant.id}', body: _payload(consultant));
    return UserModel.fromJson(data as Map<String, dynamic>);
  }

  /// Devolve o acesso a um consultor que perdeu a senha — ou cuja conta foi
  /// parar em mãos erradas. O servidor sorteia outra senha provisória e
  /// encerra todas as sessões abertas da conta.
  Future<ProvisionedConsultant> resetPassword(String id) async {
    final data = await api.post('/consultants/$id/reset-password');
    return ProvisionedConsultant.fromJson(data as Map<String, dynamic>);
  }

  Future<void> delete(String id) => api.delete('/consultants/$id');

  Map<String, dynamic> _payload(UserModel s) => {
        'fullName': s.name,
        'email': s.email,
        if (s.phone.isNotEmpty) 'phone': s.phone,
        'branch': s.branch,
      };
}
