import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/admin_api_service.dart';

abstract class AnalyticsEvent extends Equatable {
  const AnalyticsEvent();
  @override
  List<Object?> get props => [];
}

/// Loads everything the admin may see and starts polling realtime data.
class AnalyticsStarted extends AnalyticsEvent {
  /// analytics: realtime counters (polled); users: registration stats; leaderboard; murajaah: session log.
  final bool analytics, users, leaderboard, murajaah;
  const AnalyticsStarted({this.analytics = true, this.users = true, this.leaderboard = true, this.murajaah = true});
  @override
  List<Object?> get props => [analytics, users, leaderboard, murajaah];
}

class AnalyticsPolled extends AnalyticsEvent {
  const AnalyticsPolled();
}

class AnalyticsRefreshed extends AnalyticsEvent {
  const AnalyticsRefreshed();
}

class LeaderboardSortChanged extends AnalyticsEvent {
  final String sort; // score | khatam
  const LeaderboardSortChanged(this.sort);
  @override
  List<Object?> get props => [sort];
}

class AnalyticsState extends Equatable {
  final bool loading;
  final Map<String, dynamic>? realtime, stats;
  final List<Map<String, dynamic>> leaderboard, sessions;
  final String sort;
  final String? error;
  final int updates; // bumps on each successful poll so listeners/tests can observe it

  const AnalyticsState({
    this.loading = false,
    this.realtime,
    this.stats,
    this.leaderboard = const [],
    this.sessions = const [],
    this.sort = 'score',
    this.error,
    this.updates = 0,
  });

  AnalyticsState copyWith({
    bool? loading,
    Map<String, dynamic>? realtime,
    Map<String, dynamic>? stats,
    List<Map<String, dynamic>>? leaderboard,
    List<Map<String, dynamic>>? sessions,
    String? sort,
    String? error,
    bool clearError = false,
    int? updates,
  }) =>
      AnalyticsState(
        loading: loading ?? this.loading,
        realtime: realtime ?? this.realtime,
        stats: stats ?? this.stats,
        leaderboard: leaderboard ?? this.leaderboard,
        sessions: sessions ?? this.sessions,
        sort: sort ?? this.sort,
        error: clearError ? null : (error ?? this.error),
        updates: updates ?? this.updates,
      );

  @override
  List<Object?> get props => [loading, realtime, stats, leaderboard, sessions, sort, error, updates];
}

class AdminAnalyticsBloc extends Bloc<AnalyticsEvent, AnalyticsState> {
  AdminAnalyticsBloc(this.api, {this.pollInterval = const Duration(seconds: 15), this.onUnauthorized})
      : super(const AnalyticsState()) {
    on<AnalyticsStarted>(_start);
    on<AnalyticsPolled>(_poll);
    on<AnalyticsRefreshed>((e, emit) => _loadAll(emit));
    on<LeaderboardSortChanged>((e, emit) async {
      emit(state.copyWith(sort: e.sort));
      if (_scope.leaderboard) await _loadLeaderboard(emit);
    });
  }

  final AdminApiService api;
  final Duration pollInterval;
  final void Function()? onUnauthorized;
  AnalyticsStarted _scope = const AnalyticsStarted();
  Timer? _timer;

  Future<void> _start(AnalyticsStarted e, Emitter<AnalyticsState> emit) async {
    _scope = e;
    emit(state.copyWith(loading: true, clearError: true));
    await _loadAll(emit);
    _timer?.cancel();
    if (pollInterval > Duration.zero && e.analytics) {
      _timer = Timer.periodic(pollInterval, (_) => add(const AnalyticsPolled()));
    }
  }

  Future<T?> _try<T>(Future<T> Function() f, Emitter<AnalyticsState> emit) async {
    try {
      return await f();
    } on AdminApiException catch (err) {
      if (err.unauthorized) onUnauthorized?.call();
      emit(state.copyWith(error: err.message));
      return null;
    }
  }

  Future<void> _loadAll(Emitter<AnalyticsState> emit) async {
    emit(state.copyWith(loading: true, clearError: true));
    if (_scope.analytics) {
      final r = await _try(api.realtime, emit);
      if (r != null) emit(state.copyWith(realtime: r));
    }
    if (_scope.users) {
      final s = await _try(api.userStats, emit);
      if (s != null) emit(state.copyWith(stats: s));
    }
    if (_scope.leaderboard) await _loadLeaderboard(emit);
    if (_scope.murajaah) {
      final m = await _try(api.murajaahSessions, emit);
      if (m != null) emit(state.copyWith(sessions: (m['items'] as List).cast<Map<String, dynamic>>()));
    }
    emit(state.copyWith(loading: false, updates: state.updates + 1));
  }

  Future<void> _loadLeaderboard(Emitter<AnalyticsState> emit) async {
    final l = await _try(() => api.leaderboard(sort: state.sort), emit);
    if (l != null) emit(state.copyWith(leaderboard: (l['entries'] as List).cast<Map<String, dynamic>>()));
  }

  Future<void> _poll(AnalyticsPolled e, Emitter<AnalyticsState> emit) async {
    if (!_scope.analytics) return;
    final r = await _try(api.realtime, emit);
    if (r != null) emit(state.copyWith(realtime: r, clearError: true, updates: state.updates + 1));
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
