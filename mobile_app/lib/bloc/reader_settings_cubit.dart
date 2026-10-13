import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReaderSettings extends Equatable {
  final bool tajweedColors;
  final bool translation;
  final bool tahfidz;
  final bool mic;
  final ThemeMode themeMode;
  final bool paperWarm; // warm paper vs pure white in light mode
  final int reminderHour;
  final int reminderMinute;
  final bool remindersOn;

  const ReaderSettings({
    this.tajweedColors = true,
    this.translation = false,
    this.tahfidz = false,
    this.mic = false,
    this.themeMode = ThemeMode.system,
    this.paperWarm = true,
    this.reminderHour = 5,
    this.reminderMinute = 0,
    this.remindersOn = false,
  });

  ReaderSettings copyWith({
    bool? tajweedColors,
    bool? translation,
    bool? tahfidz,
    bool? mic,
    ThemeMode? themeMode,
    bool? paperWarm,
    int? reminderHour,
    int? reminderMinute,
    bool? remindersOn,
  }) =>
      ReaderSettings(
        tajweedColors: tajweedColors ?? this.tajweedColors,
        translation: translation ?? this.translation,
        tahfidz: tahfidz ?? this.tahfidz,
        mic: mic ?? this.mic,
        themeMode: themeMode ?? this.themeMode,
        paperWarm: paperWarm ?? this.paperWarm,
        reminderHour: reminderHour ?? this.reminderHour,
        reminderMinute: reminderMinute ?? this.reminderMinute,
        remindersOn: remindersOn ?? this.remindersOn,
      );

  @override
  List<Object?> get props =>
      [tajweedColors, translation, tahfidz, mic, themeMode, paperWarm, reminderHour, reminderMinute, remindersOn];
}

class ReaderSettingsCubit extends Cubit<ReaderSettings> {
  ReaderSettingsCubit(this._prefs)
      : super(ReaderSettings(
          tajweedColors: _prefs.getBool('tajweed') ?? true,
          translation: _prefs.getBool('translation') ?? false,
          themeMode: ThemeMode.values.byName(_prefs.getString('theme') ?? 'system'),
          paperWarm: _prefs.getBool('paper_warm') ?? true,
          reminderHour: _prefs.getInt('rem_h') ?? 5,
          reminderMinute: _prefs.getInt('rem_m') ?? 0,
          remindersOn: _prefs.getBool('rem_on') ?? false,
        ));

  final SharedPreferences _prefs;

  void toggleTajweed() {
    _prefs.setBool('tajweed', !state.tajweedColors);
    emit(state.copyWith(tajweedColors: !state.tajweedColors));
  }

  void toggleTranslation() {
    _prefs.setBool('translation', !state.translation);
    emit(state.copyWith(translation: !state.translation));
  }

  // Tahfidz and mic are per-session on purpose: never persisted.
  void toggleTahfidz() => emit(state.copyWith(tahfidz: !state.tahfidz));
  void setMic(bool on) => emit(state.copyWith(mic: on));

  void setThemeMode(ThemeMode m, {bool? paperWarm}) {
    _prefs.setString('theme', m.name);
    if (paperWarm != null) _prefs.setBool('paper_warm', paperWarm);
    emit(state.copyWith(themeMode: m, paperWarm: paperWarm));
  }

  void setReminder({required bool on, int? hour, int? minute}) {
    _prefs.setBool('rem_on', on);
    if (hour != null) _prefs.setInt('rem_h', hour);
    if (minute != null) _prefs.setInt('rem_m', minute);
    emit(state.copyWith(remindersOn: on, reminderHour: hour, reminderMinute: minute));
  }
}
