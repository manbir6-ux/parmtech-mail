import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class MailNotifications {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: LinuxInitializationSettings(defaultActionName: 'Open'),
      windows: WindowsInitializationSettings(
        appName: 'Parmtech Mail',
        appUserModelId: 'au.parmtech.mail',
        guid: 'a1e42715-8094-4e8b-9a16-10f54b67f6a2',
      ),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    if (!_initialized) return false;
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    if (Platform.isMacOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }

    // Windows and Linux deliver notifications through their desktop services;
    // neither plugin exposes a matching runtime permission prompt.
    return Platform.isWindows || Platform.isLinux;
  }

  Future<void> showNewMail(int count) async {
    if (!_initialized || count <= 0) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'mail_updates',
        'Mail updates',
        channelDescription: 'New messages found during inbox sync',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
      linux: LinuxNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );
    await _plugin.show(
      id: 1,
      title: 'New mail',
      body: '$count new message${count == 1 ? '' : 's'} arrived.',
      notificationDetails: details,
    );
  }
}
