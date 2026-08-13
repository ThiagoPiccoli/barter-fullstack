import 'package:flutter_test/flutter_test.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/admin_main_screen.dart';
import 'package:agrobarter_app/screens/back_office_main_screen.dart';
import 'package:agrobarter_app/screens/change_password_screen.dart';
import 'package:agrobarter_app/screens/consultant_main_screen.dart';
import 'package:agrobarter_app/screens/destination.dart';

/// O papel decide o que a pessoa vê no app inteiro. Duas coisas precisam valer
/// sempre: o valor que vem do servidor vira o papel certo, e cada papel abre a
/// SUA tela — um engano em qualquer um dos dois entrega um painel a quem não
/// deveria abri-lo.
void main() {
  UserModel user(String role, {bool mustChangePassword = false}) => UserModel.fromJson({
        'id': 1,
        'fullName': 'Fulano de Tal',
        'email': 'fulano@agrobarter.com.br',
        'role': role,
        'createdAt': '2026-01-10T00:00:00.000Z',
        'mustChangePassword': mustChangePassword,
      });

  group('UserRole', () {
    test('lê os cinco papéis do servidor', () {
      expect(UserRole.fromWire('admin'), UserRole.admin);
      expect(UserRole.fromWire('manager'), UserRole.manager);
      expect(UserRole.fromWire('committee'), UserRole.committee);
      expect(UserRole.fromWire('biller'), UserRole.biller);
      expect(UserRole.fromWire('consultant'), UserRole.consultant);
    });

    /// Servidor mais novo que o app instalado no aparelho: o papel desconhecido
    /// precisa cair no de MENOS alcance, nunca virar admin por descuido.
    test('papel desconhecido (ou ausente) cai em consultor', () {
      expect(UserRole.fromWire('diretor'), UserRole.consultant);
      expect(UserRole.fromWire(null), UserRole.consultant);
    });

    test('retaguarda é todo mundo menos o consultor', () {
      expect(UserRole.admin.isBackOffice, isTrue);
      expect(UserRole.manager.isBackOffice, isTrue);
      expect(UserRole.committee.isBackOffice, isTrue);
      expect(UserRole.biller.isBackOffice, isTrue);
      expect(UserRole.consultant.isBackOffice, isFalse);
    });
  });

  group('destinationFor', () {
    test('cada papel abre a própria tela', () {
      expect(destinationFor(user('admin')), isA<AdminMainScreen>());
      expect(destinationFor(user('manager')), isA<BackOfficeMainScreen>());
      expect(destinationFor(user('committee')), isA<BackOfficeMainScreen>());
      expect(destinationFor(user('biller')), isA<BackOfficeMainScreen>());
      expect(destinationFor(user('consultant')), isA<ConsultantMainScreen>());
    });

    /// A senha provisória vem ANTES do papel: enquanto ela não for trocada,
    /// nenhum painel abre — nem o do gerente, nem o do comitê, nem o do
    /// faturista, que são os papéis novos e entrariam por um caminho que não
    /// existia quando essa trava foi escrita.
    test('senha provisória segura qualquer papel na troca de senha', () {
      for (final role in ['admin', 'manager', 'committee', 'biller', 'consultant']) {
        expect(
          destinationFor(user(role, mustChangePassword: true)),
          isA<ChangePasswordScreen>(),
          reason: 'papel $role',
        );
      }
    });
  });
}
