import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kReadSeconds = 30;
const kPointsPerPage = 10;
const kLastPage = 604;

abstract class TrackerEvent extends Equatable {
  const TrackerEvent();
  @override
  List<Object?> get props => [];
}

class TrackerLoaded extends TrackerEvent {
  const TrackerLoaded();
}

/// The reader is now looking at [page]; resets the 30s timer.
class PageOpened extends TrackerEvent {
  final int page;
  const PageOpened(this.page);
  @override
  List<Object?> get props => [page];
}

/// One second of reading on the current page.
class ReadingTick extends TrackerEvent {
  const ReadingTick();
}

class TrackerState extends Equatable {
  final int points;
  final int khatamCount;
  final int currentPage;
  final int secondsOnPage;
  final Set<int> pagesRewardedThisCycle;
  final int lastAward; // points from the latest award, 0 if none

  const TrackerState({
    this.points = 0,
    this.khatamCount = 0,
    this.currentPage = 1,
    this.secondsOnPage = 0,
    this.pagesRewardedThisCycle = const {},
    this.lastAward = 0,
  });

  TrackerState copyWith({
    int? points,
    int? khatamCount,
    int? currentPage,
    int? secondsOnPage,
    Set<int>? pagesRewardedThisCycle,
    int? lastAward,
  }) =>
      TrackerState(
        points: points ?? this.points,
        khatamCount: khatamCount ?? this.khatamCount,
        currentPage: currentPage ?? this.currentPage,
        secondsOnPage: secondsOnPage ?? this.secondsOnPage,
        pagesRewardedThisCycle: pagesRewardedThisCycle ?? this.pagesRewardedThisCycle,
        lastAward: lastAward ?? this.lastAward,
      );

  @override
  List<Object?> get props =>
      [points, khatamCount, currentPage, secondsOnPage, pagesRewardedThisCycle, lastAward];
}

/// +10 points the first time a page is read for 30s in a cycle. Reading page
/// 604 completes the cycle: khatam +1, page set resets, points are kept.
class ReadingTrackerBloc extends Bloc<TrackerEvent, TrackerState> {
  ReadingTrackerBloc(this._prefs) : super(const TrackerState()) {
    on<TrackerLoaded>((e, emit) => emit(TrackerState(
          points: _prefs.getInt(_kPoints) ?? 0,
          khatamCount: _prefs.getInt(_kKhatam) ?? 0,
          pagesRewardedThisCycle:
              (_prefs.getStringList(_kPages) ?? const []).map(int.parse).toSet(),
        )));
    on<PageOpened>((e, emit) => emit(state.copyWith(currentPage: e.page, secondsOnPage: 0, lastAward: 0)));
    on<ReadingTick>(_onTick);
  }

  final SharedPreferences _prefs;
  static const _kPoints = 'tracker_points';
  static const _kKhatam = 'tracker_khatam';
  static const _kPages = 'tracker_pages';

  Future<void> _onTick(ReadingTick e, Emitter<TrackerState> emit) async {
    final secs = state.secondsOnPage + 1;
    if (secs < kReadSeconds || state.pagesRewardedThisCycle.contains(state.currentPage)) {
      emit(state.copyWith(secondsOnPage: secs, lastAward: 0));
      return;
    }
    final pages = {...state.pagesRewardedThisCycle, state.currentPage};
    var khatam = state.khatamCount;
    if (state.currentPage == kLastPage) {
      khatam++;
      pages.clear();
    }
    final points = state.points + kPointsPerPage;
    await _prefs.setInt(_kPoints, points);
    await _prefs.setInt(_kKhatam, khatam);
    await _prefs.setStringList(_kPages, pages.map((p) => '$p').toList());
    emit(state.copyWith(
        points: points,
        khatamCount: khatam,
        secondsOnPage: secs,
        pagesRewardedThisCycle: pages,
        lastAward: kPointsPerPage));
  }
}
