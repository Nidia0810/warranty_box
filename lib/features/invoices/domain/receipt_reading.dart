/// Sugestões de OCR, nunca dados confirmados pelo utilizador.
class ReceiptReading {
  const ReceiptReading({required this.text, this.store, this.totalCents, this.date});
  final String text;
  final String? store;
  final int? totalCents;
  final DateTime? date;
}
