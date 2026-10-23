import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class MailNotifications {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
      linux: LinuxInitializationSettings(defaultActionName: 'Open'),
      windows: WindowsInitializationSettings(appName: 'ParmTech Mail', appUserModelId: 'au.parmtech.mail', guid: 'a1e42715-8094-4e8b-9a16-10f54b67f6a2'),
    );
    await _plugin.initialize(settings);
  }

  Future<bool> requestPermission() async {
    final android = await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    final ios = await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
    final mac = await _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
    return android ?? ios ?? mac ?? false;
  }

  Future<void> showNewMail(int count) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails('mail_updates', 'Mail updates', channelDescription: 'New messages found during inbox sync', importance: Importance.defaultImportance, priority: Priority.defaultPriority),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
      linux: LinuxNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );
    await _plugin.show(1, 'New mail', '$count new message${count == 1 ? '' : 's'} arrived.', details);
  }
}
