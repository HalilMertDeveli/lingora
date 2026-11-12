// YDS Faz 2b (docs/sinav/yds-faz2-icerik.md § Bol okuma): extensive-reading texts in the app's
// ReadingStory format, assets/reading/yds_bol_okuma_*.json (a JSON array, like stories.json).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/models/reading.dart';

const _file = 'assets/reading/yds_bol_okuma_1.json';

void main() {
  group('YDS bol okuma 1', skip: File(_file).existsSync() ? false : 'not shipped yet', () {
    late final List<Map<String, dynamic>> raw = (jsonDecode(File(_file).readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

    test('60 stories (40 B1, 20 B1+) that ReadingStory reads, with unique yb_ ids', () {
      expect(raw, hasLength(60));
      expect(raw.where((s) => s['level'] == 'B1'), hasLength(40));
      expect(raw.where((s) => s['level'] == 'B1+'), hasLength(20));
      final stories = raw.map(ReadingStory.fromJson).toList();
      expect(stories.map((s) => s.id).toSet(), hasLength(60));
      for (final s in stories) {
        expect(s.id, startsWith('yb_'));
      }
      // Ids must not clash with the main library.
      final main = (jsonDecode(File('assets/reading/stories.json').readAsStringSync()) as List)
          .map((s) => (s as Map)['id'])
          .toSet();
      expect(stories.where((s) => main.contains(s.id)), isEmpty);
    });

    test('only ReadingStory fields; 400–700 words; glosses lowercase and in the text; 2 questions', () {
      const fields = {'id', 'level', 'emoji', 'title', 'titleTr', 'text', 'glosses', 'questions'};
      for (final s in raw) {
        final id = s['id'];
        expect(fields.containsAll(s.keys), isTrue, reason: '$id: ${s.keys}');
        final text = s['text'] as String;
        final words = RegExp(r"[\p{L}]+(?:[-'’][\p{L}]+)*", unicode: true).allMatches(text).length;
        expect(words, inInclusiveRange(400, 700), reason: '$id: $words kelime');
        expect(text, contains('\n\n'), reason: '$id: paragraphs');
        for (final k in (s['glosses'] as Map).keys.cast<String>()) {
          expect(k, k.toLowerCase(), reason: '$id: $k');
          expect(text.toLowerCase(), contains(k), reason: '$id: gloss "$k" not in text');
        }
        final qs = (s['questions'] as List).cast<Map<String, dynamic>>();
        expect(qs, hasLength(2), reason: '$id');
        for (final q in qs) {
          final options = (q['options'] as List).cast<String>();
          expect(options.length, inInclusiveRange(4, 5), reason: '$id ${q['q']}');
          expect(
            options.map((o) => o.toLowerCase()).toSet(),
            hasLength(options.length),
            reason: '$id ${q['q']}',
          );
          expect(
            q['answer'],
            allOf(greaterThanOrEqualTo(0), lessThan(options.length)),
            reason: '$id ${q['q']}',
          );
          expect((q['explain'] as String).trim(), isNotEmpty, reason: '$id ${q['q']}');
        }
      }
    });
  });
}
