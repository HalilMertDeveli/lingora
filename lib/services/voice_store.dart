import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/voice_manifest.dart';

/// Downloaded recordings in app storage: `<dir>/<key>.mp3`, plus
/// `verified.json` with the hash each file was checked against. Only files
/// whose hash matches the current manifest are played. Pure Dart (dart:io).
class VoiceCache {
  VoiceCache(this.dir);

  final Directory dir;
  var _ok = <String, String>{};
  var _dirty = false;

  File get _state => File('${dir.path}/verified.json');
  File _file(String key) => File('${dir.path}/$key.mp3');

  Future<void> load() async {
    try {
      _ok = (jsonDecode(await _state.readAsString()) as Map<String, dynamic>).cast<String, String>();
    } catch (_) {
      _ok = {};
    }
  }

  /// Path of the downloaded recording of [f], or null when it is missing or
  /// was made for another version of the sentence.
  String? pathFor(VoiceFile f) => _ok[f.key] == f.hash ? _file(f.key).path : null;

  bool has(VoiceFile f) => _ok[f.key] == f.hash;

  /// Bytes of [m]'s recordings that are on the phone.
  int bytesOf(VoiceManifest m) => m.files.where(has).fold(0, (n, f) => n + f.size);

  /// Stores [bytes] as the recording of [f] if size and hash match; returns
  /// whether it did. Written to a temporary file first, so a half-written
  /// file is never played.
  Future<bool> put(VoiceFile f, List<int> bytes) async {
    if (bytes.length != f.size) return false;
    if (sha256.convert(bytes).toString().substring(0, hashLength) != f.hash) return false;
    await dir.create(recursive: true);
    final tmp = File('${_file(f.key).path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(_file(f.key).path);
    _ok[f.key] = f.hash;
    _dirty = true;
    return true;
  }

  Future<void> save() async {
    if (!_dirty) return;
    _dirty = false;
    await dir.create(recursive: true);
    final tmp = File('${_state.path}.part');
    await tmp.writeAsString(jsonEncode(_ok), flush: true);
    await tmp.rename(_state.path);
  }

  /// Deletes recordings that are not in [m] (removed or re-recorded).
  Future<void> prune(VoiceManifest m) async {
    final stale = _ok.entries.where((e) => m[e.key]?.hash != e.value).map((e) => e.key).toList();
    for (final k in stale) {
      _ok.remove(k);
      try {
        await _file(k).delete();
      } on FileSystemException catch (_) {}
      _dirty = true;
    }
    await save();
  }

  /// Deletes every downloaded recording.
  Future<void> clear() async {
    _ok = {};
    _dirty = false;
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        final p = e.path;
        if (e is File && (p.endsWith('.mp3') || p.endsWith('.part') || p.endsWith('verified.json'))) {
          await e.delete();
        }
      }
    }
  }
}

/// Fetches the bytes at a URL; throws on any failure.
typedef Fetch = Future<List<int>> Function(Uri url);

/// Public download URL of a Storage object (the rules allow reading `voice/`
/// without signing in). [emulator] is `host:port` of the Storage emulator.
Uri storageUrl(String bucket, String object, {String? emulator}) => Uri.parse(
  '${emulator == null ? 'https://firebasestorage.googleapis.com' : 'http://$emulator'}'
  '/v0/b/$bucket/o/${Uri.encodeComponent(object)}?alt=media',
);

/// Plain HTTP GET with dart:io; non-200 answers throw.
Future<List<int>> httpFetch(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final res = await (await client.getUrl(url)).close().timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('HTTP ${res.statusCode}', uri: url);
    }
    final out = BytesBuilder(copy: false);
    await res.timeout(const Duration(seconds: 60)).forEach(out.add);
    return out.takeBytes();
  } finally {
    client.close();
  }
}

class DownloadResult {
  const DownloadResult(this.downloaded, this.failed, {required this.stopped});

  final int downloaded;
  final int failed;

  /// Stopped early: cancelled or no longer allowed (left Wi-Fi).
  final bool stopped;
}

/// Downloads recordings into a [VoiceCache], a few at a time, checking every
/// file's hash. A file that fails twice is skipped (the phone's voice reads
/// that sentence); [allowed] is asked before each file (Wi-Fi only).
class VoiceDownloader {
  VoiceDownloader({
    required this.cache,
    required this.fetch,
    required this.urlFor,
    Future<bool> Function()? allowed,
    this.parallel = 4,
  }) : allowed = allowed ?? (() async => true);

  final VoiceCache cache;
  final Fetch fetch;
  final Uri Function(VoiceFile f) urlFor;
  final Future<bool> Function() allowed;
  final int parallel;
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Future<DownloadResult> download(Iterable<VoiceFile> files, {void Function(VoiceFile f)? onFile}) async {
    _cancelled = false;
    final queue = files.where((f) => !cache.has(f)).toList().reversed.toList();
    var downloaded = 0, failed = 0;
    var stopped = false;

    Future<void> worker() async {
      while (queue.isNotEmpty && !stopped) {
        if (_cancelled || !await allowed()) {
          stopped = true;
          return;
        }
        if (queue.isEmpty) return;
        final f = queue.removeLast();
        var ok = false;
        for (var attempt = 0; attempt < 2 && !ok; attempt++) {
          try {
            ok = await cache.put(f, await fetch(urlFor(f)));
          } catch (_) {
            ok = false;
          }
        }
        if (ok) {
          downloaded++;
          onFile?.call(f);
          if (downloaded % 25 == 0) await cache.save();
        } else {
          failed++;
        }
      }
    }

    await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
    await cache.save();
    return DownloadResult(downloaded, failed, stopped: stopped);
  }
}
