import '../entities/warranty.dart';

abstract interface class WarrantyRepository {
  Future<List<Warranty>> findAll();
  Future<Warranty?> findById(String id);
  Future<void> save(Warranty warranty);
  Future<void> delete(String id);
}
