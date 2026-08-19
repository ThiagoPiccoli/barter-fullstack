import '../models/models.dart';
import '../services/api/api_client.dart';

/// O COMITÊ — a instância que decide as permutas, e um cadastro só.
///
/// Repositório próprio, e não um [StaffRepository] com outra rota, porque a
/// forma é outra: o comitê é uma REUNIÃO, não uma pessoa. Não há lista, não há
/// id na URL e não há exclusão — há UM cadastro, que existe ou não existe.
///
/// A rota espelha isso: `/committee`, no singular. Ver committee.controller.ts.
class CommitteeRepository {
  /// O cadastro do comitê, ou `null` enquanto ele não existe.
  ///
  /// Null é resposta normal, não erro: sistema recém-instalado ainda não tem
  /// comitê — e é a tela de cadastros do admin que existe para resolver isso.
  Future<UserModel?> find() async {
    final data = await api.get('/committee');
    if (data == null) return null;
    return UserModel.fromJson(data as Map<String, dynamic>);
  }

  /// Cria o cadastro. O servidor recusa (422) se já houver um: o comitê é um só.
  Future<ProvisionedConsultant> create(UserModel committee) async {
    final data = await api.post('/committee', body: _payload(committee));
    return ProvisionedConsultant.fromJson(data as Map<String, dynamic>);
  }

  /// Corrige nome, e-mail de acesso ou unidade. Sem id: não há qual escolher.
  Future<UserModel> update(UserModel committee) async {
    final data = await api.put('/committee', body: _payload(committee));
    return UserModel.fromJson(data as Map<String, dynamic>);
  }

  /// Nova senha para a conta da reunião, derrubando as sessões abertas.
  ///
  /// Numa conta compartilhada isto vale mais do que nos outros papéis: a senha
  /// circula entre quem participa, e é por aqui que ela se troca quando a
  /// composição muda.
  Future<ProvisionedConsultant> resetPassword() async {
    final data = await api.post('/committee/reset-password');
    return ProvisionedConsultant.fromJson(data as Map<String, dynamic>);
  }

  Map<String, dynamic> _payload(UserModel c) => {
        'fullName': c.name,
        'email': c.email,
        if (c.phone.isNotEmpty) 'phone': c.phone,
        'unitId': int.parse(c.unitId),
      };
}
