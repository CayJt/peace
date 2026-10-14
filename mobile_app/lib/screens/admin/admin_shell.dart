import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/admin/admin_auth_bloc.dart';
import '../../bloc/admin/admin_theme_cubit.dart';
import '../../theme/admin_theme.dart';
import 'admin_chats_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_feedback_screen.dart';
import 'admin_leaderboard_screen.dart';
import 'admin_provider_screen.dart';
import 'admin_rbac_screen.dart';

class AdminDestination {
  final String id, label;
  final IconData icon;
  final bool Function(AdminAuthState) visible;
  final Widget Function() build;
  const AdminDestination(this.id, this.label, this.icon, this.visible, this.build);
}

final adminDestinations = <AdminDestination>[
  AdminDestination('dashboard', 'Ringkasan', Icons.space_dashboard_outlined, (_) => true, () => const AdminDashboardScreen()),
  AdminDestination('leaderboard', 'Leaderboard', Icons.emoji_events_outlined, (a) => a.can('users.view') || a.can('murajaah.view'), () => const AdminLeaderboardScreen()),
  AdminDestination('provider', 'Provider Qur\'an', Icons.cloud_sync_outlined, (a) => a.can('config.manage'), () => const AdminProviderScreen()),
  AdminDestination('chats', 'Audit Chat AI', Icons.forum_outlined, (a) => a.can('chats.view'), () => const AdminChatsScreen()),
  AdminDestination('feedback', 'Kotak Saran', Icons.inbox_outlined, (a) => a.can('feedback.manage'), () => const AdminFeedbackScreen()),
  AdminDestination('rbac', 'Administrator', Icons.admin_panel_settings_outlined, (a) => a.can('admins.manage'), () => const AdminRbacScreen()),
];

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AdminAuthBloc>().state;
    final dests = adminDestinations.where((d) => d.visible(auth)).toList();
    if (_index >= dests.length) _index = 0;
    final layout = adminLayoutFor(MediaQuery.sizeOf(context).width);
    final dest = dests[_index];
    // Key by destination so each page initialises (and loads) itself when selected.
    final page = KeyedSubtree(key: ValueKey('page-${dest.id}'), child: dest.build());

    void select(int i) => setState(() => _index = i);

    switch (layout) {
      case AdminLayout.desktop:
        return Scaffold(
          body: Row(children: [
            _Sidebar(dests: dests, index: _index, onSelect: select),
            VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
            Expanded(child: Column(children: [_TopBar(crumb: dest.label), Expanded(child: page)])),
          ]),
        );
      case AdminLayout.tablet:
        return Scaffold(
          body: Row(children: [
            NavigationRail(
              key: const ValueKey('admin-rail'),
              selectedIndex: _index,
              onDestinationSelected: select,
              labelType: NavigationRailLabelType.all,
              trailing: Expanded(child: Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 12), child: _ProfileMenu(compact: true)))),
              destinations: [for (final d in dests) NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label, textAlign: TextAlign.center))],
            ),
            VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
            Expanded(child: Column(children: [_TopBar(crumb: dest.label), Expanded(child: page)])),
          ]),
        );
      case AdminLayout.mobile:
        return Scaffold(
          appBar: AppBar(
            title: Text(dest.label),
            actions: const [_SurfaceMenu()],
          ),
          drawer: Drawer(
            key: const ValueKey('admin-drawer'),
            child: SafeArea(
              child: _SidebarBody(
                dests: dests,
                index: _index,
                onSelect: (i) {
                  Navigator.pop(context);
                  select(i);
                },
              ),
            ),
          ),
          body: page,
        );
    }
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.dests, required this.index, required this.onSelect});
  final List<AdminDestination> dests;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
        key: const ValueKey('admin-sidebar'),
        width: AdminTokens.sidebarWidth,
        child: _SidebarBody(dests: dests, index: index, onSelect: onSelect),
      );
}

class _SidebarBody extends StatelessWidget {
  const _SidebarBody({required this.dests, required this.index, required this.onSelect});
  final List<AdminDestination> dests;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final me = context.watch<AdminAuthBloc>().state.profile;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Al-Qur\'an', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: t.colorScheme.primary)),
          Text('Konsol Admin', style: t.textTheme.labelMedium),
          const SizedBox(height: 10),
          const ArabesqueBorder(),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
          for (var i = 0; i < dests.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                key: ValueKey('nav-${dests[i].id}'),
                selected: i == index,
                selectedTileColor: t.colorScheme.primary.withValues(alpha: 0.12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTokens.radiusControl)),
                leading: Icon(dests[i].icon),
                title: Text(dests[i].label),
                onTap: () => onSelect(i),
              ),
            ),
        ]),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          CircleAvatar(radius: 16, backgroundColor: t.colorScheme.primaryContainer, child: Text((me?.fullName.isNotEmpty ?? false) ? me!.fullName[0].toUpperCase() : '?')),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(me?.fullName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.labelLarge),
            Text(me?.role ?? '', style: t.textTheme.labelSmall),
          ])),
          IconButton(
            key: const ValueKey('admin-logout'),
            tooltip: 'Keluar',
            onPressed: () => context.read<AdminAuthBloc>().add(const AdminLogoutRequested()),
            icon: const Icon(Icons.logout),
          ),
        ]),
      ),
    ]);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.crumb});
  final String crumb;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.dividerColor))),
      child: Row(children: [
        Text('Admin', style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.chevron_right, size: 16)),
        Text(crumb, key: const ValueKey('breadcrumb'), style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        const Spacer(),
        const _SurfaceMenu(),
      ]),
    );
  }
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        const _SurfaceMenu(),
        IconButton(
          key: const ValueKey('admin-logout'),
          tooltip: 'Keluar',
          onPressed: () => context.read<AdminAuthBloc>().add(const AdminLogoutRequested()),
          icon: const Icon(Icons.logout),
        ),
      ]);
}

class _SurfaceMenu extends StatelessWidget {
  const _SurfaceMenu();

  static const _labels = {
    AdminSurface.warmPaper: 'Warm Paper',
    AdminSurface.oledCharcoal: 'OLED Charcoal',
    AdminSurface.pureWhite: 'Pure White',
  };

  @override
  Widget build(BuildContext context) => PopupMenuButton<AdminSurface>(
        key: const ValueKey('surface-menu'),
        tooltip: 'Tema',
        icon: const Icon(Icons.palette_outlined),
        onSelected: context.read<AdminThemeCubit>().select,
        itemBuilder: (_) => [
          for (final e in _labels.entries)
            CheckedPopupMenuItem(value: e.key, checked: context.read<AdminThemeCubit>().state == e.key, child: Text(e.value)),
        ],
      );
}
