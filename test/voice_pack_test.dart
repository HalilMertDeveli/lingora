import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/voice_key.dart';
import 'package:lingora/core/voice_manifest.dart';
import 'package:lingora/services/voice_pack.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.index);
  final String? index;
  @override
  Future<ByteData> load(String key) async {
    if (key == 'assets/voice/index.json' && index != null) {
      return ByteData.sublistView(utf8.encode(index!));
    }
    throw StateError('missing $key');
  }
}

void main() {
  group('voice key', () {
    test('stable, 16 hex digits, spacing does not matter', () {
      final k = voiceKey('Good morning');
      expect(k, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(voiceKey('  Good   morning '), k);
      expect(voiceKey('Good morning!'), isNot(k));
      // Pinned so recordings keep their names across releases.
      expect(voiceKey('Hello'), 'f55c314b18fbf6c5');
    });

    test('Matilda reads most sentences, Eric some; single words stay with Matilda', () {
      expect(voiceForSentence('hello'), Voice.matilda);
      expect(voiceForSentence('good morning'), Voice.matilda);
      final sentences = [for (var i = 0; i < 400; i++) 'I have $i apples today.'];
      final eric = sentences.where((s) => voiceForSentence(s) == Voice.eric).length;
      expect(eric, inInclusiveRange(60, 140), reason: 'about one in four');
    });

    test('story speakers by avatar', () {
      expect(voiceForAvatar('👩'), Voice.matilda);
      expect(voiceForAvatar('👨‍🍳'), Voice.eric);
      expect(voiceForAvatar('🧑'), isNull);
    });
  });

  group('voice pack', () {
    test('a recorded sentence plays its file, others fall back', () async {
      final key = voiceKey('Good morning');
      final pack = VoicePack(bundle: _Bundle(jsonEncode({key: 'matilda'})));
      expect(await pack.assetFor(' Good  morning'), 'voice/$key.mp3');
      expect(await pack.assetFor('Good night'), isNull);
    });

    test('no pack bundled: everything falls back', () async {
      final pack = VoicePack(bundle: _Bundle(null));
      expect(await pack.assetFor('Good morning'), isNull);
    });

    test('bundled first, then downloaded, else the phone voice', () async {
      final bundled = voiceKey('Good morning');
      final downloaded = voiceKey('Good evening');
      final pack = VoicePack(
        bundle: _Bundle(jsonEncode({bundled: 'matilda'})),
        downloaded: (k) => k == downloaded ? '/data/voice/$k.mp3' : null,
      );
      expect(((await pack.sourceFor('Good morning'))! as AssetSource).path, 'voice/$bundled.mp3');
      expect(
        ((await pack.sourceFor('Good evening'))! as DeviceFileSource).path,
        '/data/voice/$downloaded.mp3',
      );
      expect(await pack.sourceFor('Good night'), isNull);
    });

    test('downloadable recordings in voice/ are indexed, listed in the manifest and not bundled', () {
      final bundled = (jsonDecode(File('assets/voice/index.json').readAsStringSync()) as Map).keys.toSet();
      final remote = (jsonDecode(File('voice/index.json').readAsStringSync()) as Map).keys.toSet();
      final files = {
        for (final f in Directory('voice').listSync().whereType<File>().where((f) => f.path.endsWith('.mp3')))
          f.uri.pathSegments.last.replaceAll('.mp3', ''),
      };
      expect(files, remote);
      final manifest = VoiceManifest.parse(File('assets/voice_manifest.json').readAsStringSync());
      for (final k in remote) {
        final entry = manifest[k];
        expect(entry, isNotNull, reason: '$k missing from the manifest: dart run tool/voice_manifest.dart');
        final bytes = File('voice/$k.mp3').readAsBytesSync();
        expect(bytes.length, entry!.size, reason: k);
        expect(sha256.convert(bytes).toString().substring(0, hashLength), entry.hash, reason: k);
      }
      expect(manifest.files.where((f) => bundled.contains(f.key)), isEmpty);
    });

    test('every indexed recording exists and no recording is unindexed', () {
      final dir = Directory('assets/voice');
      final index = (jsonDecode(File('assets/voice/index.json').readAsStringSync()) as Map).keys.toSet();
      final files = {
        for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp3')))
          f.uri.pathSegments.last.replaceAll('.mp3', ''),
      };
      expect(files, index);
      for (final v in (jsonDecode(File('assets/voice/index.json').readAsStringSync()) as Map).values) {
        expect(Voice.values.map((e) => e.name), contains(v));
      }
    });
  });
}
