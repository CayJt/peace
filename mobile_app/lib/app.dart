import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bloc/reader_settings_cubit.dart';
import 'bloc/reading_tracker_bloc.dart';
import 'bloc/tajweed_assessment_bloc.dart';
import 'database/quran_database.dart';
import 'screens/auth/login_screen.dart';
import 'screens/chat/quran_chat_screen.dart';
import 'screens/history/history_dashboard_screen.dart';
import 'screens/mushaf/mushaf_page_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'services/auth_service.dart';
import 'services/mic_source.dart';
import 'services/mushaf_audit.dart';
import 'services/notification_service.dart';
import 'services/quran_api_service.dart';
import 'services/quran_chat_service.dart';
import 'services/quran_sync_manager.dart';
import 'admin_app.dart';
import 'services/admin_api_service.dart';
import 'services/user_telemetry.dart';
import 'theme/app_theme.dart';

class AppDeps {
  AppDeps({
    required this.prefs,
    required this.db,
    required this.auth,
    required this.sync,
    required this.chat,
    required this.mic,
    required this.wsBase,
    this.api,
    this.notifications,
    this.telemetry,
    this.adminApi,
  });
  final SharedPreferences prefs;
  final QuranDatabase db;
  final AuthService auth;
  final QuranSyncManager sync;
  final QuranChatService chat;
  final MicSource mic;
  final String wsBase;
  final QuranApiService? api;
  final NotificationService? notifications;
  final UserTelemetry? telemetry;
  final AdminApiService? adminApi;
}

class QuranApp extends StatefulWidget {
  const QuranApp({super.key, required this.deps});
  final AppDeps deps;

  @override
  State<QuranApp> createState() => _QuranAppState();
}

class _QuranAppState extends State<QuranApp> {
  AuthUser? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // A secure-storage failure (e.g. no keyring on a desktop) must not block the app:
    // treat it as signed out.
    widget.deps.auth.currentUser().catchError((Object _) => null).then((u) {
      if (mounted) {
        setState(() {
          _user = u;
          _loading = false;
        });
        if (u != null) widget.deps.telemetry?.start();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.deps;
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ReaderSettingsCubit(d.prefs)),
        BlocProvider(create: (_) => ReadingTrackerBloc(d.prefs)..add(const TrackerLoaded())),
        BlocProvider(create: (_) => TajweedAssessmentBloc(db: d.db, wsBase: d.wsBase)),
      ],
      child: BlocBuilder<ReaderSettingsCubit, ReaderSettings>(
        buildWhen: (a, b) => a.themeMode != b.themeMode || a.paperWarm != b.paperWarm,
        builder: (context, s) => MaterialApp(
          title: 'Al-Qur\'an',
          debugShowCheckedModeBanner: false,
          themeMode: s.themeMode,
          theme: s.paperWarm ? AppTheme.light() : AppTheme.light().copyWith(scaffoldBackgroundColor: Colors.white),
          darkTheme: AppTheme.dark(),
          onGenerateRoute: (settings) => settings.name == '/admin' && d.adminApi != null
              ? MaterialPageRoute(settings: settings, builder: (_) => AdminRoot(api: d.adminApi!, prefs: d.prefs))
              : null,
          home: _loading
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : _user == null
                  ? LoginScreen(auth: d.auth, onAuthenticated: (u) {
                      setState(() => _user = u);
                      d.telemetry?.start();
                    })
                  : Builder(builder: (ctx) => _home(ctx, _user!)),
        ),
      ),
    );
  }

  Widget _home(BuildContext context, AuthUser user) {
    final d = widget.deps;
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final tracker = context.read<ReadingTrackerBloc>();
    final settings = context.read<ReaderSettingsCubit>();
    // Providers must be re-exposed to pushed routes (they sit above the Navigator's home only).
    Widget scoped(Widget w) => MultiBlocProvider(
          providers: [BlocProvider.value(value: tracker), BlocProvider.value(value: settings)],
          child: w,
        );
    return MushafPageScreen(
      sync: d.sync,
      db: d.db,
      mic: d.mic,
      onOpenHistory: () => push(scoped(HistoryDashboardScreen(db: d.db))),
      onSessionRecorded: (page, secs, letters, score) => d.telemetry?.uploadSession(
          page: page, durationSec: secs, lettersEvaluated: letters, score: score, khatamCount: tracker.state.khatamCount),
      onSendFeedback: d.telemetry == null ? null : (cat, msg) => d.telemetry!.sendFeedback(cat, msg),
      onOpenChat: () => push(QuranChatScreen(service: d.chat, mic: d.mic)),
      onOpenSettings: () => push(scoped(SettingsScreen(
        auth: d.auth,
        user: user,
        notifications: d.notifications,
        audit: d.api == null ? null : MushafAudit(d.api!, d.db),
        onLoggedOut: () {
          Navigator.of(context).popUntil((r) => r.isFirst);
          d.telemetry?.stop();
          setState(() => _user = null);
        },
      ))),
    );
  }
}
