// YDS extensive reading in the app's ReadingStory format, assets/reading/yds_bol_okuma_*.json (a JSON array,
// like stories.json): set 1 (Faz 2b, 40 B1 + 20 B1+, 400–700 words) and set 2 (Faz 3b, 40 B1+ + 40 B2,
// 500–800 words).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/models/reading.dart';

/// (file, level → count, word range)
const _sets = [
  ('assets/reading/yds_bol_okuma_1.json', {'B1': 40, 'B1+': 20}, (400, 700)),
  ('assets/reading/yds_bol_okuma_2.json', {'B1+': 40, 'B2': 40}, (500, 800)),
];

void main() {
  for (final (file, levels, (minWords, maxWords)) in _sets) {
    final total = levels.values.reduce((a, b) => a + b);
    group('YDS ${file.split('/').last}', skip: File(file).existsSync() ? false : 'not shipped yet', () {
      late final List<Map<String, dynamic>> raw = (jsonDecode(File(file).readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();

      test('$total stories ($levels) that ReadingStory reads, with unique yb_ ids', () {
        expect(raw, hasLength(total));
        for (final MapEntry(key: level, value: n) in levels.entries) {
          expect(raw.where((s) => s['level'] == level), hasLength(n), reason: level);
        }
        final stories = raw.map(ReadingStory.fromJson).toList();
        expect(stories.map((s) => s.id).toSet(), hasLength(total));
        for (final s in stories) {
          expect(s.id, startsWith('yb_'));
        }
        // Ids must not clash with the main library.
        final main = (jsonDecode(File('assets/reading/stories.json').readAsStringSync()) as List)
            .map((s) => (s as Map)['id'])
            .toSet();
        expect(stories.where((s) => main.contains(s.id)), isEmpty);
        // ...nor with the other YDS sets.
        for (final (other, _, _) in _sets) {
          if (other == file || !File(other).existsSync()) continue;
          final ids = (jsonDecode(File(other).readAsStringSync()) as List)
              .map((s) => (s as Map)['id'])
              .toSet();
          expect(stories.where((s) => ids.contains(s.id)), isEmpty, reason: other);
        }
      });

      test(
        'only ReadingStory fields; $minWords–$maxWords words; glosses lowercase and in the text; 2 questions',
        () {
          const fields = {'id', 'level', 'emoji', 'title', 'titleTr', 'text', 'glosses', 'questions'};
          for (final s in raw) {
            final id = s['id'];
            expect(fields.containsAll(s.keys), isTrue, reason: '$id: ${s.keys}');
            final text = s['text'] as String;
            final words = RegExp(r"[\p{L}]+(?:[-'’][\p{L}]+)*", unicode: true).allMatches(text).length;
            expect(words, inInclusiveRange(minWords, maxWords), reason: '$id: $words kelime');
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
        },
      );
    });
  }
}
