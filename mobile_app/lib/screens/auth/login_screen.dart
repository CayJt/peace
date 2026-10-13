import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth, required this.onAuthenticated});
  final AuthService auth;
  final void Function(AuthUser) onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false, _hide = true, _bio = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    () async {
      final on = await widget.auth.biometricEnabled && await widget.auth.biometricAvailable;
      if (mounted) setState(() => _bio = on);
    }();
  }

  Future<void> _run(Future<AuthUser> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      widget.onAuthenticated(await f());
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
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('بِسْمِ ٱللَّهِ', textAlign: TextAlign.center, style: AppTheme.arabicDisplay(color: t.colorScheme.primary)),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Masuk', style: t.textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const ValueKey('login-user'),
                    controller: _user,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: AuthValidators.required,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const ValueKey('login-pass'),
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
                    validator: AuthValidators.required,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(_error!, key: const ValueKey('login-error'), style: TextStyle(color: t.colorScheme.error)),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    key: const ValueKey('login-submit'),
                    onPressed: _busy
                        ? null
                        : () {
                            if (_form.currentState!.validate()) {
                              _run(() => widget.auth.login(_user.text, _pass.text));
                            }
                          },
                    child: _busy
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Masuk'),
                  ),
                  if (_bio) ...[
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      key: const ValueKey('login-biometric'),
                      onPressed: _busy ? null : () => _run(widget.auth.loginWithBiometrics),
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Masuk dengan biometrik'),
                    ),
                  ],
                  TextButton(
                    key: const ValueKey('to-register'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => RegisterScreen(auth: widget.auth, onAuthenticated: (u) {
                              Navigator.of(context).pop();
                              widget.onAuthenticated(u);
                            }))),
                    child: const Text('Belum punya akun? Daftar'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
