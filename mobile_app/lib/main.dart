import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'database/desktop_init.dart';
import 'database/quran_database.dart';
import 'services/admin_api_service.dart';
import 'services/auth_service.dart';
import 'services/user_telemetry.dart';
import 'services/mic_source.dart';
import 'services/notification_service.dart';
import 'services/quran_api_service.dart';
import 'services/quran_chat_service.dart';
import 'services/quran_sync_manager.dart';

/// `flutter run --dart-define=API_BASE=http://192.168.1.10:8000`
const _apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2:8000');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // Desktop needs the FFI factory registered before any database is opened.
  final db = await QuranDatabase.open(path: initDesktopDatabase());
  final api = QuranApiService();
  final notifications = NotificationService();
  try {
    await notifications.init();
  } catch (_) {
    // Notifications are optional. Plugin misconfiguration surfaces as an Error
    // (ArgumentError), not an Exception, so catch both: it must never block startup.
  }
  final auth = AuthService(baseUrl: _apiBase);
  runApp(QuranApp(
    deps: AppDeps(
      prefs: prefs,
      db: db,
      auth: auth,
      sync: QuranSyncManager(api, db),
      chat: QuranChatService(baseUrl: _apiBase),
      mic: RecordMicSource(),
      wsBase: _apiBase.replaceFirst(RegExp('^http'), 'ws'),
      api: api,
      notifications: notifications,
      telemetry: UserTelemetry(baseUrl: _apiBase, tokenProvider: () => auth.token, appVersion: '0.1.0'),
      adminApi: AdminApiService(baseUrl: _apiBase),
    ),
  ));
}
