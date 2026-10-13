import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.auth, required this.onAuthenticated});
  final AuthService auth;
  final void Function(AuthUser) onAuthenticated;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      widget.onAuthenticated(await widget.auth
          .register(email: _email.text, fullName: _name.text, password: _pass.text));
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Exception {
      if (mounted) setState(() => _error = 'Tidak dapat terhubung ke server');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _pass, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Daftar')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _form,
            autovalidateMode: AutovalidateMode.onUserInteraction, // instant feedback
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                key: const ValueKey('reg-name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nama lengkap'),
                validator: AuthValidators.fullName,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const ValueKey('reg-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: AuthValidators.email,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const ValueKey('reg-pass'),
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Kata sandi'),
                validator: AuthValidators.password,
                onChanged: (_) => _form.currentState?.validate(),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const ValueKey('reg-confirm'),
                controller: _confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Ulangi kata sandi'),
                validator: (v) => AuthValidators.confirm(v, _pass.text),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(_error!, key: const ValueKey('reg-error'), style: TextStyle(color: t.colorScheme.error)),
                ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                key: const ValueKey('reg-submit'),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Buat akun'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
