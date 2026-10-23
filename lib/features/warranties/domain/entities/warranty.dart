enum WarrantyStatus { ativa, aExpirar, expirada }

/// Entidade independente de Flutter e SQLite. Datas civis, sem hora persistida.
final class Warranty {
  factory Warranty({
    required String id,
    required String titulo,
    required String loja,
    required int preco,
    required DateTime dataCompra,
    required int duracaoMeses,
    required String categoria,
    String? fotoPath,
    String? notas,
    String moeda = 'EUR',
  }) {
    if (id.trim().isEmpty || titulo.trim().isEmpty || loja.trim().isEmpty ||
        categoria.trim().isEmpty) {
      throw ArgumentError('ID, título, loja e categoria são obrigatórios.');
    }
    if (preco < 0 || duracaoMeses <= 0) {
      throw ArgumentError('Preço não negativo e duração positiva obrigatórios.');
    }
    final compra = DateTime(dataCompra.year, dataCompra.month, dataCompra.day);
    final mesAlvo = DateTime(compra.year, compra.month + duracaoMeses, 1);
    final ultimoDia = DateTime(mesAlvo.year, mesAlvo.month + 1, 0).day;
    final expiracao = DateTime(
      mesAlvo.year, mesAlvo.month,
      compra.day > ultimoDia ? ultimoDia : compra.day,
    );
    return Warranty._(
      id: id.trim(), titulo: titulo.trim(), loja: loja.trim(), preco: preco,
      dataCompra: compra, duracaoMeses: duracaoMeses,
      dataExpiracao: expiracao, categoria: categoria.trim(),
      fotoPath: fotoPath, notas: notas, moeda: moeda,
    );
  }

  const Warranty._({
    required this.id, required this.titulo, required this.loja,
    required this.preco, required this.dataCompra, required this.duracaoMeses,
    required this.dataExpiracao, required this.categoria,
    required this.fotoPath, required this.notas, required this.moeda,
  });

  final String id;
  final String titulo;
  final String loja;

  /// Unidades mínimas da moeda: 499 representa 4,99 EUR. Evita erros de double.
  final int preco;
  final String moeda;
  final DateTime dataCompra;
  final int duracaoMeses;
  final DateTime dataExpiracao;

  /// Caminho relativo à pasta privada de documentos, nunca temporário.
  final String? fotoPath;

  /// ID estável, por exemplo 'eletronica'; traduzido na apresentação.
  final String categoria;
  final String? notas;

  /// UTC apenas para contar dias civis sem desvios de horário de verão.
  int diasRestantesEm(DateTime agora) =>
      DateTime.utc(dataExpiracao.year, dataExpiracao.month, dataExpiracao.day)
          .difference(DateTime.utc(agora.year, agora.month, agora.day))
          .inDays;

  /// Válida durante todo o dia de expiração.
  WarrantyStatus statusEm(DateTime agora, {int antecedenciaDias = 30}) {
    if (antecedenciaDias < 0) {
      throw ArgumentError.value(antecedenciaDias, 'antecedenciaDias');
    }
    final dias = diasRestantesEm(agora);
    if (dias < 0) return WarrantyStatus.expirada;
    if (dias <= antecedenciaDias) return WarrantyStatus.aExpirar;
    return WarrantyStatus.ativa;
  }
}
