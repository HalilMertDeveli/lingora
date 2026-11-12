// YDS reading sections and their half mocks: ys6 "Okuma evi 1" (Faz 1b), ys8 "Okuma evi 2" (Faz 2b) and
// ys10 "Okuma evi 3" (Faz 3b: YÖKDİL field texts, half mocks 6–8 inside the section, section mock at the end).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (file, units, lesson texts, test texts, extra reading lists required on text lessons, half mocks: id → title)
const _sections = [
  ('assets/courses/exam_yds/06_okuma_evi_1.json', 6, 36, 12, <String>[], {'ys6u6m': 'Yarım deneme 1 (tanı)'}),
  ('assets/courses/exam_yds/08_okuma_evi_2.json', 10, 60, 20, ['ys7', 'ys5'], {'ys8u10m': 'Yarım deneme 5'}),
  (
    'assets/courses/exam_yds/10_okuma_evi_3.json',
    8,
    48,
    16,
    ['ys9', 'ys7'],
    {'ys10u3m': 'Yarım deneme 6', 'ys10u5m': 'Yarım deneme 7', 'ys10u7m': 'Yarım deneme 8'},
  ),
];

void main() {
  for (final (file, unitCount, lessonCount, testCount, lists, halfMocks) in _sections) {
    group(
      'YDS okuma evi ${file.split('/').last}',
      skip: File(file).existsSync() ? false : 'not shipped yet',
      () {
        late final Map<String, dynamic> section =
            jsonDecode(File(file).readAsStringSync()) as Map<String, dynamic>;
        late final List<Map<String, dynamic>> units = (section['units'] as List).cast<Map<String, dynamic>>();
        List<Map<String, dynamic>> nodes(Map<String, dynamic> u) =>
            (u['nodes'] as List).cast<Map<String, dynamic>>();
        List<Map<String, dynamic>> ex(Map<String, dynamic> n) =>
            ((n['exercises'] as List?) ?? const []).cast<Map<String, dynamic>>();

        test('parallel section of $unitCount units with ${lessonCount + testCount} reading texts', () {
          expect((section['section'] as Map)['parallel'], isTrue);
          expect(units, hasLength(unitCount));
          final lessonTexts = <String>{}, testTexts = <String>{};
          for (final u in units) {
            for (final n in nodes(u)) {
              for (final e in ex(n)) {
                if (e['qtype'] != 'reading') continue;
                if (n['type'] == 'lesson') lessonTexts.add(e['passage'] as String);
                if (n['type'] == 'test') testTexts.add(e['passage'] as String);
              }
            }
          }
          expect(lessonTexts, hasLength(lessonCount));
          expect(testTexts, hasLength(testCount));
        });

        test('text lessons carry reading metadata for the library and the reading counter', () {
          for (final u in units) {
            for (final n in nodes(u).take(3)) {
              final r = n['reading'] as Map?;
              expect(r, isNotNull, reason: '${n['id']}');
              expect(['fen', 'saglik', 'sosyal'], contains(r!['field']), reason: '${n['id']}');
              expect(r['words'], isA<int>(), reason: '${n['id']}');
              expect(r['cefr'], isA<String>(), reason: '${n['id']}');
              for (final b in lists) {
                expect(r[b], isA<List>(), reason: '${n['id']} reading.$b');
              }
            }
          }
        });

        test('half mocks: fixed 40 questions in the YDS distribution, right after the unit chest', () {
          final all = {
            for (final u in units)
              for (final n in nodes(u)) n['id']: (u, n),
          };
          for (final MapEntry(key: id, value: title) in halfMocks.entries) {
            final (u, mock) = all[id]!;
            expect(nodes(u).last, same(mock), reason: '$id is the last node of its unit');
            expect(nodes(u)[nodes(u).length - 2]['type'], 'chest', reason: id);
            expect(mock['title'], title);
            expect(mock['type'], 'mock');
            expect([mock['examId'], mock['size'], mock['minutes']], ['yds', 40, 90]);
            final qs = ex(mock);
            expect(qs, hasLength(40));
            final counts = <String, int>{};
            for (final q in qs) {
              expect(q['type'], 'choice');
              expect((q['options'] as List), hasLength(5));
              counts[q['qtype'] as String] = (counts[q['qtype']] ?? 0) + 1;
            }
            expect(counts, {
              'vocabulary': 3, 'grammar': 5, 'cloze': 5, 'sentenceCompletion': 5, 'translation': 3, //
              'reading': 8,
              'dialogue': 3,
              'restatement': 2,
              'paragraphCompletion': 2,
              'irrelevantSentence': 4,
            });
          }
          // Every other mock node: only ys10's closing section mock.
          final others = [
            for (final u in units)
              for (final n in nodes(u))
                if (n['type'] == 'mock' && !halfMocks.containsKey(n['id'])) n['id'],
          ];
          expect(others, file.contains('10_okuma_evi_3') ? ['ys10u8m'] : isEmpty);
        });

        if (file.contains('10_okuma_evi_3')) {
          test('ys10 ends with a 30-question, 45-minute section mock drawn from the section', () {
            final mock = nodes(units.last).last;
            expect([mock['id'], mock['type'], mock['size'], mock['minutes']], ['ys10u8m', 'mock', 30, 45]);
            expect(mock['exercises'], isNull);
          });

          test('ys10: every text has an inference/attitude item and a paragraph-level item', () {
            final deep = RegExp(
              r'infer|impl(y|ied)|attitude|purpose|conclude|suggest|tone|most likely|assume',
              caseSensitive: false,
            );
            for (final u in units) {
              for (final n in nodes(u).where((n) => n['type'] != 'mock')) {
                final byText = <String, List<Map<String, dynamic>>>{};
                for (final e in ex(n).where((e) => e['passage'] != null && e['qtype'] != 'cloze')) {
                  byText.putIfAbsent(e['passage'] as String, () => []).add(e);
                }
                for (final qs in byText.values) {
                  expect(qs, hasLength(4), reason: '${n['id']}');
                  expect(qs.any((q) => deep.hasMatch('${q['question']}')), isTrue, reason: '${n['id']}');
                  expect(
                    qs.any((q) => ['paragraphCompletion', 'irrelevantSentence'].contains(q['qtype'])),
                    isTrue,
                    reason: '${n['id']}',
                  );
                }
              }
            }
          });
        }

        test('every choice question names its YDS question type', () {
          const qtypes = {
            'vocabulary', 'grammar', 'cloze', 'sentenceCompletion', 'translation', 'reading', 'dialogue', //
            'restatement', 'paragraphCompletion', 'irrelevantSentence',
          };
          for (final u in units) {
            for (final n in nodes(u)) {
              for (final e in ex(n).where((e) => e['type'] == 'choice')) {
                expect(qtypes, contains(e['qtype']), reason: '${n['id']} ${e['question']}');
              }
            }
          }
        });
      },
    );
  }
}
