import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/admin/admin_auth_bloc.dart';
import '../../bloc/admin/admin_management_bloc.dart';
import '../../services/admin_api_service.dart';
import '../../services/admin_validators.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin/admin_dialogs.dart';
import '../../widgets/admin/admin_widgets.dart';

class AdminRbacScreen extends StatefulWidget {
  const AdminRbacScreen({super.key});

  @override
  State<AdminRbacScreen> createState() => _AdminRbacScreenState();
}

class _AdminRbacScreenState extends State<AdminRbacScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AdminManagementBloc>().add(const ManagementLoaded());
  }

  Future<void> _add(BuildContext context, ManagementState s, AdminProfile me) async {
    final bloc = context.read<AdminManagementBloc>();
    final data = await showDialog<NewAdminData>(context: context, builder: (_) => AddAdminDialog(permissions: s.permissions, actor: me));
    if (data != null) {
      bloc.add(AdminCreateRequested(
        username: data.username, email: data.email, fullName: data.fullName, password: data.password,
        role: data.role, permissions: data.role == 'super_admin' ? null : data.permissions,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AdminAuthBloc>().state.profile;
    return BlocConsumer<AdminManagementBloc, ManagementState>(
      listenWhen: (a, b) => a.noticeId != b.noticeId && b.notice != null,
      listener: (context, s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.notice!))),
      builder: (context, s) => AdminPage(
        title: 'Administrator & RBAC',
        actions: [
          FilledButton.icon(
            key: const ValueKey('add-admin'),
            onPressed: me == null || s.permissions.isEmpty ? null : () => _add(context, s, me),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Tambah Admin'),
          ),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (s.error != null) ErrorBanner(s.error!, onRetry: () => context.read<AdminManagementBloc>().add(const ManagementLoaded())),
          if (s.loading && s.admins.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          if (me != null)
            LayoutBuilder(builder: (context, c) => c.maxWidth >= 900
                ? _Matrix(s, me)
                : Column(children: [for (final a in s.admins) _AdminCard(a, s, me)])),
        ]),
      ),
    );
  }
}

/// Which permission checkboxes the actor may toggle on [target].
bool canEditPermission(AdminProfile actor, AdminProfile target, String key) {
  if (target.isSuper || target.isPrimary) return false; // implicit "all"
  if (target.id == actor.id && !actor.isSuper) return false; // no self-service escalation
  return actor.can(key); // you can only grant/revoke what you hold
}

Future<void> _togglePerm(BuildContext context, AdminProfile a, String key, bool on) async {
  final next = {...a.permissions};
  on ? next.add(key) : next.remove(key);
  context.read<AdminManagementBloc>().add(AdminUpdateRequested(a.id, permissions: next.toList()..sort(), role: a.role == 'custom' ? null : 'custom'));
}

Future<void> _reset(BuildContext context, AdminProfile a, AdminProfile me) async {
  final bloc = context.read<AdminManagementBloc>();
  final r = await showDialog<PasswordResult>(context: context, builder: (_) => ResetPasswordDialog(username: a.username, ownAccount: a.id == me.id));
  if (r != null) bloc.add(AdminPasswordResetRequested(a.id, r.newPassword, currentPassword: r.currentPassword));
}

Future<void> _delete(BuildContext context, AdminProfile a) async {
  final bloc = context.read<AdminManagementBloc>();
  if (await confirmDialog(context, title: 'Hapus ${a.username}?', body: 'Akun dan seluruh hak aksesnya dihapus permanen.', action: 'Hapus', danger: true)) {
    bloc.add(AdminDeleteRequested(a.id));
  }
}

class _Actions extends StatelessWidget {
  const _Actions(this.a, this.me);
  final AdminProfile a, me;

  @override
  Widget build(BuildContext context) {
    final mayManageTarget = me.isSuper || !a.isSuper;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Switch(
        key: ValueKey('active-${a.id}'),
        value: a.isActive,
        onChanged: a.isPrimary || a.id == me.id || !mayManageTarget
            ? null
            : (v) => context.read<AdminManagementBloc>().add(AdminUpdateRequested(a.id, isActive: v)),
      ),
      IconButton(
        key: ValueKey('reset-${a.id}'),
        tooltip: 'Reset kata sandi',
        onPressed: me.isSuper || a.id == me.id ? () => _reset(context, a, me) : null,
        icon: const Icon(Icons.lock_reset),
      ),
      IconButton(
        key: ValueKey('delete-${a.id}'),
        tooltip: a.isPrimary ? 'Akun utama tidak dapat dihapus' : 'Hapus',
        onPressed: a.isPrimary || a.id == me.id || !mayManageTarget ? null : () => _delete(context, a),
        icon: Icon(Icons.delete_outline, color: a.isPrimary || a.id == me.id || !mayManageTarget ? null : AdminTokens.danger),
      ),
    ]);
  }
}

class _Matrix extends StatelessWidget {
  const _Matrix(this.s, this.me);
  final ManagementState s;
  final AdminProfile me;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const ValueKey('rbac-matrix'),
          columnSpacing: 14,
          horizontalMargin: 12,
          columns: [
            const DataColumn(label: Text('Administrator')),
            const DataColumn(label: Text('Peran')),
            for (final p in s.permissions) DataColumn(label: Tooltip(message: p.label, child: Text(permissionShortLabels[p.key] ?? p.key))),
            const DataColumn(label: Text('Aksi')),
          ],
          rows: [
            for (final a in s.admins)
              DataRow(key: ValueKey('row-${a.id}'), cells: [
                DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Text(a.fullName, style: t.textTheme.titleSmall), if (a.isPrimary) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.verified, size: 14, color: AdminTokens.brass))]),
                  Text('@${a.username}', style: t.textTheme.labelSmall),
                ])),
                DataCell(StatusChip(a.role, status: a.isActive ? 'active' : 'inactive')),
                for (final p in s.permissions)
                  DataCell(Checkbox(
                    key: ValueKey('perm-${a.id}-${p.key}'),
                    value: a.can(p.key),
                    onChanged: canEditPermission(me, a, p.key) && !s.busy ? (v) => _togglePerm(context, a, p.key, v ?? false) : null,
                  )),
                DataCell(_Actions(a, me)),
              ]),
          ],
        ),
      ),
    );
  }
}

class _AdminCard extends StatelessWidget {
  const _AdminCard(this.a, this.s, this.me);
  final AdminProfile a, me;
  final ManagementState s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      key: ValueKey('card-${a.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(a.fullName, style: t.textTheme.titleSmall)),
                if (a.isPrimary) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.verified, size: 14, color: AdminTokens.brass)),
              ]),
              Text('@${a.username} • ${a.email}', style: t.textTheme.labelSmall),
            ])),
            StatusChip(a.role, status: a.isActive ? 'active' : 'inactive'),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 0, children: [
            for (final p in s.permissions)
              FilterChip(
                key: ValueKey('perm-${a.id}-${p.key}'),
                label: Text(permissionShortLabels[p.key] ?? p.key),
                selected: a.can(p.key),
                onSelected: canEditPermission(me, a, p.key) && !s.busy ? (v) => _togglePerm(context, a, p.key, v) : null,
              ),
          ]),
          Align(alignment: Alignment.centerRight, child: _Actions(a, me)),
        ]),
      ),
    );
  }
}
