import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/screens/admin/admin_rbac_screen.dart';
import 'package:quran_app/services/admin_api_service.dart';
import 'package:quran_app/services/admin_validators.dart';
import 'package:quran_app/theme/app_theme.dart';
import 'package:quran_app/widgets/admin/admin_dialogs.dart';

import 'admin_test_helpers.dart';
import 'fake_backend.dart';

AdminProfile profile(int id, String role, List<String> perms, {bool primary = false}) => AdminProfile(
    id: id, username: 'u$id', email: 'u$id@x.co', fullName: 'U$id', role: role, isActive: true, isPrimary: primary, permissions: perms.toSet());

final perms = [for (final k in allPerms) Permission(k, 'Izin $k')];

/// Opens [dialog] from a button and returns what it popped.
Future<ValueNotifier<T?>> openDialog<T>(WidgetTester tester, Widget dialog) async {
  AppTheme.useGoogleFonts = false;
  setSize(tester, 900, 1400);
  final result = ValueNotifier<T?>(null);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (c) => Scaffold(body: Center(child: ElevatedButton(onPressed: () async => result.value = await showDialog<T>(context: c, builder: (_) => dialog), child: const Text('open')))),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('validators', () {
    test('username', () {
      expect(AdminValidators.username('ab'), isNotNull);
      expect(AdminValidators.username('bad name'), isNotNull);
      expect(AdminValidators.username('ok_name-1.x'), isNull);
    });
    test('password counts bytes like the server (72)', () {
      expect(AdminValidators.password('1234567'), isNotNull);
      expect(AdminValidators.password('12345678'), isNull);
      expect(AdminValidators.password('a' * 72), isNull);
      expect(AdminValidators.password('a' * 73), isNotNull);
      expect(AdminValidators.password('é' * 37), isNotNull, reason: '37 × 2 bytes = 74');
    });
    test('email and confirmation', () {
      expect(AdminValidators.email('a@b'), isNotNull);
      expect(AdminValidators.email('a@b.co'), isNull);
      expect(AdminValidators.confirm('x', 'y'), isNotNull);
    });
    test('role presets mirror the backend', () {
      expect(adminRolePresets['auditor'], ['analytics.view', 'users.view', 'chats.view', 'murajaah.view']);
      expect(adminRolePresets['custom'], isEmpty);
    });
  });

  group('AddAdminDialog', () {
    final superAdmin = profile(1, 'super_admin', allPerms, primary: true);

    testWidgets('empty submit shows every field error and does not close', (tester) async {
      final r = await openDialog<NewAdminData>(tester, AddAdminDialog(permissions: perms, actor: superAdmin));
      await tester.tap(find.byKey(const ValueKey('add-submit')));
      await tester.pump();
      expect(find.text('3–32 karakter: huruf, angka, . _ -'), findsOneWidget);
      expect(find.text('Nama lengkap wajib diisi'), findsOneWidget);
      expect(find.text('Email tidak valid'), findsOneWidget);
      expect(find.text('Minimal 8 karakter'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(r.value, isNull);
    });

    testWidgets('instant feedback while typing, including password confirmation', (tester) async {
      await openDialog<NewAdminData>(tester, AddAdminDialog(permissions: perms, actor: superAdmin));
      await tester.enterText(find.byKey(const ValueKey('add-email')), 'nope');
      await tester.pump();
      expect(find.text('Email tidak valid'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('add-password')), 'Passw0rd!x');
      await tester.enterText(find.byKey(const ValueKey('add-confirm')), 'different');
      await tester.pump();
      expect(find.text('Kata sandi tidak sama'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('add-confirm')), 'Passw0rd!x');
      await tester.pump();
      expect(find.text('Kata sandi tidak sama'), findsNothing);
    });

    testWidgets('choosing a role applies its permission preset to the checkbox matrix', (tester) async {
      await openDialog<NewAdminData>(tester, AddAdminDialog(permissions: perms, actor: superAdmin));
      bool checked(String k) => tester.widget<CheckboxListTile>(find.byKey(ValueKey('add-perm-$k'))).value!;
      expect(allPerms.where(checked), isEmpty);

      await tester.tap(find.byKey(const ValueKey('add-role')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('auditor').last);
      await tester.pumpAndSettle();
      expect(allPerms.where(checked).toSet(), adminRolePresets['auditor']!.toSet());

      await tester.tap(find.byKey(const ValueKey('add-role')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('super_admin').last);
      await tester.pumpAndSettle();
      expect(allPerms.every(checked), isTrue);
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('add-perm-config.manage'))).onChanged, isNull, reason: 'super admin is implicit-all');
    });

    testWidgets('valid form returns the data with the chosen permissions', (tester) async {
      final r = await openDialog<NewAdminData>(tester, AddAdminDialog(permissions: perms, actor: superAdmin));
      await tester.enterText(find.byKey(const ValueKey('add-username')), 'newadmin');
      await tester.enterText(find.byKey(const ValueKey('add-fullname')), 'New Admin');
      await tester.enterText(find.byKey(const ValueKey('add-email')), 'new@x.co');
      await tester.enterText(find.byKey(const ValueKey('add-password')), 'Passw0rd!x');
      await tester.enterText(find.byKey(const ValueKey('add-confirm')), 'Passw0rd!x');
      await tester.tap(find.byKey(const ValueKey('add-perm-chats.view')));
      await tester.tap(find.byKey(const ValueKey('add-perm-feedback.manage')));
      await tester.tap(find.byKey(const ValueKey('add-submit')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final d = r.value!;
      expect([d.username, d.fullName, d.email, d.role], ['newadmin', 'New Admin', 'new@x.co', 'custom']);
      expect(d.permissions, ['chats.view', 'feedback.manage']);
    });

    testWidgets('a delegated admin cannot offer super_admin or permissions they lack', (tester) async {
      final mgr = profile(2, 'custom', ['admins.manage', 'chats.view']);
      await openDialog<NewAdminData>(tester, AddAdminDialog(permissions: perms, actor: mgr));
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('add-perm-chats.view'))).onChanged, isNotNull);
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('add-perm-config.manage'))).onChanged, isNull);
      await tester.tap(find.byKey(const ValueKey('add-role')));
      await tester.pumpAndSettle();
      expect(find.text('super_admin'), findsNothing);
    });
  });

  group('ResetPasswordDialog', () {
    testWidgets('validates length and confirmation, then returns the new password', (tester) async {
      final r = await openDialog<PasswordResult>(tester, const ResetPasswordDialog(username: 'editor1'));
      expect(find.byKey(const ValueKey('pw-current')), findsNothing, reason: 'super admin resetting someone else');
      await tester.tap(find.byKey(const ValueKey('pw-submit')));
      await tester.pump();
      expect(find.text('Minimal 8 karakter'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('pw-new')), 'Another#12345');
      await tester.enterText(find.byKey(const ValueKey('pw-confirm')), 'Mismatch#1234');
      await tester.pump();
      expect(find.text('Kata sandi tidak sama'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('pw-confirm')), 'Another#12345');
      await tester.tap(find.byKey(const ValueKey('pw-submit')));
      await tester.pumpAndSettle();
      expect(r.value!.newPassword, 'Another#12345');
      expect(r.value!.currentPassword, isNull);
    });

    testWidgets('own account additionally demands the current password', (tester) async {
      final r = await openDialog<PasswordResult>(tester, const ResetPasswordDialog(username: 'me', ownAccount: true));
      await tester.enterText(find.byKey(const ValueKey('pw-new')), 'Another#12345');
      await tester.enterText(find.byKey(const ValueKey('pw-confirm')), 'Another#12345');
      await tester.tap(find.byKey(const ValueKey('pw-submit')));
      await tester.pump();
      expect(find.text('Wajib diisi'), findsOneWidget);
      expect(r.value, isNull);
      await tester.enterText(find.byKey(const ValueKey('pw-current')), 'OldPass#123');
      await tester.tap(find.byKey(const ValueKey('pw-submit')));
      await tester.pumpAndSettle();
      expect(r.value!.currentPassword, 'OldPass#123');
    });
  });

  group('canEditPermission', () {
    final sup = profile(1, 'super_admin', allPerms, primary: true);
    final mgr = profile(2, 'custom', ['admins.manage', 'chats.view']);
    final tgt = profile(3, 'custom', []);

    test('super admins and the primary account are implicit-all, never edited', () {
      expect(canEditPermission(sup, sup, 'chats.view'), isFalse);
      expect(canEditPermission(mgr, profile(9, 'super_admin', allPerms), 'chats.view'), isFalse);
    });
    test('super admin can edit anyone else', () => expect(canEditPermission(sup, tgt, 'config.manage'), isTrue));
    test('a delegated admin can only hand out what they hold', () {
      expect(canEditPermission(mgr, tgt, 'chats.view'), isTrue);
      expect(canEditPermission(mgr, tgt, 'config.manage'), isFalse);
    });
    test('no self-service escalation for non-super admins', () => expect(canEditPermission(mgr, mgr, 'chats.view'), isFalse));
  });
}
