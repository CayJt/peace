import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/admin_api_service.dart';

abstract class ManagementEvent extends Equatable {
  const ManagementEvent();
  @override
  List<Object?> get props => [];
}

class ManagementLoaded extends ManagementEvent {
  const ManagementLoaded();
}

class AdminCreateRequested extends ManagementEvent {
  final String username, email, fullName, password, role;
  final List<String>? permissions;
  const AdminCreateRequested({
    required this.username,
    required this.email,
    required this.fullName,
    required this.password,
    required this.role,
    this.permissions,
  });
  @override
  List<Object?> get props => [username, email, fullName, role, permissions];
}

class AdminUpdateRequested extends ManagementEvent {
  final int id;
  final String? role;
  final bool? isActive;
  final List<String>? permissions;
  const AdminUpdateRequested(this.id, {this.role, this.isActive, this.permissions});
  @override
  List<Object?> get props => [id, role, isActive, permissions];
}

class AdminDeleteRequested extends ManagementEvent {
  final int id;
  const AdminDeleteRequested(this.id);
  @override
  List<Object?> get props => [id];
}

class AdminPasswordResetRequested extends ManagementEvent {
  final int id;
  final String newPassword;
  final String? currentPassword;
  const AdminPasswordResetRequested(this.id, this.newPassword, {this.currentPassword});
  @override
  List<Object?> get props => [id];
}

class ManagementState extends Equatable {
  final bool loading, busy;
  final List<AdminProfile> admins;
  final List<Permission> permissions;
  final String? error, notice;
  final int noticeId;

  const ManagementState({
    this.loading = false,
    this.busy = false,
    this.admins = const [],
    this.permissions = const [],
    this.error,
    this.notice,
    this.noticeId = 0,
  });

  ManagementState copyWith({
    bool? loading,
    bool? busy,
    List<AdminProfile>? admins,
    List<Permission>? permissions,
    String? error,
    String? notice,
    bool clearError = false,
  }) =>
      ManagementState(
        loading: loading ?? this.loading,
        busy: busy ?? this.busy,
        admins: admins ?? this.admins,
        permissions: permissions ?? this.permissions,
        error: clearError ? null : (error ?? this.error),
        notice: notice,
        noticeId: notice != null ? noticeId + 1 : noticeId,
      );

  @override
  List<Object?> get props => [
        loading, busy, admins.map((a) => (a.id, a.role, a.isActive, a.permissions.toList()..sort())).toList(),
        permissions.length, error, notice, noticeId,
      ];
}

class AdminManagementBloc extends Bloc<ManagementEvent, ManagementState> {
  AdminManagementBloc(this.api, {this.onUnauthorized}) : super(const ManagementState()) {
    on<ManagementLoaded>((e, emit) async {
      emit(state.copyWith(loading: true, clearError: true));
      await _run(emit, () async {
        final perms = state.permissions.isEmpty ? await api.permissionsList() : state.permissions;
        emit(state.copyWith(permissions: perms, admins: await api.administrators()));
      });
      emit(state.copyWith(loading: false));
    });
    on<AdminCreateRequested>((e, emit) => _mutate(emit, 'Administrator ditambahkan', () => api.createAdmin(
        username: e.username, email: e.email, fullName: e.fullName, password: e.password, role: e.role,
        permissions: e.permissions)));
    on<AdminUpdateRequested>((e, emit) => _mutate(emit, 'Perubahan disimpan',
        () => api.updateAdmin(e.id, role: e.role, isActive: e.isActive, permissions: e.permissions)));
    on<AdminDeleteRequested>((e, emit) => _mutate(emit, 'Administrator dihapus', () => api.deleteAdmin(e.id)));
    on<AdminPasswordResetRequested>((e, emit) => _mutate(
        emit, 'Kata sandi diperbarui', () => api.setPassword(e.id, e.newPassword, currentPassword: e.currentPassword)));
  }

  final AdminApiService api;
  final void Function()? onUnauthorized;

  Future<void> _run(Emitter<ManagementState> emit, Future<void> Function() f) async {
    try {
      await f();
    } on AdminApiException catch (err) {
      if (err.unauthorized) onUnauthorized?.call();
      emit(state.copyWith(error: err.message));
    }
  }

  Future<void> _mutate(Emitter<ManagementState> emit, String ok, Future<Object?> Function() f) async {
    emit(state.copyWith(busy: true, clearError: true));
    var succeeded = false;
    await _run(emit, () async {
      await f();
      succeeded = true;
    });
    if (succeeded) {
      await _run(emit, () async => emit(state.copyWith(admins: await api.administrators(), notice: ok)));
    }
    emit(state.copyWith(busy: false));
  }
}
