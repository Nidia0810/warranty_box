import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_box/features/warranties/application/dashboard_controller.dart';
import 'package:warranty_box/features/warranties/domain/entities/warranty.dart';
import 'package:warranty_box/features/warranties/domain/repositories/warranty_repository.dart';
import 'package:warranty_box/features/warranties/data/demo_warranties.dart';

void main() {
  late DashboardController controller;

  setUp(() async {
    controller = DashboardController(
      repository: _MemoryRepository(createDemoWarranties(DateTime(2026, 10, 22))),
      clock: () => DateTime(2026, 10, 22),
    );
    await controller.load();
  });
  tearDown(() => controller.dispose());

  test('A demonstração inclui os três estados e destaca o mais urgente', () {
    expect(controller.total, 6);
    expect(controller.count(WarrantyStatus.ativa), 4);
    expect(controller.count(WarrantyStatus.aExpirar), 1);
    expect(controller.count(WarrantyStatus.expirada), 1);
    expect(controller.visibleWarranties.first.titulo, 'Máquina de café');
    expect(controller.visibleWarranties.last.titulo, 'Aspirador sem fios');
  });

  test('Pesquisa sem acentos e combina categoria com estado', () {
    controller.search(' maquina ');
    expect(controller.visibleWarranties.single.titulo, 'Máquina de café');
    controller.selectCategory('eletronica');
    expect(controller.visibleWarranties, isEmpty);
    controller.search('');
    controller.selectFilter(DashboardFilter.ativas);
    expect(controller.visibleWarranties.length, 2);
  });

  test('Filtrar resultados não altera os contadores globais', () {
    controller.search('não existe');
    expect(controller.visibleWarranties, isEmpty);
    expect(controller.total, 6);
    expect(controller.count(WarrantyStatus.aExpirar), 1);
  });

  test('Uma garantia persistida entra no Dashboard após recarregar', () async {
    controller.search('inexistente');
    controller.selectCategory('casa');
    controller.selectFilter(DashboardFilter.expiradas);
    await controller.repository.save(Warranty(
      id: 'capturada', titulo: 'Televisão', loja: 'Loja', preco: 49900,
      dataCompra: DateTime(2026, 10, 22), duracaoMeses: 36,
      categoria: 'eletronica', fotoPath: 'invoices/capturada.jpg',
    ));
    controller.clearFilters();
    await controller.load();
    expect(controller.total, 7);
    expect(controller.category, isNull);
    expect(controller.filter, DashboardFilter.todas);
    expect(controller.visibleWarranties.any((item) => item.id == 'capturada'), isTrue);
  });

  test('Os dias e os estados acompanham o relógio injetado', () async {
    var now = DateTime(2026, 10, 22);
    final timed = DashboardController(
      repository: _MemoryRepository(createDemoWarranties(now)), clock: () => now,
    );
    await timed.load();
    final urgent = timed.visibleWarranties.first;
    expect(urgent.diasRestantesEm(timed.now), 10);
    now = DateTime(2026, 11, 2);
    timed.refreshDate();
    expect(timed.count(WarrantyStatus.expirada), 2);
    timed.dispose();
  });

  test('Falha de leitura apresenta erro e mantém os registos carregados', () async {
    final repository = controller.repository as _MemoryRepository;
    repository.fail = true;
    await controller.load();
    expect(controller.error, isNotNull);
    expect(controller.loading, isFalse);
    expect(controller.total, 6);
  });
}

class _MemoryRepository implements WarrantyRepository {
  _MemoryRepository(this.items);
  final List<Warranty> items;
  bool fail = false;

  @override
  Future<List<Warranty>> findAll() async {
    if (fail) throw StateError('Falha simulada de leitura');
    return List.of(items);
  }

  @override
  Future<Warranty?> findById(String id) async =>
      items.where((item) => item.id == id).firstOrNull;

  @override
  Future<void> save(Warranty warranty) async {
    items.removeWhere((item) => item.id == warranty.id);
    items.add(warranty);
  }

  @override
  Future<void> delete(String id) async => items.removeWhere((item) => item.id == id);
}
