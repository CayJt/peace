import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/admin/admin_analytics_bloc.dart';
import '../../bloc/admin/admin_auth_bloc.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin/admin_widgets.dart';

class AdminLeaderboardScreen extends StatefulWidget {
  const AdminLeaderboardScreen({super.key});

  @override
  State<AdminLeaderboardScreen> createState() => _AdminLeaderboardScreenState();
}

class _AdminLeaderboardScreenState extends State<AdminLeaderboardScreen> {
  @override
  void initState() {
    super.initState();
    final a = context.read<AdminAuthBloc>().state;
    context.read<AdminAnalyticsBloc>().add(AnalyticsStarted(
        analytics: false, users: false, leaderboard: a.can('users.view'), murajaah: a.can('murajaah.view')));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AdminAuthBloc>().state;
    return AdminPage(
      title: 'Leaderboard & Murajaah',
      child: BlocBuilder<AdminAnalyticsBloc, AnalyticsState>(
        builder: (context, s) {
          final board = auth.can('users.view') ? _Board(s) : null;
          final log = auth.can('murajaah.view') ? _SessionLog(s) : null;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (s.error != null) ErrorBanner(s.error!),
            LayoutBuilder(builder: (context, c) {
              if (board != null && log != null && c.maxWidth >= 900) {
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: board),
                  const SizedBox(width: 16),
                  Expanded(child: log),
                ]);
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (board != null) board,
                if (board != null && log != null) const SizedBox(height: 16),
                if (log != null) log,
                if (board == null && log == null) const EmptyState('Tidak ada hak akses untuk data ini.'),
              ]);
            }),
          ]);
        },
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board(this.s);
  final AnalyticsState s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Peringkat', style: t.textTheme.titleMedium),
            SegmentedButton<String>(
              key: const ValueKey('lb-sort'),
              segments: const [
                ButtonSegment(value: 'score', label: Text('Skor tajwid')),
                ButtonSegment(value: 'khatam', label: Text('Khatam')),
              ],
              selected: {s.sort},
              onSelectionChanged: (v) => context.read<AdminAnalyticsBloc>().add(LeaderboardSortChanged(v.first)),
            ),
          ]),
          const SizedBox(height: 12),
          if (s.leaderboard.isEmpty) const EmptyState('Belum ada data bacaan.', icon: Icons.emoji_events_outlined),
          for (final e in s.leaderboard)
            ListTile(
              key: ValueKey('lb-${e['user_id']}'),
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: (e['rank'] as int) <= 3 ? AdminTokens.brass.withValues(alpha: 0.25) : t.colorScheme.surfaceContainer,
                child: Text('${e['rank']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              title: Text(e['name'] as String),
              subtitle: Text('${e['email']} • ${e['letters_evaluated']} huruf • ${e['sessions']} sesi'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${((e['avg_score'] as num) * 100).round()}%', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text('${e['khatam_count']}× khatam', style: t.textTheme.labelSmall),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _SessionLog extends StatelessWidget {
  const _SessionLog(this.s);
  final AnalyticsState s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Aktivitas murajaah terbaru', style: t.textTheme.titleMedium),
          Text('Ringkasan sesi; audio tidak disimpan.', style: t.textTheme.labelMedium),
          const SizedBox(height: 8),
          if (s.sessions.isEmpty) const EmptyState('Belum ada sesi.', icon: Icons.history),
          for (final m in s.sessions)
            ListTile(
              key: ValueKey('ms-${m['id']}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${m['name']} • halaman ${m['page']}'),
              subtitle: Text('${shortDate(m['created_at'] as String?)} • ${m['duration_sec']} dtk • ${m['letters_evaluated']} huruf'),
              trailing: StatusChip('${((m['score'] as num) * 100).round()}%', status: (m['score'] as num) >= 0.7 ? 'resolved' : 'open'),
            ),
        ]),
      ),
    );
  }
}
