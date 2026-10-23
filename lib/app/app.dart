import 'package:flutter/material.dart';
import '../core/services/notification_service.dart';
import '../core/services/pdf_service.dart';

import '../features/warranties/screens/add_warranty_screen.dart';
import '../features/invoices/data/receipt_image_service.dart';
import '../features/warranties/screens/paywall_screen.dart';
import '../features/paywall/application/billing_controller.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/warranties/presentation/dashboard_screen.dart';
import '../features/warranties/domain/repositories/warranty_repository.dart';
import 'theme/app_theme.dart';

class WarrantyBoxApp extends StatelessWidget {
  const WarrantyBoxApp({required this.repository, required this.billing,
    required this.notifications, required this.pdfService, this.recovery, super.key});
  final WarrantyRepository repository;
  final BillingController billing;
  final NotificationService notifications;
  final PdfService pdfService;
  final CaptureRecovery? recovery;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WarrantyBox',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routes: {
        '/': (_) => DashboardScreen(repository: repository, billing: billing,
            recovery: recovery, notifications: notifications, pdfService: pdfService),
        '/invoice': (_) => AddWarrantyScreen(repository: repository,
            billing: billing, notifications: notifications),
        '/paywall': (_) => PaywallScreen(billing: billing),
        '/settings': (_) => SettingsScreen(billing: billing,
            notifications: notifications, repository: repository),
      },
    );
  }
}
