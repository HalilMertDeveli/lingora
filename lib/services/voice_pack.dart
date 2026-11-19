import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import '../core/voice_key.dart';
import 'voice_library.dart';

/// Recorded sentences: the small core bundled in `assets/voice/` (made by
/// `tool/voice_elevenlabs.dart`) and the rest downloaded on Wi-Fi by
/// [VoiceLibrary]. A sentence that has a recording plays it; any other falls
/// back to the phone's speech engine.
class VoicePack {
  VoicePack({AssetBundle? bundle, String? Function(String key)? downloaded})
    : _bundle = bundle ?? rootBundle,
      _downloaded = downloaded ?? VoiceLibrary.instance.pathFor;

  final AssetBundle _bundle;
  final String? Function(String key) _downloaded;
  Future<Set<String>>? _keys;

  Future<Set<String>> _load() => _keys ??= _bundle
      .loadString('assets/voice/index.json')
      .then((s) => (jsonDecode(s) as Map<String, dynamic>).keys.toSet())
      .catchError((Object _) => <String>{});

  /// Asset path (for `AssetSource`) of the bundled recording of [text], or null.
  Future<String?> assetFor(String text) async {
    final key = voiceKey(text);
    return (await _load()).contains(key) ? 'voice/$key.mp3' : null;
  }

  /// Player source of the recording of [text]: bundled, else downloaded, else null.
  Future<Source?> sourceFor(String text) async {
    final asset = await assetFor(text);
    if (asset != null) return AssetSource(asset);
    final path = _downloaded(voiceKey(text));
    return path == null ? null : DeviceFileSource(path);
  }
}
