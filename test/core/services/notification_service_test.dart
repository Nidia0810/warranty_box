import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:warranty_box/core/services/notification_service.dart';
import 'package:warranty_box/features/warranties/domain/entities/warranty.dart';

void main() {
  setUpAll(tz_data.initializeTimeZones);

  Warranty sample(DateTime purchase) => Warranty(
    id: 'warranty-local-1', titulo: 'Máquina de café', loja: 'Loja', preco: 14999,
    dataCompra: purchase, duracaoMeses: 12, categoria: 'casa',
  );

  test('Agenda 30 e 7 dias antes a uma hora local, atravessando mudança de hora', () {
    final location = tz.getLocation('Europe/Lisbon');
    final plans = NotificationService.buildAlertPlan(sample(DateTime(2025, 4, 5)),
        location: location, now: DateTime.utc(2026, 1, 1));
    expect(plans.map((plan) => plan.daysBefore), [30, 7]);
    expect(plans[0].at, tz.TZDateTime(location, 2026, 3, 6, 9));
    expect(plans[1].at, tz.TZDateTime(location, 2026, 3, 29, 9));
    expect(plans[0].at.timeZoneOffset, Duration.zero);
    expect(plans[1].at.timeZoneOffset, const Duration(hours: 1));
  });

  test('Ignora o alerta passado sem perder o alerta futuro', () {
    final plans = NotificationService.buildAlertPlan(sample(DateTime(2025, 4, 5)),
        location: tz.UTC, now: DateTime.utc(2026, 3, 10));
    expect(plans.single.daysBefore, 7);
  });

  test('Não duplica antecedências e não agenda garantias expiradas', () {
    final warranty = sample(DateTime(2025, 4, 5));
    expect(NotificationService.buildAlertPlan(warranty,
        location: tz.UTC, now: DateTime.utc(2026, 1, 1),
        daysBefore: [7, 7]).length, 1);
    expect(NotificationService.buildAlertPlan(warranty,
        location: tz.UTC, now: DateTime.utc(2026, 5, 1)), isEmpty);
  });

  test('Valida horas e antecedências antes de agendar', () {
    expect(() => NotificationService.buildAlertPlan(sample(DateTime(2025, 4, 5)),
        location: tz.UTC, now: DateTime.utc(2026), hour: 24), throwsArgumentError);
    expect(() => NotificationService.buildAlertPlan(sample(DateTime(2025, 4, 5)),
        location: tz.UTC, now: DateTime.utc(2026), daysBefore: [-7]), throwsArgumentError);
  });

  test('IDs são determinísticos e distinguem as duas antecedências', () {
    final id = NotificationService.notificationIdFor('warranty-local-1', 30);
    expect(id, NotificationService.notificationIdFor('warranty-local-1', 30));
    expect(id, inInclusiveRange(1, 0x7fffffff));
    expect(id, isNot(NotificationService.notificationIdFor('warranty-local-1', 7)));
  });
}
