import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../accounts/secure_account_vault.dart';
import '../mail/cpanel_mail_service.dart';
import '../notifications/mail_notifications.dart';

const String _mailSyncTask = 'parmtech.mail.unread_sync';
const String _uniqueMailSyncTask = 'parmtech-mail-unread-sync';

class AndroidMailBackgroundSync {
  AndroidMailBackgroundSync._();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (!Platform.isAndroid || _initialized) return;
    await Workmanager().initialize(mailBackgroundCallbackDispatcher);
    _initialized = true;
  }

  static Future<void> schedule() async {
    if (!Platform.isAndroid) return;
    await initialize();
    await Workmanager().registerPeriodicTask(
      _uniqueMailSyncTask,
      _mailSyncTask,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 5),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  static Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    await initialize();
    await Workmanager().cancelByUniqueName(_uniqueMailSyncTask);
  }
}

@pragma('vm:entry-point')
void mailBackgroundCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != _mailSyncTask) return true;
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    try {
      final vault = SecureAccountVault();
      final accounts = await vault.readAll();
      if (accounts.isEmpty) return true;

      final previousCounts = await vault.readUnreadCounts();
      final latestCounts = Map<String, int>.of(previousCounts);
      final mailService = CpanelMailService();
      var newMessages = 0;

      // Keep account connections sequential and lightweight for shared hosting.
      for (final account in accounts) {
        try {
          final unread = await mailService.countUnread(account);
          final previous = previousCounts[account.id];
          if (previous != null && unread > previous) {
            newMessages += unread - previous;
          }
          latestCounts[account.id] = unread;
        } catch (_) {
          // Retain this account's last successful snapshot for the next run.
        }
      }

      await vault.writeUnreadCounts(latestCounts);
      if (newMessages > 0) {
        try {
          final notifications = MailNotifications();
          await notifications.initialize();
          await notifications.showNewMail(newMessages);
        } catch (_) {
          // Notification permission may have been denied or revoked.
        }
      }
      return true;
    } catch (_) {
      // Let WorkManager mark a failed run and retry at a later opportunity.
      return false;
    }
  });
}
