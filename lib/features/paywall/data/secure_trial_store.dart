import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/trial_record.dart';

class SecureTrialStore implements TrialStore {
  const SecureTrialStore({FlutterSecureStorage storage = const FlutterSecureStorage()})
      : _storage = storage;
  final FlutterSecureStorage _storage;
  static const _key = 'warrantybox.trial.v1';

  @override
  Future<TrialRecord?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    final data = jsonDecode(value) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException('Versão de trial inválida.');
    final start = data['startedAt'] == null ? null : DateTime.parse(data['startedAt'] as String).toUtc();
    final last = DateTime.parse(data['lastSeenAt'] as String).toUtc();
    if (start != null && last.isBefore(start)) {
      throw const FormatException('Estado de trial inconsistente.');
    }
    return TrialRecord(startedAt: start, lastSeenAt: last);
  }

  @override
  Future<void> write(TrialRecord record) async {
    final encoded = jsonEncode({
      'version': 1,
      'startedAt': record.startedAt?.toUtc().toIso8601String(),
      'lastSeenAt': record.lastSeenAt.toUtc().toIso8601String(),
    });
    await _storage.write(
        key: _key,
        value: encoded,
      );
    // Detetar configuração de Keychain que devolve sucesso sem persistir.
    if (await _storage.read(key: _key) != encoded) {
      throw StateError('Não foi possível confirmar a gravação do trial.');
    }
  }
}
