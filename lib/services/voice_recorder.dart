import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Records the learner's own voice to a local file (Mülakat Provası and
/// anything else that wants to play an answer back). Files stay on the
/// phone and are never uploaded.
abstract class VoiceRecorder {
  /// Starts recording to a new file named [name] (no extension). False when
  /// recording is not possible (no permission, web, no microphone).
  Future<bool> start(String name);

  /// Stops and returns the file path, or null when nothing was recorded.
  Future<String?> stop();

  /// Stops and deletes the current recording.
  Future<void> cancel();
}

class DeviceVoiceRecorder implements VoiceRecorder {
  AudioRecorder? _rec;
  String? _path;

  /// Folder for the recordings: app documents/prova (kept across sessions).
  static Future<Directory> folder() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/prova');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  @override
  Future<bool> start(String name) async {
    if (kIsWeb) return false;
    try {
      final rec = _rec ??= AudioRecorder();
      if (!await rec.hasPermission()) return false;
      final path = '${(await folder()).path}/$name.m4a';
      // Mono AAC at speech quality: about 0.5 MB per minute.
      await rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 22050, numChannels: 1),
        path: path,
      );
      _path = path;
      return true;
    } catch (e) {
      debugPrint('Recording failed: $e');
      return false;
    }
  }

  @override
  Future<String?> stop() async {
    try {
      final path = await _rec?.stop() ?? _path;
      _path = null;
      if (path == null) return null;
      final f = File(path);
      return f.existsSync() && f.lengthSync() > 0 ? path : null;
    } catch (e) {
      debugPrint('Stop recording failed: $e');
      return null;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _rec?.cancel();
    } catch (_) {}
    _path = null;
  }
}

/// Does nothing: tests, and the web build.
class NoVoiceRecorder implements VoiceRecorder {
  @override
  Future<bool> start(String name) async => false;
  @override
  Future<String?> stop() async => null;
  @override
  Future<void> cancel() async {}
}

final voiceRecorderProvider = Provider<VoiceRecorder>(
  (ref) => kIsWeb ? NoVoiceRecorder() : DeviceVoiceRecorder(),
);
