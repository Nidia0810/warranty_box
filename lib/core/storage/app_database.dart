import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Uma instância por aplicação. A abertura concorrente partilha o mesmo Future.
class AppDatabase {
  AppDatabase({DatabaseFactory? factory, Future<String> Function()? path})
      : _factory = factory ?? databaseFactory,
        _path = path ?? _defaultPath;

  final DatabaseFactory _factory;
  final Future<String> Function() _path;
  Future<Database>? _opening;

  static Future<String> _defaultPath() async =>
      p.join(await getDatabasesPath(), 'warranty_box.db');

  Future<Database> get database async {
    final opening = _opening ??= _open();
    try {
      return await opening;
    } catch (_) {
      if (identical(_opening, opening)) _opening = null;
      rethrow;
    }
  }

  Future<Database> _open() async => _factory.openDatabase(
        await _path(),
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute(createWarrantiesTable);
            await db.execute('CREATE INDEX idx_warranties_expiry ON warranties(expires_on)');
            await db.execute('CREATE INDEX idx_warranties_category ON warranties(category)');
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            // Acrescentar migrações incrementais quando a versão passar a 2.
            // Nunca apagar a base para recuperar de um erro de migração.
            throw UnsupportedError('Migração $oldVersion → $newVersion não implementada.');
          },
        ),
      );

  Future<void> close() async {
    final opening = _opening;
    if (opening == null) return;
    final db = await opening;
    await db.close();
    _opening = null;
  }
}

const createWarrantiesTable = '''
CREATE TABLE warranties (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(trim(id)) > 0),
  title TEXT NOT NULL CHECK(length(trim(title)) > 0),
  store TEXT NOT NULL CHECK(length(trim(store)) > 0),
  price_cents INTEGER NOT NULL CHECK(price_cents >= 0),
  currency TEXT NOT NULL DEFAULT 'EUR',
  purchased_on TEXT NOT NULL,
  duration_months INTEGER NOT NULL CHECK(duration_months > 0),
  expires_on TEXT NOT NULL,
  photo_path TEXT,
  category TEXT NOT NULL CHECK(length(trim(category)) > 0),
  notes TEXT
)
''';
