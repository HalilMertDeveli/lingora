import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/voice_manifest.dart';
import 'package:lingora/services/voice_store.dart';

VoiceFile fileOf(String key, List<int> bytes) =>
    VoiceFile(key, sha256.convert(bytes).toString().substring(0, hashLength), bytes.length);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('voice_store_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  final a = [1, 2, 3, 4];
  final b = [5, 6, 7];
  final fa = fileOf('aaaaaaaaaaaaaaaa', a);
  final fb = fileOf('bbbbbbbbbbbbbbbb', b);

  group('manifest', () {
    test('round trip, lookup by key, totals', () {
      final m = VoiceManifest(7, [
        VoicePackInfo(id: 's2', title: 'Günlük hayat', cefr: 'A2', files: [fa]),
        VoicePackInfo(id: 's3', title: 'Kendini anlatmak', files: [fb]),
      ]);
      final back = VoiceManifest.parse(m.encode());
      expect(back.version, 7);
      expect(back.packs.map((p) => p.id), ['s2', 's3']);
      expect(back.packs.first.title, 'Günlük hayat');
      expect(back.packs.first.cefr, 'A2');
      expect(back[fb.key]!.hash, fb.hash);
      expect(back.bytes, 7);
      expect(back.fileCount, 2);
      expect(back['nope'], isNull);
    });

    test('object names carry the hash, so they can be cached forever', () {
      expect(fa.objectPath, 'voice/aaaaaaaaaaaaaaaa_${fa.hash.substring(0, 8)}.mp3');
    });

    test('rejects what is not a manifest', () {
      expect(() => VoiceManifest.parse('[]'), throwsFormatException);
      expect(
        () => VoiceManifest.parse('{"packs":[{"id":"s2","files":{"k":"short:1"}}]}'),
        throwsFormatException,
      );
    });

    test('the bundled manifest parses and leaves s1 in the app', () {
      final m = VoiceManifest.parse(File('assets/voice_manifest.json').readAsStringSync());
      expect(m.version, greaterThan(0));
      expect(m.packs, isNotEmpty);
      expect(m.packs.map((p) => p.id), isNot(contains('s1')));
    });

    test('public download URL encodes the object name', () {
      expect(
        storageUrl('b.app', 'voice/x_1.mp3').toString(),
        'https://firebasestorage.googleapis.com/v0/b/b.app/o/voice%2Fx_1.mp3?alt=media',
      );
      expect(
        storageUrl('b.app', 'voice/x.mp3', emulator: '127.0.0.1:9199').toString(),
        'http://127.0.0.1:9199/v0/b/b.app/o/voice%2Fx.mp3?alt=media',
      );
    });
  });

  group('cache', () {
    test('keeps only files whose size and hash match', () async {
      final c = VoiceCache(tmp);
      expect(await c.put(fa, [1, 2, 3, 5]), isFalse, reason: 'wrong hash');
      expect(await c.put(fa, [1, 2, 3]), isFalse, reason: 'wrong size');
      expect(c.pathFor(fa), isNull);
      expect(await c.put(fa, a), isTrue);
      expect(File(c.pathFor(fa)!).readAsBytesSync(), a);
      expect(tmp.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
    });

    test('survives a restart; a re-recorded sentence is not played from the old file', () async {
      final c = VoiceCache(tmp);
      await c.put(fa, a);
      await c.save();
      final again = VoiceCache(tmp);
      await again.load();
      expect(again.has(fa), isTrue);
      expect(again.pathFor(VoiceFile(fa.key, 'f' * hashLength, fa.size)), isNull);
    });

    test('prune drops removed and re-recorded files; clear drops everything', () async {
      final c = VoiceCache(tmp);
      await c.put(fa, a);
      await c.put(fb, b);
      await c.prune(
        VoiceManifest(1, [
          VoicePackInfo(id: 's2', title: '', files: [fa]),
        ]),
      );
      expect(c.has(fa), isTrue);
      expect(c.has(fb), isFalse);
      expect(File('${tmp.path}/${fb.key}.mp3').existsSync(), isFalse);
      await c.clear();
      expect(c.has(fa), isFalse);
      expect(tmp.listSync(), isEmpty);
      final reloaded = VoiceCache(tmp);
      await reloaded.load();
      expect(reloaded.has(fa), isFalse);
    });

    test('bytesOf counts what is on the phone', () async {
      final c = VoiceCache(tmp);
      final m = VoiceManifest(1, [
        VoicePackInfo(id: 's2', title: '', files: [fa, fb]),
      ]);
      expect(c.bytesOf(m), 0);
      await c.put(fb, b);
      expect(c.bytesOf(m), 3);
    });
  });

  group('downloader', () {
    Uri url(VoiceFile f) => Uri.parse('https://x/${f.objectPath}');

    test('downloads what is missing, verifies, retries once, skips bad files', () async {
      final c = VoiceCache(tmp);
      await c.put(fa, a);
      final fc = fileOf('cccccccccccccccc', [9, 9]);
      final fd = fileOf('dddddddddddddddd', [8]);
      final calls = <String, int>{};
      final d = VoiceDownloader(
        cache: c,
        urlFor: url,
        fetch: (u) async {
          final n = calls[u.path] = (calls[u.path] ?? 0) + 1;
          if (u.path.contains(fb.key)) return n == 1 ? throw const SocketException('flaky') : b;
          if (u.path.contains(fc.key)) return [0, 0]; // corrupted on the server
          if (u.path.contains(fd.key)) return [8];
          throw StateError('already cached, must not be fetched: $u');
        },
      );
      final r = await d.download([fa, fb, fc, fd]);
      expect(r.downloaded, 2);
      expect(r.failed, 1);
      expect(r.stopped, isFalse);
      expect(c.has(fb) && c.has(fd), isTrue);
      expect(c.has(fc), isFalse);
      expect(calls.values.reduce((x, y) => x + y), 2 + 2 + 1);
      final reloaded = VoiceCache(tmp);
      await reloaded.load();
      expect(reloaded.has(fd), isTrue, reason: 'saved at the end');
    });

    test('stops when no longer allowed (left Wi-Fi) and resumes later', () async {
      final c = VoiceCache(tmp);
      var allowed = 1;
      final d = VoiceDownloader(
        cache: c,
        urlFor: url,
        parallel: 1,
        allowed: () async => allowed-- > 0,
        fetch: (u) async => u.path.contains(fa.key) ? a : b,
      );
      final r = await d.download([fa, fb]);
      expect(r.stopped, isTrue);
      expect(r.downloaded, 1);
      expect(c.has(fa), isTrue);
      allowed = 5;
      final again = await d.download([fa, fb]);
      expect(again.downloaded, 1);
      expect(c.has(fb), isTrue);
    });

    test('cancel stops the queue', () async {
      final c = VoiceCache(tmp);
      late VoiceDownloader d;
      d = VoiceDownloader(
        cache: c,
        urlFor: url,
        parallel: 1,
        fetch: (u) async {
          d.cancel();
          return u.path.contains(fa.key) ? a : b;
        },
      );
      final r = await d.download([fa, fb]);
      expect(r.stopped, isTrue);
      expect(c.has(fb), isFalse);
    });
  });
}
