import '../domain/entities/warranty.dart';

abstract final class WarrantyRowMapper {
  static Map<String, Object?> toRow(Warranty warranty) => {
        'id': warranty.id,
        'title': warranty.titulo,
        'store': warranty.loja,
        'price_cents': warranty.preco,
        'currency': warranty.moeda,
        'purchased_on': dateOnly(warranty.dataCompra),
        'duration_months': warranty.duracaoMeses,
        'expires_on': dateOnly(warranty.dataExpiracao),
        'photo_path': warranty.fotoPath,
        'category': warranty.categoria,
        'notes': warranty.notas,
      };

  static Warranty fromRow(Map<String, Object?> row) {
    final warranty = Warranty(
      id: row['id'] as String,
      titulo: row['title'] as String,
      loja: row['store'] as String,
      preco: row['price_cents'] as int,
      moeda: row['currency'] as String,
      dataCompra: _readDate(row['purchased_on'] as String),
      duracaoMeses: row['duration_months'] as int,
      fotoPath: row['photo_path'] as String?,
      categoria: row['category'] as String,
      notas: row['notes'] as String?,
    );
    if (dateOnly(warranty.dataExpiracao) != row['expires_on']) {
      throw const FormatException('Data de expiração inconsistente no registo local.');
    }
    return warranty;
  }

  static String dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static DateTime _readDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null || dateOnly(date) != value) {
      throw const FormatException('Data civil inválida no registo local.');
    }
    return DateTime(date.year, date.month, date.day);
  }
}
