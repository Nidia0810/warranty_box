import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_box/features/invoices/data/receipt_parser.dart';

void main() {
  const parser = ReceiptParser();

  test('Extrai cabeçalho, data portuguesa e total com milhares', () {
    final result = parser.parse('LOJA EXEMPLO\nNIF 123456789\n22/10/2026 14:30\n'
        'Subtotal 1.000,00\nTOTAL 1.234,56 EUR\nTOTAL IVA 234,56\nTroco 0,00');
    expect(result.store, 'LOJA EXEMPLO');
    expect(result.totalCents, 123456);
    expect(result.date, DateTime(2026, 10, 22));
  });

  test('Suporta data ISO e total na linha seguinte', () {
    final result = parser.parse('LOJA\n2026-10-22\nTOTAL A PAGAR\n€ 24,99');
    expect(result.totalCents, 2499);
    expect(result.date, DateTime(2026, 10, 22));
  });

  test('Não confunde preços de artigos ou subtotal com total da compra', () {
    expect(parser.parse('LOJA\nArtigo 99,99\nSUBTOTAL 99,99').totalCents, isNull);
  });

  test('Datas inválidas e datas distintas exigem revisão manual', () {
    expect(parser.parse('LOJA\n31/02/2026').date, isNull);
    expect(parser.parse('LOJA\n22/10/2026\n23/10/2026').date, isNull);
    expect(parser.parse('LOJA\n22/10/2026\n22/10/2026').date, DateTime(2026, 10, 22));
  });

  test('Talão vazio e devoluções não geram valores positivos inventados', () {
    final empty = parser.parse('');
    expect(empty.store, isNull);
    expect(empty.date, isNull);
    expect(empty.totalCents, isNull);
    expect(parser.parse('LOJA\nTOTAL -24,99').totalCents, isNull);
  });

  test('Dá prioridade ao valor a pagar e ignora subtotais, impostos e troco', () {
    final result = parser.parse('FATURA SIMPLIFICADA\nNIF 123456789\n'
        'LOJA CENTRAL\nRua das Flores 20\nSubtotal 20,00\nTOTAL 20,00\n'
        'VALOR A PAGAR € 24,60\nTOTAL IVA 4,60\nTOTAL 20,00\nTroco 5,40');
    expect(result.store, 'LOJA CENTRAL');
    expect(result.totalCents, 2460);
  });

  test('Suporta espaços Unicode e total com IVA incluído', () {
    expect(parser.parse('LOJA\nTOTAL C/IVA 1\u202f234,56 €').totalCents, 123456);
    expect(parser.parse('LOJA\nTOTAL GERAL EUR 1,234.56').totalCents, 123456);
  });

  test('Totais contraditórios e valores malformados não são adivinhados', () {
    expect(parser.parse('TOTAL 10,00\nTOTAL 20,00').totalCents, isNull);
    expect(parser.parse('TOTAL 10,00\nTOTAL 10,00').totalCents, 1000);
    expect(parser.parse('TOTAL 1.23,45').totalCents, isNull);
    expect(parser.parse('TOTAL 1,23,45').totalCents, isNull);
    expect(parser.parse('TOTAL − EUR 24,99').totalCents, isNull);
  });

  test('Prefere compra ou emissão e ignora validade e vencimento', () {
    expect(parser.parse('Compra 22/10/2026\nValidade 22/10/2028').date,
        DateTime(2026, 10, 22));
    expect(parser.parse('Data de emissão\n2026-10-22\nVencimento\n2026-11-22').date,
        DateTime(2026, 10, 22));
    expect(parser.parse('Validade\n2028-10-22').date, isNull);
    expect(parser.parse('Emissão 22/10/2026\nCompra 23/10/2026').date, isNull);
  });

  test('Converte dinheiro em cêntimos sem aritmética de ponto flutuante', () {
    expect(ReceiptParser.parseMoney('1.234,56 €'), 123456);
    expect(ReceiptParser.parseMoney('1,234.56'), 123456);
    expect(ReceiptParser.parseMoney('0,01'), 1);
    expect(ReceiptParser.parseMoney('-10,00'), isNull);
    expect(ReceiptParser.parseMoney('12,345'), isNull);
    expect(ReceiptParser.parseMoney('1.23,45'), isNull);
    expect(ReceiptParser.parseMoney('1\u00a0234,56 EUR'), 123456);
  });
}
