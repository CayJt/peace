import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/admin/admin_config_bloc.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin/admin_widgets.dart';

const _providerLabels = {'quran.com': 'Quran.com API v4', 'kemenag': 'Kemenag (Kementerian Agama RI)'};

class AdminProviderScreen extends StatefulWidget {
  const AdminProviderScreen({super.key});

  @override
  State<AdminProviderScreen> createState() => _AdminProviderScreenState();
}

class _AdminProviderScreenState extends State<AdminProviderScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AdminConfigBloc>().add(const ConfigLoaded());
  }

  Future<void> _select(BuildContext context, ConfigState s, String p) async {
    final bloc = context.read<AdminConfigBloc>();
    if (s.adapters[p] == false) {
      final ok = await confirmDialog(
        context,
        title: 'Adapter belum tersedia',
        body: 'Server belum memiliki adapter untuk "$p". Pilihan akan disimpan, tetapi data ayat tetap diambil dari Quran.com sampai adapter dibuat. Lanjutkan?',
        action: 'Simpan pilihan',
      );
      if (!ok) return;
    }
    bloc.add(ProviderSelected(p));
  }

  @override
  Widget build(BuildContext context) => AdminPage(
        title: 'Provider Al-Qur\'an',
        actions: [
          OutlinedButton.icon(
            key: const ValueKey('health-recheck'),
            onPressed: () => context.read<AdminConfigBloc>().add(const HealthCheckRequested()),
            icon: const Icon(Icons.network_check),
            label: const Text('Cek latensi'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('cache-clear'),
            onPressed: () async {
              final bloc = context.read<AdminConfigBloc>();
              if (await confirmDialog(context, title: 'Bersihkan cache?', body: 'Cache ayat/terjemahan di server dihapus dan diambil ulang saat dibutuhkan.', action: 'Bersihkan')) {
                bloc.add(const CacheClearRequested());
              }
            },
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Bersihkan cache'),
          ),
        ],
        child: BlocConsumer<AdminConfigBloc, ConfigState>(
          listenWhen: (a, b) => a.noticeId != b.noticeId && b.notice != null,
          listener: (context, s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.notice!))),
          builder: (context, s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (s.error != null) ErrorBanner(s.error!, onRetry: () => context.read<AdminConfigBloc>().add(const ConfigLoaded())),
            if (s.loading && s.provider == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            LayoutBuilder(builder: (context, c) {
              final cards = [for (final p in s.available) _ProviderCard(p, s, () => _select(context, s, p))];
              if (c.maxWidth >= 700) {
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final w in cards) Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: w)),
                ]);
              }
              return Column(children: [for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: w)]);
            }),
          ]),
        ),
      );
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard(this.name, this.s, this.onTap);
  final String name;
  final ConfigState s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final active = s.provider == name;
    final h = s.health[name];
    final ok = h?['ok'] == true;
    final latency = h?['latency_ms'] as int?;
    final latencyColor = latency == null ? AdminTokens.danger : (latency < 400 ? AdminTokens.success : (latency < 1200 ? AdminTokens.warning : AdminTokens.danger));
    return InkWell(
      key: ValueKey('provider-$name'),
      borderRadius: BorderRadius.circular(AdminTokens.radiusCard),
      onTap: s.loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.cardTheme.color,
          borderRadius: BorderRadius.circular(AdminTokens.radiusCard),
          border: Border.all(color: active ? t.colorScheme.primary : t.colorScheme.outlineVariant.withValues(alpha: 0.6), width: active ? 2 : 1),
          boxShadow: active ? AdminTokens.elevation(t.brightness) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(active ? Icons.radio_button_checked : Icons.radio_button_off, color: active ? t.colorScheme.primary : t.colorScheme.outline),
            const SizedBox(width: 8),
            Expanded(child: Text(_providerLabels[name] ?? name, style: t.textTheme.titleMedium)),
            if (active) const StatusChip('Aktif', status: 'active'),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 6, children: [
            StatusChip(s.adapters[name] == true ? 'Adapter aktif' : 'Adapter belum ada', status: s.adapters[name] == true ? 'active' : 'open'),
            if (s.checking && h == null)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else if (h != null)
              Container(
                key: ValueKey('latency-$name'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: latencyColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                child: Text(ok ? '${latency ?? '?'} ms' : 'Tidak terjangkau', style: t.textTheme.labelSmall?.copyWith(color: latencyColor, fontWeight: FontWeight.w700)),
              ),
          ]),
        ]),
      ),
    );
  }
}
