import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import 'turn_taking.dart';
import 'voice_catalog.dart';

/// The learner's choices for the voice conversation (kept on the device).
class VoiceSettings {
  const VoiceSettings({
    this.voice = defaultVoiceId,
    this.characterVoices = const {},
    this.bargeIn = true,
    this.pauseMs = 700,
    this.level,
  });

  /// Neural voice for scenarios and free talk.
  final String voice;

  /// A different voice for a character (character id -> voice id).
  final Map<String, String> characterVoices;

  /// The learner may interrupt the partner by speaking.
  final bool bargeIn;

  /// Pause (ms) that ends the learner's turn.
  final int pauseMs;

  /// CEFR level the partner speaks at ("A2"); null = from the level karne.
  final String? level;

  static const pauseChoices = [700, 1000, 1200, 1500];

  String voiceFor(Character? c) => c == null ? voice : (characterVoices[c.id] ?? c.voice);

  /// Eller serbest is the only mode: listening opens by itself and a turn
  /// ends after the pause (an old "handsFree" value is ignored).
  TurnConfig get turnConfig => TurnConfig(
    bargeIn: bargeIn,
    endOfTurn: Duration(milliseconds: pauseMs),
    confirmDelay: utteranceConfirmDelay,
  );

  VoiceSettings copyWith({
    String? voice,
    Map<String, String>? characterVoices,
    bool? bargeIn,
    int? pauseMs,
    String? level,
    bool clearLevel = false,
  }) => VoiceSettings(
    voice: voice ?? this.voice,
    characterVoices: characterVoices ?? this.characterVoices,
    bargeIn: bargeIn ?? this.bargeIn,
    pauseMs: pauseMs ?? this.pauseMs,
    level: clearLevel ? null : (level ?? this.level),
  );

  Map<String, Object?> toJson() => {
    'voice': voice,
    'characterVoices': characterVoices,
    'bargeIn': bargeIn,
    'pauseMs': pauseMs,
    'level': level,
  };

  static VoiceSettings fromJson(Map<String, Object?> j) => VoiceSettings(
    voice: voiceById(j['voice'] as String?).id,
    characterVoices: {
      for (final e in (j['characterVoices'] as Map? ?? const {}).entries)
        if (e.key is String && e.value is String) e.key as String: voiceById(e.value as String).id,
    },
    bargeIn: j['bargeIn'] as bool? ?? true,
    pauseMs: ((j['pauseMs'] as num?)?.toInt() ?? 700).clamp(600, 2000),
    level: const {'A1', 'A2', 'B1', 'B2', 'C1'}.contains(j['level']) ? j['level'] as String : null,
  );
}

class VoiceSettingsNotifier extends Notifier<VoiceSettings> {
  static const key = 'voice_talk_v1';

  @override
  VoiceSettings build() {
    final raw = ref.read(prefsProvider).getString(key);
    if (raw == null) return const VoiceSettings();
    try {
      return VoiceSettings.fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map));
    } on Object {
      return const VoiceSettings();
    }
  }

  void _save(VoiceSettings s) {
    state = s;
    ref.read(prefsProvider).setString(key, jsonEncode(s.toJson()));
  }

  void setVoice(String id) => _save(state.copyWith(voice: voiceById(id).id));
  void setCharacterVoice(String characterId, String voiceId) =>
      _save(state.copyWith(characterVoices: {...state.characterVoices, characterId: voiceById(voiceId).id}));
  void setBargeIn(bool on) => _save(state.copyWith(bargeIn: on));
  void setPause(int ms) => _save(state.copyWith(pauseMs: ms));
  void setLevel(String? level) =>
      _save(level == null ? state.copyWith(clearLevel: true) : state.copyWith(level: level));
}

final voiceSettingsProvider = NotifierProvider<VoiceSettingsNotifier, VoiceSettings>(
  VoiceSettingsNotifier.new,
);
