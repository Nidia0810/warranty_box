import '../domain/entities/warranty.dart';

/// Fixture dos testes. O Dashboard real nunca insere estes registos na base.
List<Warranty> createDemoWarranties(DateTime today) {
  final date = DateTime(today.year, today.month, today.day);
  Warranty item(String id, String title, String store, int price,
      String category, DateTime purchase, int months, String notes) {
    return Warranty(
      id: id, titulo: title, loja: store, preco: price,
      categoria: category, dataCompra: purchase, duracaoMeses: months,
      notas: notes,
    );
  }

  // Deslocar a compra dois anos para trás e dez dias para a frente produz
  // uma garantia perto do fim, incluindo meses com durações diferentes.
  final near = DateTime(date.year - 2, date.month, date.day + 10);
  return [
    item('demo-1', 'AirPods Pro', 'Worten', 24999, 'eletronica',
        date.subtract(const Duration(days: 60)), 36, 'Comprovativo de demonstração.'),
    item('demo-2', 'Máquina de café', 'Fnac', 18990, 'eletrodomesticos',
        near, 24, 'Verificar a garantia antes de terminar.'),
    item('demo-3', 'Sapatilhas de corrida', 'Decathlon', 7999, 'vestuario',
        date.subtract(const Duration(days: 120)), 24, ''),
    item('demo-4', 'MacBook Air', 'Apple Store', 129900, 'eletronica',
        date.subtract(const Duration(days: 200)), 36, 'Número de série no comprovativo.'),
    item('demo-5', 'Aspirador sem fios', 'Worten', 32900, 'eletrodomesticos',
        DateTime(date.year - 3, date.month, date.day), 24, ''),
    item('demo-6', 'Candeeiro de secretária', 'IKEA', 3999, 'casa',
        date.subtract(const Duration(days: 30)), 24, ''),
  ];
}
