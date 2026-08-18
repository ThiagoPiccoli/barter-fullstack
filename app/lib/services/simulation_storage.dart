import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/barter_simulation.dart';

/// As simulações de permuta gravadas NO APARELHO — a parte do offline-first que
/// já existe hoje.
///
/// Tudo vive num único documento JSON, sob uma chave só. É deliberado enquanto o
/// volume for este: um consultor guarda dezenas de simulações, não milhares, e
/// reler e reescrever a lista inteira a cada gravação é mais simples — e muito
/// mais fácil de trocar — do que um banco local. Quando o offline-first alcançar
/// as outras listas (carteira, catálogo, permutas já enviadas), o banco entra
/// AQUI DENTRO e quem chama não muda: o contrato é ler tudo e gravar tudo.
///
/// Grava no cofre do sistema porque ele já está montado no app — é onde mora o
/// token — e não custa mais do que um arquivo. A simulação não é segredo, mas é
/// negociação com nome de produtor e quantidades: criptografia em repouso não
/// atrapalha, e evita uma segunda dependência de armazenamento.
class SimulationStorage {
  SimulationStorage._();

  static const _key = 'barter.simulations';
  static const _storage = FlutterSecureStorage();

  /// Todas as simulações do aparelho, de todos os consultores que já o usaram.
  /// Quem separa por dono é quem chama (ver `AppData.mySimulations`).
  ///
  /// Nunca lança, pelo mesmo motivo de `TokenStorage`: um cofre indisponível
  /// (desktop sem entitlement, Linux sem libsecret, plugin ausente nos testes)
  /// não pode derrubar a tela de permutas. Sem cofre o app funciona como
  /// funcionava antes desta feature — e a simulação vale só enquanto ele
  /// estiver aberto.
  ///
  /// Uma linha ilegível é PULADA, e não fatal. O arquivo é a única cópia do
  /// trabalho do consultor: uma simulação corrompida não pode levar junto as
  /// outras nove que estavam boas.
  static Future<List<BarterSimulation>> load() async {
    String? raw;
    try {
      raw = await _storage.read(key: _key);
    } catch (_) {
      return [];
    }
    if (raw == null || raw.isEmpty) return [];

    final List<dynamic> rows;
    try {
      final decoded = jsonDecode(raw);
      rows = decoded is List ? decoded : const [];
    } on FormatException {
      return [];
    }

    final simulations = <BarterSimulation>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic> || row['id'] is! String) continue;
      try {
        simulations.add(BarterSimulation.fromJson(row));
      } catch (_) {
        // Linha que o parse tolerante ainda assim não abriu: as outras seguem.
      }
    }
    return simulations;
  }

  /// Reescreve a lista inteira. Devolve `false` quando o aparelho recusou a
  /// gravação.
  ///
  /// O retorno existe e PRECISA ser olhado. Este é o único lugar do app em que
  /// engolir a falha em silêncio seria pior do que o erro: o consultor tocaria
  /// "Salvar", veria a confirmação e perderia a permuta ao fechar o app — que é
  /// exatamente o que esta feature foi feita para impedir. Quem chama avisa a
  /// tela (ver `AppData.saveSimulation`).
  static Future<bool> saveAll(List<BarterSimulation> simulations) async {
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode([for (final item in simulations) item.toJson()]),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
