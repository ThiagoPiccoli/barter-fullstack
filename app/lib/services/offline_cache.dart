import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// O PACOTE DO BARTER guardado no aparelho — o que permite montar uma simulação
/// sem sinal, inclusive abrindo o app do zero.
///
/// A simulação já vivia offline, mas MONTAR uma dependia do cache em memória,
/// hidratado da API no login. Fechar o app apagava esse cache, e reabri-lo sem
/// sinal parava na tela de abertura: o trabalho guardado estava a salvo e o
/// consultor não alcançava nem ele. Este cache fecha essa porta.
///
/// ## As cinco coisas, e por que elas viajam JUNTAS
///
/// Montar uma permuta precisa da versão vigente (com a tabela e a cotação da
/// saca), do catálogo (unidade, classe e exigência por hectare de cada insumo),
/// das classes (as regras de mínimo), da carteira (a ÁREA do produtor, que
/// define os mínimos) e das unidades de retirada.
///
/// Elas são gravadas num documento só, de uma vez, e é o ponto central deste
/// arquivo: uma versão cuja tabela referencia um catálogo de outro momento
/// produz um número de sacas que nunca existiu. Por isso quem escreve aqui é só
/// `AppData.syncOfflinePackage`, que busca as cinco na mesma viagem — os
/// refreshes avulsos mexem só na memória.
///
/// ## O que é guardado é o JSON CRU
///
/// Não os modelos. Os dois caminhos — servidor e aparelho — atravessam o mesmo
/// `fromJson`, e o app não ganha uma segunda gramática para o mesmo dado. Um
/// `toJson` escrito à mão poderia divergir do parser em silêncio, e o sintoma
/// seria a permuta montada offline sair com outro número.
///
/// ## Sobre o tamanho
///
/// Um catálogo de cooperativa dá algo como algumas centenas de KB de JSON, que
/// o cofre do sistema guarda sem reclamar. Se o dataset crescer a ponto de
/// incomodar, o que muda é só o de dentro desta classe: o contrato — grava
/// tudo, lê tudo — é o mesmo de um banco local.
class OfflineCache {
  OfflineCache._();

  static const _key = 'barter.offline_package';
  static const _storage = FlutterSecureStorage();

  /// O pacote lido do aparelho, ou null quando nunca houve sincronização (ou o
  /// cofre não está disponível). Nunca lança.
  static Future<OfflinePackage?> load() async {
    String? raw;
    try {
      raw = await _storage.read(key: _key);
    } catch (_) {
      return null;
    }
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return OfflinePackage.fromJson(decoded);
    } catch (_) {
      // Pacote ilegível é pacote ausente: o app volta a exigir uma sincronização
      // em vez de montar permuta sobre um catálogo pela metade.
      return null;
    }
  }

  /// Grava o pacote. Devolve `false` quando o aparelho recusou.
  ///
  /// Falhar aqui é menos grave do que falhar ao gravar uma simulação — o que se
  /// perde é a conveniência de abrir offline, não trabalho do consultor —, mas o
  /// retorno existe para quem quiser contar isso.
  static Future<bool> save(OfflinePackage package) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(package.toJson()));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Apaga o pacote. Usado ao SAIR de verdade: as simulações ficam (são
  /// trabalho), mas a carteira e a tabela do Barter não têm por que continuar
  /// no aparelho depois que a pessoa se desconectou.
  static Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nada a apagar, ou cofre indisponível.
    }
  }
}

/// O conteúdo do cache: as cinco listas cruas mais o instante da sincronização.
class OfflinePackage {
  /// Quando este pacote foi baixado. É o que a faixa de offline mostra — sem a
  /// data, o consultor não teria como saber com que tabela está simulando.
  final DateTime savedAt;

  final Map<String, dynamic>? user;

  /// A versão vigente, ou null. Null AQUI significa "o servidor disse que não há
  /// Barter aberto", e não "não perguntei": o pacote só existe depois de uma
  /// sincronização bem-sucedida.
  final Map<String, dynamic>? version;

  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> classes;
  final List<Map<String, dynamic>> producers;
  final List<Map<String, dynamic>> units;

  const OfflinePackage({
    required this.savedAt,
    required this.user,
    required this.version,
    required this.products,
    required this.classes,
    required this.producers,
    required this.units,
  });

  Map<String, dynamic> toJson() => {
        'savedAt': savedAt.toIso8601String(),
        'user': user,
        'version': version,
        'products': products,
        'classes': classes,
        'producers': producers,
        'units': units,
      };

  factory OfflinePackage.fromJson(Map<String, dynamic> json) => OfflinePackage(
        savedAt: DateTime.tryParse('${json['savedAt']}') ?? DateTime.now(),
        user: json['user'] as Map<String, dynamic>?,
        version: json['version'] as Map<String, dynamic>?,
        products: _rows(json['products']),
        classes: _rows(json['classes']),
        producers: _rows(json['producers']),
        units: _rows(json['units']),
      );

  static List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? [
          for (final row in value)
            if (row is Map<String, dynamic>) row,
        ]
      : const [];
}
