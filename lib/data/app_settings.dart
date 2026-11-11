import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'progress.dart';

/// Who the app is styled for. Adults get a calm, minimal look; kids get the
/// playful one (Pofuduk, emoji, tea celebrations, bouncy motion).
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

/// English accent of the read-aloud voice, picked with the flags in the
/// course drawer.
enum Accent {
  us('Amerikan', 'en-US', 'assets/flags/us.png'),
  gb('İngiliz', 'en-GB', 'assets/flags/gb.png');

  const Accent(this.label, this.locale, this.flag);
  final String label;
  final String locale;
  final String flag;
}

/// Countries a tourism worker can tick on the Turizm İngilizcesi path
/// ("Misafirlerin nereden geliyor?"), with their flag assets.
const guestCountries = {
  'gb': 'Birleşik Krallık',
  'us': 'ABD',
  'es': 'İspanya',
  'fr': 'Fransa',
  'in': 'Hindistan',
  'pk': 'Pakistan',
  'sa': 'Suudi Arabistan',
};

String flagAsset(String country) => 'assets/flags/$country.png';

class AppSettings {
  const AppSettings({
    this.mode = AppMode.adult,
    this.theme = ThemePref.system,
    this.sound = true,
    this.reduceMotion = false,
    this.accent = Accent.us,
    this.guests = const [],
  });

  final AppMode mode;
  final ThemePref theme;

  /// Short system click on answers and celebrations (haptics always run).
  final bool sound;

  /// "Animasyonları azalt": the app behaves as if the phone asked for reduced
  /// motion (no loops, bounces, steam or celebrations; screens switch instantly).
  final bool reduceMotion;

  /// Accent of the English voice.
  final Accent accent;

  /// Guest countries ticked on the tourism path (keys of [guestCountries]).
  final List<String> guests;

  bool get isKid => mode == AppMode.kid;

  AppSettings copyWith({
    AppMode? mode,
    ThemePref? theme,
    bool? sound,
    bool? reduceMotion,
    Accent? accent,
    List<String>? guests,
  }) => AppSettings(
    mode: mode ?? this.mode,
    theme: theme ?? this.theme,
    sound: sound ?? this.sound,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    accent: accent ?? this.accent,
    guests: guests ?? this.guests,
  );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'theme': theme.name,
    'sound': sound,
    'reduceMotion': reduceMotion,
    'accent': accent.name,
    'guests': guests,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    mode: AppMode.values.asNameMap()[j['mode']] ?? AppMode.adult,
    theme: ThemePref.values.asNameMap()[j['theme']] ?? ThemePref.system,
    sound: j['sound'] is bool ? j['sound'] as bool : true,
    reduceMotion: j['reduceMotion'] is bool ? j['reduceMotion'] as bool : false,
    accent: Accent.values.asNameMap()[j['accent']] ?? Accent.us,
    guests: [
      if (j['guests'] case final List<dynamic> g)
        for (final c in g)
          if (c is String && guestCountries.containsKey(c)) c,
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.mode == mode &&
      other.theme == theme &&
      other.sound == sound &&
      other.reduceMotion == reduceMotion &&
      other.accent == accent &&
      _sameList(other.guests, guests);

  static bool _sameList(List<String> a, List<String> b) =>
      a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  @override
  int get hashCode => Object.hash(mode, theme, sound, reduceMotion, accent, Object.hashAll(guests));
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
  void setAccent(Accent a) => _save(state.copyWith(accent: a));

  /// Ticks or unticks a guest country on the tourism path.
  void toggleGuest(String country) {
    final next = [...state.guests];
    if (!next.remove(country)) next.add(country);
    _save(state.copyWith(guests: next));
  }
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);
