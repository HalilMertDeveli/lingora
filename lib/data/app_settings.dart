import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'progress.dart';

/// Who the app is styled for. Adults get a calm, minimal look; kids get the
/// playful one (mascot, emoji, confetti, bouncy motion).
enum AppMode {
  adult('Yetişkin'),
  kid('Çocuk');

  const AppMode(this.label);
  final String label;
}

/// Light / dark preference. [system] follows the phone setting.
enum ThemePref {
  system('Sistem'),
  light('Açık'),
  dark('Koyu');

  const ThemePref(this.label);
  final String label;
}

class AppSettings {
  const AppSettings({
    this.mode = AppMode.adult,
    this.theme = ThemePref.system,
    this.sound = true,
    this.reduceMotion = false,
  });

  final AppMode mode;
  final ThemePref theme;

  /// Short system click on answers and celebrations (haptics always run).
  final bool sound;

  /// "Animasyonları azalt": the app behaves as if the phone asked for reduced
  /// motion (no loops, bounces or confetti; screens switch instantly).
  final bool reduceMotion;

  bool get isKid => mode == AppMode.kid;

  AppSettings copyWith({AppMode? mode, ThemePref? theme, bool? sound, bool? reduceMotion}) => AppSettings(
    mode: mode ?? this.mode,
    theme: theme ?? this.theme,
    sound: sound ?? this.sound,
    reduceMotion: reduceMotion ?? this.reduceMotion,
  );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'theme': theme.name,
    'sound': sound,
    'reduceMotion': reduceMotion,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    mode: AppMode.values.asNameMap()[j['mode']] ?? AppMode.adult,
    theme: ThemePref.values.asNameMap()[j['theme']] ?? ThemePref.system,
    sound: j['sound'] is bool ? j['sound'] as bool : true,
    reduceMotion: j['reduceMotion'] is bool ? j['reduceMotion'] as bool : false,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.mode == mode &&
      other.theme == theme &&
      other.sound == sound &&
      other.reduceMotion == reduceMotion;

  @override
  int get hashCode => Object.hash(mode, theme, sound, reduceMotion);
}

/// Display settings, stored apart from learning progress under `settings_v1`
/// so resetting progress keeps them.
class AppSettingsNotifier extends Notifier<AppSettings> {
  static const key = 'settings_v1';

  @override
  AppSettings build() {
    final raw = ref.read(prefsProvider).getString(key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const AppSettings();
    }
  }

  void _save(AppSettings s) {
    state = s;
    ref.read(prefsProvider).setString(key, jsonEncode(s.toJson()));
  }

  void setMode(AppMode mode) => _save(state.copyWith(mode: mode));
  void setTheme(ThemePref theme) => _save(state.copyWith(theme: theme));
  void setSound(bool on) => _save(state.copyWith(sound: on));
  void setReduceMotion(bool on) => _save(state.copyWith(reduceMotion: on));
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);
