import '../models/models.dart';
import '../services/api/api_client.dart';

/// Gestão de vendedores (rotas exclusivas do admin). Vendedor novo nasce com
/// a senha padrão definida no servidor (123456) até existir troca de senha.
class SellerRepository {
  Future<List<UserModel>> list() async {
    final data = await api.get('/sellers') as List;
    return data.cast<Map<String, dynamic>>().map(UserModel.fromJson).toList();
  }

  Future<UserModel> create(UserModel seller) async {
    final data = await api.post('/sellers', body: _payload(seller));
    return UserModel.fromJson(data as Map<String, dynamic>);
  }

  Future<UserModel> update(UserModel seller) async {
    final data = await api.put('/sellers/${seller.id}', body: _payload(seller));
    return UserModel.fromJson(data as Map<String, dynamic>);
  }

  Future<void> delete(String id) => api.delete('/sellers/$id');

  Map<String, dynamic> _payload(UserModel s) => {
        'fullName': s.name,
        'email': s.email,
        if (s.phone.isNotEmpty) 'phone': s.phone,
        'branch': s.branch,
      };
}
