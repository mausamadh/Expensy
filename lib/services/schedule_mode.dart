import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Cached exact-alarm capability. It only changes if the user toggles the
/// system "Alarms & reminders" setting, which is rare, so a single process-
/// lifetime check is sufficient.
bool? _exactAlarmsAllowed;

/// [AndroidScheduleMode] for reminder notifications: exact when the OS allows
/// it, otherwise an inexact fallback so reminders still fire.
///
/// Android 14+ can deny [android.permission.SCHEDULE_EXACT_ALARM]; scheduling
/// an exact alarm without it throws, so we degrade to inexact (the reminder
/// fires at roughly the requested time instead of the exact minute).
Future<AndroidScheduleMode> reminderScheduleMode(
  FlutterLocalNotificationsPlugin plugin,
) async {
  if (_exactAlarmsAllowed == null) {
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    _exactAlarmsAllowed = await android?.canScheduleExactNotifications() ?? true;
  }
  return _exactAlarmsAllowed!
      ? AndroidScheduleMode.exactAllowWhileIdle
      : AndroidScheduleMode.inexactAllowWhileIdle;
}
