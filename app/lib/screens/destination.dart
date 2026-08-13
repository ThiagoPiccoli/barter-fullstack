import 'package:flutter/material.dart';
import '../models/models.dart';
import 'admin_main_screen.dart';
import 'back_office_main_screen.dart';
import 'change_password_screen.dart';
import 'consultant_main_screen.dart';

/// Para onde um usuário autenticado vai. Regra única, usada pelo login e pela
/// retomada de sessão na abertura — se ficasse duplicada, um dos dois caminhos
/// acabaria deixando passar quem ainda está com a senha provisória.
///
/// O `switch` sem `default` é de propósito: acrescentar um papel em [UserRole]
/// passa a ser um erro de compilação aqui, e não uma tela que abre no painel
/// errado por herdar o "senão" de alguém.
Widget destinationFor(UserModel user) {
  if (user.mustChangePassword) {
    return ChangePasswordScreen(user: user, forced: true);
  }
  switch (user.role) {
    case UserRole.admin:
      return AdminMainScreen(admin: user);
    case UserRole.manager:
    case UserRole.committee:
    case UserRole.biller:
      return BackOfficeMainScreen(user: user);
    case UserRole.consultant:
      return ConsultantMainScreen(consultant: user);
  }
}
