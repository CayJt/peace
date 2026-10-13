import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/reading_tracker_bloc.dart';
import '../../database/quran_database.dart';
import '../../theme/app_theme.dart';

class HistoryData {
  final Map<String, dynamic> summary;
  final List<int> secondsPerDay;
  final List<Map<String, Object?>> recent;
  const HistoryData(this.summary, this.secondsPerDay, this.recent);
}

Future<HistoryData> loadHistory(QuranDatabase db) async =>
    HistoryData(await db.getOverallScoreSummary(), await db.secondsPerDay(), await db.recentSessions());

class HistoryDashboardScreen extends StatelessWidget {
  const HistoryDashboardScreen({super.key, required this.db, this.now});
  final QuranDatabase db;
  final DateTime? now;

  static const _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat')),
      body: FutureBuilder<HistoryData>(
        future: loadHistory(db),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final d = snap.data!;
          final avg = (d.summary['average_score'] as double) * 100;
          final today = now ?? DateTime.now();
          return ListView(padding: const EdgeInsets.all(AppSpacing.margin), children: [
            Row(children: [
              _Stat('Rata-rata skor', '${avg.round()}%', const ValueKey('stat-avg')),
              _Stat('Huruf dinilai', '${d.summary['letters_evaluated']}', const ValueKey('stat-letters')),
              BlocBuilder<ReadingTrackerBloc, TrackerState>(
                builder: (_, ts) => _Stat('Khatam', '${ts.khatamCount}', const ValueKey('stat-khatam')),
              ),
            ]),
            const SizedBox(height: AppSpacing.lg),
            Text('Aktivitas 7 hari (menit)', style: t.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 180,
              child: BarChart(BarChartData(
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final day = today.subtract(Duration(days: 6 - v.toInt()));
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_days[day.weekday - 1], style: t.textTheme.labelSmall),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < d.secondsPerDay.length; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: d.secondsPerDay[i] / 60,
                        width: 16,
                        color: t.colorScheme.primary,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ]),
                ],
              )),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Sesi terbaru', style: t.textTheme.titleMedium),
            if (d.recent.isEmpty)
              const Padding(padding: EdgeInsets.all(AppSpacing.md), child: Text('Belum ada sesi bacaan.')),
            for (final s in d.recent)
              ListTile(
                key: ValueKey('session-${s['id']}'),
                contentPadding: EdgeInsets.zero,
                title: Text('Halaman ${s['page']}'),
                subtitle: Text('${s['duration_sec']} dtk • ${s['letters_evaluated']} huruf'),
                trailing: Text('${((s['score'] as num) * 100).round()}%', style: t.textTheme.titleMedium),
              ),
          ]);
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.k);
  final String label, value;
  final Key k;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(children: [
              Text(value, key: k, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.center),
            ]),
          ),
        ),
      );
}
