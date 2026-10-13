import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// What we know about the reader's habits, used to word the reminder.
class ReadingHabit {
  final int streakDays;
  final int lastPage;
  final int daysSinceLastRead;
  final int khatamCount;
  const ReadingHabit({this.streakDays = 0, this.lastPage = 1, this.daysSinceLastRead = 0, this.khatamCount = 0});
}

class ReminderMessage {
  final String title;
  final String body;
  const ReminderMessage(this.title, this.body);
}

/// Fixed, vetted snippets. Verse text is never generated; only these
/// references/short translations (Indonesian) are shown.
const _snippets = <(String, String)>[
  ('Al-Baqarah 2:152', 'Maka ingatlah kepada-Ku, Aku pun akan ingat kepadamu.'),
  ('Ar-Ra\'d 13:28', 'Ingatlah, hanya dengan mengingat Allah hati menjadi tenteram.'),
  ('Al-Muzzammil 73:4', 'Bacalah Al-Qur\'an itu dengan perlahan-lahan.'),
  ('Al-Insyirah 94:6', 'Sesungguhnya bersama kesulitan ada kemudahan.'),
  ('Thaha 20:114', 'Ya Tuhanku, tambahkanlah ilmu kepadaku.'),
];

ReminderMessage composeReminder(ReadingHabit h, {DateTime? now}) {
  final day = (now ?? DateTime.now()).difference(DateTime(2024)).inDays;
  final s = _snippets[day % _snippets.length];
  final String lead;
  if (h.daysSinceLastRead >= 3) {
    lead = 'Sudah ${h.daysSinceLastRead} hari. Mari kembali membaca dari halaman ${h.lastPage}.';
  } else if (h.streakDays >= 2) {
    lead = 'Konsisten ${h.streakDays} hari berturut-turut! Lanjutkan di halaman ${h.lastPage}.';
  } else if (h.khatamCount > 0) {
    lead = 'Semoga istiqamah. Lanjutkan tilawah di halaman ${h.lastPage}.';
  } else {
    lead = 'Waktunya membaca. Lanjutkan di halaman ${h.lastPage}.';
  }
  return ReminderMessage('Waktu Tilawah', '$lead\n${s.$1}: ${s.$2}');
}

class NotificationService {
  @visibleForTesting
  static bool? debugSupportsScheduling;

  /// Scheduled notifications work on Android, iOS and macOS only.
  static bool get supportsScheduling =>
      debugSupportsScheduling ?? !(Platform.isLinux || Platform.isWindows);

  NotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  static const _id = 1001;

  Future<void> init() async {
    // Scheduled notifications are unsupported by the plugin on Linux/Windows, and the
    // Linux backend needs a D-Bus session (its async failure cannot be caught here).
    if (!supportsScheduling) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone())));
    } on Exception {
      // fall back to UTC
    }
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
          requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      macOS: DarwinInitializationSettings(
          requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      linux: LinuxInitializationSettings(defaultActionName: 'Buka'),
    ));
  }

  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final a = await android?.requestNotificationsPermission();
    final i = await ios?.requestPermissions(alert: true, badge: true, sound: true);
    return (a ?? i ?? true);
  }

  /// Next occurrence of hh:mm in the local zone.
  static tz.TZDateTime nextInstance(int hour, int minute, tz.TZDateTime now) {
    var t = tz.TZDateTime(now.location, now.year, now.month, now.day, hour, minute);
    if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  /// Schedules ONE notification at the next hh:mm with text for [habit].
  /// Call again after each reading session / app start so the text stays
  /// current (the OS cannot compute dynamic text by itself).
  Future<void> scheduleDaily({required int hour, required int minute, required ReadingHabit habit}) async {
    // zonedSchedule is not implemented by the plugin on Linux/Windows.
    if (!supportsScheduling) return;
    final msg = composeReminder(habit);
    await _plugin.zonedSchedule(
      _id,
      msg.title,
      msg.body,
      nextInstance(hour, minute, tz.TZDateTime.now(tz.local)),
      const NotificationDetails(
        android: AndroidNotificationDetails('daily_reading', 'Pengingat tilawah',
            importance: Importance.defaultImportance, styleInformation: BigTextStyleInformation('')),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancel() => _plugin.cancel(_id);
}
