import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../accounts/secure_account_vault.dart';
import '../mail/cpanel_mail_service.dart';
import '../notifications/mail_notifications.dart';

/// Fast checks are opt-in. Android requires an ongoing foreground-service
/// notification and may stop it under battery/OS restrictions.
class LiveMailService {
  LiveMailService._();

  static const interval = Duration(minutes: 2);
  static const channelId = 'parmtech_live_mail_service';
  static const notificationId = 18021;
  static bool _configured = false;

  static Future<void> configure() async {
    if (!Platform.isAndroid || _configured) return;
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          channelId,
          'Live mail checking',
          description: 'Ongoing notification for fast background mail checks',
          importance: Importance.low,
          playSound: false,
        ));
    await FlutterBackgroundService().configure(
      androidConfiguration: AndroidConfiguration(
        onStart: liveMailEntryPoint,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        foregroundServiceTypes: const [AndroidForegroundType.dataSync],
        notificationChannelId: channelId,
        foregroundServiceNotificationId: notificationId,
        initialNotificationTitle: 'ParmTech Mail',
        initialNotificationContent: 'Checking mail every 2 minutes',
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
    _configured = true;
  }

  static Future<bool> isRunning() async {
    if (!Platform.isAndroid) return false;
    await configure();
    return FlutterBackgroundService().isRunning();
  }

  static Future<bool> start() async {
    if (!Platform.isAndroid) return false;
    await configure();
    if (await isRunning()) return true;
    return FlutterBackgroundService().startService();
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (await isRunning()) {
      FlutterBackgroundService().invoke('stopService');
    }
  }
}

@pragma('vm:entry-point')
void liveMailEntryPoint(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  bool busy = false;
  bool stopping = false;
  Timer? timer;

  Future<void> check() async {
    if (busy || stopping) return;
    busy = true;
    try {
      final vault = SecureAccountVault();
      final accounts = await vault.readAll();
      if (accounts.isEmpty) return;
      final previousCounts = await vault.readUnreadCounts();
      final latest = Map<String, int>.of(previousCounts);
      final client = CpanelMailService();
      var newCount = 0;
      for (final account in accounts) {
        if (stopping) break;
        try {
          final unread = await client.countUnread(account);
          final old = latest[account.id];
          if (old != null && unread > old) newCount += unread - old;
          latest[account.id] = unread;
        } catch (_) {
          // One offline account must not prevent other accounts syncing.
        }
      }
      if (stopping) return;
      latest.removeWhere((key, _) => !accounts.any((a) => a.id == key));
      await vault.writeUnreadCounts(latest);
      if (newCount > 0) {
        final notifications = MailNotifications();
        await notifications.initialize();
        await notifications.showNewMail(newCount);
      }
    } catch (_) {
      // Android may suspend network/storage in battery-restricted modes.
    } finally {
      busy = false;
    }
  }

  service.on('stopService').listen((_) async {
    stopping = true;
    timer?.cancel();
    if (service is AndroidServiceInstance) await service.stopSelf();
  });
  unawaited(check());
  timer = Timer.periodic(LiveMailService.interval, (_) => unawaited(check()));
}
