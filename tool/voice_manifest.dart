// Splits the course recordings into the small core bundled in the app
// (`assets/voice/`) and the rest, downloaded on demand from Firebase Storage,
// and writes the download list `assets/voice_manifest.json` (docs/ses.md).
//
//   dart run tool/voice_manifest.dart --extra D:/DilmacSes/voice
//   dart run tool/voice_manifest.dart --rebalance --core-mb 10 --extra D:/DilmacSes/voice
//
// --rebalance  moves recordings between assets/voice (bundled) and voice/
//              (in the repo, not bundled) so the bundle holds the first
//              --core-mb MB of the course in course order.
// --extra DIR  another folder of recordings with its own index.json (the
//              --overflow folder of tool/voice_elevenlabs.dart); repeatable.
// --check      exits with 1 when the manifest is not up to date.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lingora/core/voice_key.dart';
import 'package:lingora/core/voice_manifest.dart';

import 'voice_elevenlabs.dart' show allUnits, spokenIn;

final bundleDir = Directory('assets/voice');
final remoteDir = Directory('voice');
final manifestFile = File('assets/voice_manifest.json');

/// Pack id of the recordings no course unit uses (other screens).
const otherPack = 'diger';

Map<String, String> readIndex(Directory d) {
  final f = File('${d.path}/index.json');
  return f.existsSync()
      ? (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>).cast<String, String>()
      : <String, String>{};
}

void writeIndex(Directory d, Map<String, String> index) {
  d.createSync(recursive: true);
  File('${d.path}/index.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ')
        .convert(Map.fromEntries(index.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))),
  );
}

/// Section id of a unit id: `u3` → s1, `s4u13` → s4.
String sectionOf(String unitId) => RegExp(r'^(s\d+)u').firstMatch(unitId)?.group(1) ?? 's1';

/// Section titles and levels from the course files.
Map<String, (String, String?)> sectionTitles() {
  final out = <String, (String, String?)>{};
  final files = [
    File('assets/courses/tr_en.json'),
    ...Directory('assets/courses/tr_en').listSync().whereType<File>().where((f) => f.path.endsWith('.json')),
  ];
  for (final f in files) {
    final s = (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)['section'];
    if (s is Map<String, dynamic>) out[s['id'] as String] = (s['title'] as String, s['cefr'] as String?);
  }
  return out;
}

String _arg(List<String> args, String name, String fallback) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
}

String fileHash(File f) => sha256.convert(f.readAsBytesSync()).toString().substring(0, hashLength);

void main(List<String> args) {
  final rebalance = args.contains('--rebalance');
  final check = args.contains('--check');
  final coreBytes = (double.parse(_arg(args, '--core-mb', '10')) * 1024 * 1024).round();
  final extras = [
    for (var i = 0; i < args.length - 1; i++)
      if (args[i] == '--extra') Directory(args[i + 1]),
  ];

  // Every sentence of the course in course order, with its section.
  final sectionOfKey = <String, String>{};
  for (final u in allUnits()) {
    for (final text in spokenIn(u).keys) {
      sectionOfKey.putIfAbsent(voiceKey(text), () => sectionOf(u['id'] as String));
    }
  }
  final order = sectionOfKey.keys.toList();

  var bundled = readIndex(bundleDir);
  var remote = readIndex(remoteDir);
  File source(String key) => File('${(bundled.containsKey(key) ? bundleDir : remoteDir).path}/$key.mp3');

  if (rebalance) {
    final committed = {...bundled, ...remote};
    final core = <String>{};
    var used = 0;
    for (final k in order.where(committed.containsKey)) {
      final size = source(k).lengthSync();
      if (used + size > coreBytes) break;
      used += size;
      core.add(k);
    }
    final nextBundled = {for (final k in core) k: committed[k]!};
    final nextRemote = {
      for (final e in committed.entries)
        if (!core.contains(e.key)) e.key: e.value,
    };
    remoteDir.createSync(recursive: true);
    var moved = 0;
    for (final k in committed.keys) {
      final from = source(k);
      final to = File('${(core.contains(k) ? bundleDir : remoteDir).path}/$k.mp3');
      if (from.path != to.path) {
        from.renameSync(to.path);
        moved++;
      }
    }
    bundled = nextBundled;
    remote = nextRemote;
    writeIndex(bundleDir, bundled);
    writeIndex(remoteDir, remote);
    stdout.writeln(
      'Pakette ${bundled.length} kayıt (${(used / 1048576).toStringAsFixed(1)} MB), '
      'indirilecek ${remote.length}; $moved dosya taşındı.',
    );
  }

  // Downloadable files: voice/ and the extra folders, never the bundled ones.
  final files = <String, File>{};
  for (final k in remote.keys) {
    files[k] = File('${remoteDir.path}/$k.mp3');
  }
  for (final d in extras) {
    for (final k in readIndex(d).keys) {
      if (!bundled.containsKey(k)) files.putIfAbsent(k, () => File('${d.path}/$k.mp3'));
    }
  }
  final missing = files.entries.where((e) => !e.value.existsSync()).map((e) => e.key).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('${missing.length} kayıt dosyası yok, örnek: ${missing.first}');
    exit(66);
  }

  final titles = sectionTitles();
  final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
  final byPack = <String, List<VoiceFile>>{};
  for (final k in files.keys.toList()..sort((a, b) => (rank[a] ?? 1 << 30).compareTo(rank[b] ?? 1 << 30))) {
    final f = files[k]!;
    byPack.putIfAbsent(sectionOfKey[k] ?? otherPack, () => []).add(VoiceFile(k, fileHash(f), f.lengthSync()));
  }
  int packRank(String id) => id == otherPack ? 1 << 30 : int.parse(id.substring(1));
  final packs = [
    for (final id in byPack.keys.toList()..sort((a, b) => packRank(a).compareTo(packRank(b))))
      VoicePackInfo(
        id: id,
        title: titles[id]?.$1 ?? 'Diğer kayıtlar',
        cefr: titles[id]?.$2,
        files: byPack[id]!,
      ),
  ];

  // Same content keeps the old version, so re-running is a no-op.
  final old = manifestFile.existsSync() ? VoiceManifest.parse(manifestFile.readAsStringSync()) : null;
  final same = old != null && VoiceManifest(old.version, packs).encode() == old.encode();
  final manifest = VoiceManifest(same ? old.version : DateTime.now().millisecondsSinceEpoch ~/ 1000, packs);
  if (check) {
    if (!same) {
      stderr.writeln('assets/voice_manifest.json güncel değil: dart run tool/voice_manifest.dart');
      exit(1);
    }
    stdout.writeln('Güncel.');
    return;
  }
  manifestFile.writeAsStringSync(manifest.encode());

  final bundleBytes = bundled.keys.fold<int>(0, (n, k) => n + File('${bundleDir.path}/$k.mp3').lengthSync());
  stdout.writeln(
    'Pakette ${bundled.length} kayıt, ${(bundleBytes / 1048576).toStringAsFixed(1)} MB. '
    'İndirilecek ${manifest.fileCount} kayıt, ${(manifest.bytes / 1048576).toStringAsFixed(1)} MB:',
  );
  for (final p in packs) {
    stdout.writeln(
      '  ${p.id.padRight(6)} ${p.files.length.toString().padLeft(5)} kayıt '
      '${(p.bytes / 1048576).toStringAsFixed(1).padLeft(5)} MB  ${p.title}',
    );
  }
}
