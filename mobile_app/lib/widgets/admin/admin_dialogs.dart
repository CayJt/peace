import 'package:flutter/material.dart';

import '../../services/admin_api_service.dart';
import '../../services/admin_validators.dart';

class NewAdminData {
  final String username, email, fullName, password, role;
  final List<String> permissions;
  const NewAdminData(this.username, this.email, this.fullName, this.password, this.role, this.permissions);
}

/// "Tambah Admin" modal: profile fields, role (applies a preset) and a permission checkbox matrix.
/// Pops with [NewAdminData] when the form is valid.
class AddAdminDialog extends StatefulWidget {
  const AddAdminDialog({super.key, required this.permissions, required this.actor});
  final List<Permission> permissions;
  final AdminProfile actor;

  @override
  State<AddAdminDialog> createState() => _AddAdminDialogState();
}

class _AddAdminDialogState extends State<AddAdminDialog> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  String _role = 'custom';
  final _perms = <String>{};

  @override
  void dispose() {
    for (final c in [_username, _email, _name, _pass, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setRole(String r) => setState(() {
        _role = r;
        _perms
          ..clear()
          ..addAll(r == 'super_admin' ? widget.permissions.map((p) => p.key) : (adminRolePresets[r] ?? []));
      });

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, NewAdminData(_username.text.trim(), _email.text.trim(), _name.text.trim(), _pass.text, _role, _perms.toList()..sort()));
  }

  @override
  Widget build(BuildContext context) {
    final roles = adminRoles.where((r) => r != 'super_admin' || widget.actor.isSuper).toList();
    return AlertDialog(
      title: const Text('Tambah Admin'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(key: const ValueKey('add-username'), controller: _username, decoration: const InputDecoration(labelText: 'Username'), validator: AdminValidators.username),
              const SizedBox(height: 12),
              TextFormField(key: const ValueKey('add-fullname'), controller: _name, decoration: const InputDecoration(labelText: 'Nama lengkap'), validator: AdminValidators.fullName),
              const SizedBox(height: 12),
              TextFormField(key: const ValueKey('add-email'), controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email'), validator: AdminValidators.email),
              const SizedBox(height: 12),
              TextFormField(key: const ValueKey('add-password'), controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Kata sandi'), validator: AdminValidators.password, onChanged: (_) => _form.currentState?.validate()),
              const SizedBox(height: 12),
              TextFormField(key: const ValueKey('add-confirm'), controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Ulangi kata sandi'), validator: (v) => AdminValidators.confirm(v, _pass.text)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('add-role'),
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Peran'),
                items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(r))],
                onChanged: (v) => v == null ? null : _setRole(v),
              ),
              const SizedBox(height: 8),
              Text('Hak akses', style: Theme.of(context).textTheme.labelLarge),
              for (final p in widget.permissions)
                CheckboxListTile(
                  key: ValueKey('add-perm-${p.key}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.label),
                  subtitle: Text(p.key, style: Theme.of(context).textTheme.labelSmall),
                  value: _perms.contains(p.key),
                  // Super admins hold everything; others can only grant what they hold themselves.
                  onChanged: _role == 'super_admin' || !widget.actor.can(p.key)
                      ? null
                      : (v) => setState(() => v == true ? _perms.add(p.key) : _perms.remove(p.key)),
                ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(key: const ValueKey('add-submit'), onPressed: _submit, child: const Text('Simpan')),
      ],
    );
  }
}

class PasswordResult {
  final String newPassword;
  final String? currentPassword;
  const PasswordResult(this.newPassword, this.currentPassword);
}

/// Reset dialog. [ownAccount] additionally demands the current password (server rule).
class ResetPasswordDialog extends StatefulWidget {
  const ResetPasswordDialog({super.key, required this.username, this.ownAccount = false});
  final String username;
  final bool ownAccount;

  @override
  State<ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<ResetPasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    for (final c in [_current, _pass, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Reset kata sandi: ${widget.username}'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: _form,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.ownAccount) ...[
                TextFormField(key: const ValueKey('pw-current'), controller: _current, obscureText: true, decoration: const InputDecoration(labelText: 'Kata sandi saat ini'), validator: AdminValidators.required),
                const SizedBox(height: 12),
              ],
              TextFormField(key: const ValueKey('pw-new'), controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Kata sandi baru'), validator: AdminValidators.password, onChanged: (_) => _form.currentState?.validate()),
              const SizedBox(height: 12),
              TextFormField(key: const ValueKey('pw-confirm'), controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Ulangi kata sandi baru'), validator: (v) => AdminValidators.confirm(v, _pass.text)),
              const SizedBox(height: 8),
              Text('Semua sesi aktif akun ini akan diakhiri.', style: Theme.of(context).textTheme.labelMedium),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            key: const ValueKey('pw-submit'),
            onPressed: () {
              if (_form.currentState!.validate()) {
                Navigator.pop(context, PasswordResult(_pass.text, widget.ownAccount ? _current.text : null));
              }
            },
            child: const Text('Reset'),
          ),
        ],
      );
}
