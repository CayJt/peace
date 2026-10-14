import 'package:flutter/material.dart';

import '../../theme/admin_theme.dart';

/// Scrolling page body: centred, max-width, padding by breakpoint.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key, required this.title, required this.child, this.actions = const [], this.scroll = true});
  final String title;
  final Widget child;
  final List<Widget> actions;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final layout = adminLayoutFor(MediaQuery.sizeOf(context).width);
    final pad = layout == AdminLayout.mobile ? 16.0 : 24.0;
    final header = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 8,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (actions.isNotEmpty) Wrap(spacing: 8, children: actions),
      ],
    );
    final body = Padding(
      padding: EdgeInsets.all(pad),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        const SizedBox(height: 4),
        const ArabesqueBorder(),
        const SizedBox(height: 16),
        if (scroll) child else Expanded(child: child),
      ]),
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AdminTokens.contentMaxWidth),
        child: scroll ? SingleChildScrollView(child: body) : body,
      ),
    );
  }
}

class PulseDot extends StatefulWidget {
  const PulseDot({super.key, this.color = AdminTokens.success, this.size = 10});
  final Color color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size * 2.4,
        height: widget.size * 2.4,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(painter: _PulsePainter(widget.color, _c.value, widget.size)),
        ),
      );
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.color, this.t, this.r);
  final Color color;
  final double t, r;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, r / 2 + (r * 0.7) * t, Paint()..color = color.withValues(alpha: 0.35 * (1 - t)));
    canvas.drawCircle(c, r / 2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PulsePainter o) => o.t != t || o.color != color;
}

class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.label, required this.value, this.subtitle, this.leading, this.valueKey});
  final String label, value;
  final String? subtitle;
  final Widget? leading;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.cardTheme.color,
        borderRadius: BorderRadius.circular(AdminTokens.radiusCard),
        border: Border.all(color: t.colorScheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: AdminTokens.elevation(t.brightness),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Expanded(child: Text(label, style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onSurfaceVariant))),
        ]),
        const SizedBox(height: 8),
        Text(value, key: valueKey, style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        if (subtitle != null) Text(subtitle!, style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, required this.status});
  final String label, status;

  @override
  Widget build(BuildContext context) {
    final c = AdminTheme.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('error-banner'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AdminTokens.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AdminTokens.radiusControl),
          border: Border.all(color: AdminTokens.danger.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: AdminTokens.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ]),
        ),
      );
}

String shortDate(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String body, String action = 'Ya', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(key: const ValueKey('confirm-cancel'), onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
        FilledButton(
          key: const ValueKey('confirm-ok'),
          style: danger ? FilledButton.styleFrom(backgroundColor: AdminTokens.danger) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return r ?? false;
}
