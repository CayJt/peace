import 'dart:convert';

/// Client-side mirrors of the server's rules (the server stays the authority).
class AdminValidators {
  static final _username = RegExp(r'^[A-Za-z0-9_.-]{3,32}$');
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? username(String? v) =>
      v == null || !_username.hasMatch(v.trim()) ? '3–32 karakter: huruf, angka, . _ -' : null;
  static String? email(String? v) => v == null || !_email.hasMatch(v.trim()) ? 'Email tidak valid' : null;
  static String? fullName(String? v) => v == null || v.trim().isEmpty ? 'Nama lengkap wajib diisi' : null;
  static String? password(String? v) {
    if (v == null || v.length < 8) return 'Minimal 8 karakter';
    if (utf8.encode(v).length > 72) return 'Maksimal 72 byte';
    return null;
  }

  static String? confirm(String? v, String password) => v != password ? 'Kata sandi tidak sama' : null;
  static String? required(String? v) => v == null || v.isEmpty ? 'Wajib diisi' : null;
}

/// Mirrors backend `ROLE_PRESETS`.
const adminRolePresets = <String, List<String>>{
  'editor': ['analytics.view', 'users.view', 'config.manage', 'murajaah.view', 'feedback.manage'],
  'auditor': ['analytics.view', 'users.view', 'chats.view', 'murajaah.view'],
  'custom': [],
};
const adminRoles = ['super_admin', 'editor', 'auditor', 'custom'];

const permissionShortLabels = <String, String>{
  'analytics.view': 'Analitik',
  'users.view': 'Pengguna',
  'config.manage': 'Konfigurasi',
  'chats.view': 'Chat AI',
  'murajaah.view': 'Murajaah',
  'feedback.manage': 'Saran',
  'admins.manage': 'Admin',
};
