// Shared by the app and `tool/voice_manifest.dart`: the list of course
// recordings that are not bundled in the app but downloaded on demand from
// Firebase Storage (docs/ses.md). Pure Dart (no Flutter).

import 'dart:convert';

/// One downloadable recording: the sentence's [key] (`voiceKey`), the first
/// 32 hex digits of the SHA-256 of the MP3 and its size in bytes.
class VoiceFile {
  const VoiceFile(this.key, this.hash, this.size);

  final String key;
  final String hash;
  final int size;

  /// Object name in the bucket. The hash is part of the name, so a
  /// re-recorded sentence gets a new object and every object can be cached
  /// forever (`Cache-Control: immutable`).
  String get objectPath => '$voiceObjectPrefix/${key}_${hash.substring(0, 8)}.mp3';

  String encode() => '$hash:$size';

  static VoiceFile decode(String key, String value) {
    final i = value.indexOf(':');
    if (i != hashLength) throw FormatException('bad voice entry', value);
    return VoiceFile(key, value.substring(0, i), int.parse(value.substring(i + 1)));
  }
}

/// A downloadable group of recordings: one course section (level), e.g.
/// `s3` "Kendini anlatmak", in course order.
class VoicePackInfo {
  const VoicePackInfo({required this.id, required this.title, this.cefr, required this.files});

  final String id;
  final String title;
  final String? cefr;
  final List<VoiceFile> files;

  int get bytes => files.fold(0, (n, f) => n + f.size);
}

/// Folder of the recordings in the bucket.
const voiceObjectPrefix = 'voice';

/// Object name of the manifest itself (uploaded with a short cache, so new
/// recordings reach installed apps without an update).
const voiceManifestObject = '$voiceObjectPrefix/manifest.json';

/// Hex digits of SHA-256 kept per file (128 bits).
const hashLength = 32;

class VoiceManifest {
  VoiceManifest(this.version, this.packs) {
    for (final p in packs) {
      for (final f in p.files) {
        _byKey.putIfAbsent(f.key, () => f);
      }
    }
  }

  /// Grows with every regenerated manifest (seconds since epoch at build).
  final int version;
  final List<VoicePackInfo> packs;
  final _byKey = <String, VoiceFile>{};

  static final empty = VoiceManifest(0, const []);

  VoiceFile? operator [](String key) => _byKey[key];
  int get fileCount => _byKey.length;
  int get bytes => _byKey.values.fold(0, (n, f) => n + f.size);
  Iterable<VoiceFile> get files => _byKey.values;

  /// Throws [FormatException] for anything that is not a valid manifest.
  static VoiceManifest parse(String json) {
    final m = jsonDecode(json);
    if (m is! Map<String, dynamic> || m['packs'] is! List) {
      throw const FormatException('not a voice manifest');
    }
    return VoiceManifest(m['version'] as int? ?? 0, [
      for (final p in (m['packs'] as List).cast<Map<String, dynamic>>())
        VoicePackInfo(
          id: p['id'] as String,
          title: p['title'] as String? ?? p['id'] as String,
          cefr: p['cefr'] as String?,
          files: [
            for (final e in (p['files'] as Map<String, dynamic>).entries)
              VoiceFile.decode(e.key, e.value as String),
          ],
        ),
    ]);
  }

  String encode() => const JsonEncoder.withIndent(' ').convert({
    'version': version,
    'packs': [
      for (final p in packs)
        {
          'id': p.id,
          'title': p.title,
          if (p.cefr != null) 'cefr': p.cefr,
          'files': {for (final f in p.files) f.key: f.encode()},
        },
    ],
  });
}
