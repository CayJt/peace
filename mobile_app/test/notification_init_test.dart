import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quran_app/services/notification_service.dart';

class MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(const InitializationSettings()));
  tearDown(() => NotificationService.debugSupportsScheduling = null);

  test('on platforms without scheduling (Linux/Windows) init never touches the plugin', () async {
    NotificationService.debugSupportsScheduling = false;
    final plugin = MockPlugin();
    await NotificationService(plugin).init();
    verifyNever(() => plugin.initialize(any()));
    await NotificationService(plugin).scheduleDaily(hour: 5, minute: 0, habit: const ReadingHabit());
    verifyZeroInteractions(plugin);
  });

  test('where supported, init passes settings for every platform the plugin may target', () async {
    NotificationService.debugSupportsScheduling = true;
    final plugin = MockPlugin();
    when(() => plugin.initialize(any())).thenAnswer((_) async => true);
    await NotificationService(plugin).init();
    final s = verify(() => plugin.initialize(captureAny())).captured.single as InitializationSettings;
    expect(s.android, isNotNull);
    expect(s.iOS, isNotNull);
    expect(s.macOS, isNotNull);
    expect(s.linux, isNotNull, reason: 'plugin throws "Linux settings must be set" otherwise');
  });
}
