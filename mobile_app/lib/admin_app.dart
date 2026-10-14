import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bloc/admin/admin_analytics_bloc.dart';
import 'bloc/admin/admin_auth_bloc.dart';
import 'bloc/admin/admin_chats_cubit.dart';
import 'bloc/admin/admin_config_bloc.dart';
import 'bloc/admin/admin_feedback_bloc.dart';
import 'bloc/admin/admin_management_bloc.dart';
import 'bloc/admin/admin_theme_cubit.dart';
import 'screens/admin/admin_login_screen.dart';
import 'screens/admin/admin_shell.dart';
import 'services/admin_api_service.dart';
import 'theme/admin_theme.dart';

/// Isolated admin area: its own session, theme and blocs. Mounted at `/admin` in the
/// mobile app, and as the root of the web build (`lib/admin_main.dart`).
class AdminRoot extends StatelessWidget {
  const AdminRoot({super.key, required this.api, AdminSessionStore? store, this.prefs, this.pollInterval = const Duration(seconds: 15)})
      : _store = store;

  final AdminApiService api;
  final AdminSessionStore? _store;
  final SharedPreferences? prefs;
  final Duration pollInterval;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => AdminThemeCubit(prefs)),
          BlocProvider(
            create: (_) => AdminAuthBloc(api: api, store: _store ?? SecureAdminSessionStore())..add(const AdminSessionRestoreRequested()),
          ),
        ],
        child: BlocBuilder<AdminThemeCubit, AdminSurface>(
          builder: (context, surface) => Theme(
            data: AdminTheme.of(surface),
            child: Builder(
              builder: (context) => ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: BlocBuilder<AdminAuthBloc, AdminAuthState>(
                  buildWhen: (a, b) => a.status != b.status,
                  builder: (context, auth) => switch (auth.status) {
                    AdminAuthStatus.unknown => const Scaffold(body: Center(child: CircularProgressIndicator())),
                    AdminAuthStatus.loading when context.read<AdminAuthBloc>().state.profile == null =>
                      // login in flight: keep the form on screen (it shows its own spinner)
                      const AdminLoginScreen(),
                    AdminAuthStatus.authenticated => _Authenticated(api: api, pollInterval: pollInterval),
                    _ => const AdminLoginScreen(),
                  },
                ),
              ),
            ),
          ),
        ),
      );
}

class _Authenticated extends StatelessWidget {
  const _Authenticated({required this.api, required this.pollInterval});
  final AdminApiService api;
  final Duration pollInterval;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AdminAuthBloc>();
    void expired() => auth.add(const AdminSessionExpired());
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => AdminAnalyticsBloc(api, pollInterval: pollInterval, onUnauthorized: expired)),
        BlocProvider(create: (_) => AdminConfigBloc(api, onUnauthorized: expired)),
        BlocProvider(create: (_) => AdminFeedbackBloc(api, onUnauthorized: expired)),
        BlocProvider(create: (_) => AdminManagementBloc(api, onUnauthorized: expired)),
        BlocProvider(create: (_) => AdminChatsCubit(api, onUnauthorized: expired)),
      ],
      child: const AdminShell(),
    );
  }
}

/// Standalone app (web / desktop admin build).
class AdminApp extends StatelessWidget {
  const AdminApp({super.key, required this.api, this.prefs});
  final AdminApiService api;
  final SharedPreferences? prefs;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Konsol Admin Al-Qur\'an',
        debugShowCheckedModeBanner: false,
        theme: AdminTheme.of(AdminSurface.warmPaper),
        home: AdminRoot(api: api, prefs: prefs),
      );
}
