import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/admin/admin_chats_cubit.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin/admin_widgets.dart';

class AdminChatsScreen extends StatefulWidget {
  const AdminChatsScreen({super.key});

  @override
  State<AdminChatsScreen> createState() => _AdminChatsScreenState();
}

class _AdminChatsScreenState extends State<AdminChatsScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<AdminChatsCubit>().load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(Map<String, dynamic> m) {
    final verses = (m['referenced_verses'] as List).cast<Map<String, dynamic>>();
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        key: const ValueKey('chat-audit-dialog'),
        title: Row(children: [
          const Expanded(child: Text('Audit percakapan')),
          StatusChip(m['is_guardrail_triggered'] == true ? 'Guardrail aktif' : 'Dijawab', status: m['is_guardrail_triggered'] == true ? 'open' : 'resolved'),
        ]),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${shortDate(m['created_at'] as String?)} • pengguna ${m['user_id']}', style: Theme.of(c).textTheme.labelMedium),
              const SizedBox(height: 12),
              Text('Pertanyaan', style: Theme.of(c).textTheme.labelLarge),
              SelectableText(m['question'] as String),
              const SizedBox(height: 12),
              Text('Jawaban', style: Theme.of(c).textTheme.labelLarge),
              SelectableText(m['answer'] as String),
              const SizedBox(height: 12),
              Text('Referensi ayat (${verses.length})', style: Theme.of(c).textTheme.labelLarge),
              if (verses.isEmpty) const Text('Tidak ada ayat yang dirujuk.'),
              for (final v in verses)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${v['verse_key']}', style: Theme.of(c).textTheme.labelLarge),
                      Directionality(textDirection: TextDirection.rtl, child: SelectableText('${v['text']}', style: const TextStyle(fontSize: 20, height: 1.8))),
                      Text('${v['translation']}'),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tutup'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AdminPage(
        title: 'Audit Chat AI',
        child: BlocBuilder<AdminChatsCubit, ChatsState>(
          builder: (context, s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (s.error != null) ErrorBanner(s.error!, onRetry: () => context.read<AdminChatsCubit>().load()),
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 320,
                child: TextField(
                  key: const ValueKey('chat-search'),
                  controller: _search,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari pertanyaan/jawaban', isDense: true),
                  onSubmitted: (v) => context.read<AdminChatsCubit>().load(query: v.trim()),
                ),
              ),
              FilterChip(
                key: const ValueKey('chat-guardrail-filter'),
                label: Text('Guardrail aktif (${s.guardrailTotal})'),
                selected: s.guardrailOnly,
                onSelected: (v) => context.read<AdminChatsCubit>().load(guardrailOnly: v),
              ),
              Text('${s.total} dari ${s.allTotal} percakapan', style: Theme.of(context).textTheme.labelMedium),
            ]),
            const SizedBox(height: 12),
            if (s.loading && s.items.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            if (!s.loading && s.items.isEmpty && s.error == null) const EmptyState('Belum ada percakapan.', icon: Icons.chat_bubble_outline),
            for (final m in s.items)
              Card(
                key: ValueKey('chat-${m['id']}'),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => _open(m),
                  title: Text(m['question'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${m['answer']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (m['is_guardrail_triggered'] == true)
                      const Icon(Icons.shield_outlined, color: AdminTokens.warning, size: 18)
                    else
                      const Icon(Icons.check_circle_outline, color: AdminTokens.success, size: 18),
                    Text(shortDate(m['created_at'] as String?), style: Theme.of(context).textTheme.labelSmall),
                  ]),
                ),
              ),
          ]),
        ),
      );
}
