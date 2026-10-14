import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_app.dart';
import 'services/admin_api_service.dart';

/// Web/desktop admin console, independent of the reader's SQLite stack:
///   flutter run -d chrome -t lib/admin_main.dart --dart-define=API_BASE=http://localhost:8000
///   flutter build web -t lib/admin_main.dart --dart-define=API_BASE=https://api.example.com
const _apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8000');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    // theme choice just won't persist
  }
  runApp(AdminApp(api: AdminApiService(baseUrl: _apiBase), prefs: prefs));
}
