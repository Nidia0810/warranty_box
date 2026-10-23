import '../domain/receipt_reading.dart';

/// Heurísticas para talões portugueses. Campos ambíguos ficam por preencher.
class ReceiptParser {
  const ReceiptParser();

  // Compilados uma vez, reutilizados em todas as leituras.
  static final _lineBreak = RegExp(r'[\r\n]+');
  static final _letters = RegExp(r'[a-zA-ZÀ-ÿ]{3}');
  static final _headerNoise = RegExp(
    r'^(?:fatura|factura|recibo|tal[aã]o|nif|nipc|contribuinte|www\.|https?:|'
    r'tel\b|telefone|rua\b|avenida\b|av\.|morada|data\b|original|duplicado|bem.vind)',
    caseSensitive: false,
  );
  static final _totalLabel = RegExp(
    r'\b(?:total\s+a\s+pagar|valor\s+a\s+pagar|total\s+geral|'
    r'total\s+(?:da\s+)?(?:fatura|factura|compra)|montante\s+total|total)\b',
    caseSensitive: false,
  );
  static final _strongTotal = RegExp(
    r'\b(?:total\s+a\s+pagar|valor\s+a\s+pagar|total\s+geral|'
    r'total\s+(?:da\s+)?(?:fatura|factura|compra)|montante\s+total)\b',
    caseSensitive: false,
  );
  static final _excludedTotal = RegExp(
    r'sub\s*total|total\s+(?:de\s+)?iva\b|desconto|troco|recebido|'
    r'sem\s+(?:iva|imposto)|total\s+pago',
    caseSensitive: false,
  );
  static final _negative = RegExp(r'[-−]\s*(?:(?:EUR|€)\s*)?\d', caseSensitive: false);
  static final _money = RegExp(
    r'(?<![\d.,])(?:\d{1,3}(?:[. ]\d{3})+|\d+),\d{2}(?![\d.,])|'
    r'(?<![\d.,])(?:\d{1,3}(?:[, ]\d{3})+|\d+)\.\d{2}(?![\d.,])',
  );
  static final _moneyLine = RegExp(
    r'^(?:EUR|€)?\s*\d[\d., ]*[.,]\d{2}\s*(?:EUR|€)?$', caseSensitive: false,
  );
  static final _currency = RegExp(r'[\s€]|EUR', caseSensitive: false);
  static final _validMoney = RegExp(
    r'^(?:\d+|\d{1,3}(?:\.\d{3})+),\d{2}$|'
    r'^(?:\d+|\d{1,3}(?:,\d{3})+)\.\d{2}$',
  );
  static final _separators = RegExp(r'[.,]');
  static final _datePattern = RegExp(
    r'\b(?:(\d{4})[-/](\d{1,2})[-/](\d{1,2})|(\d{1,2})[./-](\d{1,2})[./-](\d{4}))\b',
  );
  static final _purchaseLabel = RegExp(
    r'\b(?:compra|emiss[aã]o|emitid[ao]|data\s+(?:da\s+)?(?:fatura|factura))\b',
    caseSensitive: false,
  );
  static final _otherDate = RegExp(
    r'\b(?:validade|vencimento|expira[cç][aã]o|garantia|entrega)\b', caseSensitive: false,
  );

  ReceiptReading parse(String text) {
    final lines = text.replaceAll('\u00a0', ' ').replaceAll('\u202f', ' ').split(_lineBreak)
        .map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
    String? store;
    for (final line in lines.take(5)) {
      if (_letters.hasMatch(line) && !_headerNoise.hasMatch(line) &&
          !_totalLabel.hasMatch(line) && !_datePattern.hasMatch(line)) {
        store = line;
        break;
      }
    }

    final totals = <int>{};
    var bestRank = 0;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final label = _totalLabel.firstMatch(line);
      if (label == null || _excludedTotal.hasMatch(line) || _negative.hasMatch(line)) continue;
      // Considerar apenas o montante depois do rótulo, nunca números de artigos.
      final amounts = _amounts(line.substring(label.end));
      if (amounts.isEmpty && index + 1 < lines.length && _moneyLine.hasMatch(lines[index + 1])) {
        amounts.addAll(_amounts(lines[index + 1]));
      }
      if (amounts.length != 1) continue;
      final rank = _strongTotal.hasMatch(line) ? 2 : 1;
      if (rank < bestRank) continue;
      if (rank > bestRank) totals.clear();
      bestRank = rank;
      totals.add(amounts.single);
    }

    final dates = <DateTime>{};
    final purchaseDates = <DateTime>{};
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (_otherDate.hasMatch(line) || (index > 0 &&
          _otherDate.hasMatch(lines[index - 1]) &&
          !_datePattern.hasMatch(lines[index - 1]))) continue;
      // Um rótulo isolado pode preceder a data na linha seguinte do OCR.
      final purchase = _purchaseLabel.hasMatch(line) ||
          (index > 0 && _purchaseLabel.hasMatch(lines[index - 1]) &&
              !_datePattern.hasMatch(lines[index - 1]) && !_otherDate.hasMatch(lines[index - 1]));
      for (final match in _datePattern.allMatches(line)) {
        final year = int.parse(match.group(1) ?? match.group(6)!);
        final month = int.parse(match.group(2) ?? match.group(5)!);
        final day = int.parse(match.group(3) ?? match.group(4)!);
        final date = DateTime(year, month, day);
        if (year >= 1900 && year <= 2100 && date.year == year &&
            date.month == month && date.day == day) {
          dates.add(date);
          if (purchase) purchaseDates.add(date);
        }
      }
    }
    final candidates = purchaseDates.isNotEmpty ? purchaseDates : dates;
    return ReceiptReading(text: text, store: store,
        totalCents: totals.length == 1 ? totals.single : null,
        date: candidates.length == 1 ? candidates.single : null);
  }

  static List<int> _amounts(String line) => _money.allMatches(line)
      .map((match) => parseMoney(match.group(0)!)).whereType<int>().toList();

  /// Aceita 1234,56, 1.234,56 e 1,234.56; devolve cêntimos, sem double.
  static int? parseMoney(String value) {
    final clean = value.trim().replaceAll(_currency, '');
    if (!_validMoney.hasMatch(clean)) {
      return null;
    }
    final whole = clean.substring(0, clean.length - 3).replaceAll(_separators, '');
    return int.tryParse('$whole${clean.substring(clean.length - 2)}');
  }
}
