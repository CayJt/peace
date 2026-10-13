import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

class AuthUser {
  final String email;
  final String fullName;
  const AuthUser(this.email, this.fullName);
}

/// Form validation shared by the screens and tests.
class AuthValidators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static String? email(String? v) =>
      v == null || !_email.hasMatch(v.trim()) ? 'Email tidak valid' : null;
  static String? fullName(String? v) =>
      v == null || v.trim().isEmpty ? 'Nama lengkap wajib diisi' : null;
  static String? password(String? v) =>
      v == null || v.length < 8 ? 'Minimal 8 karakter' : null;
  static String? confirm(String? v, String password) =>
      v != password ? 'Kata sandi tidak sama' : null;
  static String? required(String? v) => v == null || v.isEmpty ? 'Wajib diisi' : null;
}

class AuthService {
  AuthService({
    http.Client? client,
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
    this.baseUrl = 'http://10.0.2.2:8000',
  })  : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage(),
        _localAuth = localAuth ?? LocalAuthentication();

  final http.Client _client;
  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;
  final String baseUrl;

  static const _kToken = 'auth_token';
  static const _kUser = 'auth_user';
  static const _kBiometric = 'biometric_enabled';

  Future<AuthUser> login(String username, String password) =>
      _authenticate('/api/v1/auth/login', {'username': username.trim(), 'password': password});

  Future<AuthUser> register({required String email, required String fullName, required String password}) =>
      _authenticate('/api/v1/auth/register',
          {'email': email.trim(), 'full_name': fullName.trim(), 'password': password});

  Future<AuthUser> _authenticate(String path, Map<String, String> body) async {
    final r = await _client.post(Uri.parse('$baseUrl$path'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
    final json = jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode != 200 && r.statusCode != 201) {
      final d = json is Map ? json['detail'] : null;
      throw AuthException(d is String ? d : 'Permintaan gagal (${r.statusCode})');
    }
    final user = AuthUser(json['user']['email'], json['user']['full_name']);
    await _storage.write(key: _kToken, value: json['token']);
    await _storage.write(key: _kUser, value: jsonEncode({'e': user.email, 'n': user.fullName}));
    return user;
  }

  Future<String?> get token => _storage.read(key: _kToken);

  Future<AuthUser?> currentUser() async {
    if (await token == null) return null;
    final raw = await _storage.read(key: _kUser);
    if (raw == null) return null;
    final m = jsonDecode(raw);
    return AuthUser(m['e'], m['n']);
  }

  Future<bool> get biometricEnabled async => await _storage.read(key: _kBiometric) == 'true';

  Future<bool> get biometricAvailable async {
    try {
      return await _localAuth.canCheckBiometrics && await _localAuth.isDeviceSupported();
    } on Exception {
      return false;
    }
  }

  Future<void> setBiometricEnabled(bool on) async {
    if (on) {
      if (await token == null) throw AuthException('Masuk terlebih dahulu');
      if (!await _prompt('Aktifkan masuk dengan biometrik')) {
        throw AuthException('Verifikasi biometrik dibatalkan');
      }
    }
    await _storage.write(key: _kBiometric, value: '$on');
  }

  Future<bool> _prompt(String reason) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } on Exception {
      return false;
    }
  }

  /// Restores the stored session after a successful biometric check.
  Future<AuthUser> loginWithBiometrics() async {
    if (!await biometricEnabled) throw AuthException('Biometrik belum diaktifkan');
    if (await token == null) throw AuthException('Sesi berakhir, masuk dengan kata sandi');
    if (!await _prompt('Masuk ke Al-Qur\'an')) throw AuthException('Biometrik gagal');
    final u = await currentUser();
    if (u == null) throw AuthException('Sesi tidak ditemukan');
    return u;
  }

  /// Revokes the token server-side (best effort) and always clears local secrets.
  Future<void> logout() async {
    final t = await token;
    try {
      if (t != null) {
        await _client.post(Uri.parse('$baseUrl/api/v1/auth/logout'),
            headers: {'Authorization': 'Bearer $t'});
      }
    } on Exception {
      // Offline logout still removes local credentials.
    } finally {
      await _storage.delete(key: _kToken);
      await _storage.delete(key: _kUser);
      await _storage.delete(key: _kBiometric);
    }
  }
}
