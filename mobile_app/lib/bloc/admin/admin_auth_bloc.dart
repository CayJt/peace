import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../services/admin_api_service.dart';

/// Where the admin JWT is kept (secure storage in production, fake in tests).
abstract class AdminSessionStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureAdminSessionStore implements AdminSessionStore {
  SecureAdminSessionStore([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  static const _k = 'admin_token';

  @override
  Future<String?> read() async {
    try {
      return await _s.read(key: _k);
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> write(String token) async {
    try {
      await _s.write(key: _k, value: token);
    } on Exception {
      // session then lasts only until the app closes
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _s.delete(key: _k);
    } on Exception {
      // nothing to clear
    }
  }
}

abstract class AdminAuthEvent extends Equatable {
  const AdminAuthEvent();
  @override
  List<Object?> get props => [];
}

class AdminSessionRestoreRequested extends AdminAuthEvent {
  const AdminSessionRestoreRequested();
}

class AdminLoginRequested extends AdminAuthEvent {
  final String username, password;
  const AdminLoginRequested(this.username, this.password);
  @override
  List<Object?> get props => [username, password];
}

class AdminLogoutRequested extends AdminAuthEvent {
  const AdminLogoutRequested();
}

/// Raised by any screen when the API answers 401 (expired/revoked token).
class AdminSessionExpired extends AdminAuthEvent {
  const AdminSessionExpired();
}

/// Re-reads /auth/me (e.g. after permissions were edited).
class AdminProfileRefreshed extends AdminAuthEvent {
  const AdminProfileRefreshed();
}

enum AdminAuthStatus { unknown, loading, authenticated, unauthenticated }

class AdminAuthState extends Equatable {
  final AdminAuthStatus status;
  final AdminProfile? profile;
  final String? error;
  const AdminAuthState({this.status = AdminAuthStatus.unknown, this.profile, this.error});

  bool can(String permission) => profile?.can(permission) ?? false;

  @override
  List<Object?> get props =>
      [status, profile?.id, (profile?.permissions.toList() ?? [])..sort(), profile?.role, error];
}

class AdminAuthBloc extends Bloc<AdminAuthEvent, AdminAuthState> {
  AdminAuthBloc({required this.api, required this.store}) : super(const AdminAuthState()) {
    api.tokenProvider = () => _token;
    on<AdminSessionRestoreRequested>(_restore);
    on<AdminLoginRequested>(_login);
    on<AdminLogoutRequested>(_logout);
    on<AdminSessionExpired>((e, emit) async {
      await _drop();
      emit(const AdminAuthState(status: AdminAuthStatus.unauthenticated, error: 'Sesi berakhir, silakan masuk kembali'));
    });
    on<AdminProfileRefreshed>(_refresh);
  }

  final AdminApiService api;
  final AdminSessionStore store;
  String? _token;

  Future<void> _drop() async {
    _token = null;
    await store.clear();
  }

  Future<void> _restore(AdminSessionRestoreRequested e, Emitter<AdminAuthState> emit) async {
    _token = await store.read();
    if (_token == null) {
      emit(const AdminAuthState(status: AdminAuthStatus.unauthenticated));
      return;
    }
    // stays `unknown` (full-screen spinner) while the stored token is verified
    try {
      emit(AdminAuthState(status: AdminAuthStatus.authenticated, profile: await api.me()));
    } on AdminApiException catch (err) {
      if (err.unauthorized) await _drop();
      emit(AdminAuthState(status: AdminAuthStatus.unauthenticated, error: err.unauthorized ? null : err.message));
    }
  }

  Future<void> _login(AdminLoginRequested e, Emitter<AdminAuthState> emit) async {
    emit(const AdminAuthState(status: AdminAuthStatus.loading));
    try {
      final (token, profile) = await api.login(e.username, e.password);
      _token = token;
      await store.write(token);
      emit(AdminAuthState(status: AdminAuthStatus.authenticated, profile: profile));
    } on AdminApiException catch (err) {
      emit(AdminAuthState(
        status: AdminAuthStatus.unauthenticated,
        error: err.statusCode == 401
            ? 'Username atau kata sandi salah'
            : err.statusCode == 429
                ? 'Terlalu banyak percobaan. Coba lagi nanti.'
                : err.message,
      ));
    }
  }

  Future<void> _logout(AdminLogoutRequested e, Emitter<AdminAuthState> emit) async {
    await _drop();
    emit(const AdminAuthState(status: AdminAuthStatus.unauthenticated));
  }

  Future<void> _refresh(AdminProfileRefreshed e, Emitter<AdminAuthState> emit) async {
    try {
      emit(AdminAuthState(status: AdminAuthStatus.authenticated, profile: await api.me()));
    } on AdminApiException catch (err) {
      if (err.unauthorized) add(const AdminSessionExpired());
    }
  }
}
