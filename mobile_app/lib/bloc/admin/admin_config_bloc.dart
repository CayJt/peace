import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/admin_api_service.dart';

abstract class ConfigEvent extends Equatable {
  const ConfigEvent();
  @override
  List<Object?> get props => [];
}

class ConfigLoaded extends ConfigEvent {
  const ConfigLoaded();
}

class ProviderSelected extends ConfigEvent {
  final String provider;
  const ProviderSelected(this.provider);
  @override
  List<Object?> get props => [provider];
}

class HealthCheckRequested extends ConfigEvent {
  const HealthCheckRequested();
}

class CacheClearRequested extends ConfigEvent {
  const CacheClearRequested();
}

class ConfigState extends Equatable {
  final bool loading, checking;
  final String? provider, error, notice;
  final List<String> available;
  final Map<String, bool> adapters;
  final Map<String, Map<String, dynamic>> health; // name -> {ok, latency_ms, status_code, error}
  final int noticeId;

  const ConfigState({
    this.loading = false,
    this.checking = false,
    this.provider,
    this.error,
    this.notice,
    this.available = const [],
    this.adapters = const {},
    this.health = const {},
    this.noticeId = 0,
  });

  ConfigState copyWith({
    bool? loading,
    bool? checking,
    String? provider,
    String? error,
    String? notice,
    List<String>? available,
    Map<String, bool>? adapters,
    Map<String, Map<String, dynamic>>? health,
    bool clearError = false,
  }) =>
      ConfigState(
        loading: loading ?? this.loading,
        checking: checking ?? this.checking,
        provider: provider ?? this.provider,
        error: clearError ? null : (error ?? this.error),
        notice: notice,
        available: available ?? this.available,
        adapters: adapters ?? this.adapters,
        health: health ?? this.health,
        noticeId: notice != null ? noticeId + 1 : noticeId,
      );

  @override
  List<Object?> get props => [loading, checking, provider, error, notice, available, adapters, health, noticeId];
}

class AdminConfigBloc extends Bloc<ConfigEvent, ConfigState> {
  AdminConfigBloc(this.api, {this.onUnauthorized}) : super(const ConfigState()) {
    on<ConfigLoaded>((e, emit) async {
      emit(state.copyWith(loading: true, clearError: true));
      await _guard(emit, () async => _apply(emit, await api.quranProvider()));
      emit(state.copyWith(loading: false));
      add(const HealthCheckRequested());
    });
    on<ProviderSelected>((e, emit) async {
      if (e.provider == state.provider) return;
      emit(state.copyWith(loading: true, clearError: true));
      await _guard(emit, () async {
        _apply(emit, await api.setQuranProvider(e.provider));
        emit(state.copyWith(notice: 'Provider diganti ke ${e.provider}'));
      });
      emit(state.copyWith(loading: false));
    });
    on<HealthCheckRequested>((e, emit) async {
      emit(state.copyWith(checking: true));
      await _guard(emit, () async {
        final h = await api.providerHealth();
        emit(state.copyWith(
            health: (h['providers'] as Map).map((k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)))));
      });
      emit(state.copyWith(checking: false));
    });
    on<CacheClearRequested>((e, emit) async {
      await _guard(emit, () async {
        final n = await api.clearCache();
        emit(state.copyWith(notice: 'Cache dibersihkan ($n entri)'));
      });
    });
  }

  final AdminApiService api;
  final void Function()? onUnauthorized;

  void _apply(Emitter<ConfigState> emit, Map<String, dynamic> j) => emit(state.copyWith(
        provider: j['provider'] as String,
        available: (j['available'] as List).cast<String>(),
        adapters: (j['adapter_implemented'] as Map).map((k, v) => MapEntry(k as String, v as bool)),
      ));

  Future<void> _guard(Emitter<ConfigState> emit, Future<void> Function() f) async {
    try {
      await f();
    } on AdminApiException catch (err) {
      if (err.unauthorized) onUnauthorized?.call();
      emit(state.copyWith(error: err.message));
    }
  }
}
