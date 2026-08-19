import '../models/models.dart';
import '../services/api/api_client.dart';

/// As rotas de PESSOAS que o admin provisiona: consultor, gerente e faturista.
///
/// Um motor só, como no servidor — lá as quatro rotas de usuário compartilham o
/// `UserProvisioningService` pelo mesmo motivo: senha de primeira entrada,
/// e-mail único e reset que derruba sessões são a MESMA regra para todos, e três
/// cópias disso é a receita para corrigir uma falha em duas e esquecer a
/// terceira. Este arquivo nasceu quando o faturista ia virar a terceira cópia.
///
/// O que muda entre eles é só a rota — e, no consultor, um campo a mais no
/// payload (ver `_payload`).
///
/// O COMITÊ não passa por aqui: ele não é uma pessoa, é uma reunião, e o
/// cadastro dele é único. Ver [CommitteeRepository].
class StaffRepository {
  /// O caminho da rota deste papel: `/consultants`, `/managers`, `/billers`.
  final String path;

  const StaffRepository(this.path);

  Future<List<UserModel>> list() async {
    final data = await api.get(path) as List;
    return data.cast<Map<String, dynamic>>().map(UserModel.fromJson).toList();
  }

  /// A senha de primeira entrada é sorteada pelo SERVIDOR e volta na resposta —
  /// é a única vez que ela existe em texto puro. O app não inventa senha
  /// nenhuma: se inventasse, ela precisaria trafegar em algum lugar previsível,
  /// que é exatamente o que a aleatoriedade evita.
  Future<ProvisionedConsultant> create(UserModel user) async {
    final data = await api.post(path, body: _payload(user));
    return ProvisionedConsultant.fromJson(data as Map<String, dynamic>);
  }

  Future<UserModel> update(UserModel user) async {
    final data = await api.put('$path/${user.id}', body: _payload(user));
    return UserModel.fromJson(data as Map<String, dynamic>);
  }

  /// Devolve o acesso a quem perdeu a senha — ou cuja conta foi parar em mãos
  /// erradas. O servidor sorteia outra provisória e encerra as sessões abertas.
  Future<ProvisionedConsultant> resetPassword(String id) async {
    final data = await api.post('$path/$id/reset-password');
    return ProvisionedConsultant.fromJson(data as Map<String, dynamic>);
  }

  /// O servidor pode RECUSAR (422) — o gerente com time ou com fila de parecer é
  /// o caso —, e a mensagem dele diz o que falta. A tela só a mostra.
  Future<void> delete(String id) => api.delete('$path/$id');

  /// A unidade vai como id; o `branch` que sai na resposta é o NOME dela,
  /// escrito pelo servidor. Enquanto isto era texto livre, "Filial 02" e
  /// "FILIAL 02" eram duas filiais para qualquer agrupamento.
  ///
  /// O GERENTE só vai quando existe, e só o consultor tem: é a ele que as
  /// permutas serão enviadas. Nas outras rotas o servidor descartaria o campo de
  /// qualquer jeito (o DTO delas não o declara), então mandá-lo vazio seria
  /// pedir para ser ignorado.
  Map<String, dynamic> _payload(UserModel s) => {
        'fullName': s.name,
        'email': s.email,
        if (s.phone.isNotEmpty) 'phone': s.phone,
        'unitId': int.parse(s.unitId),
        if (s.managerId.isNotEmpty) 'managerId': int.parse(s.managerId),
      };
}
