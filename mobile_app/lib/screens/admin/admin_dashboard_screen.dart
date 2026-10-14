import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/admin/admin_analytics_bloc.dart';
import '../../bloc/admin/admin_auth_bloc.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin/admin_widgets.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  @override
  void initState() {
    super.initState();
    final a = context.read<AdminAuthBloc>().state;
    context.read<AdminAnalyticsBloc>().add(AnalyticsStarted(
        analytics: a.can('analytics.view'), users: a.can('users.view'), leaderboard: false, murajaah: false));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AdminAuthBloc>().state;
    return AdminPage(
      title: 'Ringkasan',
      actions: [
        IconButton(
          key: const ValueKey('dashboard-refresh'),
          tooltip: 'Muat ulang',
          onPressed: () => context.read<AdminAnalyticsBloc>().add(const AnalyticsRefreshed()),
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: BlocBuilder<AdminAnalyticsBloc, AnalyticsState>(
        builder: (context, s) {
          final cards = <Widget>[
            if (auth.can('analytics.view'))
              MetricCard(
                label: 'Pengguna aktif (5 menit)',
                value: '${s.realtime?['active_users'] ?? '—'}',
                valueKey: const ValueKey('metric-active'),
                subtitle: 'Koneksi WS: ${s.realtime?['active_ws_connections'] ?? '—'}',
                leading: const PulseDot(),
              ),
            if (auth.can('users.view')) ...[
              MetricCard(
                label: 'Total pengguna',
                value: '${s.stats?['total_users'] ?? '—'}',
                valueKey: const ValueKey('metric-total'),
                subtitle: '+${s.stats?['new_last_7d'] ?? 0} dalam 7 hari',
              ),
              MetricCard(label: 'Registrasi 30 hari', value: '${s.stats?['new_last_30d'] ?? '—'}'),
            ],
            if (auth.can('analytics.view'))
              MetricCard(
                label: 'Saran menunggu',
                value: '${s.realtime?['pending_feedback'] ?? '—'}',
                valueKey: const ValueKey('metric-pending'),
                subtitle: 'status: open',
                leading: const Icon(Icons.mark_email_unread_outlined, size: 16, color: AdminTokens.warning),
              ),
          ];
          final trend = (s.stats?['trend'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (s.error != null) ErrorBanner(s.error!, onRetry: () => context.read<AdminAnalyticsBloc>().add(const AnalyticsRefreshed())),
            if (cards.isEmpty)
              const EmptyState('Akun Anda belum memiliki hak akses untuk melihat metrik.')
            else
              LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 560 ? 2 : 1);
                const gap = 12.0;
                final w = (c.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(spacing: gap, runSpacing: gap, children: [for (final k in cards) SizedBox(width: w, child: k)]);
              }),
            if (trend.isNotEmpty) ...[
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Tren registrasi', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    SizedBox(height: 200, child: _TrendChart(trend)),
                  ]),
                ),
              ),
            ],
          ]);
        },
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart(this.trend);
  final List<Map<String, dynamic>> trend;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final maxY = trend.map((t) => (t['count'] as int)).fold<int>(0, (a, b) => a > b ? a : b);
    return LineChart(LineChartData(
      minY: 0,
      maxY: (maxY < 4 ? 4 : maxY + 1).toDouble(),
      gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: c.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, interval: 1, getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: Theme.of(context).textTheme.labelSmall))),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: (trend.length / 5).ceilToDouble(),
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= trend.length) return const SizedBox.shrink();
              final d = trend[i]['date'] as String;
              return Padding(padding: const EdgeInsets.only(top: 6), child: Text(d.substring(5), style: Theme.of(context).textTheme.labelSmall));
            },
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['count'] as int).toDouble())],
          isCurved: true,
          preventCurveOverShooting: true,
          color: c.primary,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: c.primary.withValues(alpha: 0.12)),
        ),
      ],
    ));
  }
}
