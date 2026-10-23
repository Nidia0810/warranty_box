import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/storage/app_database.dart';
import 'core/services/notification_service.dart';
import 'core/services/pdf_service.dart';
import 'features/invoices/data/receipt_image_service.dart';
import 'features/warranties/data/sqlite_warranty_repository.dart';
import 'features/paywall/application/billing_controller.dart';
import 'features/paywall/data/revenuecat_gateway.dart';
import 'features/paywall/data/secure_trial_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final recovery = await ReceiptImageService().recover();
  final repository = SqliteWarrantyRepository(AppDatabase());
  final notifications = NotificationService();
  final pdfService = PdfService();
  final billing = BillingController(
    gateway: RevenueCatGateway(), trialStore: const SecureTrialStore(),
  );
  unawaited(billing.initialize());
  runApp(ProviderScope(child: WarrantyBoxApp(
    repository: repository, billing: billing, recovery: recovery,
    notifications: notifications, pdfService: pdfService,
  )));
}
