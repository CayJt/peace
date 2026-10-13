import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool get isDesktop => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

/// Per-user data directory for the app database on desktop (pure, testable).
/// Linux follows XDG; the default ffi location (`./.dart_tool/...`) is relative
/// to the working directory and unsuitable for an installed app.
String desktopDataDir({required String os, required Map<String, String> env}) {
  const app = 'quran_app';
  switch (os) {
    case 'windows':
      return p.join(env['APPDATA'] ?? env['USERPROFILE'] ?? '.', app);
    case 'macos':
      return p.join(env['HOME'] ?? '.', 'Library', 'Application Support', app);
    default:
      final xdg = env['XDG_DATA_HOME'];
      return p.join(
        xdg != null && xdg.isNotEmpty ? xdg : p.join(env['HOME'] ?? '.', '.local', 'share'),
        app,
      );
  }
}

/// Initialises sqflite for desktop (FFI) and returns the database file path.
/// Mobile (Android/iOS) uses the default platform plugin, so returns null.
String? initDesktopDatabase() {
  if (!isDesktop) return null;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dir = desktopDataDir(os: Platform.operatingSystem, env: Platform.environment);
  Directory(dir).createSync(recursive: true);
  return p.join(dir, 'quran.db');
}
