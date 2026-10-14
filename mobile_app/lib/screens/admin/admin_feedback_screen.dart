import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/admin/admin_feedback_bloc.dart';
import '../../services/admin_api_service.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin/admin_widgets.dart';

const _columns = [
  ('open', 'Open'),
  ('in_progress', 'In Progress'),
  ('resolved', 'Resolved'),
  ('discarded', 'Dibuang'),
];
const _categoryLabels = {'bug': 'Bug', 'suggestion': 'Saran', 'content': 'Konten', 'other': 'Lainnya'};

class AdminFeedbackScreen extends StatefulWidget {
  const AdminFeedbackScreen({super.key});

  @override
  State<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends State<AdminFeedbackScreen> {
  bool _showDiscarded = false;

  @override
  void initState() {
    super.initState();
    context.read<AdminFeedbackBloc>().add(const FeedbackLoaded());
  }

  @override
  Widget build(BuildContext context) => AdminPage(
        title: 'Kotak Saran',
        actions: [
          FilterChip(
            key: const ValueKey('show-discarded'),
            label: const Text('Tampilkan dibuang'),
            selected: _showDiscarded,
            onSelected: (v) => setState(() => _showDiscarded = v),
          ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () => context.read<AdminFeedbackBloc>().add(const FeedbackLoaded()),
            icon: const Icon(Icons.refresh),
          ),
        ],
        child: BlocBuilder<AdminFeedbackBloc, FeedbackState>(
          builder: (context, s) {
            final cols = _columns.where((c) => c.$1 != 'discarded' || _showDiscarded).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (s.error != null) ErrorBanner(s.error!, onRetry: () => context.read<AdminFeedbackBloc>().add(const FeedbackLoaded())),
              if (s.loading && s.items.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              LayoutBuilder(builder: (context, c) {
                final wide = c.maxWidth >= 900;
                final columns = [for (final col in cols) _Column(col.$1, col.$2, s)];
                if (wide) {
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final w in columns) Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: w)),
                  ]);
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final w in columns) SizedBox(width: 300, child: Padding(padding: const EdgeInsets.only(right: 12), child: w)),
                  ]),
                );
              }),
            ]);
          },
        ),
      );
}

class _Column extends StatelessWidget {
  const _Column(this.status, this.title, this.state);
  final String status, title;
  final FeedbackState state;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final items = state.byStatus(status);
    return Container(
      key: ValueKey('col-$status'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: t.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(AdminTokens.radiusCard)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: AdminTheme.statusColor(status), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: t.textTheme.titleSmall)),
          Text('${state.counts[status] ?? items.length}', key: ValueKey('count-$status'), style: t.textTheme.labelLarge),
        ]),
        const SizedBox(height: 8),
        if (items.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('Kosong'))),
        for (final i in items) _FeedbackCard(i),
      ]),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard(this.item);
  final FeedbackItem item;

  Future<void> _notes(BuildContext context) async {
    final bloc = context.read<AdminFeedbackBloc>();
    final saved = await showDialog<String>(context: context, builder: (_) => _NotesDialog(initial: item.adminNotes));
    if (saved != null) bloc.add(FeedbackNotesSaved(item.id, saved));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      key: ValueKey('fb-${item.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Chip(label: Text(_categoryLabels[item.category] ?? item.category), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
            const Spacer(),
            PopupMenuButton<String>(
              key: ValueKey('fb-menu-${item.id}'),
              tooltip: 'Pindahkan ke…',
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (v) => v == 'notes' ? _notes(context) : context.read<AdminFeedbackBloc>().add(FeedbackStatusChanged(item.id, v)),
              itemBuilder: (_) => [
                for (final c in _columns)
                  if (c.$1 != item.status) PopupMenuItem(value: c.$1, child: Text('Pindahkan ke ${c.$2}')),
                const PopupMenuItem(value: 'notes', child: Text('Catatan…')),
              ],
            ),
          ]),
          SelectableText(item.message),
          if (item.adminNotes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: t.colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(6)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.sticky_note_2_outlined, size: 14),
                const SizedBox(width: 6),
                Expanded(child: Text(item.adminNotes, style: t.textTheme.labelMedium)),
              ]),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '${item.userId == 'anonymous' ? 'Anonim' : 'Pengguna ${item.userId}'} • ${shortDate(item.createdAt)}${item.appVersion.isEmpty ? '' : ' • v${item.appVersion}'}',
            style: t.textTheme.labelSmall,
          ),
        ]),
      ),
    );
  }
}

/// Owns its controller so it is disposed only after the dialog route is fully gone.
class _NotesDialog extends StatefulWidget {
  const _NotesDialog({required this.initial});
  final String initial;

  @override
  State<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<_NotesDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Catatan admin'),
        content: TextField(key: const ValueKey('notes-field'), controller: _ctrl, maxLines: 4, maxLength: 2000, decoration: const InputDecoration(hintText: 'Catatan internal')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(key: const ValueKey('notes-save'), onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Simpan')),
        ],
      );
}
