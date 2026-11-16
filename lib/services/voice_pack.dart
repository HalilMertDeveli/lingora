import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/voice_key.dart';

/// Recorded sentences in `assets/voice/` (made by `tool/voice_elevenlabs.dart`).
/// A sentence that has a recording plays it; any other falls back to the
/// phone's speech engine.
class VoicePack {
  VoicePack({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  Future<Set<String>>? _keys;

  Future<Set<String>> _load() => _keys ??= _bundle
      .loadString('assets/voice/index.json')
      .then((s) => (jsonDecode(s) as Map<String, dynamic>).keys.toSet())
      .catchError((Object _) => <String>{});

  /// Asset path (for `AssetSource`) of the recording of [text], or null.
  Future<String?> assetFor(String text) async {
    final key = voiceKey(text);
    return (await _load()).contains(key) ? 'voice/$key.mp3' : null;
  }
}
