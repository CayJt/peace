import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/reader_settings_cubit.dart';
import '../../bloc/reading_tracker_bloc.dart';
import '../../services/auth_service.dart';
import '../../services/mushaf_audit.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.auth,
    required this.user,
    required this.onLoggedOut,
    this.notifications,
    this.audit,
    this.habit = const ReadingHabit(),
  });

  final AuthService auth;
  final AuthUser user;
  final VoidCallback onLoggedOut;
  final NotificationService? notifications;
  final MushafAudit? audit; // QA only
  final ReadingHabit habit;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _bio = false, _bioAvailable = false;
  String? _auditResult;
  double? _auditProgress;

  @override
  void initState() {
    super.initState();
    () async {
      final on = await widget.auth.biometricEnabled;
      final av = await widget.auth.biometricAvailable;
      if (mounted) {
        setState(() {
          _bio = on;
          _bioAvailable = av;
        });
      }
    }();
  }

  Future<void> _toggleBio(bool on) async {
    try {
      await widget.auth.setBiometricEnabled(on);
      setState(() => _bio = on);
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: const Text('Sesi ini akan diakhiri dan Anda perlu masuk kembali.'),
        actions: [
          TextButton(key: const ValueKey('logout-cancel'), onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          FilledButton(
            key: const ValueKey('logout-confirm'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.auth.logout();
      widget.onLoggedOut();
    }
  }

  Future<void> _runAudit() async {
    setState(() {
      _auditProgress = 0;
      _auditResult = null;
    });
    try {
      final r = await widget.audit!.run(onProgress: (p) => setState(() => _auditProgress = p));
      setState(() => _auditResult = r.summary + (r.allAuthentic ? '' : '\n${r.problems.take(3).join('\n')}'));
    } on Exception catch (e) {
      setState(() => _auditResult = 'Audit gagal: $e');
    } finally {
      setState(() => _auditProgress = null);
    }
  }

  Future<void> _pickTime(ReaderSettings s) async {
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute));
    if (t == null || !mounted) return;
    context.read<ReaderSettingsCubit>().setReminder(on: s.remindersOn, hour: t.hour, minute: t.minute);
    if (s.remindersOn) {
      await widget.notifications?.scheduleDaily(hour: t.hour, minute: t.minute, habit: widget.habit);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cubit = context.read<ReaderSettingsCubit>();
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: BlocBuilder<ReaderSettingsCubit, ReaderSettings>(
        builder: (context, s) => ListView(
          padding: const EdgeInsets.all(AppSpacing.margin),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: t.colorScheme.primaryContainer,
                    child: Text(widget.user.fullName.isEmpty ? '?' : widget.user.fullName[0].toUpperCase(),
                        style: TextStyle(color: t.colorScheme.onPrimaryContainer, fontSize: 22)),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.user.fullName, style: t.textTheme.titleMedium),
                      Text(widget.user.email, style: t.textTheme.labelMedium),
                    ]),
                  ),
                  BlocBuilder<ReadingTrackerBloc, TrackerState>(
                    builder: (_, ts) => Chip(
                      key: const ValueKey('khatam-badge'),
                      avatar: const Icon(Icons.workspace_premium, color: AppColors.gold, size: 18),
                      label: Text('${ts.khatamCount}× khatam'),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Tampilan', style: t.textTheme.labelSmall),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<(ThemeMode, bool)>(
              key: const ValueKey('theme-switch'),
              segments: const [
                ButtonSegment(value: (ThemeMode.light, true), label: Text('Kertas'), icon: Icon(Icons.menu_book_outlined)),
                ButtonSegment(value: (ThemeMode.light, false), label: Text('Terang'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: (ThemeMode.dark, true), label: Text('Gelap'), icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {(s.themeMode == ThemeMode.system ? ThemeMode.light : s.themeMode, s.themeMode == ThemeMode.dark ? true : s.paperWarm)},
              onSelectionChanged: (v) => cubit.setThemeMode(v.first.$1, paperWarm: v.first.$2),
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              key: const ValueKey('biometric-toggle'),
              title: const Text('Masuk dengan biometrik'),
              subtitle: _bioAvailable ? null : const Text('Tidak tersedia di perangkat ini'),
              value: _bio,
              onChanged: _bioAvailable ? _toggleBio : null,
            ),
            SwitchListTile(
              title: const Text('Pengingat tilawah harian'),
              subtitle: Text('Pukul ${s.reminderHour.toString().padLeft(2, '0')}:${s.reminderMinute.toString().padLeft(2, '0')}'),
              value: s.remindersOn,
              onChanged: (on) async {
                if (on) {
                  final ok = await widget.notifications?.requestPermission() ?? true;
                  if (!ok) return;
                  await widget.notifications
                      ?.scheduleDaily(hour: s.reminderHour, minute: s.reminderMinute, habit: widget.habit);
                } else {
                  await widget.notifications?.cancel();
                }
                cubit.setReminder(on: on);
              },
            ),
            ListTile(
              title: const Text('Ubah waktu pengingat'),
              trailing: const Icon(Icons.schedule),
              onTap: () => _pickTime(s),
            ),
            if (kDebugMode)
              ListTile(
                key: const ValueKey('open-admin'),
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Konsol Admin (debug)'),
                onTap: () => Navigator.of(context).pushNamed('/admin'),
              ),
            if (!kReleaseMode && widget.audit != null) ...[
              const Divider(),
              Text('QA (non-produksi)', style: t.textTheme.labelSmall),
              ListTile(
                key: const ValueKey('audit-button'),
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Audit Mushaf Database'),
                subtitle: _auditProgress != null
                    ? LinearProgressIndicator(value: _auditProgress)
                    : _auditResult == null
                        ? const Text('SHA-256 6.236 ayat vs Quran.com API v4')
                        : Row(children: [
                            Icon(_auditResult!.startsWith('Semua') ? Icons.check_circle : Icons.error,
                                color: _auditResult!.startsWith('Semua') ? Colors.green : t.colorScheme.error, size: 18),
                            const SizedBox(width: 6),
                            Expanded(child: Text(_auditResult!)),
                          ]),
                onTap: _auditProgress == null ? _runAudit : null,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              key: const ValueKey('logout-button'),
              style: OutlinedButton.styleFrom(
                foregroundColor: t.colorScheme.error,
                side: BorderSide(color: t.colorScheme.error),
              ),
              onPressed: _confirmLogout,
              icon: const Icon(Icons.logout),
              label: const Text('Keluar'),
            ),
          ],
        ),
      ),
    );
  }
}
