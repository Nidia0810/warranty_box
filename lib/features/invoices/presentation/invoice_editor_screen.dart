import 'package:flutter/material.dart';
import '../../../core/services/notification_service.dart';

import '../../paywall/application/billing_controller.dart';
import '../../warranties/domain/repositories/warranty_repository.dart';
import '../../warranties/screens/add_warranty_screen.dart';
import '../data/receipt_image_service.dart';

/// Compatibilidade com imports anteriores; o formulário vive em warranties.
@Deprecated('Usar AddWarrantyScreen em features/warranties/screens.')
class InvoiceEditorScreen extends StatelessWidget {
  const InvoiceEditorScreen({
    required this.repository,
    required this.billing,
    required this.notifications,
    this.recovery,
    super.key,
  });

  final WarrantyRepository repository;
  final BillingController billing;
  final NotificationService notifications;
  final CaptureRecovery? recovery;

  @override
  Widget build(BuildContext context) => AddWarrantyScreen(
        repository: repository,
        billing: billing,
        notifications: notifications,
        recovery: recovery,
      );
}
