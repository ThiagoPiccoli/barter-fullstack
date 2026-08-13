import 'package:flutter/material.dart';
import '../models/models.dart';
import 'admin_main_screen.dart';
import 'change_password_screen.dart';
import 'consultant_main_screen.dart';

/// Para onde um usuário autenticado vai. Regra única, usada pelo login e pela
/// retomada de sessão na abertura — se ficasse duplicada, um dos dois caminhos
/// acabaria deixando passar quem ainda está com a senha provisória.
Widget destinationFor(UserModel user) {
  if (user.mustChangePassword) {
    return ChangePasswordScreen(user: user, forced: true);
  }
  return user.role == UserRole.admin
      ? AdminMainScreen(admin: user)
      : ConsultantMainScreen(consultant: user);
}
