import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/admin/admin_auth_bloc.dart';
import '../../services/admin_validators.dart';
import '../../theme/admin_theme.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _hide = true;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      context.read<AdminAuthBloc>().add(AdminLoginRequested(_user.text, _pass.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: BlocBuilder<AdminAuthBloc, AdminAuthState>(
              builder: (context, s) {
                final busy = s.status == AdminAuthStatus.loading;
                return Form(
                  key: _form,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Icon(Icons.admin_panel_settings_outlined, size: 44, color: t.colorScheme.primary),
                    const SizedBox(height: 8),
                    Text('Konsol Admin', textAlign: TextAlign.center, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const ArabesqueBorder(),
                    const SizedBox(height: 24),
                    TextFormField(
                      key: const ValueKey('admin-username'),
                      controller: _user,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(labelText: 'Username'),
                      validator: AdminValidators.required,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('admin-password'),
                      controller: _pass,
                      obscureText: _hide,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Kata sandi',
                        suffixIcon: IconButton(
                          tooltip: _hide ? 'Tampilkan' : 'Sembunyikan',
                          icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hide = !_hide),
                        ),
                      ),
                      validator: AdminValidators.required,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (s.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(s.error!, key: const ValueKey('admin-login-error'), style: const TextStyle(color: AdminTokens.danger)),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const ValueKey('admin-login-submit'),
                      onPressed: busy ? null : _submit,
                      child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Masuk'),
                    ),
                  ]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
