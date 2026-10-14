import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/admin_theme.dart';

class AdminThemeCubit extends Cubit<AdminSurface> {
  AdminThemeCubit([this._prefs]) : super(_initial(_prefs));
  final SharedPreferences? _prefs;

  static AdminSurface _initial(SharedPreferences? p) {
    final v = p?.getString('admin_surface');
    return AdminSurface.values.where((s) => s.name == v).firstOrNull ?? AdminSurface.warmPaper;
  }

  void select(AdminSurface s) {
    _prefs?.setString('admin_surface', s.name);
    emit(s);
  }
}
