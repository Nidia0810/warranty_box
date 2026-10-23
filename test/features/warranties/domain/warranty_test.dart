import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_box/features/warranties/domain/entities/warranty.dart';

Warranty makeWarranty(DateTime date, int months) => Warranty(
      id: 'test-id', titulo: 'Portátil', loja: 'Loja', preco: 99999,
      dataCompra: date, duracaoMeses: months, categoria: 'eletronica',
    );

void main() {
  test('Limita o dia ao último dia do mês de destino', () {
    expect(makeWarranty(DateTime(2025, 1, 31), 1).dataExpiracao,
        DateTime(2025, 2, 28));
  });
  test('Calcula o aniversário de uma compra em dia bissexto', () {
    expect(makeWarranty(DateTime(2024, 2, 29), 12).dataExpiracao,
        DateTime(2025, 2, 28));
  });
  test('Distingue ativa, a expirar e expirada por dias civis', () {
    final warranty = makeWarranty(DateTime(2025, 3, 31), 12);
    expect(warranty.statusEm(DateTime(2026, 1, 1)), WarrantyStatus.ativa);
    expect(warranty.diasRestantesEm(DateTime(2026, 3, 30, 23)), 1);
    expect(warranty.statusEm(DateTime(2026, 3, 31, 23)), WarrantyStatus.aExpirar);
    expect(warranty.statusEm(DateTime(2026, 4, 1)), WarrantyStatus.expirada);
  });
  test('Rejeita duração inválida em execução', () {
    expect(() => makeWarranty(DateTime(2026), 0), throwsArgumentError);
  });
}
