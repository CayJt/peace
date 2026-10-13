import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/bloc/reading_tracker_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ReadingTrackerBloc> make([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  final b = ReadingTrackerBloc(await SharedPreferences.getInstance())..add(const TrackerLoaded());
  await b.stream.first;
  return b;
}

Future<void> read(ReadingTrackerBloc b, int page, int seconds) async {
  b.add(PageOpened(page));
  for (var i = 0; i < seconds; i++) {
    b.add(const ReadingTick());
  }
  await Future<void>.delayed(Duration.zero);
  await pumpEventQueue();
}

void main() {
  test('29s earns nothing, 30s earns +10 once', () async {
    final b = await make();
    await read(b, 5, 29);
    expect(b.state.points, 0);
    b.add(const ReadingTick());
    await pumpEventQueue();
    expect(b.state.points, 10);
    expect(b.state.lastAward, 10);
    for (var i = 0; i < 60; i++) {
      b.add(const ReadingTick());
    }
    await pumpEventQueue();
    expect(b.state.points, 10, reason: 'same page must not pay twice in a cycle');
  });

  test('each new page pays once; revisiting does not', () async {
    final b = await make();
    await read(b, 1, 30);
    await read(b, 2, 30);
    await read(b, 1, 30);
    expect(b.state.points, 20);
  });

  test('reading page 604 completes a khatam, resets pages and keeps points', () async {
    final b = await make({
      'tracker_points': 6030,
      'tracker_khatam': 2,
      'tracker_pages': ['1', '2', '603'],
    });
    await read(b, 604, 30);
    expect(b.state.khatamCount, 3);
    expect(b.state.points, 6040);
    expect(b.state.pagesRewardedThisCycle, isEmpty);
    await read(b, 1, 30); // new cycle: page 1 pays again
    expect(b.state.points, 6050);
    expect(b.state.khatamCount, 3);
  });

  test('state persists across restarts', () async {
    final b = await make();
    await read(b, 7, 30);
    final prefs = await SharedPreferences.getInstance();
    final again = ReadingTrackerBloc(prefs)..add(const TrackerLoaded());
    await again.stream.first;
    expect(again.state.points, 10);
    expect(again.state.pagesRewardedThisCycle, {7});
  });

  blocTest<ReadingTrackerBloc, TrackerState>(
    'opening a page resets the timer',
    build: () {
      SharedPreferences.setMockInitialValues({});
      return ReadingTrackerBloc(_FakePrefs());
    },
    act: (b) => b
      ..add(const PageOpened(3))
      ..add(const ReadingTick())
      ..add(const PageOpened(4)),
    verify: (b) => expect(b.state.secondsOnPage, 0),
  );
}

class _FakePrefs implements SharedPreferences {
  @override
  noSuchMethod(Invocation i) => null;
}
