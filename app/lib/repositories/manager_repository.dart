import '../models/models.dart';
import '../services/api/api_client.dart';

/// GERENTES — as pessoas a quem as permutas dos consultores são enviadas.
///
/// Espelha `/managers`, que é rota exclusiva do admin. O formato é idêntico ao
/// de `/consultants` de propósito: no servidor as quatro rotas de usuário
/// compartilham o mesmo motor de provisionamento, e a senha de primeira entrada
/// segue a mesma promessa — sorteada pelo servidor e devolvida UMA vez.
///
/// O que muda em relação ao consultor é o payload: gerente não tem gerente.
class ManagerRepository {
  Future<List<UserModel>> list() async {
    final data = await api.get('/managers') as List;
    return data.cast<Map<String, dynamic>>().map(UserModel.fromJson).toList();
  }

  Future<ProvisionedConsultant> create(UserModel manager) async {
    final data = await api.post('/managers', body: _payload(manager));
    return ProvisionedConsultant.fromJson(data as Map<String, dynamic>);
  }

  Future<UserModel> update(UserModel manager) async {
    final data = await api.put('/managers/${manager.id}', body: _payload(manager));
    return UserModel.fromJson(data as Map<String, dynamic>);
  }

  Future<ProvisionedConsultant> resetPassword(String id) async {
    final data = await api.post('/managers/$id/reset-password');
    return ProvisionedConsultant.fromJson(data as Map<String, dynamic>);
  }

  /// O servidor RECUSA (422) enquanto o gerente tiver consultores no time ou
  /// permutas esperando o parecer dele — a mensagem diz qual dos dois falta.
  /// A tela só precisa mostrá-la.
  Future<void> delete(String id) => api.delete('/managers/$id');

  Map<String, dynamic> _payload(UserModel m) => {
        'fullName': m.name,
        'email': m.email,
        if (m.phone.isNotEmpty) 'phone': m.phone,
        'unitId': int.parse(m.unitId),
      };
}
