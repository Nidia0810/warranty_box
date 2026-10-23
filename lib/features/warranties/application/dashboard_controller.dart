import 'package:flutter/foundation.dart';

import '../domain/entities/warranty.dart';
import '../domain/repositories/warranty_repository.dart';

enum DashboardFilter { todas, ativas, aExpirar, expiradas }

const warrantyCategories = <String, String>{
  'eletronica': 'Eletrónica',
  'eletrodomesticos': 'Eletrodomésticos',
  'vestuario': 'Vestuário',
  'casa': 'Casa',
  'outros': 'Outros',
};

class DashboardController extends ChangeNotifier {
  DashboardController({required this.repository, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final WarrantyRepository repository;

  final DateTime Function() _clock;
  final List<Warranty> _items = [];
  bool loading = false;
  String? error;
  bool _disposed = false;
  int _loadGeneration = 0;
  String _query = '';
  String? _category;
  DashboardFilter _filter = DashboardFilter.todas;

  DateTime get now => _clock();
  String? get category => _category;
  DashboardFilter get filter => _filter;
  int get total => _items.length;
  List<Warranty> get warranties => List.unmodifiable(_items);
  void clearFilters() {
    _query = '';
    _category = null;
    _filter = DashboardFilter.todas;
    notifyListeners();
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final items = await repository.findAll();
      if (_disposed || generation != _loadGeneration) return;
      _items..clear()..addAll(items);
    } catch (_) {
      if (_disposed || generation != _loadGeneration) return;
      error = 'Não foi possível ler as faturas locais. Os dados não foram apagados.';
    } finally {
      if (!_disposed && generation == _loadGeneration) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
  int count(WarrantyStatus status) =>
      _items.where((item) => item.statusEm(now) == status).length;

  List<Warranty> get visibleWarranties {
    final today = now;
    final query = _normalize(_query.trim());
    final result = _items.where((item) {
      if (_category != null && item.categoria != _category) return false;
      final status = item.statusEm(today);
      final matchesStatus = switch (_filter) {
        DashboardFilter.todas => true,
        DashboardFilter.ativas => status == WarrantyStatus.ativa,
        DashboardFilter.aExpirar => status == WarrantyStatus.aExpirar,
        DashboardFilter.expiradas => status == WarrantyStatus.expirada,
      };
      return matchesStatus && _normalize('${item.titulo} ${item.loja}').contains(query);
    }).toList();
    // A expirar primeiro, depois ativas e, por último, expiradas.
    int rank(Warranty item) => switch (item.statusEm(today)) {
          WarrantyStatus.aExpirar => 0,
          WarrantyStatus.ativa => 1,
          WarrantyStatus.expirada => 2,
        };
    result.sort((a, b) {
      final comparison = rank(a).compareTo(rank(b));
      return comparison != 0 ? comparison : a.dataExpiracao.compareTo(b.dataExpiracao);
    });
    return result;
  }

  void search(String value) {
    _query = value;
    notifyListeners();
  }

  void selectFilter(DashboardFilter value) {
    _filter = value;
    notifyListeners();
  }

  void selectCategory(String? value) {
    _category = value;
    notifyListeners();
  }

  void refreshDate() => notifyListeners();

  static String _normalize(String value) {
    var result = value.toLowerCase();
    const accents = {'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'é': 'e',
      'ê': 'e', 'í': 'i', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'ç': 'c'};
    for (final entry in accents.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }
}
