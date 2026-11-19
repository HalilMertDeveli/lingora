// Course audio against the Firebase Storage emulator (never the real
// bucket): the security rules and the app's download path end to end.
//
//   firebase emulators:exec --only storage --project demo-lingora \
//     "flutter test test/voice_storage_emulator_test.dart"
//
// Skipped when STORAGE_EMULATOR_HOST is not set (plain `flutter test`).

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/voice_manifest.dart';
import 'package:lingora/services/voice_library.dart';
import 'package:lingora/services/voice_store.dart';

/// host:port (the variable may carry an http:// prefix).
final host = Platform.environment['STORAGE_EMULATOR_HOST']?.replaceFirst(RegExp('^https?://'), '');

Future<(int, String)> send(String method, Uri url, {List<int>? body, bool owner = false}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, url);
    if (owner) req.headers.set('Authorization', 'Bearer owner');
    if (body != null) {
      req.headers
        ..set('Content-Type', 'audio/mpeg')
        ..set('X-Goog-Upload-Protocol', 'raw');
      req.add(body);
    }
    final res = await req.close();
    final bytes = await res.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    return (res.statusCode, utf8.decode(bytes, allowMalformed: true));
  } finally {
    client.close();
  }
}

Uri uploadUrl(String object) =>
    Uri.parse('http://$host/v0/b/$voiceBucket/o?name=${Uri.encodeQueryComponent(object)}');

void main() {
  final skip = host == null ? 'STORAGE_EMULATOR_HOST not set' : null;
  final bytes = List<int>.generate(2048, (i) => i * 7 % 256);
  final file = VoiceFile(
    'eeeeeeeeeeeeeeee',
    sha256.convert(bytes).toString().substring(0, hashLength),
    bytes.length,
  );

  setUpAll(() async {
    if (host == null) return;
    final (code, body) = await send('POST', uploadUrl(file.objectPath), body: bytes, owner: true);
    expect(code, 200, reason: body);
    final (code2, body2) = await send('POST', uploadUrl('private/secret.txt'), body: [1], owner: true);
    expect(code2, 200, reason: body2);
  });

  test('course audio is public to read, without signing in', () async {
    final (code, _) = await send('GET', storageUrl(voiceBucket, file.objectPath, emulator: host));
    expect(code, 200);
  }, skip: skip);

  test('nobody writes through the client API', () async {
    final (code, _) = await send('POST', uploadUrl('voice/evil.mp3'), body: [1, 2, 3]);
    expect(code, anyOf(401, 403));
    final (code2, _) = await send('DELETE', storageUrl(voiceBucket, file.objectPath, emulator: host));
    expect(code2, anyOf(401, 403));
  }, skip: skip);

  test('everything outside voice/ is closed', () async {
    final (code, _) = await send('GET', storageUrl(voiceBucket, 'private/secret.txt', emulator: host));
    expect(code, anyOf(401, 403));
  }, skip: skip);

  test('the app downloads, verifies and caches a recording; a tampered one is refused', () async {
    final dir = Directory.systemTemp.createTempSync('voice_emu_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final cache = VoiceCache(dir);
    final tampered = VoiceFile(file.key.replaceAll('e', 'f'), 'a' * hashLength, file.size);
    // Same bytes under the tampered entry's name: the hash will not match.
    await send('POST', uploadUrl(tampered.objectPath), body: bytes, owner: true);
    final d = VoiceDownloader(
      cache: cache,
      fetch: httpFetch,
      urlFor: (f) => storageUrl(voiceBucket, f.objectPath, emulator: host),
    );
    final r = await d.download([file, tampered]);
    expect(r.downloaded, 1);
    expect(r.failed, 1);
    expect(File(cache.pathFor(file)!).readAsBytesSync(), bytes);
    expect(cache.pathFor(tampered), isNull);

    // Offline afterwards: still there after a restart.
    final again = VoiceCache(dir);
    await again.load();
    expect(again.has(file), isTrue);
  }, skip: skip);
}
