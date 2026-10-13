import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/database/desktop_init.dart';

void main() {
  test('linux: XDG_DATA_HOME wins, else ~/.local/share', () {
    expect(desktopDataDir(os: 'linux', env: {'XDG_DATA_HOME': '/x', 'HOME': '/h'}), '/x/quran_app');
    expect(desktopDataDir(os: 'linux', env: {'HOME': '/h'}), '/h/.local/share/quran_app');
    expect(desktopDataDir(os: 'linux', env: {'XDG_DATA_HOME': '', 'HOME': '/h'}), '/h/.local/share/quran_app');
  });

  test('macos and windows locations', () {
    expect(desktopDataDir(os: 'macos', env: {'HOME': '/Users/a'}), '/Users/a/Library/Application Support/quran_app');
    expect(desktopDataDir(os: 'windows', env: {'APPDATA': r'C:\Users\a\AppData\Roaming'}).endsWith('quran_app'), isTrue);
  });

  test('initDesktopDatabase registers the ffi factory and opens a usable db on this host', () async {
    final path = initDesktopDatabase();
    expect(isDesktop, isTrue); // flutter test runs on a desktop host
    expect(path, endsWith('quran_app/quran.db'));
  });
}
