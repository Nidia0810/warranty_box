import '../../../core/storage/app_database.dart';
import '../domain/entities/warranty.dart';
import '../domain/repositories/warranty_repository.dart';
import 'warranty_row_mapper.dart';

class SqliteWarrantyRepository implements WarrantyRepository {
  SqliteWarrantyRepository(this._database);
  final AppDatabase _database;

  @override
  Future<List<Warranty>> findAll() async {
    final db = await _database.database;
    final rows = await db.query('warranties', orderBy: 'expires_on ASC, id ASC');
    return rows.map(WarrantyRowMapper.fromRow).toList();
  }

  @override
  Future<Warranty?> findById(String id) async {
    final db = await _database.database;
    final rows = await db.query('warranties', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : WarrantyRowMapper.fromRow(rows.single);
  }

  /// Insert/update atómicos, sem apagar o registo como faria INSERT OR REPLACE.
  @override
  Future<void> save(Warranty warranty) async {
    final db = await _database.database;
    final row = WarrantyRowMapper.toRow(warranty);
    await db.transaction((transaction) async {
      final changed = await transaction.update('warranties', row,
          where: 'id = ?', whereArgs: [warranty.id]);
      if (changed == 0) await transaction.insert('warranties', row);
    });
  }

  @override
  Future<void> delete(String id) async {
    final db = await _database.database;
    await db.delete('warranties', where: 'id = ?', whereArgs: [id]);
  }
}
