// Android 7–9: every emoji the app shows must be one Android 7.0 can draw,
// after the legacy swap (lib/core/emoji_compat.dart). A new content emoji
// newer than Emoji 3.0 fails here until it gets a stand-in in legacyEmojiMap.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/legacy_emoji.dart';

Set<String> _tooNew() => {
  for (final line in File('test/fixtures/emoji_too_new.txt').readAsLinesSync())
    if (line.isNotEmpty && !line.startsWith('#'))
      String.fromCharCodes(line.split(' ').map((h) => int.parse(h, radix: 16))),
};

String _strip(String s) => s.replaceAll('️', '');

Iterable<File> _files(String dir) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => RegExp(r'\.(dart|json|md|txt)$').hasMatch(f.path))
        .where((f) => !f.path.replaceAll('\\', '/').endsWith('lib/core/emoji_compat.dart'));

class _MapBundle extends CachingAssetBundle {
  _MapBundle(this.files);
  final Map<String, String> files;
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(files[key]!)));
}

void main() {
  final tooNew = _tooNew();

  tearDown(() => LegacyEmoji.enabled = false);

  test('the stand-ins themselves exist on Android 7.0', () {
    for (final v in legacyEmojiMap.values) {
      for (final g in v.characters) {
        expect(tooNew.contains(_strip(g)), isFalse, reason: 'stand-in $v is too new');
      }
    }
  });

  test('no content or code emoji is left that Android 7.0 cannot draw', () {
    final missing = <String, String>{};
    for (final dir in ['lib', 'assets']) {
      for (final f in _files(dir)) {
        final text = legacyEmoji(f.readAsStringSync(), force: true);
        for (final g in text.characters) {
          if (tooNew.contains(_strip(g))) missing[g] = f.path;
        }
      }
    }
    expect(missing, isEmpty, reason: 'add these to legacyEmojiMap: $missing');
  });

  test('swaps whole sequences, keeps kept ZWJ sequences and plain text', () {
    String s(String t) => legacyEmoji(t, force: true);
    expect(s('Doktor 👩‍⚕️ ve ⚕️'), 'Doktor 👩‍⚕️ ve 💊');
    expect(s('🧑‍🏫 teacher, 🧑 teen, 🧔🏻 Arda'), '👩‍🏫 teacher, 👦 teen, 👨🏻 Arda');
    expect(s('🐻‍❄️ ve 🐦‍⬛'), '🐻 ve 🐦');
    expect(s('Merhaba 👋 İngilizce'), 'Merhaba 👋 İngilizce');
    // Newer phones: untouched.
    expect(legacyEmoji('🩺 🪑'), '🩺 🪑');
  });

  test('getters of named products follow the device', () {
    LegacyEmoji.enabled = true;
    expect(legacyEmoji('🦩'), '🐦');
    LegacyEmoji.enabled = false;
    expect(legacyEmoji('🦩'), '🦩');
  });

  test('the app bundle rewrites JSON on old Android only', () async {
    const json = '{"text": "chair", "emoji": "🪑"}';
    final inner = _MapBundle({'a.json': json, 'b.bin': json});
    LegacyEmoji.enabled = false;
    expect(await LegacyEmojiBundle(inner).loadString('a.json'), json);
    LegacyEmoji.enabled = true;
    final bundle = LegacyEmojiBundle(inner);
    expect(await bundle.loadString('a.json'), '{"text": "chair", "emoji": "💺"}');
    expect(await bundle.loadString('b.bin'), json);
  });
}
