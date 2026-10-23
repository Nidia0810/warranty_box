import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:warranty_box/core/storage/app_database.dart';
import 'package:warranty_box/features/warranties/data/sqlite_warranty_repository.dart';
import 'package:warranty_box/features/warranties/data/warranty_row_mapper.dart';
import 'package:warranty_box/features/warranties/domain/entities/warranty.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late AppDatabase database;
  late SqliteWarrantyRepository repository;

  Warranty sample({String id = 'local-1', String title = "Máquina d'água"}) => Warranty(
    id: id, titulo: title, loja: "Loja d'Exemplo", preco: 123456,
    dataCompra: DateTime(2024, 2, 29), duracaoMeses: 12,
    fotoPath: 'invoices/local-1.jpg', categoria: 'eletrodomesticos',
    notas: 'Acentos: café, proteção.\nSegunda linha.',
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('warranty_box_test_');
    database = AppDatabase(factory: databaseFactoryFfi,
        path: () async => '${directory.path}/warranty_box.db');
    repository = SqliteWarrantyRepository(database);
  });

  tearDown(() async {
    await database.close();
    // Só a pasta temporária criada por este teste.
    await directory.delete(recursive: true);
  });

  test('Instalação nova começa vazia e preserva todos os campos ao reabrir', () async {
    expect(await repository.findAll(), isEmpty);
    final warranty = sample();
    await repository.save(warranty);
    await database.close();
    final restored = await repository.findById(warranty.id);
    expect(restored, isNotNull);
    expect(WarrantyRowMapper.toRow(restored!), WarrantyRowMapper.toRow(warranty));
    expect(restored.dataExpiracao, DateTime(2025, 2, 28));
  });

  test('Gravar o mesmo ID atualiza em vez de duplicar', () async {
    await repository.save(sample());
    await repository.save(sample(title: 'Título corrigido'));
    expect((await repository.findAll()).length, 1);
    expect((await repository.findById('local-1'))!.titulo, 'Título corrigido');
  });

  test('Valores com sintaxe SQL são tratados como dados', () async {
    const id = "x' OR 1=1 --";
    await repository.save(sample());
    await repository.save(sample(id: id));
    expect((await repository.findById(id))!.id, id);
    await repository.delete(id);
    expect(await repository.findById(id), isNull);
    expect((await repository.findAll()).single.id, 'local-1');
  });

  test('Eliminar persiste após fechar e reabrir a base', () async {
    await repository.save(sample());
    await repository.delete('local-1');
    await database.close();
    expect(await repository.findAll(), isEmpty);
    expect(await repository.findById('inexistente'), isNull);
  });

  test('Restrições SQLite rejeitam preços negativos sem alterar outros dados', () async {
    await repository.save(sample());
    final db = await database.database;
    final row = WarrantyRowMapper.toRow(sample(id: 'invalid'));
    row['price_cents'] = -1;
    await expectLater(db.insert('warranties', row), throwsA(isA<DatabaseException>()));
    expect((await repository.findAll()).length, 1);
  });

  test('O mapper deteta datas inválidas e expiração inconsistente', () {
    final row = WarrantyRowMapper.toRow(sample());
    row['purchased_on'] = '2024-02-31';
    expect(() => WarrantyRowMapper.fromRow(row), throwsFormatException);
    final mismatch = WarrantyRowMapper.toRow(sample());
    mismatch['expires_on'] = '2025-03-01';
    expect(() => WarrantyRowMapper.fromRow(mismatch), throwsFormatException);
  });
}
